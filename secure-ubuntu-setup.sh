#!/bin/bash

echo "This script will set up your server for running a SvelteAppFast based web application."
echo "To proceed, please hit return, to cancel hit ctrl+c"
read    

ensure_ubuntu_24_04_lts() {
    if ! grep -q "Ubuntu" /etc/os-release || ! grep -q "24.04" /etc/os-release; then
        echo "This script is written for use with Ubuntu 24.04 LTS."
        echo "Current system:"
        cat /etc/os-release | grep "PRETTY_NAME"
        exit 1
    fi
}

ensure_ubuntu_24_04_lts

# Exit on error
set -e

# Function to handle errors
handle_error() {
    echo "Error occurred in script at line: $1"
    exit 1
}

trap 'handle_error $LINENO' ERR

# Function to validate username format
validate_username() {
    if [[ $1 =~ ^[a-z][a-z0-9_]{1,31}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to validate SSH key
validate_ssh_key() {
    if [[ $1 =~ ^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521)[[:space:]] ]]; then
        return 0
    else
        return 1
    fi
}

# Function to generate random SSH port
generate_ssh_port() {
    echo $(shuf -i 1024-65535 -n 1)
}

# Function to validate hostname format
validate_hostname() {
    if [[ $1 =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]]; then
        return 0
    else
        return 1
    fi
}

# Collect user input
echo "Welcome to the server setup script!"
echo "-------------------------------------------------"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root"
    exit 1
fi

# Get username
while true; do
    read -p "Enter the username for the server (lowercase letters, numbers, and underscores only): " USERNAME
    if [[ -z "$USERNAME" ]]; then
        echo "Username cannot be empty"
    elif ! validate_username "$USERNAME"; then
        echo "Invalid username format. Username must:"
        echo "- Start with a lowercase letter"
        echo "- Contain only lowercase letters, numbers, and underscores"
        echo "- Be between 2 and 32 characters long"
    else
        break
    fi
done

# Get hostname
while true; do
    read -p "Enter the hostname for this server (letters, numbers, and hyphens only): " HOSTNAME
    if [[ -z "$HOSTNAME" ]]; then
        echo "Hostname cannot be empty"
    elif ! validate_hostname "$HOSTNAME"; then
        echo "Invalid hostname format. Hostname must:"
        echo "- Start and end with a letter or number"
        echo "- Contain only letters, numbers, and hyphens"
        echo "- Not exceed 63 characters"
    else
        break
    fi
done

# Set system hostname
echo "Setting system hostname to: $HOSTNAME"
hostnamectl set-hostname "$HOSTNAME"
echo "127.0.0.1 $HOSTNAME" >> /etc/hosts

# Instructions for SSH key
echo "
To get your SSH public key, follow these steps:
1. Open terminal on your local machine
2. Run: cat ~/.ssh/id_rsa.pub
3. If you don't have an SSH key, generate one using: ssh-keygen -t rsa -b 4096
4. Copy the entire content of the public key
"
while true; do
    read -p "Enter your SSH public key: " SSH_KEY
    if [[ -z "$SSH_KEY" ]]; then
        echo "SSH key cannot be empty"
    elif ! validate_ssh_key "$SSH_KEY"; then
        echo "Invalid SSH key format. The key should start with 'ssh-rsa', 'ssh-ed25519', or similar."
        echo "Please make sure you've copied the entire key correctly."
    else
        break
    fi
done

# Ask about SSH port
read -p "Would you like to use a random SSH port instead of the default port 22? (y/n): " CHANGE_SSH_PORT
if [[ "${CHANGE_SSH_PORT,,}" == "y" ]]; then
    SSH_PORT=$(generate_ssh_port)
    echo "Generated random SSH port: $SSH_PORT"
else
    SSH_PORT=22
    echo "Using default SSH port: 22"
fi

# Update system
echo "Updating system packages..."
apt update && apt upgrade -y

# Setup swap file
echo "Setting up swap file..."
if [ ! -f /swapfile ]; then
    dd if=/dev/zero of=/swapfile bs=1M count=4096 || {
        echo "Failed to create swap file"
        exit 1
    }
    chmod 600 /swapfile || {
        echo "Failed to set swap file permissions"
        exit 1
    }
    mkswap /swapfile || {
        echo "Failed to set up swap file"
        exit 1
    }
    swapon /swapfile || {
        echo "Failed to enable swap file"
        exit 1
    }
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    echo "Swap file created and enabled"
    free -h
fi

# Install required packages
echo "Installing required packages..."
apt install -y unzip

# Create user and add to sudo group
echo "Creating user $USERNAME..."
useradd -m -s /bin/bash "$USERNAME"
usermod -aG sudo "$USERNAME"

# Set up password for the user
while true; do
    echo "Please set a password for user $USERNAME"
    if passwd "$USERNAME"; then
        break
    else
        echo "Password setup failed. Please try again."
    fi
done

echo "$USERNAME ALL=(ALL) ALL" >> /etc/sudoers.d/$USERNAME

# Setup SSH
echo "Configuring SSH..."

# Backup original sshd_config
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

# Configure SSH settings
# Set custom port if requested
if [ "$SSH_PORT" != "22" ]; then
    sed -i "s/^#Port 22/Port $SSH_PORT/" /etc/ssh/sshd_config
fi

# Disable root login and password authentication
sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

mkdir -p /home/$USERNAME/.ssh
echo "$SSH_KEY" > /home/$USERNAME/.ssh/authorized_keys
chmod 700 /home/$USERNAME/.ssh
chmod 600 /home/$USERNAME/.ssh/authorized_keys
chown -R $USERNAME:$USERNAME /home/$USERNAME/.ssh

# Test the SSH configuration
echo "Testing SSH configuration..."
if sshd -t; then
    echo "SSH configuration is valid"
    systemctl reload ssh || systemctl reload sshd || {
        echo "Warning: Could not reload SSH service. You may need to restart it manually after checking the configuration."
        echo "The current SSH session will remain active."
    }
else
    echo "Error: SSH configuration test failed. Restoring backup..."
    cp /etc/ssh/sshd_config.backup /etc/ssh/sshd_config
    exit 1
fi

# Install and configure UFW
echo "Configuring firewall..."
apt install ufw -y
ufw default deny incoming
ufw default allow outgoing

if [ "$SSH_PORT" != "22" ]; then
    ufw allow 22/tcp
    echo "
IMPORTANT: New SSH port ($SSH_PORT) will be enabled after system reboot.
1. After reboot, the new port will be active
2. Test SSH access on new port: ssh $USERNAME@$HOSTNAME -p $SSH_PORT
3. Once confirmed working, run: sudo ufw delete allow 22/tcp
"
else
    ufw allow 22/tcp
fi

# Add the new port to a delayed configuration
if [ "$SSH_PORT" != "22" ]; then
    echo "ufw allow $SSH_PORT/tcp" > /root/enable_ssh_port.sh
    chmod +x /root/enable_ssh_port.sh
    
    cat > /etc/systemd/system/enable-ssh-port.service << EOF
[Unit]
Description=Enable new SSH port in UFW
After=network.target

[Service]
Type=oneshot
ExecStart=/root/enable_ssh_port.sh
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl enable enable-ssh-port.service
fi

ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

echo "Root setup of your server is now complete! For the second step you need to log out and log back in again."

echo "You need to log out and log back in again to finish the setup. To log out, run:"
echo "exit"

# Get server IP address
SERVER_IP=$(hostname -I | awk '{print $1}')
if [ -z "$SERVER_IP" ]; then
    echo "Warning: Could not detect server IP address."
    echo "To log back in again, run the following command:"
    echo "ssh $USERNAME@your_server_ip -p $SSH_PORT"
    exit 1
fi

echo "To log back in again, run the following command:"
echo "ssh $USERNAME@$SERVER_IP -p $SSH_PORT"
