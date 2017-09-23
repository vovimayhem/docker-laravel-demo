FROM php:alpine

WORKDIR /usr/src

# 3: We'll add the app's binaries path to $PATH:
ENV HOME=/usr/src \
    PATH=/usr/src:/usr/src/vendor/bin:$PATH

# 4: Install composer:
RUN set -ex \
  && export COMPOSER_VERSION=1.5.2 \
  && export COMPOSER_SHA256=c0a5519c768ef854913206d45bd360efc2eb4a3e6eb1e1c7d0a4b5e0d3bbb31f \
  && curl -o /usr/local/bin/composer "https://getcomposer.org/download/${COMPOSER_VERSION}/composer.phar" \
  && echo "${COMPOSER_SHA256}  /usr/local/bin/composer" | sha256sum -c - \
  && chmod a+x /usr/local/bin/composer

# 5: Install dependency packages:
RUN set -ex && apk add --no-cache \
  build-base \
  ca-certificates \
  less \
  openssl \
  mysql-dev \
  tzdata \
  zlib-dev

# 6: Install PHP packages:
RUN set -ex && docker-php-ext-install \
  zip \
  pdo_mysql

# 7: Explicitly set user/group IDs
RUN addgroup -g 1000 demo \
  && adduser -H -D -G demo -u 1000 demo \
  && chown -R demo:demo /usr/src

# 8: Set the user to 'demo':
USER demo
