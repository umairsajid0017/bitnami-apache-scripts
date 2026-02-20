#!/usr/bin/env bash
set -euo pipefail

############################################
# REQUIRE ROOT
############################################
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root"
  echo "Run: sudo bash $0"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

log() { echo "[install] $*"; }

############################################
# VARIABLES
############################################
PG_VERSION=16
PGADMIN_EMAIL="admin@example.com"
PGADMIN_PASS="Alpha##77"
POSTGRES_PASS="Alpha##77"
# Server IP for pgAdmin URL and CURL test (override: SERVER_IP=1.2.3.4 sudo ./install_postgress.sh)
SERVER_IP="${SERVER_IP:-47.131.48.162}"
PGADMIN_URL="http://${SERVER_IP}/pgadmin4"
# Optional public URL to test (e.g. https://cdranalyzersuit.com/pgadmin4)
PGADMIN_PUBLIC_URL="${PGADMIN_PUBLIC_URL:-}"
BITNAMI_HTTPD_CONF="/opt/bitnami/apache/conf/httpd.conf"
BITNAMI_CONF_DIR="/opt/bitnami/apache/conf"
BITNAMI_BITNAMI_CONF="/opt/bitnami/apache/conf/bitnami/bitnami.conf"
BITNAMI_PROXY_CONF="/opt/bitnami/apache/conf/pgadmin4-proxy.conf"
BITNAMI_PGADMIN_VHOST_SNIPPET="/opt/bitnami/apache/conf/bitnami/pgadmin4-default-vhost.conf"
HTTPD_DEFAULT_CONF="/opt/bitnami/apache/conf/extra/httpd-default.conf"
# Apache request limits (avoids 400 "header exceeds server limit")
LIMIT_REQUEST_SIZE=32768

############################################
# CLEAN OLD INSTALLS
############################################
log "Removing old PostgreSQL & pgAdmin"

systemctl stop postgresql 2>/dev/null || true
systemctl stop apache2 2>/dev/null || true

apt-get remove --purge -y postgresql* pgadmin4* || true
rm -rf /var/lib/postgresql /etc/postgresql /var/lib/pgadmin || true
apt-get autoremove -y || true

############################################
# INSTALL REQUIRED TOOLS
############################################
log "Installing required packages"
apt-get update -y
apt-get install -y curl gnupg ca-certificates lsb-release

############################################
# ADD POSTGRESQL REPO (MODERN METHOD)
############################################
log "Adding PostgreSQL repository"

curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
| gpg --batch --yes --dearmor -o /usr/share/keyrings/postgresql.gpg

echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] \
http://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" \
> /etc/apt/sources.list.d/pgdg.list

apt-get update -y

############################################
# INSTALL POSTGRESQL
############################################
log "Installing PostgreSQL $PG_VERSION"
apt-get install -y postgresql-$PG_VERSION \
                   postgresql-client-$PG_VERSION \
                   postgresql-contrib-$PG_VERSION

systemctl enable --now postgresql

############################################
# SET POSTGRES PASSWORD
############################################
log "Setting PostgreSQL root user"

sudo -u postgres psql <<EOF
DO \$\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'root') THEN
      CREATE ROLE root WITH LOGIN PASSWORD '$POSTGRES_PASS' CREATEDB CREATEROLE;
   END IF;
END
\$\$;
EOF

############################################
# ADD PGADMIN REPOSITORY
############################################
log "Adding pgAdmin repository"

curl -fsSL https://www.pgadmin.org/static/packages_pgadmin_org.pub \
| gpg --batch --yes --dearmor -o /usr/share/keyrings/pgadmin4.gpg

echo "deb [signed-by=/usr/share/keyrings/pgadmin4.gpg] \
https://ftp.postgresql.org/pub/pgadmin/pgadmin4/apt/bookworm pgadmin4 main" \
> /etc/apt/sources.list.d/pgadmin4.list

apt-get update -y

############################################
# INSTALL PGADMIN WEB
############################################
log "Installing pgAdmin4 Web"
apt-get install -y pgadmin4-web

############################################
# CONFIGURE PGADMIN WEB
############################################
log "Configuring pgAdmin"

if [ ! -f /var/lib/pgadmin/pgadmin4.db ]; then
  PGADMIN_SETUP_EMAIL="$PGADMIN_EMAIL" \
  PGADMIN_SETUP_PASSWORD="$PGADMIN_PASS" \
  /usr/pgadmin4/bin/setup-web.sh --yes
fi

############################################
# BITNAMI APACHE: pgAdmin via WSGI + request limits (avoids 400)
############################################
if [ -f "$BITNAMI_HTTPD_CONF" ]; then
  log "Configuring Bitnami Apache for pgAdmin (WSGI + header limits)"

  # Global request limits (included from httpd.conf)
  cat > "$BITNAMI_PROXY_CONF" <<EOF
