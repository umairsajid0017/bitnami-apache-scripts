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
    if sudo "$APACHE_CTL" graceful 2>/dev/null || sudo systemctl restart apache2 2>/dev/null || sudo service apache2 restart 2>/dev/null; then
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
    
    local count=0
    # Remove all domain vhost files except default/system files
    for vhost_file in "${APACHE_VHOSTS_DIR}"/*-vhost.conf "${APACHE_VHOSTS_DIR}"/*-https-vhost.conf; do
        if [[ -f "$vhost_file" ]]; then
            # Skip system files (like 00_status-vhost.conf)
            if [[ "$(basename "$vhost_file")" =~ ^00_ ]]; then
                continue
            fi
            print_info "Removing: $(basename "$vhost_file")"
            sudo rm -f "$vhost_file"
            ((count++))
        fi
    done
    
    if [[ $count -eq 0 ]]; then
        print_info "No domain virtual hosts found to remove"
    else
        print_success "Removed $count domain virtual host file(s)"
    fi
    
    # Also remove any backup files
    local backup_count=0
    for backup_file in "${APACHE_VHOSTS_DIR}"/*.back.* "${APACHE_VHOSTS_DIR}"/*.backup; do
        if [[ -f "$backup_file" ]]; then
            print_info "Removing backup: $(basename "$backup_file")"
            sudo rm -f "$backup_file"
            ((backup_count++))
        fi
    done
    
    if [[ $backup_count -gt 0 ]]; then
        print_success "Removed $backup_count backup file(s)"
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

# Function to clean certificate directories (optional)
clean_certificate_directories() {
    print_warning "Certificate directories found in: $CERTS_DIR"
    read -p "Do you want to remove all certificate directories? (y/N): " DELETE_CERTS
    
    if [[ "$DELETE_CERTS" =~ ^[Yy]$ ]]; then
        print_info "Removing all certificate directories..."
        local count=0
        for cert_dir in "$CERTS_DIR"/*; do
            if [[ -d "$cert_dir" ]]; then
                print_info "Removing: $(basename "$cert_dir")"
                sudo rm -rf "$cert_dir"
                ((count++))
            fi
        done
        
        if [[ $count -eq 0 ]]; then
            print_info "No certificate directories found"
        else
            print_success "Removed $count certificate directory(ies)"
        fi
    else
        print_info "Certificate directories kept intact"
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
    
    # Clean certificate directories (optional)
    if [[ -d "$CERTS_DIR" ]]; then
        clean_certificate_directories
    fi
    
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

