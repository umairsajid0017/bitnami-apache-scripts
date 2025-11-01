# 🚀 Bitnami Apache Domain Management Scripts

A collection of powerful bash scripts to manage Apache virtual hosts and SSL certificates on Bitnami installations. These scripts provide a clean, automated way to add, remove, and manage domains with proper SSL certificate handling.

![Apache](https://img.shields.io/badge/Apache-2.4-D22128?style=flat&logo=apache)
![Bitnami](https://img.shields.io/badge/Bitnami-Stack-FE8916?style=flat&logo=bitnami)
![Shell Script](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat&logo=gnu-bash)
![License](https://img.shields.io/badge/License-MIT-blue?style=flat)

## 📋 Table of Contents

- [Features](#-features)
- [Prerequisites](#-prerequisites)
- [Installation](#-installation)
- [Scripts Overview](#-scripts-overview)
- [Usage](#-usage)
  - [Adding a Domain](#adding-a-domain)
  - [Removing a Domain](#removing-a-domain)
  - [Cleaning Apache Configuration](#cleaning-apache-configuration)
- [Configuration Structure](#-configuration-structure)
- [Examples](#-examples)
- [Troubleshooting](#-troubleshooting)
- [Contributing](#-contributing)

## ✨ Features

- ✅ **Clean Architecture**: Organized certificate storage and vhost configuration
- ✅ **Subdomain Support**: Handle both main domains and subdomains seamlessly
- ✅ **SSL Certificate Management**: Automated Let's Encrypt certificate installation via certbot
- ✅ **No Config Overwrites**: Uses certbot webroot method (doesn't modify main Apache configs)
- ✅ **Automatic HTTPS Redirect**: HTTP traffic automatically redirects to HTTPS
- ✅ **Bulk Operations**: Clean all domains at once with a single command
- ✅ **Safety First**: Validation, confirmation prompts, and configuration testing
- ✅ **Bitnami Compatible**: Uses Bitnami's official control scripts for service management

## 📦 Prerequisites

- Bitnami LAMP/LEMP stack installation
- `sudo` or `root` access
- Domain DNS pointing to your server
- Ports 80 and 443 open in firewall
- `certbot` installed (for SSL certificates)

### Installing Certbot

```bash
sudo apt-get update
sudo apt-get install -y certbot
```

## 🛠️ Installation

1. Clone or download this repository:
```bash
cd /home/bitnami
git clone <repository-url> bitnami-apache-scripts
cd bitnami-apache-scripts
```

2. Make scripts executable:
```bash
chmod +x *.sh
```

## 📜 Scripts Overview

### 1. `add_domain.sh` - Add Domain Configuration

Creates Apache virtual hosts for a new domain, sets up directory structure, and optionally installs SSL certificates.

**Features:**
- Creates domain directory with default index.html
- Sets up HTTP virtual host (redirects to HTTPS)
- Sets up HTTPS virtual host template
- Optional SSL certificate installation via certbot
- Supports both main domains and subdomains
- Smart www alias handling (only for main domains)

### 2. `remove_domain.sh` - Remove Domain Configuration

Removes domain virtual hosts and optionally cleans up domain files and SSL certificates.

**Features:**
- Removes HTTP and HTTPS virtual hosts
- Optional domain directory removal
- Optional SSL certificate cleanup
- Apache configuration validation
- Safe removal with confirmation prompts

### 3. `clean_apache.sh` - Clean Apache Configuration

Completely cleans Apache configuration to default state while preserving domain storage.

**Features:**
- Removes ALL domain virtual hosts
- Cleans certificate symlinks
- Removes certificate directories
- Removes backup files
- Restores clean default configs
- Keeps domain storage directories intact

## 🚀 Usage

### Adding a Domain

#### Basic Usage
```bash
sudo ./add_domain.sh example.com
```

#### With SSL Installation
```bash
sudo ./add_domain.sh example.com
# When prompted: "Do you want to install SSL certificate now? (y/N):" type 'y'
```

#### Adding a Subdomain
```bash
sudo ./add_domain.sh api.example.com
# Subdomains won't get www alias automatically
```

#### Interactive Mode
```bash
sudo ./add_domain.sh
# Script will prompt for domain name
```

**What it does:**
1. Validates domain format
2. Creates domain directory at `/home/bitnami/domain.com/`
3. Creates HTTP vhost (redirects to HTTPS)
4. Creates HTTPS vhost template (SSL disabled initially)
5. Tests Apache configuration
6. Restarts Apache
7. Optionally installs SSL certificate

### Removing a Domain

#### Basic Usage
```bash
sudo ./remove_domain.sh example.com
```

#### Interactive Mode
```bash
sudo ./remove_domain.sh
# Script will prompt for domain name
```

**What it does:**
1. Validates domain format
2. Confirms removal
3. Removes HTTP and HTTPS virtual hosts
4. Tests Apache configuration
5. Restarts Apache
6. Optionally removes domain directory
7. Optionally removes SSL certificates

### Cleaning Apache Configuration

Reset Apache to clean default state (removes all domains):

```bash
sudo ./clean_apache.sh
```

**What it does:**
1. Confirms action (destructive operation)
2. Removes ALL domain virtual hosts
3. Removes certificate symlinks
4. Removes certificate directories
5. Removes backup files
6. Restores clean `bitnami.conf` and `bitnami-ssl.conf`
7. Tests and restarts Apache

## 📁 Configuration Structure

After running the scripts, your Apache configuration will be organized as follows:

```
/opt/bitnami/apache/conf/
├── bitnami/
│   ├── bitnami.conf          # Clean default port 80 vhost
│   └── bitnami-ssl.conf      # SSL module config only (no default SSL vhost)
├── certs/                     # Organized certificate storage
│   └── domain.com/
│       ├── server.crt         # SSL certificate
│       └── server.key         # SSL private key
└── vhosts/                    # Domain-specific configurations
    ├── domain.com-vhost.conf          # HTTP redirect vhost
    ├── domain.com-https-vhost.conf    # HTTPS vhost
    ├── api.example.com-vhost.conf    # Subdomain HTTP vhost
    └── api.example.com-https-vhost.conf  # Subdomain HTTPS vhost
```

**Domain Storage:**
```
/home/bitnami/
├── example.com/               # Main domain files
├── api.example.com/           # Subdomain files
└── ...
```

## 💡 Examples

### Example 1: Add Main Domain with SSL

```bash
# Add domain
sudo ./add_domain.sh mysite.com

# When prompted for SSL installation, type 'y'
# Certbot will request certificate for both mysite.com and www.mysite.com
```

### Example 2: Add API Subdomain

```bash
# Add API subdomain (no www alias will be added)
sudo ./add_domain.sh api.mysite.com
```

### Example 3: Add Multiple Domains

```bash
sudo ./add_domain.sh site1.com
sudo ./add_domain.sh site2.com
sudo ./add_domain.sh mail.site1.com  # Subdomain
```

### Example 4: Remove Domain but Keep Files

```bash
sudo ./remove_domain.sh olddomain.com
# When prompted to delete directory, type 'N' to keep files
```

### Example 5: Complete Cleanup

```bash
# Remove all domains and reset to default
sudo ./clean_apache.sh
# Domain storage directories remain intact
```

## 🔧 Troubleshooting

### Apache Configuration Test Fails

If you see configuration errors:
```bash
# Test Apache configuration manually
sudo /opt/bitnami/apache/bin/apachectl configtest

# Check for specific errors in the output
```

### Certbot Installation Fails

**Issue:** `certbot not found`

**Solution:**
```bash
sudo apt-get update
sudo apt-get install -y certbot
```

### Certificate Not Found After Installation

**Issue:** Script can't locate certificates

**Solution:**
- Check if certificates exist: `ls -la /etc/letsencrypt/live/yourdomain.com/`
- Manually copy certificates to: `/opt/bitnami/apache/conf/certs/yourdomain.com/`
- Ensure files are named `server.crt` and `server.key`

### Domain Not Accessible

**Checklist:**
1. DNS points to server IP: `dig yourdomain.com`
2. Ports 80 and 443 are open: `sudo ufw status`
3. Apache is running: `sudo /opt/bitnami/ctlscript.sh status apache`
4. Virtual host files exist: `ls /opt/bitnami/apache/conf/vhosts/`

### Permission Issues

**Issue:** Script requires sudo

**Solution:**
Always run scripts with sudo:
```bash
sudo ./add_domain.sh example.com
```

## 📝 Notes

- **Main Domains**: Scripts automatically add `www` alias for main domains (e.g., `example.com` → `www.example.com`)
- **Subdomains**: No `www` alias is added for subdomains (e.g., `api.example.com`)
- **SSL Certificates**: Uses Let's Encrypt via certbot with webroot method
- **Configuration Safety**: Main Apache configs (`bitnami.conf`, `bitnami-ssl.conf`) are never overwritten
- **Domain Storage**: Domain files are preserved unless explicitly deleted

## 🎯 Best Practices

1. **Always test configuration** after making changes
2. **Backup before cleanup** if you want to restore later
3. **Use descriptive domain names** in your DNS records
4. **Keep certificates organized** in the `/opt/bitnami/apache/conf/certs/` structure
5. **Monitor certificate expiration** and renew as needed

## 🔄 Certificate Renewal

Certificates are managed by certbot. To renew manually:

```bash
sudo certbot renew
sudo /opt/bitnami/ctlscript.sh restart apache
```

Or set up automatic renewal via cron:
```bash
# Add to crontab
0 0 * * * certbot renew --quiet && /opt/bitnami/ctlscript.sh restart apache
```

## 📄 License

This project is open source and available under the [MIT License](LICENSE).

## 🤝 Contributing

Contributions, issues, and feature requests are welcome! Feel free to check the [issues page](https://github.com/yourusername/bitnami-apache-scripts/issues).

## 🙏 Acknowledgments

- Built for Bitnami LAMP/LEMP stacks
- Uses Let's Encrypt for SSL certificates
- Apache HTTP Server configuration management

---

**Made with ❤️ for Bitnami users**

*For questions or issues, please open an issue on GitHub.*

