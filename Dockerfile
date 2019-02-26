# I: Runtime Stage: ============================================================
# This is the stage where we build the runtime base image, which is used as the
# common ancestor by the rest of the stages, and contains the minimal runtime
# dependencies required for the application to run:

# Step 1: Use the official PHP 7.3.x Alpine image as base:
FROM php:7.3-alpine AS runtime

# Step 2: We'll set '/usr/src' path as the working directory:
WORKDIR /usr/src

# Step 3: We'll set the working dir as HOME and add the app's binaries path to
# $PATH:
ENV HOME=/usr/src \
    COMPOSER_HOME=/usr/local/composer \
    PATH=/usr/src/bin:/usr/src/vendor/bin:/usr/local/composer/vendor/bin:$PATH

# Step 4: Install the common runtime dependencies:
RUN apk add --no-cache \
  ca-certificates \
  less \
  nodejs \
  npm \
  mariadb-client \
  openssl \
  su-exec \
  tzdata \
  zlib

# II: Development Stage: =======================================================
# In this stage we'll build the image used for development, including compilers,
# and development libraries. This is also a first step for building a releasable
# Docker image:

# Step 5: Start off from the "runtime" stage:
FROM runtime AS development

# Step 6: Install the development dependency packages with alpine package
# manager:
RUN apk add --no-cache \
    build-base \
    chromium \
    chromium-chromedriver \
    git \
    libzip-dev \
    mariadb-dev \
    yarn \
    zlib-dev

# Step 7: Fix npm uid-number error
# - see https://github.com/npm/uid-number/issues/7
RUN npm config set unsafe-perm true

# Step 8: Install the 'check-dependencies' node package:
RUN npm install -g check-dependencies

# Step 9: Install PHP packages required by laravel:
RUN set -ex && docker-php-ext-install \
  bcmath \
  pdo_mysql \
  zip

# Step 10: Install composer:
RUN set -ex \
 && export COMPOSER_VERSION=1.8.4 \
 && export COMPOSER_SHA256=1722826c8fbeaf2d6cdd31c9c9af38694d6383a0f2bf476fe6bbd30939de058a \
 && curl -o /usr/local/bin/composer "https://getcomposer.org/download/${COMPOSER_VERSION}/composer.phar" \
 && echo "${COMPOSER_SHA256}  /usr/local/bin/composer" | sha256sum -c - \
 && chmod a+x /usr/local/bin/composer

ARG DEVELOPER_USER="you"
ARG DEVELOPER_UID="1000"

RUN adduser -D -u $DEVELOPER_UID $DEVELOPER_USER \
 && addgroup $DEVELOPER_USER wheel

ENV DEVELOPER_USER=$DEVELOPER_USER

# Step X: Create the COMPOSER_HOME directory (where the global packages will be
# in):
RUN mkdir -p $COMPOSER_HOME \
 && chgrp wheel $COMPOSER_HOME \
 && chmod g+rws $COMPOSER_HOME
