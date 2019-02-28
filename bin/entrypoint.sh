#! /bin/sh

# The Docker App Container's production entrypoint.
set -e

: ${APP_PATH:="/usr/src"}
: ${APP_TEMP_PATH:="$APP_PATH/tmp"}
: ${APP_SETUP_LOCK:="$APP_TEMP_PATH/setup.lock"}
: ${APP_SETUP_WAIT:="5"}

# 1: Define the functions lock and unlock our app containers setup processes:
clear_temp_files() {
  rm -rf ${APP_TEMP_PATH}/pids/*
  rm -rf ${APP_TEMP_PATH}/sockets/*
}

configure_nginx() {
  php -f config/nginx.conf > /etc/nginx/nginx.conf
}

configure_php_fpm() {
  php -f config/php-fpm.conf > /usr/local/etc/php-fpm.conf
}

cache_laravel_config() {
  php artisan config:cache
}

# 2: 'Unlock' the setup process if the script exits prematurely:
trap unlock_setup HUP INT QUIT KILL TERM EXIT

case $1 in
	web)
		configure_nginx
    configure_php_fpm
    cache_laravel_config
    set -- supervisord -c config/supervisord.conf
		;;
	worker)
    cache_laravel_config
		set -- su-exec www-data php artisan queue:work "$@"
		;;
esac

# 9: Execute the given or default command:
exec "$@"
