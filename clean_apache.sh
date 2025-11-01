#!/bin/bash

###############################################################################
# Apache Configuration Cleanup Script
# This script cleans Apache configuration to default state:
# - Removes all domain virtual hosts
# - Resets to clean IP:80 default (no SSL)
# - Keeps domain storage directories intact
#
# Usage:
#   sudo ./clean_apache.sh
#
# Requirements:
#   - Run with sudo or as root
#
###############################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration paths
APACHE_VHOSTS_DIR="/opt/bitnami/apache/conf/vhosts"
APACHE_CTL="/opt/bitnami/apache/bin/apachectl"
BITNAMI_CONF="/opt/bitnami/apache/conf/bitnami/bitnami.conf"
BITNAMI_SSL_CONF="/opt/bitnami/apache/conf/bitnami/bitnami-ssl.conf"
CERTS_DIR="/opt/bitnami/apache/conf/certs"

# Function to print colored messages
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}→ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Function to test Apache configuration
test_apache_config() {
    print_info "Testing Apache configuration"
    if sudo "$APACHE_CTL" configtest 2>&1 | grep -q "Syntax OK"; then
        print_success "Apache configuration is valid"
        return 0
    else
        print_error "Apache configuration has errors:"
        sudo "$APACHE_CTL" configtest
        return 1
    fi
}

# Function to restart Apache
restart_apache() {
    print_info "Restarting Apache server"
    if sudo /opt/bitnami/ctlscript.sh restart apache 2>/dev/null; then
        print_success "Apache restarted successfully"
        return 0
    else
        print_error "Failed to restart Apache. You may need to restart it manually."
        return 1
    fi
}

