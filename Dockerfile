
FROM php:8.3-apache

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpng-dev \
    libjpeg62-turbo-dev \
    libfreetype6-dev \
    libzip-dev \
    libcurl4-openssl-dev \
    libmagickwand-dev \
    libonig-dev \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Configure GD
RUN docker-php-ext-configure gd \
    --with-freetype \
    --with-jpeg

# Install required PHP extensions
RUN docker-php-ext-install -j"$(nproc)" \
    bcmath \
    curl \
    gd \
    mbstring \
    pdo_mysql \
    zip

# Install Imagick
RUN pecl install imagick \
    && docker-php-ext-enable imagick

# Enable Apache modules
RUN a2enmod rewrite headers setenvif

# Enable .htaccess overrides
RUN sed -i 's/AllowOverride None/AllowOverride All/g' \
    /etc/apache2/apache2.conf

# Trust HTTPS protocol from reverse proxy
RUN printf '%s\n' \
    'SetEnvIfNoCase X-Forwarded-Proto "^https$" HTTPS=on' \
    > /etc/apache2/conf-available/reverse-proxy-https.conf \
    && a2enconf reverse-proxy-https

# PHP configuration
RUN printf "allow_url_fopen=On\nfile_uploads=On\nmemory_limit=256M\nupload_max_filesize=64M\npost_max_size=64M\nmax_execution_time=120\n" \
    > /usr/local/etc/php/conf.d/piprapay.ini

# Application directory
WORKDIR /var/www/html

# Copy application files
COPY . /var/www/html/

# Set application permissions
RUN chown -R www-data:www-data /var/www/html

# Persistent configuration directory
RUN mkdir -p /var/lib/piprapay \
    && chown www-data:www-data /var/lib/piprapay

# Startup script for persistent configuration
RUN printf '%s\n' \
    '#!/bin/sh' \
    'if [ ! -f /var/lib/piprapay/pp-config.php ] && [ -f /var/www/html/pp-config.php ] && [ ! -L /var/www/html/pp-config.php ]; then' \
    '    cp /var/www/html/pp-config.php /var/lib/piprapay/pp-config.php' \
    'fi' \
    'if [ -f /var/lib/piprapay/pp-config.php ]; then' \
    '    ln -sfn /var/lib/piprapay/pp-config.php /var/www/html/pp-config.php' \
    'fi' \
    'exec apache2-foreground' \
    > /usr/local/bin/start-piprapay \
    && chmod +x /usr/local/bin/start-piprapay

# Expose Apache port
EXPOSE 80

# Start Apache
CMD ["/usr/local/bin/start-piprapay"]
