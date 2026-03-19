#!/bin/bash
set -e

# --------------------
#  Configuration
# --------------------
MAGENTO_DOMAIN="localhost"
DB_NAME="magento2"
DB_USER="magentouser"
DB_PASSWORD="magento_pass_2024"
DB_ROOT_PASSWORD="root_pass_2024"
ADMIN_FIRSTNAME="Admin"
ADMIN_LASTNAME="User"
ADMIN_EMAIL="admin@example.com"
ADMIN_USER="admin"
ADMIN_PASSWORD="Admin1234!"
MAGENTO_CURRENCY="EUR"
MAGENTO_LANGUAGE="en_GB"
MAGENTO_TIMEZONE="Europe/Paris"
MAGENTO_VERSION="2.4.6"

PROJECT_DIR="magento2-docker"

echo ""
echo "-------------------------------------------"
echo "|     Magento 2 - Docker Setup Script     |"
echo "-------------------------------------------"
echo ""

# --------------------
# Checking requirements
# --------------------
echo "[ 0/4 ] Checking requirements"
if ! command -v docker &>/dev/null; then
    echo "  Docker is not installed"
    echo "  -> https://docs.docker.com/get-docker/"
    exit 1
fi
if ! docker compose version &>/dev/null 2>&1 && ! docker-compose version &>/dev/null 2>&1; then
    echo "  Docker Compose is not installed"
    exit 1
fi
if docker compose version &>/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
else
    COMPOSE_CMD="docker-compose"
fi
echo "  Docker OK — $(docker --version)"
echo "  Compose OK — $($COMPOSE_CMD version --short 2>/dev/null || echo 'v1')"

# --------------------
# Project structure creation
# --------------------
echo ""
echo "[ 1/4 ] Creating project structure"

mkdir -p "$PROJECT_DIR/docker"
cd "$PROJECT_DIR"

echo "$PROJECT_DIR/"
echo "$PROJECT_DIR/docker/"

# --------------------
# Dockerfile
# --------------------
cat > docker/Dockerfile << 'EOF'
FROM php:8.1-apache

