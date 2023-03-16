#!/bin/bash
# shellcheck disable=1090,2009

set -e

components_roots='./src/components'
word_press_components_root='/var/www/html/web/app'
copy_watch_cmd='bash run.sh app.cp'

function _env {
  local env
  local splitted_envs=""

  if [[ -n "$1" ]]; then
    env="$1"
  elif [[ -e .env ]]; then
    env=".env"
  fi

  if [[ -n "$env" ]]; then
    set -a
    . $env
    set +a

    splitted_envs=$(splitenvs "$env" --lines)
  fi

  printf "%s" "$splitted_envs"
}

function _wait_until {
  command="${1}"
  timeout="${2:-30}"

  echo -e "\n\n\n=Running: $command=\n\n"

  i=0
  until eval "${command}"; do
    ((i++))

    if [ "${i}" -gt "${timeout}" ]; then
      echo -e "\n\n\n=Command: $command="
      echo -e "failed, aborting due to ${timeout}s timeout!\n\n"
      exit 1
    fi

    sleep 1
  done

  echo -e "\n\n\n= Done successfully running: $command =\n\n"
}

function _timestamp {
  date +'%s'
}

function _raise_on_no_env_file {
  if [[ -z "$ENV_FILE" ]]; then
    echo -e "\nERROR: env file not set.\n"
    exit 1
  elif [[ "$ENV_FILE" =~ .env.example ]]; then
    echo -e "\nERROR: env filename can not be .env.example.\n"
    exit 1
  fi
}

function _has_internet {
  if ping -q -c 1 -W 1 8.8.8.8 >/dev/null; then
    printf 0
  fi

  printf 1
}

function _cert_folder {
  printf '%s' "${SITE_CERT_FOLDER:-./certs}"
}

function cert {
  : "Generate certificate for use with HTTPS"

  _raise_on_no_env_file "$@"

  _env "$1"

  local path
  path="$(_timestamp)"

  local cert_folder
  cert_folder="$(_cert_folder)"

  mkdir -p "$path"
  rm -rf "${cert_folder}"
  mkdir -p "${cert_folder}"

  cd "$path"

  mkcert -install "${DOMAIN}"

  cd -

  find "./$path" \
    -type f \
    -name "*.pem" \
    -exec mv {} "${cert_folder}" \;

  rm -rf "./$path"

  local host_entry="127.0.0.1 $DOMAIN"

  if [[ ! "$(cat /etc/hosts)" =~ $host_entry ]]; then
    printf "%s\n" "$host_entry" |
      sudo tee -a /etc/hosts
  fi

  mkdir -p ./_certs

  cat "$(mkcert -CAROOT)/rootCA.pem" >./_certs/mkcert-ca-root.pem
}

function domain {
  if command -v xclip; then
    echo "$WP_HOME" | xclip -selection c
  fi

  echo -e "\n${WP_HOME}"
}

function d {
  : "Start docker compose services required for development"

  _raise_on_no_env_file "$@"

  clear

  if ! compgen -G "${cert_folder}/*.pem" >/dev/null; then
    # shellcheck disable=2145
    _wait_until "cert $@"
  fi

  if _has_internet; then
    cd src
    composer install
    cd - >/dev/null
  fi

  local services="mysql app ng p-admin mail"

  docker compose up -d $services
  docker compose logs -f $services
}

