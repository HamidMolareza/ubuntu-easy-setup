#!/bin/bash

# Update package lists
sudo apt update

# Upgrade installed packages
sudo apt upgrade -y

# Perform distribution upgrade
sudo apt dist-upgrade -y

# Refresh snap packages
sudo snap refresh