RUN apt-get update && apt-get install -y \
    libfreetype6-dev libjpeg62-turbo-dev libpng-dev \
    libzip-dev libxml2-dev libxslt-dev libicu-dev \
    libonig-dev libsodium-dev libgd-dev \
    unzip git curl gnupg \
    && rm -rf /var/lib/apt/lists/*

RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) \
        bcmath gd intl mbstring opcache pdo_mysql \
        soap xsl zip sockets sodium

RUN echo "memory_limit=2G"                   >> /usr/local/etc/php/conf.d/magento.ini \
    && echo "max_execution_time=1800"        >> /usr/local/etc/php/conf.d/magento.ini \
    && echo "zlib.output_compression=On"     >> /usr/local/etc/php/conf.d/magento.ini \
    && echo "opcache.enable=1"               >> /usr/local/etc/php/conf.d/magento.ini \
    && echo "opcache.memory_consumption=512" >> /usr/local/etc/php/conf.d/magento.ini

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

RUN a2enmod rewrite

RUN printf '<VirtualHost *:80>\n\
    DocumentRoot /var/www/html/pub\n\
    <Directory /var/www/html>\n\
        Options FollowSymLinks\n\
        AllowOverride All\n\
        Require all granted\n\
    </Directory>\n\
    <Directory /var/www/html/pub>\n\
        Options FollowSymLinks\n\
        AllowOverride All\n\
        Require all granted\n\
    </Directory>\n\
</VirtualHost>\n' > /etc/apache2/sites-available/000-default.conf

WORKDIR /var/www/html

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 80
ENTRYPOINT ["/entrypoint.sh"]
EOF

echo "  docker/Dockerfile created"

# --------------------
# entrypoint.sh
# --------------------
cat > docker/entrypoint.sh << ENTRY
#!/bin/bash
set -e

INSTALL_FLAG="/var/www/html/.magento_installed"

wait_for_db() {
    echo ">>> Waiting for MariaDB"
    until php -r "
        try {
            new PDO('mysql:host=\${DB_HOST};dbname=\${DB_NAME}', '\${DB_USER}', '\${DB_PASSWORD}', [PDO::ATTR_TIMEOUT => 2]);
            exit(0);
        } catch (Exception \\\$e) { exit(1); }
    " 2>/dev/null; do
        echo "    MariaDB is not ready, retry in 3s"
        sleep 3
    done
    echo ">>> MariaDB ready !"
}

if [ ! -f "\$INSTALL_FLAG" ]; then
    echo ">>> First execution : Magento installation ${MAGENTO_VERSION}"

    wait_for_db

    echo ">>> Waiting Elasticsearch..."
    until curl -sf "http://\$ES_HOST:9200/_cluster/health" | grep -qE '"status":"(green|yellow)"'; do
        echo "    Elasticsearch is not ready, retry in 5s"
        sleep 5
    done
    echo ">>> Elasticsearch ready !"

    if [ ! -f "/var/www/html/composer.json" ]; then
        echo ">>> Downloading Magento ${MAGENTO_VERSION} from GitHub..."
        cd /tmp
        curl -fL \
            "https://github.com/magento/magento2/archive/refs/tags/${MAGENTO_VERSION}.tar.gz" \
            -o magento2.tar.gz

        echo ">>> Extraction..."
        tar -xzf magento2.tar.gz
        cp -a magento2-${MAGENTO_VERSION}/. /var/www/html/
        rm -rf magento2.tar.gz magento2-${MAGENTO_VERSION}

        echo ">>> Compose dependencies installation"
        cd /var/www/html
        COMPOSER_HOME=/tmp/composer composer install \
            --no-dev \
            --no-interaction \
            --optimize-autoloader \
            2>&1
    fi

    chmod +x /var/www/html/bin/magento

    echo ">>> Launch setup:install..."
    cd /var/www/html
    php bin/magento setup:install \
        --base-url="http://\${MAGENTO_DOMAIN}" \
        --db-host="\${DB_HOST}" \
        --db-name="\${DB_NAME}" \
        --db-user="\${DB_USER}" \
        --db-password="\${DB_PASSWORD}" \
        --admin-firstname="\${ADMIN_FIRSTNAME}" \
        --admin-lastname="\${ADMIN_LASTNAME}" \
        --admin-email="\${ADMIN_EMAIL}" \
        --admin-user="\${ADMIN_USER}" \
        --admin-password="\${ADMIN_PASSWORD}" \
        --language="\${MAGENTO_LANGUAGE}" \
        --currency="\${MAGENTO_CURRENCY}" \
        --timezone="\${MAGENTO_TIMEZONE}" \
        --use-rewrites=1 \
        --search-engine=elasticsearch7 \
        --elasticsearch-host="\${ES_HOST}" \
        --elasticsearch-port=9200 \
        --elasticsearch-index-prefix=magento2 \
        --elasticsearch-timeout=15

    php bin/magento deploy:mode:set developer
    php bin/magento cache:enable

    chown -R www-data:www-data /var/www/html
    find /var/www/html -type d -exec chmod 755 {} \;
    find /var/www/html -type f -exec chmod 644 {} \;
    chmod +x /var/www/html/bin/magento

    touch "\$INSTALL_FLAG"
    echo ">>>Magento installation Magento done !"
else
    echo ">>> Magento is already installed, direct launch."
fi

exec apache2-foreground
ENTRY

chmod +x docker/entrypoint.sh
echo "  docker/entrypoint.sh created"

# --------------------
# .env
# --------------------
cat > .env << EOF
MAGENTO_DOMAIN=${MAGENTO_DOMAIN}
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
DB_ROOT_PASSWORD=${DB_ROOT_PASSWORD}
ADMIN_EMAIL=${ADMIN_EMAIL}
ADMIN_USER=${ADMIN_USER}
ADMIN_PASSWORD=${ADMIN_PASSWORD}
MAGENTO_LANGUAGE=${MAGENTO_LANGUAGE}
MAGENTO_CURRENCY=${MAGENTO_CURRENCY}
MAGENTO_TIMEZONE=${MAGENTO_TIMEZONE}
ADMIN_FIRSTNAME=${ADMIN_FIRSTNAME}
ADMIN_LASTNAME=${ADMIN_LASTNAME}
MAGENTO_VERSION=${MAGENTO_VERSION}
EOF

echo "  .env created"

# --------------------
# docker-compose.yml
# --------------------
cat > docker-compose.yml << EOF
services:

  db:
    image: mariadb:10.6
    container_name: magento2_db
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: \${DB_ROOT_PASSWORD}
      MYSQL_DATABASE: \${DB_NAME}
      MYSQL_USER: \${DB_USER}
      MYSQL_PASSWORD: \${DB_PASSWORD}
    volumes:
      - db_data:/var/lib/mysql
    networks:
      - magento_net
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-u", "root", "-p\${DB_ROOT_PASSWORD}"]
      interval: 10s
      timeout: 5s
      retries: 15

  elasticsearch:
    image: elasticsearch:7.17.13
    container_name: magento2_elasticsearch
    restart: unless-stopped
    environment:
      - discovery.type=single-node
      - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
      - xpack.security.enabled=false
    volumes:
      - es_data:/usr/share/elasticsearch/data
    networks:
      - magento_net
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:9200/_cluster/health | grep -qE '\"status\":\"(green|yellow)\"'"]
      interval: 15s
      timeout: 10s
      retries: 15

  magento:
    build:
      context: ./docker
      dockerfile: Dockerfile
    container_name: magento2_app
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
      elasticsearch:
        condition: service_healthy
    environment:
      DB_HOST: db
      DB_NAME: \${DB_NAME}
      DB_USER: \${DB_USER}
      DB_PASSWORD: \${DB_PASSWORD}
      ES_HOST: elasticsearch
      MAGENTO_DOMAIN: \${MAGENTO_DOMAIN}
      ADMIN_FIRSTNAME: \${ADMIN_FIRSTNAME}
      ADMIN_LASTNAME: \${ADMIN_LASTNAME}
      ADMIN_EMAIL: \${ADMIN_EMAIL}
      ADMIN_USER: \${ADMIN_USER}
      ADMIN_PASSWORD: \${ADMIN_PASSWORD}
      MAGENTO_LANGUAGE: \${MAGENTO_LANGUAGE}
      MAGENTO_CURRENCY: \${MAGENTO_CURRENCY}
      MAGENTO_TIMEZONE: \${MAGENTO_TIMEZONE}
    volumes:
      - magento_data:/var/www/html
    ports:
      - "80:80"
    networks:
      - magento_net

  phpmyadmin:
    image: phpmyadmin:latest
    container_name: magento2_phpmyadmin
    restart: unless-stopped
    depends_on:
      - db
    environment:
      PMA_HOST: db
      PMA_USER: root
      PMA_PASSWORD: \${DB_ROOT_PASSWORD}
    ports:
      - "8081:80"
    networks:
      - magento_net

volumes:
  db_data:
  es_data:
  magento_data:

networks:
  magento_net:
    driver: bridge
EOF

echo "  docker-compose.yml created"

# --------------------
# Files ceated
# --------------------
echo ""
echo "[ 2/4 ] Files generated"
echo ""
echo "  magento2-docker/"
echo "  ├── docker/"
echo "  │   ├── Dockerfile"
echo "  │   └── entrypoint.sh"
echo "  ├── docker-compose.yml"
echo "  └── .env"

# --------------------
# Build & launch
# --------------------
echo ""
echo "[ 3/4 ] Building docker image (can take 2-3 min)"
echo ""

$COMPOSE_CMD down --remove-orphans 2>/dev/null || true
$COMPOSE_CMD up -d --build

echo ""
echo "[ 4/4 ] Launch done !"
echo ""
echo ""
echo "Ready !"
echo ""
echo "Magento installation is running in docker"
echo "  It can take 10-20 min beside you internet connexion"
echo ""
echo "Find your logs in"
echo "$COMPOSE_CMD logs -f magento"
echo ""
echo "Storefront  -> http://${MAGENTO_DOMAIN}"
echo "Admin       -> http://${MAGENTO_DOMAIN}/admin"
echo "Login       -> ${ADMIN_USER} / ${ADMIN_PASSWORD}"
echo "phpMyAdmin  -> http://localhost:8081"
echo ""
echo "Stop        -> $COMPOSE_CMD down"
echo "Total reset -> $COMPOSE_CMD down -v"
echo ""
