#!/bin/bash

# Unbound Management Script
CONFIG_PATH="/etc/unbound/unbound.conf.d/custom.conf"
RESOLV_PATH="/etc/resolv.conf"
HOSTNAME_DEFAULT="server"  # Set default hostname

# Function: Set Hostname and configure /etc/hosts
set_hostname() {
    echo "Setting up default hostname: $HOSTNAME_DEFAULT..."
    sudo hostnamectl set-hostname "$HOSTNAME_DEFAULT"
    
    # Ensure the /etc/hosts file has the correct entries
    if ! grep -q "$HOSTNAME_DEFAULT" /etc/hosts; then
        echo "Adding hostname entry to /etc/hosts..."
        sudo bash -c "echo '127.0.1.1    $HOSTNAME_DEFAULT' >> /etc/hosts"
    fi
    
    echo "Hostname and /etc/hosts updated successfully!"
}

# Function: Install Unbound
install_unbound() {
    echo "Setting up hostname before installation..."
    set_hostname  # Set hostname during installation

    echo "Installing Unbound..."
    sudo apt update
    sudo apt install -y unbound
    sudo unbound-control-setup

    echo "Creating configuration file..."
    sudo bash -c "cat > $CONFIG_PATH << 'EOF'
server:
    cache-max-ttl: 86400
    cache-min-ttl: 3600
    prefetch: yes
    do-ip4: yes
    do-ip6: yes
    do-udp: yes
    do-tcp: yes
    interface: 127.0.0.1
    interface: ::1
    port: 53
    access-control: 127.0.0.0/8 allow
    access-control: ::1 allow
    private-address: 192.168.0.0/16
    private-address: 172.16.0.0/12
    private-address: 10.0.0.0/8
    private-address: fd00::/8
    private-address: fe80::/10

    remote-control:
        control-enable: yes
        control-interface: 127.0.0.1

forward-zone:
    name: "."
    forward-first: no
    forward-addr: 8.8.8.8
    forward-addr: 8.8.4.4
    forward-addr: 2001:4860:4860::8888
    forward-addr: 2001:4860:4860::8844
EOF"

    echo "Validating configuration..."
    sudo unbound-checkconf
    if [ $? -eq 0 ]; then
        echo "Configuration is valid."
    else
        echo "Configuration is invalid. Exiting..."
        exit 1
    fi

    echo "Restarting Unbound service..."
    sudo systemctl restart unbound
    echo "Unbound installed and configured successfully!"
}

# Function: Configure DNS
configure_dns() {
    echo "Configuring DNS to use Unbound..."

    # Stop and disable systemd-resolved
    sudo systemctl stop systemd-resolved
    sudo systemctl disable systemd-resolved

    # Remove immutable flag if set
    sudo chattr -i $RESOLV_PATH

    # Remove existing resolv.conf
    sudo rm -f $RESOLV_PATH

    # Create new resolv.conf for Unbound
    sudo bash -c "cat > $RESOLV_PATH << 'EOF'
nameserver 127.0.0.1
nameserver ::1
EOF"

    # Set resolv.conf as immutable
    sudo chattr +i $RESOLV_PATH

    echo "DNS configured successfully!"
}

# Function: Restart Unbound
restart_unbound() {
    echo "Restarting Unbound service..."
    sudo systemctl restart unbound
    echo "Unbound service restarted."
}

# Function: Uninstall Unbound
uninstall_unbound() {
    echo "Uninstalling Unbound..."
    sudo apt remove -y unbound
    sudo rm -rf /etc/unbound
    sudo chattr -i $RESOLV_PATH
    sudo rm -f $RESOLV_PATH
    echo "Unbound uninstalled successfully!"
}

# Function: Show Features
show_features() {
    echo "Unbound Features and Useful Commands:"
    echo "- Local DNS resolver with caching."
    echo "- Reduces latency and increases security."
    echo "- Example commands:"
    echo "  Flush a domain cache: sudo unbound-control flush <domain>"
    echo "  Lookup cache: sudo unbound-control lookup <domain>"
    echo "  Test local DNS: dig @127.0.0.1 google.com"
}

# Main Menu
while true; do
    echo "Choose an option:"
    echo "1) Install Unbound"
    echo "2) Configure DNS"
    echo "3) Restart Unbound"
    echo "4) Uninstall Unbound"
    echo "5) Show Features"
    echo "6) Exit"
    read -rp "Enter your choice [1-6]: " choice

    case $choice in
        1) install_unbound ;;
        2) configure_dns ;;
        3) restart_unbound ;;
        4) uninstall_unbound ;;
        5) show_features ;;
        6) echo "Exiting..."; exit 0 ;;
        *) echo "Invalid choice, please try again." ;;
    esac
done
