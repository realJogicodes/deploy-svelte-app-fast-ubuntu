#!/bin/bash

# Exit on error
set -e

# Function to handle errors
handle_error() {
    echo "Error occurred in script at line: $1"
    exit 1
}

trap 'handle_error $LINENO' ERR

# Function to get system architecture
get_arch() {
    local arch=$(uname -m)
    case $arch in
        x86_64)
            echo "linux_amd64"
            ;;
        aarch64|arm64)
            echo "linux_arm64"
            ;;
        *)
            echo "Unsupported architecture: $arch"
            exit 1
            ;;
    esac
}

# Function to validate domain name format
validate_domain() {
    if [[ $1 =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to convert HTTPS GitHub URL to SSH format
convert_github_url() {
    local url=$1
    # Check if already SSH format
    if [[ $url == git@github.com:* ]]; then
        echo "$url"
        return 0
    fi
    # Convert HTTPS to SSH format
    if [[ $url =~ ^https://github.com/(.+/.+)/?$ ]]; then
        echo "git@github.com:${BASH_REMATCH[1]}.git"
        return 0
    fi
    # Invalid format
    return 1
}

# Load configuration
USERNAME=$USER
HOSTNAME=$(hostname)

# Get GitHub info
while true; do
    read -p "Enter your GitHub repository URL (HTTPS or SSH format): " GITHUB_REPO
    if [[ -z "$GITHUB_REPO" ]]; then
        echo "GitHub repository URL cannot be empty"
        continue
    fi
    
    GITHUB_REPO=$(convert_github_url "$GITHUB_REPO")
    if [ $? -eq 0 ]; then
        echo "Using repository URL: $GITHUB_REPO"
        break
    else
        echo "Invalid GitHub URL format. Please enter a valid GitHub repository URL"
        echo "Examples:"
        echo "  HTTPS: https://github.com/username/repository"
        echo "  SSH: git@github.com:username/repository.git"
    fi
done

read -p "Enter your GitHub email: " GITHUB_EMAIL
while [[ -z "$GITHUB_EMAIL" ]]; do
    echo "GitHub email cannot be empty"
    read -p "Enter your GitHub email: " GITHUB_EMAIL
done

# Get domain and verify DNS configuration
read -p "Enter your domain (e.g., example.com): " DOMAIN
while ! validate_domain "$DOMAIN"; do
    echo "Invalid domain format. Please enter a valid domain (e.g., example.com)"
    read -p "Enter your domain: " DOMAIN
done

# Get server's IP address from the network interface
PUBLIC_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n 1)
if [ -z "$PUBLIC_IP" ]; then
    # Fallback to hostname -I if ip command fails
    PUBLIC_IP=$(hostname -I | awk '{print $1}')
fi
if [ -z "$PUBLIC_IP" ]; then
    echo "Failed to detect server IP address"
    exit 1
fi

# Ask about DNS configuration
while true; do
    read -p "Is your domain ($DOMAIN) properly configured to point to this server ($PUBLIC_IP)? (yes/no): " DNS_CONFIGURED
    case $DNS_CONFIGURED in
        [Yy]* ) 
            USE_DOMAIN=true
            break
            ;;
        [Nn]* ) 
            USE_DOMAIN=false
            break
            ;;
        * ) echo "Please answer yes or no.";;
    esac
done

# Install NVM and Node.js
echo "Installing Node.js..."
wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
nvm install 22.12.0 || {
    echo "Failed to install Node.js"
    exit 1
}

# Create app directory
echo "Setting up application directory..."
mkdir -p ~/app

# Generate GitHub SSH key
echo "Generating GitHub SSH key..."
ssh-keygen -t ed25519 -C "$GITHUB_EMAIL" -f "$HOME/.ssh/github" -N ""
echo ""
echo "Here's your GitHub SSH key. Add this to your GitHub account settings at:"
echo "https://github.com/settings/ssh/new"
echo ""
cat "$HOME/.ssh/github.pub"

# Configure SSH for GitHub
cat > "$HOME/.ssh/config" << EOF
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/github
EOF

# Wait for user to add key to GitHub
read -p "Press Enter after you've added the SSH key to your GitHub account..."

# Clone and set up the web application
echo "Cloning and setting up the web application..."
cd ~/app && git clone $GITHUB_REPO frontend || {
    echo "Failed to clone repository"
    exit 1
}

# Create .env file with placeholders
echo "Creating .env file with placeholder values..."
cat > ~/app/frontend/.env << EOF
PRIVATE_RESEND_API_KEY="re_placeholder_resend_api_key"
PUBLIC_STRIPE_PUBLIC_KEY="pk_test_placeholder_stripe_public"
PRIVATE_STRIPE_SECRET_KEY="sk_test_placeholder_stripe_secret"
PRIVATE_PB_ADMIN_EMAIL="admin@example.com"
PRIVATE_PB_ADMIN_PASSWORD="placeholder_password"
PRIVATE_STRIPE_WEBHOOK_SECRET="whsec_placeholder_webhook_secret"
PRIVATE_RESEND_AUDIENCE_ID="aud_placeholder_audience_id"
EOF

echo "Building application..."
# Create temporary swap for build
echo "Creating temporary swap file for build process..."
sudo fallocate -l 4G /swapfile_build || {
    echo "Failed to create swap file using fallocate, trying dd..."
    sudo dd if=/dev/zero of=/swapfile_build bs=1M count=4096
}
sudo chmod 600 /swapfile_build
sudo mkswap /swapfile_build
sudo swapon /swapfile_build

# Aggressive memory cleanup before build
sync
echo 3 | sudo tee /proc/sys/vm/drop_caches
# Kill any existing node processes
pkill node || true
# Clear npm cache
npm cache clean --force
# Remove previous builds and dependencies
cd ~/app/frontend
rm -rf build .svelte-kit node_modules/.cache node_modules/.vite node_modules

# Install pnpm
curl -fsSL https://get.pnpm.io/install.sh | sh -

# Source the updated PATH immediately
export PNPM_HOME="/home/$USER/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac

# Use pnpm for installation and build with optimized settings
cd ~/app/frontend && \
export NODE_OPTIONS="--max-old-space-size=2048" && \
$PNPM_HOME/pnpm install --force && \
NODE_ENV=production $PNPM_HOME/pnpm run build || {
    echo "Failed to build application"
    exit 1
}

# Clean up dev dependencies after build
$PNPM_HOME/pnpm prune --production

# Remove temporary swap
sudo swapoff /swapfile_build
sudo rm /swapfile_build


# Install Pocketbase
echo "Installing Pocketbase..."
mkdir -p ~/app/pocketbase
cd ~/app/pocketbase

ARCH=$(get_arch)
POCKETBASE_URL="https://github.com/pocketbase/pocketbase/releases/download/v0.23.8/pocketbase_0.23.8_${ARCH}.zip"

wget "$POCKETBASE_URL" || {
    echo "Failed to download Pocketbase"
    exit 1
}
unzip "pocketbase_0.23.8_${ARCH}.zip"
rm "pocketbase_0.23.8_${ARCH}.zip"
chmod +x ~/app/pocketbase/pocketbase

# Create PocketBase service
echo "Configuring Pocketbase service..."
sudo mkdir -p /var/log/pocketbase
sudo touch /var/log/pocketbase/std.log
sudo chown -R $USER:$USER /var/log/pocketbase

sudo bash -c "cat > /etc/systemd/system/pocketbase.service << EOF
[Unit]
Description = pocketbase

[Service]
Type           = simple
User           = $USER
Group          = $USER
LimitNOFILE    = 4096
Restart        = always
RestartSec     = 5s
StandardOutput = append:/var/log/pocketbase/std.log
StandardError  = append:/var/log/pocketbase/std.log
ExecStart      = $HOME/app/pocketbase/pocketbase serve 

[Install]
WantedBy = multi-user.target
EOF"

sudo systemctl enable pocketbase
sudo systemctl start pocketbase || {
    echo "Failed to start Pocketbase"
    exit 1
}

# Install and configure PM2
echo "Installing PM2..."
npm install pm2 -g || {
    echo "Failed to install PM2"
    exit 1
}

# Configure PM2 startup
echo "Configuring PM2 startup..."
NODE_PATH=$(which node)
PM2_PATH=$(which pm2)
sudo env PATH=$PATH:$(dirname $NODE_PATH) $PM2_PATH startup systemd -u $USERNAME --hp $HOME || {
    echo "Failed to setup PM2 startup"
    exit 1
}

# Start the web application with PM2
echo "Starting application with PM2..."
cd ~/app/frontend && pm2 start npm --name 'webapp' -- start || {
    echo "Failed to start application"
    exit 1
}

# Save PM2 process list
pm2 save

# Install Caddy
echo "Installing Caddy..."
sudo apt-get update
sudo apt-get install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt-get update
sudo apt-get install -y caddy

# Configure Caddy
echo "Configuring Caddy..."
if [ "$USE_DOMAIN" = true ]; then
    # Use domain-based configuration with automatic HTTPS
    sudo tee /etc/caddy/Caddyfile > /dev/null << EOF
# Main application
$DOMAIN {
    reverse_proxy localhost:3000
}

# PocketBase instance
pb.$DOMAIN {
    reverse_proxy localhost:8090
}
EOF
else
    # Use IP-based configuration with self-signed certificates
    sudo tee /etc/caddy/Caddyfile > /dev/null << EOF
{
    # Use self-signed certificates for IP address
    auto_https disable_redirects
}

# Main application and PocketBase
$PUBLIC_IP {
    tls internal

    handle /pb/* {
        uri strip_prefix /pb
        reverse_proxy localhost:8090
    }

    handle /* {
        reverse_proxy localhost:3000
    }
}
EOF
fi

# Update Caddy service
sudo systemctl stop caddy
sudo tee /etc/systemd/system/caddy.service << EOF
[Unit]
Description=Caddy web server
Documentation=https://caddyserver.com/docs/
After=network.target network-online.target
Requires=network-online.target

[Service]
Type=notify
User=caddy
Group=caddy
ExecStart=/usr/bin/caddy run --environ --config /etc/caddy/Caddyfile
ExecReload=/usr/bin/caddy reload --config /etc/caddy/Caddyfile
TimeoutStopSec=5s
LimitNOFILE=1048576
LimitNPROC=512
PrivateDevices=yes
PrivateTmp=true
ProtectSystem=full
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and restart Caddy
sudo systemctl daemon-reload
sudo systemctl restart caddy

echo "User setup complete! Your development environment is ready."
echo "Your applications are available at:"
if [ "$USE_DOMAIN" = true ]; then
    echo "- Main application: https://$DOMAIN"
    echo "- PocketBase admin: https://pb.$DOMAIN/_"
else
    echo "- Main application: https://$PUBLIC_IP"
    echo "- PocketBase admin: https://$PUBLIC_IP/pb/_"
    echo "Note: When using IP address, you'll see certificate warnings because it's using self-signed certificates."
fi
echo ""
echo "Next steps:"
echo "1. Set up your domain DNS records to point to this server"

# load bashrc at the end
[ -f ~/.bashrc ] && source ~/.bashrc