# Function to remove all domain virtual hosts
remove_domain_vhosts() {
    print_info "Removing all domain virtual hosts..."
    
    # Collect all files to remove
    local files_to_remove=()
    local backup_files=()
    
    # Find all domain vhost files (excluding system files like 00_*)
    while IFS= read -r -d '' vhost_file; do
        local filename=$(basename "$vhost_file")
        # Skip system files (like 00_status-vhost.conf)
        if [[ ! "$filename" =~ ^00_ ]]; then
            files_to_remove+=("$vhost_file")
        fi
    done < <(find "${APACHE_VHOSTS_DIR}" -maxdepth 1 \( -name "*-vhost.conf" -o -name "*-https-vhost.conf" \) -type f -print0 2>/dev/null)
    
    # Find all backup files
    while IFS= read -r -d '' backup_file; do
        backup_files+=("$backup_file")
    done < <(find "${APACHE_VHOSTS_DIR}" -maxdepth 1 \( -name "*.back.*" -o -name "*.backup" \) -type f -print0 2>/dev/null)
    
    # Remove all vhost files at once
    if [[ ${#files_to_remove[@]} -gt 0 ]]; then
        print_info "Removing ${#files_to_remove[@]} domain virtual host file(s)..."
        printf "  %s\n" "${files_to_remove[@]}" | xargs -n1 basename | sed 's/^/  → /'
        sudo rm -f "${files_to_remove[@]}"
        print_success "Removed ${#files_to_remove[@]} domain virtual host file(s)"
    else
        print_info "No domain virtual hosts found to remove"
    fi
    
    # Remove all backup files at once
    if [[ ${#backup_files[@]} -gt 0 ]]; then
        print_info "Removing ${#backup_files[@]} backup file(s)..."
        printf "  %s\n" "${backup_files[@]}" | xargs -n1 basename | sed 's/^/  → /'
        sudo rm -f "${backup_files[@]}"
        print_success "Removed ${#backup_files[@]} backup file(s)"
    else
        print_info "No backup files found to remove"
    fi
}

# Function to clean certificate symlinks
clean_certificate_symlinks() {
    print_info "Cleaning certificate symlinks from Apache conf directory..."
    
    local count=0
    for cert_file in /opt/bitnami/apache/conf/*.crt /opt/bitnami/apache/conf/*.key; do
        if [[ -f "$cert_file" ]] || [[ -L "$cert_file" ]]; then
            print_info "Removing: $(basename "$cert_file")"
            sudo rm -f "$cert_file"
            ((count++))
        fi
    done
    
    if [[ $count -eq 0 ]]; then
        print_info "No certificate symlinks found"
    else
        print_success "Removed $count certificate symlink(s)"
    fi
}

# Function to clean certificate directories
clean_certificate_directories() {
    if [[ ! -d "$CERTS_DIR" ]]; then
        print_info "Certificate directory does not exist"
        return 0
    fi
    
    # Collect all certificate directories
    local cert_dirs=()
    while IFS= read -r -d '' cert_dir; do
        cert_dirs+=("$cert_dir")
    done < <(find "$CERTS_DIR" -maxdepth 1 -mindepth 1 -type d -print0 2>/dev/null)
    
    if [[ ${#cert_dirs[@]} -gt 0 ]]; then
        print_info "Removing ${#cert_dirs[@]} certificate director(ies)..."
        printf "  %s\n" "${cert_dirs[@]}" | xargs -n1 basename | sed 's/^/  → /'
        sudo rm -rf "${cert_dirs[@]}"
        print_success "Removed ${#cert_dirs[@]} certificate director(ies)"
    else
        print_info "No certificate directories found"
    fi
}

# Function to restore clean bitnami.conf
restore_bitnami_conf() {
    print_info "Restoring clean bitnami.conf..."
    
    sudo bash -c 'cat > '"$BITNAMI_CONF"' << "EOFCONF"
# Default Virtual Host configuration.

# Let Apache know we are behind a SSL reverse proxy
SetEnvIf X-Forwarded-Proto https HTTPS=on

<VirtualHost _default_:80>
  DocumentRoot "/opt/bitnami/apache/htdocs"
  # BEGIN: Configuration for letsencrypt
  Include "/opt/bitnami/apps/letsencrypt/conf/httpd-prefix.conf"
  # END: Configuration for letsencrypt
  # BEGIN: Support domain renewal when using mod_proxy without Location
  <IfModule mod_proxy.c>
    ProxyPass /.well-known !
  </IfModule>
  # END: Support domain renewal when using mod_proxy without Location
  <Directory "/opt/bitnami/apache/htdocs">
    Options Indexes FollowSymLinks
    AllowOverride All
    Require all granted
  </Directory>

  # Error Documents
  ErrorDocument 503 /503.html
  # BEGIN: Support domain renewal when using mod_proxy within Location
  <Location /.well-known>
    <IfModule mod_proxy.c>
      ProxyPass !
    </IfModule>
  </Location>
  # END: Support domain renewal when using mod_proxy within Location
</VirtualHost>
EOFCONF'
    
    print_success "bitnami.conf restored to clean state"
}

# Function to restore clean bitnami-ssl.conf
restore_bitnami_ssl_conf() {
    print_info "Restoring clean bitnami-ssl.conf..."
    
    sudo bash -c 'cat > '"$BITNAMI_SSL_CONF"' << '"'"'EOFSSL'"'"'
# Default SSL Virtual Host configuration.

<IfModule !ssl_module>
  LoadModule ssl_module modules/mod_ssl.so
</IfModule>

Listen 443
SSLProtocol all -SSLv2 -SSLv3
SSLHonorCipherOrder on
SSLCipherSuite "EECDH+ECDSA+AESGCM EECDH+aRSA+AESGCM EECDH+ECDSA+SHA384 EECDH+ECDSA+SHA256 EECDH+aRSA+SHA384 EECDH+aRSA+SHA256 EECDH !aNULL !eNULL !LOW !3DES !MD5 !EXP !PSK !SRP !DSS !EDH !RC4"
SSLPassPhraseDialog  builtin
SSLSessionCache "shmcb:/opt/bitnami/apache/logs/ssl_scache(512000)"
SSLSessionCacheTimeout  300
EOFSSL'
    
    print_success "bitnami-ssl.conf restored to clean state"
}

# Function to remove backup files
remove_backup_files() {
    print_info "Removing Apache configuration backup files..."
    
    local count=0
    sudo find /opt/bitnami/apache/conf -name "*.back.*" -type f | while read -r backup_file; do
        print_info "Removing: $(basename "$backup_file")"
        sudo rm -f "$backup_file"
        ((count++))
    done
    
    if [[ $count -eq 0 ]]; then
        print_info "No backup files found"
    else
        print_success "Removed backup files"
    fi
}

# Function to clean httpd.conf ServerName
clean_httpd_conf() {
    print_info "Cleaning httpd.conf ServerName..."
    
    local httpd_conf="/opt/bitnami/apache/conf/httpd.conf"
    if sudo grep -q "^ServerName" "$httpd_conf"; then
        sudo sed -i 's/^ServerName.*/ServerName localhost:80/' "$httpd_conf"
        print_success "httpd.conf ServerName set to localhost:80"
    else
        print_info "ServerName not found or already clean"
    fi
}

# Main execution
main() {
    echo ""
    echo "=========================================="
    echo "  Apache Configuration Cleanup Script"
    echo "=========================================="
    echo ""
    
    # Check if running as root or with sudo
    if [[ $EUID -eq 0 ]]; then
        print_info "Running as root"
    elif sudo -n true 2>/dev/null; then
        print_info "Running with sudo privileges"
    else
        print_error "This script requires sudo privileges. Please run with sudo or as root."
        exit 1
    fi
    
    echo ""
    print_warning "This will clean all Apache domain configurations!"
    print_warning "Domain storage directories will be kept intact."
    read -p "Are you sure you want to continue? (y/N): " CONFIRM
    
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        print_info "Operation cancelled"
        exit 0
    fi
    
    echo ""
    print_info "Starting Apache configuration cleanup..."
    echo ""
    
    # Remove domain virtual hosts
    remove_domain_vhosts
    
    # Clean certificate symlinks
    clean_certificate_symlinks
    
    # Clean certificate directories
    clean_certificate_directories
    
    # Remove backup files
    remove_backup_files
    
    # Restore clean configs
    restore_bitnami_conf
    restore_bitnami_ssl_conf
    clean_httpd_conf
    
    echo ""
    # Test Apache configuration
    if ! test_apache_config; then
        print_error "Apache configuration test failed. Please check the errors above."
        exit 1
    fi
    
    # Restart Apache
    restart_apache
    
    echo ""
    print_success "Apache configuration cleaned successfully!"
    echo ""
    print_info "Summary:"
    echo "  ✓ All domain virtual hosts removed"
    echo "  ✓ Certificate symlinks removed"
    echo "  ✓ Backup files removed"
    echo "  ✓ Default configs restored (IP:80 only, no SSL)"
    echo "  ✓ Domain storage directories kept intact"
    echo ""
    print_info "Apache is now in clean default state serving:"
    echo "  → http://$(hostname -I | awk '{print $1}') → /opt/bitnami/apache/htdocs"
    echo ""
}

# Run main function
main "$@"

