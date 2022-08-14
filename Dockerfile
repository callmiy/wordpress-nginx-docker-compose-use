FROM urre/wordpress-nginx-docker-compose-image:1.2.1

# Install wp-cli
RUN \
  apt update \
  && apt install -y --no-install-recommends \
  sudo \
  less \
  vim \
  openssl \
  ca-certificates \
  mariadb-client \
  && rm -rf /var/lib/apt/lists/* \
  && curl -o /bin/wp-cli.phar https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
  && chmod +x /bin/wp-cli.phar \
  && cd /bin \
  && mv wp-cli.phar wp \
  && mkdir -p /var/www/.wp-cli/cache \
  && chown www-data:www-data /var/www/.wp-cli/cache \
  # Forward Message to mailhog
  && curl --location --output \
  /usr/local/bin/mhsendmail https://github.com/mailhog/mhsendmail/releases/download/v0.2.0/mhsendmail_linux_amd64  \
  && chmod +x /usr/local/bin/mhsendmail \
  # && echo 'sendmail_path="/usr/local/bin/mhsendmail --smtp-addr=mailhog:1025 --from=no-reply@gbp.lo"' > /usr/local/etc/php/conf.d/mailhog.ini
  && groupadd wordpress \
  && useradd -m -g wordpress wordpress

# Note: Use docker-compose up -d --force-recreate --build when Dockerfile has changed.
USER wordpress
