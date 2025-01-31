#!/bin/bash
# Unbound Management Script with Logging and Colored Output
CONFIG_PATH="/etc/unbound/unbound.conf.d/custom.conf"
RESOLV_PATH="/etc/resolv.conf"
LOG_PATH="/var/log/unbound-management.log"
HOSTNAME_DEFAULT="server"  # Default hostname

# ANSI Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function: Log Messages
log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | sudo tee -a "$LOG_PATH" > /dev/null
}

# Function: Print Colored Message
print_message() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${NC}"
}

# Function: Set Hostname and configure /etc/hosts
set_hostname() {
    print_message "$BLUE" "Setting up default hostname: $HOSTNAME_DEFAULT..."

    # Add hostname entry to /etc/hosts if not present
    if ! grep -q "$HOSTNAME_DEFAULT" /etc/hosts; then
        print_message "$YELLOW" "Adding hostname entry to /etc/hosts..."
        echo "127.0.1.1    $HOSTNAME_DEFAULT" | sudo tee -a /etc/hosts > /dev/null
        log_message "Added hostname entry to /etc/hosts."
    fi

    # Set the hostname
    sudo hostnamectl set-hostname "$HOSTNAME_DEFAULT"
    log_message "Hostname set to $HOSTNAME_DEFAULT."

    print_message "$GREEN" "Hostname and /etc/hosts updated successfully!"
}

# Function: Install Unbound
install_unbound() {
    print_message "$BLUE" "Setting up hostname before installation..."
    set_hostname  # Set hostname during installation

    print_message "$BLUE" "Installing Unbound..."
    sudo apt update || { print_message "$RED" "Failed to update package lists."; log_message "Failed to update package lists."; exit 1; }
    sudo apt install -y unbound || { print_message "$RED" "Failed to install Unbound."; log_message "Failed to install Unbound."; exit 1; }

    # Generate control keys for remote management
    sudo unbound-control-setup || { print_message "$RED" "Failed to setup unbound-control."; log_message "Failed to setup unbound-control."; exit 1; }

    print_message "$BLUE" "Creating configuration file..."
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

    print_message "$BLUE" "Validating configuration..."
    if sudo unbound-checkconf; then
        print_message "$GREEN" "Configuration is valid."
        log_message "Unbound configuration validated successfully."
    else
        print_message "$RED" "Configuration is invalid. Exiting..."
        log_message "Unbound configuration validation failed."
        exit 1
    fi

    print_message "$BLUE" "Restarting Unbound service..."
    sudo systemctl restart unbound || { print_message "$RED" "Failed to restart Unbound."; log_message "Failed to restart Unbound."; exit 1; }

    print_message "$GREEN" "Unbound installed and configured successfully!"
    log_message "Unbound installed and configured successfully."
}

# Function: Configure DNS
configure_dns() {
    print_message "$BLUE" "Configuring DNS to use Unbound..."

    # Stop and disable systemd-resolved
    if systemctl is-active --quiet systemd-resolved; then
        sudo systemctl stop systemd-resolved || { print_message "$RED" "Failed to stop systemd-resolved."; log_message "Failed to stop systemd-resolved."; exit 1; }
        sudo systemctl disable systemd-resolved || { print_message "$RED" "Failed to disable systemd-resolved."; log_message "Failed to disable systemd-resolved."; exit 1; }
    fi

    # Remove immutable flag if set
    if lsattr "$RESOLV_PATH" 2>/dev/null | grep -q 'i'; then
        sudo chattr -i "$RESOLV_PATH" || { print_message "$RED" "Failed to remove immutable flag from $RESOLV_PATH."; log_message "Failed to remove immutable flag from $RESOLV_PATH."; exit 1; }
    fi

    # Remove existing resolv.conf
    sudo rm -f "$RESOLV_PATH" || { print_message "$RED" "Failed to remove $RESOLV_PATH."; log_message "Failed to remove $RESOLV_PATH."; exit 1; }

    # Create new resolv.conf for Unbound
    sudo bash -c "cat > $RESOLV_PATH << 'EOF'
nameserver 127.0.0.1
nameserver ::1
EOF"

    # Set resolv.conf as immutable
    sudo chattr +i "$RESOLV_PATH" || { print_message "$RED" "Failed to set immutable flag on $RESOLV_PATH."; log_message "Failed to set immutable flag on $RESOLV_PATH."; exit 1; }

    print_message "$GREEN" "DNS configured successfully!"
    log_message "DNS configured to use Unbound."
}

# Function: Restart Unbound
restart_unbound() {
    print_message "$BLUE" "Restarting Unbound service..."
    sudo systemctl restart unbound || { print_message "$RED" "Failed to restart Unbound."; log_message "Failed to restart Unbound."; exit 1; }
    print_message "$GREEN" "Unbound service restarted."
    log_message "Unbound service restarted."
}

# Function: Uninstall Unbound
uninstall_unbound() {
    print_message "$BLUE" "Uninstalling Unbound..."

    # Remove Unbound package
    sudo apt remove -y unbound || { print_message "$RED" "Failed to uninstall Unbound."; log_message "Failed to uninstall Unbound."; exit 1; }

    # Remove configuration files
    sudo rm -rf /etc/unbound || { print_message "$RED" "Failed to remove Unbound configuration files."; log_message "Failed to remove Unbound configuration files."; exit 1; }

    # Restore resolv.conf
    if lsattr "$RESOLV_PATH" 2>/dev/null | grep -q 'i'; then
        sudo chattr -i "$RESOLV_PATH" || { print_message "$RED" "Failed to remove immutable flag from $RESOLV_PATH."; log_message "Failed to remove immutable flag from $RESOLV_PATH."; exit 1; }
    fi
    sudo rm -f "$RESOLV_PATH" || { print_message "$RED" "Failed to remove $RESOLV_PATH."; log_message "Failed to remove $RESOLV_PATH."; exit 1; }

    print_message "$GREEN" "Unbound uninstalled successfully!"
    log_message "Unbound uninstalled successfully."
}

# Function: Show Features
show_features() {
    print_message "$BLUE" "Unbound Features and Useful Commands:"
    print_message "$YELLOW" "- Local DNS resolver with caching."
    print_message "$YELLOW" "- Reduces latency and increases security."
    print_message "$YELLOW" "- Example commands:"
    print_message "$YELLOW" "  Flush a domain cache: sudo unbound-control flush <domain>"
    print_message "$YELLOW" "  Lookup cache: sudo unbound-control lookup <domain>"
    print_message "$YELLOW" "  Test local DNS: dig @127.0.0.1 google.com"
}

# Main Menu
while true; do
    print_message "$BLUE" "Choose an option:"
    print_message "$YELLOW" "1) Install Unbound"
    print_message "$YELLOW" "2) Configure DNS"
    print_message "$YELLOW" "3) Restart Unbound"
    print_message "$YELLOW" "4) Uninstall Unbound"
    print_message "$YELLOW" "5) Show Features"
    print_message "$YELLOW" "6) Exit"
    read -rp "Enter your choice [1-6]: " choice

    case $choice in
        1) install_unbound ;;
        2) configure_dns ;;
        3) restart_unbound ;;
        4) uninstall_unbound ;;
        5) show_features ;;
        6) print_message "$BLUE" "Exiting..."; log_message "Script exited by user."; exit 0 ;;
        *) print_message "$RED" "Invalid choice, please try again." ;;
    esac
done