# Allow larger request headers (avoids 400 "header exceeds server limit")
LimitRequestFieldSize $LIMIT_REQUEST_SIZE
LimitRequestLine $LIMIT_REQUEST_SIZE
EOF

  if ! grep -q "pgadmin4-proxy.conf" "$BITNAMI_HTTPD_CONF"; then
    echo "Include conf/pgadmin4-proxy.conf" >> "$BITNAMI_HTTPD_CONF"
  fi

  # Default vhost: serve pgAdmin via WSGI (no proxy to 127.0.0.1) + limits
  if [ -f "$BITNAMI_BITNAMI_CONF" ]; then
    # Remove any existing inline pgadmin block to avoid duplicate directives (Apache would fail to start)
    sed -i '/LimitRequestFieldSize 32768/d' "$BITNAMI_BITNAMI_CONF" || true
    sed -i '/LimitRequestLine 32768/d' "$BITNAMI_BITNAMI_CONF" || true
    sed -i '/# Serve pgAdmin via WSGI/d' "$BITNAMI_BITNAMI_CONF" || true
    sed -i '/WSGIScriptAlias \/pgadmin4 \/usr\/pgadmin4/d' "$BITNAMI_BITNAMI_CONF" || true
    sed -i '/<Directory \/usr\/pgadmin4\/web\/>/,/<\/Directory>/d' "$BITNAMI_BITNAMI_CONF" || true
    mkdir -p "$(dirname "$BITNAMI_PGADMIN_VHOST_SNIPPET")"
    cat > "$BITNAMI_PGADMIN_VHOST_SNIPPET" <<SNIPPET
  LimitRequestFieldSize $LIMIT_REQUEST_SIZE
  LimitRequestLine $LIMIT_REQUEST_SIZE
  WSGIScriptAlias /pgadmin4 /usr/pgadmin4/web/pgAdmin4.wsgi
  <Directory /usr/pgadmin4/web/>
    WSGIProcessGroup pgadmin
    WSGIApplicationGroup %{GLOBAL}
    Require all granted
  </Directory>
SNIPPET
    if ! grep -q "pgadmin4-default-vhost.conf" "$BITNAMI_BITNAMI_CONF"; then
      sed -i "/<VirtualHost _default_:80>/a\\  Include conf/bitnami/pgadmin4-default-vhost.conf" "$BITNAMI_BITNAMI_CONF"
    fi
  fi

  # Global limits in httpd-default.conf (applies to all vhosts)
  if [ -f "$HTTPD_DEFAULT_CONF" ] && ! grep -q "LimitRequestFieldSize" "$HTTPD_DEFAULT_CONF"; then
    echo "" >> "$HTTPD_DEFAULT_CONF"
    echo "# pgAdmin: allow larger request headers" >> "$HTTPD_DEFAULT_CONF"
    echo "LimitRequestLine $LIMIT_REQUEST_SIZE" >> "$HTTPD_DEFAULT_CONF"
    echo "LimitRequestFieldSize $LIMIT_REQUEST_SIZE" >> "$HTTPD_DEFAULT_CONF"
  fi

  # pgAdmin data/log dirs: Bitnami Apache runs as User daemon
  APACHE_USER="daemon"
  for dir in /var/lib/pgadmin /var/log/pgadmin; do
    if [ -d "$dir" ]; then
      chown -R "$APACHE_USER:$APACHE_USER" "$dir"
      chmod -R 755 "$dir"
      log "Set ownership of $dir to $APACHE_USER"
    fi
  done

  # Free port 80: pgadmin4-web pulls in system apache2 which binds to 80
  log "Stopping system Apache so Bitnami Apache can use port 80"
  systemctl stop apache2 2>/dev/null || true
  systemctl disable apache2 2>/dev/null || true

  /opt/bitnami/ctlscript.sh restart apache
fi

############################################
# FINAL STATUS
############################################
log "PostgreSQL version:"
psql --version || true

log "Services:"
systemctl is-active postgresql || true

echo ""
echo "=============================================="
echo "INSTALLATION COMPLETE"
echo ""
echo "PostgreSQL User:"
echo "  Username: root"
echo "  Password: $POSTGRES_PASS"
echo ""
echo "pgAdmin Login:"
echo "  Email:    $PGADMIN_EMAIL"
echo "  Password: $PGADMIN_PASS"
echo ""
echo "Access pgAdmin at:"
echo "  $PGADMIN_URL"
echo "=============================================="

############################################
# CURL TESTS
############################################
log "Testing with CURL..."

# Test PostgreSQL (local)
if sudo -u postgres psql -tAc "SELECT 1" >/dev/null 2>&1; then
  echo "[OK] PostgreSQL: local connection works"
else
  echo "[FAIL] PostgreSQL: local connection failed"
fi

# Test pgAdmin endpoint
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$PGADMIN_URL" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "302" ]; then
  echo "[OK] pgAdmin: $PGADMIN_URL returned HTTP $HTTP_CODE"
else
  echo "[INFO] pgAdmin: $PGADMIN_URL returned HTTP $HTTP_CODE (200/301/302 expected once Apache is reachable)"
fi

# Test optional public URL (e.g. https://cdranalyzersuit.com/pgadmin4)
if [ -n "$PGADMIN_PUBLIC_URL" ]; then
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 -H "User-Agent: curl-test" "$PGADMIN_PUBLIC_URL" 2>/dev/null || echo "000")
  if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "302" ]; then
    echo "[OK] pgAdmin (public): $PGADMIN_PUBLIC_URL returned HTTP $HTTP_CODE"
  else
    echo "[INFO] pgAdmin (public): $PGADMIN_PUBLIC_URL returned HTTP $HTTP_CODE"
  fi
fi
