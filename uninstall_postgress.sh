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

log() { echo "[uninstall] $*"; }

BITNAMI_HTTPD_CONF="/opt/bitnami/apache/conf/httpd.conf"
BITNAMI_PROXY_CONF="/opt/bitnami/apache/conf/pgadmin4-proxy.conf"

echo ""
echo "=============================================="
echo "WARNING: This will completely remove:"
echo "  - PostgreSQL"
echo "  - All databases"
echo "  - pgAdmin4"
echo "  - All related data"
echo "=============================================="
echo ""
read -p "Type YES to continue: " CONFIRM

if [ "$CONFIRM" != "YES" ]; then
  echo "Aborted."
  exit 1
fi

############################################
# STOP SERVICES
############################################
log "Stopping services"

systemctl stop postgresql 2>/dev/null || true
systemctl stop apache2 2>/dev/null || true

if [ -x "/opt/bitnami/ctlscript.sh" ]; then
  /opt/bitnami/ctlscript.sh stop apache 2>/dev/null || true
fi

############################################
# REMOVE PACKAGES
############################################
log "Removing PostgreSQL and pgAdmin packages"

apt-get remove --purge -y postgresql* pgadmin4* || true
apt-get autoremove -y || true
apt-get autoclean || true

############################################
# REMOVE DATA DIRECTORIES
############################################
log "Removing data directories"

rm -rf /var/lib/postgresql
rm -rf /etc/postgresql
rm -rf /var/log/postgresql
rm -rf /var/lib/pgadmin
rm -rf /var/log/pgadmin
rm -rf /usr/pgadmin4

############################################
# REMOVE REPOSITORIES
############################################
log "Removing repositories"

rm -f /etc/apt/sources.list.d/pgdg.list
rm -f /etc/apt/sources.list.d/pgadmin4.list
rm -f /usr/share/keyrings/postgresql.gpg
rm -f /usr/share/keyrings/pgadmin4.gpg

apt-get update -y

############################################
# REMOVE POSTGRES USER (if exists)
############################################
if id postgres >/dev/null 2>&1; then
  log "Removing postgres system user"
  userdel -r postgres 2>/dev/null || true
fi

############################################
# REMOVE BITNAMI PROXY CONFIG
############################################
if [ -f "$BITNAMI_PROXY_CONF" ]; then
  log "Removing Bitnami pgAdmin proxy config"
  rm -f "$BITNAMI_PROXY_CONF"
fi

if [ -f "$BITNAMI_HTTPD_CONF" ]; then
  log "Cleaning Bitnami httpd.conf include"
  sed -i '/pgadmin4-proxy\.conf/d' "$BITNAMI_HTTPD_CONF" || true
fi

############################################
# RESTART BITNAMI APACHE (IF EXISTS)
############################################
if [ -x "/opt/bitnami/ctlscript.sh" ]; then
  /opt/bitnami/ctlscript.sh restart apache 2>/dev/null || true
fi

############################################
# FINAL MESSAGE
############################################
echo ""
echo "=============================================="
echo "UNINSTALL COMPLETE"
echo ""
echo "PostgreSQL and pgAdmin4 fully removed."
echo "All databases and configurations deleted."
echo "=============================================="
