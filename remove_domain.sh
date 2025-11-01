#!/bin/bash

###############################################################################
# Bitnami Domain Removal Script
# This script removes a domain configuration and optionally its directory
#
# Usage:
#   sudo ./remove_domain.sh [domain.com]
#
# Example:
#   sudo ./remove_domain.sh example.com
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

# Function to validate domain format (supports domains and subdomains)
validate_domain() {
    local domain="$1"
    # Allow domains like: example.com, subdomain.example.com, www.subdomain.example.com, etc.
    # Pattern: allows multiple labels separated by dots, each label 1-63 chars
    if [[ ! "$domain" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
        print_error "Invalid domain format: $domain"
        print_info "Valid examples: example.com, subdomain.example.com, www.example.com"
        return 1
    fi
    return 0
}

# Function to check if domain configuration exists
check_domain_exists() {
    local domain="$1"
    local http_vhost="${APACHE_VHOSTS_DIR}/${domain}-vhost.conf"
    local https_vhost="${APACHE_VHOSTS_DIR}/${domain}-https-vhost.conf"
    
    if [[ -f "$http_vhost" ]] || [[ -f "$https_vhost" ]]; then
        return 0
    else
        print_error "Domain configuration not found for: $domain"
        return 1
    fi
}

# Function to remove HTTP virtual host
remove_http_vhost() {
    local domain="$1"
    local vhost_file="${APACHE_VHOSTS_DIR}/${domain}-vhost.conf"
    
    if [[ -f "$vhost_file" ]]; then
        print_info "Removing HTTP virtual host: $vhost_file"
        sudo rm -f "$vhost_file"
        print_success "HTTP virtual host removed"
    else
        print_info "HTTP virtual host not found (may not exist)"
    fi
}

# Function to remove HTTPS virtual host
remove_https_vhost() {
    local domain="$1"
    local vhost_file="${APACHE_VHOSTS_DIR}/${domain}-https-vhost.conf"
    
    if [[ -f "$vhost_file" ]]; then
        print_info "Removing HTTPS virtual host: $vhost_file"
        sudo rm -f "$vhost_file"
        print_success "HTTPS virtual host removed"
    else
        print_info "HTTPS virtual host not found (may not exist)"
    fi
}

# Function to remove domain directory
remove_domain_directory() {
    local domain="$1"
    local domain_path="${DOMAIN_DIR}/${domain}"
    
    if [[ -d "$domain_path" ]]; then
        print_warning "Domain directory exists: $domain_path"
        read -p "Do you want to delete the domain directory and all its contents? (y/N): " DELETE_DIR
        if [[ "$DELETE_DIR" =~ ^[Yy]$ ]]; then
            print_info "Removing domain directory: $domain_path"
            rm -rf "$domain_path"
            print_success "Domain directory removed"
        else
            print_info "Domain directory kept: $domain_path"
        fi
    else
        print_info "Domain directory not found (may not exist)"
    fi
}

# Function to remove SSL certificates (optional)
remove_ssl_certificates() {
    local domain="$1"
    local cert_dir="/opt/bitnami/apache/conf/certs/${domain}"
    local old_cert_dir="/opt/bitnami/apache/conf/bitnami/certs/${domain}"
    
    # Check new location first
    if [[ -d "$cert_dir" ]]; then
        print_warning "SSL certificate directory exists: $cert_dir"
        read -p "Do you want to delete the SSL certificates? (y/N): " DELETE_CERTS
        if [[ "$DELETE_CERTS" =~ ^[Yy]$ ]]; then
            print_info "Removing SSL certificate directory: $cert_dir"
            sudo rm -rf "$cert_dir"
            print_success "SSL certificates removed"
        else
            print_info "SSL certificates kept: $cert_dir"
        fi
    # Also check old location for backwards compatibility
    elif [[ -d "$old_cert_dir" ]]; then
        print_warning "SSL certificate directory exists (old location): $old_cert_dir"
        read -p "Do you want to delete the SSL certificates? (y/N): " DELETE_CERTS
        if [[ "$DELETE_CERTS" =~ ^[Yy]$ ]]; then
            print_info "Removing SSL certificate directory: $old_cert_dir"
            sudo rm -rf "$old_cert_dir"
            print_success "SSL certificates removed"
        else
            print_info "SSL certificates kept: $old_cert_dir"
        fi
    else
        print_info "SSL certificate directory not found (may not exist)"
    fi
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

# Main execution
main() {
    echo ""
    echo "=========================================="
    echo "  Bitnami Domain Removal Script"
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
        read -p "Enter domain name to remove (e.g., example.com): " DOMAIN
    else
        DOMAIN="$1"
    fi
    
    # Validate domain
    if ! validate_domain "$DOMAIN"; then
        exit 1
    fi
    
    # Check if domain configuration exists
    if ! check_domain_exists "$DOMAIN"; then
        exit 1
    fi
    
    echo ""
    print_warning "You are about to remove domain: $DOMAIN"
    read -p "Are you sure you want to continue? (y/N): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        print_info "Operation cancelled"
        exit 0
    fi
    
    echo ""
    print_info "Removing domain configuration: $DOMAIN"
    echo ""
    
    # Remove virtual hosts
    remove_http_vhost "$DOMAIN"
    remove_https_vhost "$DOMAIN"
    
    # Test Apache configuration
    if ! test_apache_config; then
        print_error "Apache configuration test failed. Please check the errors above."
        exit 1
    fi
    
    # Restart Apache to apply changes
    restart_apache
    
    echo ""
    print_success "Domain configuration removed successfully!"
    echo ""
    
    # Optionally remove domain directory
    remove_domain_directory "$DOMAIN"
    
    # Optionally remove SSL certificates
    remove_ssl_certificates "$DOMAIN"
    
    echo ""
    print_success "Domain removal completed!"
    echo ""
}

# Run main function
main "$@"


