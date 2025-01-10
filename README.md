# Svelte App Fast - Deployment Scripts for Hosting on Ubuntu VPS

This repository contains two essential scripts for setting up a production environment for [Svelte App Fast](https://svelteappfast.com) based applications on Ubuntu 24.04 LTS VPS servers. These scripts automate the complete server setup process, from initial security configuration to application deployment.

## Repository

```bash
git clone https://github.com/realJogicodes/deploy-svelte-app-fast-ubunutu.git
```

Visit the [GitHub Repository](https://github.com/realJogicodes/deploy-svelte-app-fast-ubunutu) for the latest updates and to contribute.

## Scripts Overview

### 1. `secure-ubuntu-setup.sh` (formerly 1_root_setup.sh)

This script handles the initial server security setup and must be run as root. It performs the following tasks:

- Validates Ubuntu 24.04 LTS environment
- Creates a non-root user with sudo privileges
- Configures SSH security (custom port, key-based authentication)
- Sets up firewall (UFW) with essential ports
- Configures system hostname
- Sets up swap space for better performance
- Implements security best practices

### 2. `setup-svelte-environment.sh` (formerly 2_user_setup.sh)

This script sets up the application environment and should be run as the non-root user created by the first script. It handles:

- Node.js installation via NVM (v22.12.0)
- GitHub SSH key generation and configuration
- Application directory structure setup
- PNPM package manager installation
- PocketBase backend setup
- PM2 process manager configuration
- Caddy web server installation and configuration
- Automatic HTTPS with Let's Encrypt
- Development environment configuration

## Prerequisites

- Ubuntu 24.04 LTS VPS
- Root access to the server
- Domain name (optional but recommended)
- GitHub repository with your Svelte application

## Installation

1. First, connect to your VPS as root and download the first setup script:

```bash
wget https://raw.githubusercontent.com/realJogicodes/deploy-svelte-app-fast-ubunutu/main/secure-ubuntu-setup.sh
```

2. Make the script executable:

```bash
chmod +x secure-ubuntu-setup.sh
```

3. Run the first script as root:

```bash
./secure-ubuntu-setup.sh
```

4. After the first script completes, log out and log back in as the new user created during setup.

5. Download the second setup script:

```bash
wget https://raw.githubusercontent.com/realJogicodes/deploy-svelte-app-fast-ubunutu/main/setup-svelte-environment.sh
```

6. Make the second script executable:

```bash
chmod +x setup-svelte-environment.sh
```

7. Run the second script as the new user:

```bash
./setup-svelte-environment.sh
```

## What the Scripts Configure

### Security Setup (secure-ubuntu-setup.sh)

- Creates a non-root user with sudo privileges
- Configures SSH with:
  - Custom port option
  - Key-based authentication
  - Root login disabled
  - Password authentication disabled
- Sets up UFW firewall:
  - Allows SSH (custom or default port)
  - Allows HTTP (80)
  - Allows HTTPS (443)
- Configures 4GB swap space (needed for avoiding out of memory errors on entry level servers.)
- Sets system hostname

### Environment Setup (setup-svelte-environment.sh)

- Installs development tools:
  - Node.js 22.12.0 (via NVM)
  - PNPM package manager
  - PM2 process manager
- Sets up application structure:
  - Creates ~/app directory
  - Configures GitHub SSH access
  - Clones your application repository
- Installs and configures:
  - PocketBase (latest version)
  - Caddy web server with automatic HTTPS
- Creates necessary service files:
  - PocketBase systemd service
  - PM2 startup configuration
  - Caddy server configuration

## Configuration Options

During setup, you'll be prompted for:

- Username for the non-root user
- SSH public key for secure access
- Custom SSH port (optional)
- GitHub repository URL
- Domain name (optional)
- GitHub email for SSH key generation

## Post-Installation

After running both scripts, you'll have:

1. A secure Ubuntu server with:

   - Non-root user access
   - SSH key authentication
   - Active firewall

2. A complete development environment with:
   - Running Svelte application
   - PocketBase backend
   - Automatic HTTPS via Caddy
   - Process management via PM2

## Notes

- The scripts are specifically designed for Ubuntu 24.04 LTS
- Domain setup is optional but recommended for production use
- All services are configured to start automatically on system boot
- Logs are available in:
  - PocketBase: `/var/log/pocketbase/std.log`
  - PM2: `pm2 logs`
  - Caddy: System journal

## Security Considerations

- SSH password authentication is disabled by default
- Root login is disabled
- Custom SSH port option for additional security
- UFW firewall is configured with minimal required ports
- All services run under non-root user
- Automatic HTTPS certificates via Let's Encrypt

## Troubleshooting

If you encounter issues:

1. Check the logs:

   ```bash
   # PocketBase logs
   tail -f /var/log/pocketbase/std.log

   # PM2 logs
   pm2 logs

   # Caddy logs
   sudo journalctl -u caddy
   ```

2. Verify services are running:

   ```bash
   # Check PocketBase
   sudo systemctl status pocketbase

   # Check PM2 processes
   pm2 status

   # Check Caddy
   sudo systemctl status caddy
   ```

## Contributing

Feel free to submit issues and enhancement requests!
