<?php
/**
* Plugin Name: Simple Contact Form
* Description: One Awesome Plugin
* Plugin URI: https://
* Author: Adekanmi Ademiiju
* Author URI: https://
* Version: 0.0.0.
*
* Text Domain: simple-contact-form
*
* @category Core
*/
if (!defined('ABSPATH')) {
  exit; // Exit if accessed directly.
}

add_filter('the_content', function ($content) {
  if (is_single() || is_main_query()) {
    return $content . ' <p> The name of the boy boy!!! </p>';
  }
});
