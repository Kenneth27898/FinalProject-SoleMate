
# ==========================================
# 1. Install Composer dependencies
# ==========================================
FROM composer:2 AS composer_stage

WORKDIR /app

COPY composer.json composer.lock ./

RUN composer install \
    --no-dev \
    --no-interaction \
    --prefer-dist \
    --optimize-autoloader \
    --no-scripts


# ==========================================
# 2. Build Vite frontend assets
# ==========================================
FROM node:20-alpine AS node_stage

WORKDIR /app

COPY package*.json ./

RUN npm install

COPY . .

RUN npm run build


# ==========================================
# 3. Main Laravel application
# ==========================================
FROM php:8.2-apache

WORKDIR /var/www/html

RUN apt-get update && apt-get install -y \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    libzip-dev \
    libicu-dev \
    libpq-dev \
    libonig-dev \
    unzip \
    git \
    && docker-php-ext-configure gd \
        --with-freetype \
        --with-jpeg \
    && docker-php-ext-install \
        pdo_mysql \
        pdo_pgsql \
        mbstring \
        exif \
        pcntl \
        bcmath \
        gd \
        zip \
        intl \
    && a2enmod rewrite \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Configure Apache document root
ENV APACHE_DOCUMENT_ROOT=/var/www/html/public

RUN sed -ri \
    -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' \
    /etc/apache2/sites-available/*.conf \
    /etc/apache2/apache2.conf \
    /etc/apache2/conf-available/*.conf

RUN printf '<Directory /var/www/html/public>\n\
    AllowOverride All\n\
    Require all granted\n\
</Directory>\n' > /etc/apache2/conf-available/laravel.conf \
    && a2enconf laravel

# Copy application source code
COPY . .

# Copy Composer dependencies
COPY --from=composer_stage /app/vendor ./vendor

# Copy compiled frontend assets
COPY --from=node_stage /app/public/build ./public/build

# Prepare Laravel runtime directories and package discovery
RUN mkdir -p \
    storage/app/public \
    storage/framework/cache/data \
    storage/framework/sessions \
    storage/framework/views \
    storage/logs \
    bootstrap/cache \
    && php artisan package:discover --ansi \
    && php artisan storage:link \
    && chown -R www-data:www-data storage bootstrap/cache \
    && chmod -R 775 storage bootstrap/cache

EXPOSE 80

# Run migrations before starting Apache
CMD ["sh", "-c", "php artisan migrate --force && apache2-foreground"]
