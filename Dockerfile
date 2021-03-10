# Other articles read on my research about laravel + Docker:
#  - https://laravel-news.com/multi-stage-docker-builds-for-laravel
#  - https://www.pascallandau.com/blog/php-php-fpm-and-nginx-on-docker-in-windows-10/

# I: Runtime Stage: ============================================================
# This is the stage where we build the runtime base image, which is used as the
# common ancestor by the rest of the stages, and contains the minimal runtime
# dependencies required for the application to run in production:

# Use the official PHP 8.0.3 fpm buster image as base:
FROM php:8.0.3-fpm-buster AS runtime

# Install runtime dependency packages
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    libmariadb3 \
    libzip4 \
    openssl \
    supervisor \
 && rm -rf /var/lib/apt/lists/*

# Stage 2: Testing =============================================================

FROM runtime AS testing

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    git \
    libmariadb-dev \
    libzip-dev \
    unzip \
    zip

RUN set -ex \
 && docker-php-ext-install \
    bcmath \
    pdo_mysql \
    zip

# Install Node:
COPY --from=node:lts-buster-slim /opt/yarn-* /opt/yarn/
COPY --from=node:lts-buster-slim /usr/local/bin/node /usr/local/bin/node
COPY --from=node:lts-buster-slim /usr/local/include/node /usr/local/include/node
COPY --from=node:lts-buster-slim /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s /opt/yarn/bin/yarn /usr/local/bin/yarn \
 && ln -s /usr/local/bin/node /usr/local/bin/nodejs \
 && ln -s /opt/yarn/bin/yarnpkg /usr/local/bin/yarnpkg \
 && ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
 && ln -s /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx

# Install PHP composer
COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

# Receive the app path as an argument:
ARG APP_PATH=/srv/demo

# Receive the developer user's UID and USER:
ARG DEVELOPER_UID=1000
ARG DEVELOPER_USERNAME=you

# Replicate the developer user in the development image:
RUN addgroup --gid ${DEVELOPER_UID} ${DEVELOPER_USERNAME} \
 ;  useradd -r -m -u ${DEVELOPER_UID} --gid ${DEVELOPER_UID} \
    --shell /bin/bash -c "Developer User,,," ${DEVELOPER_USERNAME}

# Ensure the developer user's home directory and APP_PATH are owned by him/her:
# (A workaround to a side effect of setting WORKDIR before creating the user)
RUN userhome=$(eval echo ~${DEVELOPER_USERNAME}) \
 && chown -R ${DEVELOPER_USERNAME}:${DEVELOPER_USERNAME} $userhome \
 && mkdir -p ${APP_PATH} \
 && chown -R ${DEVELOPER_USERNAME}:${DEVELOPER_USERNAME} ${APP_PATH}

# Add the app's "bin/" directory to PATH:
ENV PATH=${APP_PATH}/bin:$PATH

# Set the app path as the working directory:
WORKDIR ${APP_PATH}

# Change to the developer user:
USER ${DEVELOPER_USERNAME}

# Copy the composer files and run `composer install` - note that the autoloader
# generation will be disabled, as at this point there will be no code yet, hence
# some files required for the autoloader generation are missing:
COPY --chown=${DEVELOPER_USERNAME} composer.* ${APP_PATH}/
RUN mkdir -p ${APP_PATH}/vendor \
 && composer install \
    --no-autoloader \
    --no-scripts \
    --no-interaction \
    --prefer-dist
ENV PATH=${APP_PATH}/vendor/bin:$PATH

# Copy the node files and run `yarn install`:
COPY --chown=${DEVELOPER_USERNAME} package.json yarn.lock ${APP_PATH}/
RUN yarn install

# Stage 3: Development =========================================================
# In this stage we'll add the packages, libraries and tools required in the
# day-to-day development process.

# Use the "testing" stage as base:
FROM testing AS development

# Receive the developer username again, as ARGS won't persist between stages on
# non-buildkit builds:
ARG DEVELOPER_USERNAME=you

# Change to root user to install the development packages:
USER root

# Install sudo, along with any other tool required at development phase:
RUN apt-get install -y --no-install-recommends \
  # Adding bash autocompletion as git without autocomplete is a pain...
  bash-completion \
  # gpg & gpgconf is used to get Git Commit GPG Signatures working inside the
  # VSCode devcontainer:
  gpg \
  gpgconf \
  openssh-client \
  # Vim will be used to edit files when inside the container (git, etc):
  vim \
  # Sudo will be used to install/configure system stuff if needed during dev:
  sudo

# Add the developer user to the sudoers list:
RUN echo "${DEVELOPER_USERNAME} ALL=(ALL) NOPASSWD:ALL" | tee "/etc/sudoers.d/${DEVELOPER_USERNAME}"

# Install xdebug (you can specify a version instead: xdebug-2.7.2)
RUN pecl install xdebug && docker-php-ext-enable xdebug
ENV XDEBUG_MODE=debug XDEBUG_CONFIG="client_host=host.docker.internal client_port=9000"

# Change back to the developer user:
USER ${DEVELOPER_USERNAME}

# Stage 4: Builder =============================================================
# In this stage we'll compile assets coming from the project's source, remove
# development libraries, and other cleanup tasks, in preparation for the final
# "release" image:

# Start off from the development stage image:
FROM testing AS builder

# Receive the developer username and the app path arguments again, as ARGS
# won't persist between stages on non-buildkit builds:
ARG DEVELOPER_USERNAME=you
ARG APP_PATH=/srv/rails-google-cloud-demo

# Copy the full contents of the project:
COPY --chown=${DEVELOPER_USERNAME} . ${APP_PATH}/

# Precompile assets and remove compiled source code:
RUN yarn production && rm -rf resources/js resources/sass

# Remove installed composer libraries that belong to the development
# group - we'll copy the remaining composer libraries into the deployable image
# on the next stage - see https://laravel.com/docs/5.7/deployment#optimization.
# Notice that we're removing our 'composer' wrapper script, as we no longer need
# to switch from root user as we should during development time:
RUN composer install --optimize-autoloader --no-dev

# Remove files not used on release image:
RUN rm -rf \
    .env.example \
    bin/dev-entrypoint \
    node_modules \
    tmp/* \
    webpack.mix.js \
    yarn.lock

# Stage 5: Release =============================================================
# In this stage, we build the final, deployable Docker image, which will be
# smaller than the images generated on previous stages:

# Start off from the runtime stage image:
FROM runtime AS release

# Receive the app path as an argument:
ARG APP_PATH=/srv/demo

# Copy the previously-compiled PHP extensions & their configurations:
COPY --from=builder /usr/local/lib/php/extensions /usr/local/lib/php/extensions
COPY --from=builder /usr/local/etc/php/conf.d /usr/local/etc/php/conf.d

# Copy from app code from the "builder" stage, which at this point should have
# the assets (javascript & css) already compiled:
COPY --from=builder --chown=www-data:www-data ${APP_PATH} /srv/demo

# Set the APP_ENV and PORT default values:
ENV APP_ENV=production PORT=8000

# Define the image's default command:
CMD [ "start-web" ]

# Step down to an unprivileged user:
USER www-data
