#!/bin/bash

# k3s Node Preparation Script
# Installs and configures k3s-specific dependencies and optimizations

set -e
set -x

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== k3s Node Preparation Starting ===${NC}"

# Install k3s-specific dependencies
echo -e "${YELLOW}Installing k3s dependencies...${NC}"
sudo apt-get install -y \
  conntrack \
  ebtables \
  ethtool \
  iptables \
  ipset \
  ipvsadm \
  libseccomp2 \
  socat \
  util-linux \
  aufs-tools \
  cgroup-lite \
  cifs-utils \
  nfs-common \
  thin-provisioning-tools \
  lvm2 \
  xfsprogs \
  nftables

# Install additional networking tools
echo -e "${YELLOW}Installing networking tools...${NC}"
sudo apt-get install -y \
  isc-dhcp-client \
  isc-dhcp-common \
  iproute2 \
  iputils-arping \
  bridge-utils

# Configure system limits for container runtime
echo -e "${YELLOW}Configuring system limits...${NC}"
cat <<EOF | sudo tee /etc/security/limits.d/k3s.conf
*       soft    nofile  65536
*       hard    nofile  65536
*       soft    nproc   32768
*       hard    nproc   32768
root    soft    nofile  65536
root    hard    nofile  65536
root    soft    nproc   32768
root    hard    nproc   32768
EOF

# Configure cgroup settings
echo -e "${YELLOW}Configuring cgroup settings...${NC}"
cat <<EOF | sudo tee /boot/grub/grub.d/40_custom_k3s.cfg
#!/bin/sh -e
echo 'Adding custom k3s kernel parameters'
cat << 'GRUB'
if [ "\${recordfail}" = 1 ]; then
  set timeout=10
else
  set timeout=0
fi
EOF

# Configure container registry (containerd)
echo -e "${YELLOW}Configuring containerd...${NC}"
sudo mkdir -p /etc/containerd

cat <<EOF | sudo tee /etc/containerd/config.toml
version = 2

[plugins]
  [plugins."io.containerd.grpc.v1.cri"]
    [plugins."io.containerd.grpc.v1.cri".containerd]
      snapshotter = "overlayfs"
      default_runtime_name = "runc"
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes]
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
          runtime_engine = ""
          runtime_root = ""
    [plugins."io.containerd.grpc.v1.cri".cni]
      bin_dir = "/opt/cni/bin"
      conf_dir = "/etc/cni/net.d"
      conf_template = ""
    [plugins."io.containerd.grpc.v1.cri".registry]
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors]
        [plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
          endpoint = ["https://registry-1.docker.io"]
EOF

# Create CNI configuration directory
echo -e "${YELLOW}Creating CNI configuration directory...${NC}"
sudo mkdir -p /opt/cni/bin
sudo mkdir -p /etc/cni/net.d

# Install CNI plugins
echo -e "${YELLOW}Installing CNI plugins...${NC}"
CNI_VERSION="v1.3.0"
RCHIVE_VERSION=$(echo $CNI_VERSION | sed 's/v//')
ARCH="amd64"

sudo mkdir -p /opt/cni/bin
wget -q https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-${ARCH}-${CNI_VERSION}.tgz
sudo tar -xzf cni-plugins-linux-${ARCH}-${CNI_VERSION}.tgz -C /opt/cni/bin/
rm -f cni-plugins-linux-${ARCH}-${CNI_VERSION}.tgz
sudo chmod +x /opt/cni/bin/*

# Configure kubelet parameters
echo -e "${YELLOW}Preparing kubelet configuration...${NC}"
sudo mkdir -p /etc/kubernetes/kubelet

cat <<EOF | sudo tee /etc/kubernetes/kubelet/kubeadm-flags.env
KUBELET_KUBEADM_ARGS="--network-plugin=cni --cni-conf-dir=/etc/cni/net.d --cni-bin-dir=/opt/cni/bin"
EOF

# Disable unnecessary services
echo -e "${YELLOW}Disabling unnecessary services...${NC}"
sudo systemctl disable bluetooth || true
sudo systemctl disable cups || true

# Enable required services
echo -e "${YELLOW}Enabling required services...${NC}"
sudo systemctl enable docker
sudo systemctl enable containerd

# Create directories for k3s
echo -e "${YELLOW}Creating k3s directories...${NC}"
sudo mkdir -p /var/lib/k3s
sudo mkdir -p /var/lib/kubelet
sudo mkdir -p /etc/rancher/k3s
sudo mkdir -p /etc/rancher/k3s/manifests

# Create k3s service files directory
sudo mkdir -p /etc/systemd/system/k3s.service.d

# Pre-create necessary paths
sudo mkdir -p /opt/k3s
sudo mkdir -p /var/log/pods

# Configure log rotation
echo -e "${YELLOW}Configuring log rotation...${NC}"
cat <<EOF | sudo tee /etc/logrotate.d/k3s
/var/log/pods/*/*.log {
    daily
    rotate 3
    missingok
    notifempty
    compress
    delaycompress
    copytruncate
}
EOF

# Install helm (for later use)
echo -e "${YELLOW}Installing helm...${NC}"
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install kubectl
echo -e "${YELLOW}Installing kubectl...${NC}"
curl -fsSL https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl -o /tmp/kubectl
sudo install -o root -g root -m 0755 /tmp/kubectl /usr/local/bin/kubectl
rm /tmp/kubectl

# Optimize disk performance
echo -e "${YELLOW}Optimizing disk performance...${NC}"
cat <<EOF | sudo tee /etc/udev/rules.d/90-disk-performance.rules
ACTION=="add|change", KERNEL=="sd*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="noop"
ACTION=="add|change", KERNEL=="sd*", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="deadline"
EOF

# Configure network interface bonding support
echo -e "${YELLOW}Configuring network bonding...${NC}"
sudo modprobe -q bonding
echo bonding | sudo tee -a /etc/modules

# Clean up
echo -e "${YELLOW}Cleaning up...${NC}"
sudo apt-get clean
sudo apt-get autoclean
sudo apt-get autoremove -y

echo -e "${GREEN}=== k3s Node Preparation Completed Successfully ===${NC}"
echo -e "${GREEN}Node is ready for k3s cluster deployment${NC}"
