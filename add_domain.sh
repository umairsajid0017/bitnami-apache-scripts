#!/bin/bash

###############################################################################
# Bitnami Domain Setup Script
# This script adds a new domain, creates its folder, and installs SSL
#
# Usage:
#   sudo ./add_domain.sh [domain.com]
#
# Example:
#   sudo ./add_domain.sh example.com
#
# Requirements:
#   - Run with sudo or as root
#   - Domain DNS must point to this server
#   - Ports 80 and 443 must be open
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
DOMAIN_DIR="/home/bitnami"
APACHE_CTL="/opt/bitnami/apache/bin/apachectl"

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

# Function to validate domain format
validate_domain() {
    local domain="$1"
    if [[ ! "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
        print_error "Invalid domain format: $domain"
        return 1
    fi
    return 0
}

# Function to check if domain already exists
check_domain_exists() {
    local domain="$1"
    if [[ -f "${APACHE_VHOSTS_DIR}/${domain}-vhost.conf" ]] || \
       [[ -f "${APACHE_VHOSTS_DIR}/${domain}-https-vhost.conf" ]]; then
        print_error "Domain configuration already exists for: $domain"
        return 1
    fi
    return 0
}

# Function to create domain directory
create_domain_directory() {
    local domain="$1"
    local domain_path="${DOMAIN_DIR}/${domain}"
    
    if [[ -d "$domain_path" ]]; then
        print_info "Domain directory already exists: $domain_path"
    else
        print_info "Creating domain directory: $domain_path"
        mkdir -p "$domain_path"
        chown -R bitnami:daemon "$domain_path"
        chmod 755 "$domain_path"
        print_success "Domain directory created"
    fi
    
    # Create a basic index.html file
    if [[ ! -f "${domain_path}/index.html" ]]; then
        cat > "${domain_path}/index.html" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Welcome to $domain</title>
</head>
<body>
    <h1>Welcome to $domain</h1>
    <p>Your domain is successfully configured!</p>
</body>
</html>
EOF
        chown bitnami:daemon "${domain_path}/index.html"
        print_success "Created default index.html"
    fi
}

# Function to create HTTP virtual host (redirects to HTTPS)
create_http_vhost() {
    local domain="$1"
    local vhost_file="${APACHE_VHOSTS_DIR}/${domain}-vhost.conf"
    
    print_info "Creating HTTP redirect virtual host (port 80 -> 443)"
    
    cat > "$vhost_file" << EOF
<VirtualHost 127.0.0.1:80 _default_:80>
  ServerName ${domain}
  ServerAlias www.${domain}
  DocumentRoot ${DOMAIN_DIR}/${domain}
  
  # Allow .well-known for ACME challenge (certbot)
  <Directory "${DOMAIN_DIR}/${domain}/.well-known">
    Options -Indexes
    AllowOverride None
    Require all granted
  </Directory>
  
  # Redirect all HTTP traffic to HTTPS (except .well-known for certbot)
  RewriteEngine On
  RewriteCond %{REQUEST_URI} !^/.well-known
  RewriteRule ^(.*)$ https://%{SERVER_NAME}$1 [R=301,L]
  
  # Logging
  ErrorLog "/opt/bitnami/apache/logs/${domain}-error.log"
  CustomLog "/opt/bitnami/apache/logs/${domain}-access.log" common
</VirtualHost>
EOF
    
    chmod 644 "$vhost_file"
    print_success "HTTP redirect virtual host created: $vhost_file"
}

# Function to create HTTPS virtual host
create_https_vhost() {
    local domain="$1"
    local domain_path="${DOMAIN_DIR}/${domain}"
    local vhost_file="${APACHE_VHOSTS_DIR}/${domain}-https-vhost.conf"
    
    print_info "Creating HTTPS virtual host template"
    
    cat > "$vhost_file" << EOF
<VirtualHost 127.0.0.1:443 _default_:443>
  ServerName ${domain}
  ServerAlias www.${domain}
  # SSL will be enabled after certificate installation by certbot
  SSLEngine off
  # Uncomment these lines after SSL certificate installation:
  # SSLEngine on
  # SSLCertificateFile "/opt/bitnami/apache/conf/certs/${domain}/server.crt"
  # SSLCertificateKeyFile "/opt/bitnami/apache/conf/certs/${domain}/server.key"
  DocumentRoot ${domain_path}
  <Directory "${domain_path}">
    Options -Indexes +FollowSymLinks -MultiViews
    AllowOverride All
    Require all granted
  </Directory>
  
  # Logging
  ErrorLog "/opt/bitnami/apache/logs/${domain}-ssl-error.log"
  CustomLog "/opt/bitnami/apache/logs/${domain}-ssl-access.log" common
</VirtualHost>
EOF
    
    chmod 644 "$vhost_file"
    print_success "HTTPS virtual host template created: $vhost_file"
}

# Function to enable SSL in HTTPS vhost after certificate installation
enable_ssl_in_vhost() {
    local domain="$1"
    local vhost_file="${APACHE_VHOSTS_DIR}/${domain}-https-vhost.conf"
    
    if [[ ! -f "$vhost_file" ]]; then
        print_error "HTTPS vhost file not found: $vhost_file"
        return 1
    fi
    
    # Check if certificates exist
    local cert_file="/opt/bitnami/apache/conf/certs/${domain}/server.crt"
    local key_file="/opt/bitnami/apache/conf/certs/${domain}/server.key"
    
    if [[ -f "$cert_file" && -f "$key_file" ]]; then
        print_info "Enabling SSL in HTTPS vhost"
        # Replace SSLEngine off with SSLEngine on and uncomment certificate lines
        sed -i 's/^  SSLEngine off$/  SSLEngine on/' "$vhost_file"
        sed -i "s|^  # SSLEngine on$|  SSLEngine on|" "$vhost_file"
        sed -i "s|^  # SSLCertificateFile|  SSLCertificateFile|" "$vhost_file"
        sed -i "s|^  # SSLCertificateKeyFile|  SSLCertificateKeyFile|" "$vhost_file"
        print_success "SSL enabled in HTTPS vhost"
    else
        print_info "SSL certificates not found yet. They will be enabled automatically after installation."
    fi
}

# Function to install SSL certificate
install_ssl() {
    local domain="$1"
    local domain_path="${DOMAIN_DIR}/${domain}"
    local certs_dir="/opt/bitnami/apache/conf/certs/${domain}"
    local letsencrypt_dir="/etc/letsencrypt/live/${domain}"
    
    print_info "Installing SSL certificate for: $domain"
    
    # Check if certbot is available
    if ! command -v certbot >/dev/null 2>&1 && ! command -v /usr/bin/certbot >/dev/null 2>&1; then
        print_error "certbot not found. Installing certbot..."
        print_info "Please install certbot first: sudo apt-get update && sudo apt-get install -y certbot"
        return 1
    fi
    
    # Find certbot executable
    local CERTBOT_CMD=""
    if command -v certbot >/dev/null 2>&1; then
        CERTBOT_CMD="certbot"
    elif [ -f "/usr/bin/certbot" ]; then
        CERTBOT_CMD="/usr/bin/certbot"
    else
        print_error "certbot not found in PATH or /usr/bin/certbot"
        return 1
    fi
    
    # Create webroot directory for ACME challenge
    local webroot_dir="${domain_path}/.well-known/acme-challenge"
    sudo mkdir -p "$webroot_dir"
    sudo chown -R bitnami:daemon "$(dirname "$webroot_dir")"
    
    # Ensure domain HTTP vhost allows .well-known access
    print_info "Running certbot to obtain SSL certificate..."
    print_info "You may be prompted for email address."
    
    # Use certbot with webroot plugin (doesn't modify Apache configs)
    sudo "$CERTBOT_CMD" certonly \
        --webroot \
        --webroot-path="$domain_path" \
        --email "${CERTBOT_EMAIL:-}" \
        --agree-tos \
        --no-eff-email \
        --keep-until-expiring \
        -d "$domain" \
        -d "www.$domain" \
        --non-interactive 2>/dev/null || {
        
        # If non-interactive fails, try interactive
        print_info "Running certbot in interactive mode..."
        sudo "$CERTBOT_CMD" certonly \
            --webroot \
            --webroot-path="$domain_path" \
            -d "$domain" \
            -d "www.$domain" || {
            print_error "SSL certificate installation failed."
            return 1
        }
    }
    
    # Check where certbot placed certificates
    local certbot_cert="${letsencrypt_dir}/fullchain.pem"
    local certbot_key="${letsencrypt_dir}/privkey.pem"
    
    # Alternative location
    if [[ ! -f "$certbot_cert" ]]; then
        certbot_cert="${letsencrypt_dir}/cert.pem"
    fi
    
    if [[ -f "$certbot_cert" && -f "$certbot_key" ]]; then
        # Create certs directory structure
        print_info "Organizing certificates into clean structure..."
        sudo mkdir -p "$certs_dir"
        
        # Copy certificates to our clean structure
        sudo cp "$certbot_cert" "${certs_dir}/server.crt"
        sudo cp "$certbot_key" "${certs_dir}/server.key"
        sudo chmod 644 "${certs_dir}/server.crt"
        sudo chmod 600 "${certs_dir}/server.key"
        
        print_success "Certificates organized in: $certs_dir"
    else
        print_warning "Could not locate certificates from certbot at: $letsencrypt_dir"
        print_info "Checking alternative locations..."
        
        # Try finding certs in other common locations
        local alt_cert="/etc/letsencrypt/live/${domain}/cert.pem"
        local alt_key="/etc/letsencrypt/live/${domain}/privkey.pem"
        
        if [[ -f "$alt_cert" && -f "$alt_key" ]]; then
            sudo mkdir -p "$certs_dir"
            # Combine cert and chain if needed
            if [ -f "/etc/letsencrypt/live/${domain}/fullchain.pem" ]; then
                sudo cp "/etc/letsencrypt/live/${domain}/fullchain.pem" "${certs_dir}/server.crt"
            else
                sudo cp "$alt_cert" "${certs_dir}/server.crt"
            fi
            sudo cp "$alt_key" "${certs_dir}/server.key"
            sudo chmod 644 "${certs_dir}/server.crt"
            sudo chmod 600 "${certs_dir}/server.key"
            print_success "Certificates found and organized in: $certs_dir"
        else
            print_error "Could not locate certificates. Please check certbot output."
            return 1
        fi
    fi
    
    # Enable SSL in vhost after certificate installation
    enable_ssl_in_vhost "$domain"
    
    print_success "SSL certificate installation completed"
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

# Main execution
main() {
    echo ""
    echo "=========================================="
    echo "  Bitnami Domain Setup Script"
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
    
    # Get domain name
    if [[ -z "$1" ]]; then
        read -p "Enter domain name (e.g., example.com): " DOMAIN
    else
        DOMAIN="$1"
    fi
    
    # Validate domain
    if ! validate_domain "$DOMAIN"; then
        exit 1
    fi
    
    # Check if domain already exists
    if ! check_domain_exists "$DOMAIN"; then
        read -p "Do you want to overwrite existing configuration? (y/N): " OVERWRITE
        if [[ ! "$OVERWRITE" =~ ^[Yy]$ ]]; then
            print_info "Operation cancelled"
            exit 1
        fi
    fi
    
    echo ""
    print_info "Setting up domain: $DOMAIN"
    echo ""
    
    # Create domain directory
    create_domain_directory "$DOMAIN"
    
    # Create virtual hosts
    create_http_vhost "$DOMAIN"
    create_https_vhost "$DOMAIN"
    
    # Test Apache configuration
    if ! test_apache_config; then
        print_error "Apache configuration test failed. Please check the errors above."
        exit 1
    fi
    
    # Restart Apache to apply virtual hosts
    restart_apache
    
    echo ""
    print_success "Domain configuration created successfully!"
    echo ""
    print_info "Next steps:"
    echo "  1. Point your domain DNS to this server's IP address"
    echo "  2. Ensure ports 80 and 443 are open in your firewall"
    echo "  3. Install certbot if not already installed:"
    echo "     sudo apt-get update && sudo apt-get install -y certbot"
    echo "  4. Run SSL installation when prompted below"
    echo ""
    print_info "Your domain files are located at: ${DOMAIN_DIR}/${DOMAIN}"
    echo ""
    
    # Ask if user wants to install SSL now
    read -p "Do you want to install SSL certificate now? (y/N): " INSTALL_SSL
    if [[ "$INSTALL_SSL" =~ ^[Yy]$ ]]; then
        echo ""
        print_info "Starting SSL installation..."
        install_ssl "$DOMAIN"
        restart_apache
        echo ""
        print_success "SSL installation completed!"
        echo ""
        print_info "Your domain should now be accessible at: https://$DOMAIN"
    else
        print_info "SSL installation skipped. Run /opt/bitnami/bncert-tool manually when ready."
    fi
    
    echo ""
    print_success "Domain setup completed!"
    echo ""
}

# Run main function
main "$@"

