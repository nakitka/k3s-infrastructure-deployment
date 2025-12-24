#!/bin/bash

# Base OS Setup Script for Debian 12 Template
# Installs and configures common dependencies for both k3s nodes and NFS servers

set -e
set -x

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Base OS Setup Starting ===${NC}"
echo "Template Type: ${TEMPLATE_TYPE}"

# Update system
echo -e "${YELLOW}Updating system packages...${NC}"
sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get dist-upgrade -y

# Install base packages
echo -e "${YELLOW}Installing base packages...${NC}"
sudo apt-get install -y \
  curl \
  wget \
  git \
  htop \
  net-tools \
  nano \
  vim \
  openssh-server \
  openssh-client \
  sudo \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  apt-transport-https \
  software-properties-common \
  cloud-init \
  cloud-guest-utils \
  open-vm-tools \
  open-vm-tools-dev \
  iputils-ping \
  traceroute \
  dnsutils \
  telnet \
  ntp \
  chrony \
  jq \
  zip \
  unzip

# Install Docker (used for various tools)
echo -e "${YELLOW}Installing Docker...${NC}"
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo usermod -aG docker debian || true

# Install additional container tools
echo -e "${YELLOW}Installing container tools...${NC}"
sudo apt-get install -y \
  podman \
  podman-docker \
  cri-tools \
  containernetworking-plugins

# Disable swap
echo -e "${YELLOW}Disabling swap...${NC}"
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Configure kernel modules for networking
echo -e "${YELLOW}Configuring kernel modules...${NC}"
sudo modprobe overlay
sudo modprobe br_netfilter

# Add kernel module configuration
cat <<EOF | sudo tee /etc/modules-load.d/k3s.conf
overlay
br_netfilter
EOF

# Configure sysctl parameters
echo -e "${YELLOW}Configuring sysctl parameters...${NC}"
cat <<EOF | sudo tee /etc/sysctl.d/99-k3s-setup.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
net.ipv4.conf.all.forwarding = 1
net.ipv4.conf.default.forwarding = 1
fs.inotify.max_user_watches = 524288
fs.inotify.max_queued_events = 32768
fs.inotify.max_user_instances = 8192
EOF

sudo sysctl -p /etc/sysctl.d/99-k3s-setup.conf

# Configure SSH for better security
echo -e "${YELLOW}Configuring SSH...${NC}"
sudo sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo sed -i 's/^#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sudo sed -i 's/^#PermitRootLogin prohibit-password/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sudo sed -i 's/^#X11Forwarding yes/X11Forwarding no/' /etc/ssh/sshd_config

# Setup root SSH directory for cloud-init
sudo mkdir -p /root/.ssh
sudo chmod 700 /root/.ssh

# Create debian user if it doesn't exist
echo -e "${YELLOW}Setting up debian user...${NC}"
if ! id "debian" &>/dev/null; then
  sudo useradd -m -s /bin/bash -G sudo,docker debian
  echo "debian ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/debian
fi

# Setup debian user SSH directory
sudo mkdir -p /home/debian/.ssh
sudo chmod 700 /home/debian/.ssh
sudo chown debian:debian /home/debian/.ssh

# Set timezone
echo -e "${YELLOW}Setting timezone to UTC...${NC}"
sudo timedatectl set-timezone UTC

# Configure cron
echo -e "${YELLOW}Configuring cron...${NC}"
sudo systemctl enable cron
sudo systemctl start cron

# Install monitoring tools
echo -e "${YELLOW}Installing monitoring tools...${NC}"
sudo apt-get install -y \
  iotop \
  sysstat \
  atop \
  dstat

# Configure systemd-resolved for better DNS resolution
echo -e "${YELLOW}Configuring DNS resolution...${NC}"
sudo mkdir -p /etc/systemd/resolved.conf.d/
cat <<EOF | sudo tee /etc/systemd/resolved.conf.d/custom-dns.conf
[Resolve]
FallbackDNS=1.1.1.1 8.8.8.8
DNSSEC=no
EOF

sudo systemctl restart systemd-resolved

# Enable IP forwarding (important for Kubernetes networking)
echo -e "${YELLOW}Enabling IP forwarding...${NC}"
sudo sysctl -w net.ipv4.ip_forward=1

# Install cloud-init finalize
echo -e "${YELLOW}Installing cloud-init finalize...${NC}"
sudo mkdir -p /var/lib/cloud/instance
sudo touch /var/lib/cloud/instance/boot-finished

# Clean up
echo -e "${YELLOW}Cleaning up...${NC}"
sudo apt-get clean
sudo apt-get autoclean
sudo apt-get autoremove -y
sudo rm -rf /tmp/* /var/tmp/*

# Cleanup SSH
echo -e "${YELLOW}Cleaning up SSH...${NC}"
sudo rm -f /etc/ssh/ssh_host_*

# Cleanup cloud-init
echo -e "${YELLOW}Cleaning up cloud-init...${NC}"
sudo cloud-init clean --logs --seed

# Clear command history
echo -e "${YELLOW}Clearing history...${NC}"
history -c
history -w

echo -e "${GREEN}=== Base OS Setup Completed Successfully ===${NC}"
echo -e "${GREEN}System is ready for template-specific configuration${NC}"
