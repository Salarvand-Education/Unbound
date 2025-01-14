# Unbound Manager Installation Script  

This script automates the installation, configuration, and management of **Unbound DNS Resolver** on Linux servers.  

## Features  
- Automatic installation of Unbound.  
- Default configuration with caching and security settings.  
- Restart and DNS configuration.  
- Easy removal of Unbound with cleanup.  

## Quick Installation  

Run the following command to install and configure Unbound:  

```bash  
bash <(curl -s https://raw.githubusercontent.com/Salarvand-Education/Unbound/main/install.sh)

How It Works

The script will:

1. Update your package manager and install Unbound.


2. Set up a default configuration file for Unbound.


3. Restart the Unbound service to apply changes.
