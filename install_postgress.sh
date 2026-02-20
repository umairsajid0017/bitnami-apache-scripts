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
BITNAMI_HTTPD_CONF="/opt/bitnami/apache/conf/httpd.conf"
BITNAMI_PROXY_CONF="/opt/bitnami/apache/conf/pgadmin4-proxy.conf"

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
| gpg --dearmor -o /usr/share/keyrings/postgresql.gpg

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
| gpg --dearmor -o /usr/share/keyrings/pgadmin4.gpg

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
/usr/pgadmin4/bin/setup-web.sh <<EOF
$PGADMIN_EMAIL
$PGADMIN_PASS
$PGADMIN_PASS
EOF
fi

############################################
# BITNAMI APACHE REVERSE PROXY
############################################
if [ -f "$BITNAMI_HTTPD_CONF" ]; then
  log "Configuring Bitnami Apache reverse proxy"

  cat > "$BITNAMI_PROXY_CONF" <<EOF
ProxyPass /pgadmin4 http://127.0.0.1/pgadmin4
ProxyPassReverse /pgadmin4 http://127.0.0.1/pgadmin4
EOF

  if ! grep -q "pgadmin4-proxy.conf" "$BITNAMI_HTTPD_CONF"; then
    echo "Include conf/pgadmin4-proxy.conf" >> "$BITNAMI_HTTPD_CONF"
  fi

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
echo "  http://YOUR_SERVER_IP/pgadmin4"
echo "=============================================="
