#!/bin/bash
set -e

DOMAIN="$1"

if [[ -z "$DOMAIN" ]]; then
  echo "Usage: sudo ./renew_ssl_domain.sh example.com"
  exit 1
fi

DOMAIN_DIR="/home/bitnami/$DOMAIN"
CERTS_DIR="/opt/bitnami/apache/conf/certs/$DOMAIN"
LE_DIR="/etc/letsencrypt/live/$DOMAIN"

echo "Renewing SSL for: $DOMAIN"

certbot certonly \
  --webroot \
  --webroot-path="$DOMAIN_DIR" \
  -d "$DOMAIN" \
  -d "www.$DOMAIN" \
  --quiet

mkdir -p "$CERTS_DIR"

cp "$LE_DIR/fullchain.pem" "$CERTS_DIR/server.crt"
cp "$LE_DIR/privkey.pem" "$CERTS_DIR/server.key"

chmod 644 "$CERTS_DIR/server.crt"
chmod 600 "$CERTS_DIR/server.key"

# ✅ Correct reload method for Bitnami
/opt/bitnami/apache/bin/apachectl graceful

echo "✓ SSL updated successfully for $DOMAIN"
