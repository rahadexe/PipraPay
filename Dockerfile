
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

# Install PHP extensions
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

# Trust HTTPS reverse proxy
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

# Application permissions
RUN chown -R www-data:www-data /var/www/html

# Persistent configuration directory
RUN mkdir -p /var/lib/piprapay \
    && chown -R www-data:www-data /var/lib/piprapay

# Persistent configuration startup script
RUN cat > /usr/local/bin/start-piprapay <<'EOF'
#!/bin/sh
set -eu

APP_DIR="/var/www/html"
PERSIST_DIR="/var/lib/piprapay"

mkdir -p "$PERSIST_DIR"
chown -R www-data:www-data "$PERSIST_DIR"

# Remove completed installation temporary config
if [ -f "$PERSIST_DIR/pp-config.php" ]; then
    rm -f "$PERSIST_DIR/pp-temp-config.php"
fi

# Preserve and link configuration files
for FILE in pp-config.php pp-temp-config.php
do
    APP_FILE="$APP_DIR/$FILE"
    PERSIST_FILE="$PERSIST_DIR/$FILE"

    # Migrate an existing application config if present
    if [ -f "$APP_FILE" ] && [ ! -L "$APP_FILE" ]; then
        if [ ! -f "$PERSIST_FILE" ]; then
            cp -p "$APP_FILE" "$PERSIST_FILE"
            chown www-data:www-data "$PERSIST_FILE"
        fi
        rm -f "$APP_FILE"
    fi

    # Always create a link to persistent storage
    if [ ! -L "$APP_FILE" ]; then
        ln -s "$PERSIST_FILE" "$APP_FILE"
    fi
done

exec apache2-foreground
EOF

RUN chmod +x /usr/local/bin/start-piprapay

# Expose Apache port
EXPOSE 80

# Start application
CMD ["/usr/local/bin/start-piprapay"]