function clean {
  docker compose kill
  docker compose down -v

  sudo chown -R "$USER:$USER" .

  rm -rf ./*certs "$(_cert_folder)"

  rm -rf \
    src/vendor/ \
    src/web/wp \
    src/composer.lock \
    src/web/app/upgrade

  for frag in "plugins" "themes" "uploads"; do

    local path="./src/web/app/$frag"

    if [[ -e "$path" ]]; then
      # shellcheck disable=2045
      for content in $(ls "$path"); do
        # shellcheck disable=2115
        rm -rf "$path/$content"
      done
    fi

  done

  rm -rf ./docker/
}

function app.cpwk {
  : "Stop watching copy."

  local pid
  pid="$(ps a | grep "${copy_watch_cmd}" | grep -v grep | awk '{print $1}')"

  if [[ -n "$pid" ]]; then
    local cmd="kill -9 ${pid}"
    printf '%s\n\n' "${cmd}"
    eval "${cmd}"
  fi
}

function app.rm {
  : "Delete a wordpress component."
  local component_type="$1"
  local component_name="$2"

  if [[ -z "$component_type" ]] || [[ -z "$component_name" ]]; then
    printf '\nERROR: You must specify component type and component name.\n\n'
    exit 1
  fi

  app.cpwk

  # shellcheck disable=2115
  rm -rf "${components_roots}/${component_type}/${component_name}"

  docker compose \
    exec app \
    rm -rf "${word_press_components_root}/$component_type/${component_name}"
}

function app.m {
  : "Make a wordpress component. Examples:"
  : "  run.sh component themes theme-name"

  local component_type="$1"

  if [[ "$component_type" != "themes" ]] && [[ "$component_type" != "plugins" ]]; then
    printf '\nERROR: "%s" must be "themes" or "plugins"\n\n' "$component_type"
    exit 1
  fi

  local component_name="$2"

  local component_root="${components_roots}/${component_type}/${component_name}"

  mkdir -p "${component_root}"

  if [[ "$component_type" == 'themes' ]]; then
    for theme_file in 'style.css' 'index.php'; do
      local theme_file_abs="${component_root}/${theme_file}"

      if [[ ! -e "$theme_file_abs" ]]; then
        touch "$theme_file_abs"
      fi
    done
  elif [[ ! -e "${component_root}/index.php" ]]; then
    touch "${component_root}/index.php"
    touch "${component_root}/${component_name}.php"
  fi

  printf '%s\n\n' "$component_root"
}

function app.cp {
  : "Copy from our app codes to appropriate wordpress folders"

  if [[ ! -e "${components_roots}" ]]; then
    printf '\nERROR: You have not created any custom wordpress component. Exiting!\n\n'
    exit 1
  fi

  clear

  # shellcheck disable=2045
  for component_type in $(ls "${components_roots}"); do
    local word_press_component_path="${word_press_components_root}/$component_type"
    local component_root="${components_roots}/${component_type}"

    # shellcheck disable=2045
    for filename in $(ls "$component_root"); do
      local component_file_full_path="${component_root}/${filename}"

      local cmd="docker cp \
        ${component_file_full_path} \
        ${CONTAINER_NAME:my-site-app}:${word_press_component_path}"

      printf 'Executing:\n\t %s\n\n' "${cmd}"
      eval "${cmd}"
    done
  done

}

function app.cpw {
  : "Copy from our app codes to appropriate wordpress folders in watch mode."

  chokidar \
    "${components_roots}" \
    --initial \
    -c "${copy_watch_cmd}" &

  disown
}

function tunnel-pid {
  : "Get the pid of the tunnel"

  local pid

  pid="$(ps a | grep -P "${CLOUDFLARE_TUNNEL_CONFIG_FILE}" | grep -v grep | awk '{print $1}')"

  printf '%s' "${pid}"
}

function kill-tunnel {
  : "Kill the local proxy tunnel"

  local pid
  pid="$(tunnel-pid)"

  if [ -n "${pid}" ]; then
    kill -KILL "${pid}"
  fi

  printf '%s' "${pid}"
}

function create-tunnel {
  : ""
  local config_file
  local uuid

  config_file="${CLOUDFLARE_TUNNEL_CONFIG_FILE:-.cloudflare-tunnel-config.yml}"

  uuid=$(cloudflared tunnel create "$CLOUDFLARE_TUNNEL_NAME" |
    grep -P "Created tunnel ${CLOUDFLARE_TUNNEL_NAME} with id" |
    awk '{print $NF}')

  cat <<EOF >"${config_file}"
url: ${WP_HOME}
tunnel: $CLOUDFLARE_TUNNEL_NAME
credentials-file: ${HOME}/.cloudflared/${uuid}.json
EOF

  cloudflared tunnel route dns \
    "${CLOUDFLARE_TUNNEL_NAME}" \
    "${CLOUDFLARE_TUNNEL_NAME}.${CLOUDFLARE_TUNNEL_DOMAIN}"
}

function tunnel {
  : ""
  cloudflared tunnel --config "${CLOUDFLARE_TUNNEL_CONFIG_FILE}" run &
  disown
}

function help {
  : "List available tasks."

  mapfile -t names < <(compgen -A function | grep -v '^_')

  local len=0
  declare -A names_map=()

  for name in "${names[@]}"; do
    _len="${#name}"
    names_map["$name"]="${_len}"
    if [[ "${_len}" -gt "${len}" ]]; then len=${_len}; fi
  done

  len=$((len + 10))

  for name in "${names[@]}"; do
    local spaces=""
    _len="${names_map[$name]}"
    _len=$((len - _len))

    for _ in $(seq "${_len}"); do
      spaces="${spaces}-"
      ((++t))
    done

    mapfile -t doc1 < <(
      type "$name" |
        sed -nEe "s/^[[:space:]]*: ?\"(.*)\";/\1/p"

    )

    if [[ -n "${doc1[*]}" ]]; then
      for _doc in "${doc1[@]}"; do
        echo -e "${name} ${spaces} ${_doc}"
      done
    else
      echo "${name} ${spaces} *************"
    fi

    echo
  done
}

TIMEFORMAT=$'\n\nTask completed in %3lR\n'
time "${@:-help}"
