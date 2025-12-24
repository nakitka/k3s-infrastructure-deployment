#!/bin/bash

# NFS Server Preparation Script
# Installs and configures NFS server, keepalived, and rsync for high availability

set -e
set -x

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== NFS Server Preparation Starting ===${NC}"

# Install NFS server packages
echo -e "${YELLOW}Installing NFS server packages...${NC}"
sudo apt-get install -y \
  nfs-kernel-server \
  nfs-common \
  portmap \
  rpcbind \
  python3-rpc.nfs4 \
  nfs4-acl-tools

# Install high availability packages
echo -e "${YELLOW}Installing HA packages (Keepalived, Rsync)...${NC}"
sudo apt-get install -y \
  keepalived \
  rsync \
  openssh-server \
  openssh-client

# Install monitoring and management tools
echo -e "${YELLOW}Installing monitoring tools...${NC}"
sudo apt-get install -y \
  nfs-utils \
  nfs-ganesha \
  nfs-ganesha-utils \
  monitoring-plugins-nfs \
  snmp \
  snmp-mibs-downloader

# Create NFS export directory
echo -e "${YELLOW}Creating NFS export directory...${NC}"
sudo mkdir -p /srv/nfs/shared
sudo mkdir -p /srv/nfs/backup
sudo chmod 755 /srv/nfs
sudo chmod 777 /srv/nfs/shared
sudo chmod 755 /srv/nfs/backup

# Setup filesystem detection and formatting script for additional disk
echo -e "${YELLOW}Creating disk setup script...${NC}"
cat <<'EOF' | sudo tee /opt/setup-nfs-disk.sh
#!/bin/bash

# This script will be run by Ansible to format and mount the NFS storage disk
set -e

# Find the second disk (assuming /dev/sdb)
DISK="/dev/sdb"

if [ -b "$DISK" ]; then
    echo "Setting up NFS storage disk: $DISK"
    
    # Check if disk is already formatted
    if ! sudo blkid $DISK; then
        echo "Formatting $DISK with ext4..."
        sudo mkfs.ext4 -F $DISK
    fi
    
    # Create mount point
    sudo mkdir -p /mnt/nfs-storage
    
    # Get UUID of the disk
    UUID=$(sudo blkid -s UUID -o value $DISK)
    
    # Add to fstab if not already present
    if ! grep -q "$UUID" /etc/fstab; then
        echo "UUID=$UUID /mnt/nfs-storage ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab
    fi
    
    # Mount the disk
    sudo mount /mnt/nfs-storage
    
    # Create NFS export symlink
    sudo rm -rf /srv/nfs/shared
    sudo ln -s /mnt/nfs-storage /srv/nfs/shared
    
    echo "NFS storage disk setup completed"
else
    echo "Storage disk not found at $DISK"
fi
EOF

sudo chmod +x /opt/setup-nfs-disk.sh

# Create NFS exports configuration template
echo -e "${YELLOW}Creating NFS exports configuration template...${NC}"
cat <<EOF | sudo tee /etc/exports.template
# NFS Exports Configuration Template
# This file will be populated by Ansible with actual network ranges

# Kubernetes cluster mounts
/srv/nfs/shared *(rw,sync,no_subtree_check,no_root_squash,fsid=0)

# Backup directory (read-only for non-backup servers)
/srv/nfs/backup *(rw,sync,no_subtree_check,no_root_squash,fsid=1)
EOF

# Configure NFS server options
echo -e "${YELLOW}Configuring NFS server...${NC}"
cat <<EOF | sudo tee /etc/default/nfs-kernel-server
# Options for nfs-kernel-server
EXPORTFS_OPTIONS="-av"
EOF

# Configure NFS server threads
echo -e "${YELLOW}Configuring NFS server threads...${NC}"
sudo sed -i 's/^RPCNFSDCOUNT=.*/RPCNFSDCOUNT=32/' /etc/default/nfs-kernel-server || \
echo 'RPCNFSDCOUNT=32' | sudo tee -a /etc/default/nfs-kernel-server

# Create keepalived configuration template
echo -e "${YELLOW}Creating Keepalived configuration template...${NC}"
cat <<EOF | sudo tee /etc/keepalived/keepalived.conf.template
global_defs {
    router_id NFS_SERVER
    script_user root
    enable_script_security
    vrrp_skip_check_adv_addr
    vrrp_strict
    vrrp_garp_interval 0
    vrrp_gna_interval 0
}

vrrp_script check_nfs {
    script "/opt/check-nfs-health.sh"
    interval 2
    weight -20
    fall 3
    rise 2
}

vrrp_instance VI_1 {
    state BACKUP
    interface eth0
    virtual_router_id 51
    priority 100
    advert_int 1
    track_script {
        check_nfs
    }
    authentication {
        auth_type PASS
        auth_pass 1111
    }
    virtual_ipaddress {
        # VIP will be set by Ansible
    }
}
EOF

# Create NFS health check script
echo -e "${YELLOW}Creating NFS health check script...${NC}"
cat <<EOF | sudo tee /opt/check-nfs-health.sh
#!/bin/bash

# Check if NFS service is running
sudo systemctl is-active --quiet nfs-server || exit 1

# Check if NFS mounts are accessible
sudo test -r /srv/nfs/shared || exit 1

# Check disk usage
DISK_USAGE=\$(df /srv/nfs/shared | tail -1 | awk '{print \$5}' | sed 's/%//')
if [ "\$DISK_USAGE" -gt 90 ]; then
    exit 1
fi

exit 0
EOF

sudo chmod +x /opt/check-nfs-health.sh

# Create rsync configuration for server-to-server sync
echo -e "${YELLOW}Creating rsync configuration...${NC}"
cat <<EOF | sudo tee /etc/rsyncd.conf.template
# Rsync Daemon Configuration Template
port = 873
log file = /var/log/rsync.log
pid file = /var/run/rsyncd.pid
lock file = /var/run/rsync.lock

[nfs-shared]
    path = /srv/nfs/shared
    comment = NFS Shared Storage
    uid = root
    gid = root
    read only = false
    list = yes
    auth users = rsync
    secrets file = /etc/rsync.secrets
    hosts allow = 0.0.0.0/0

[nfs-backup]
    path = /srv/nfs/backup
    comment = NFS Backup Directory
    uid = root
    gid = root
    read only = true
    list = yes
    auth users = rsync
    secrets file = /etc/rsync.secrets
    hosts allow = 0.0.0.0/0
EOF

# Create rsync secrets template
echo -e "${YELLOW}Creating rsync secrets template...${NC}"
sudo touch /etc/rsync.secrets
sudo chmod 600 /etc/rsync.secrets

# Create rsync cron script
echo -e "${YELLOW}Creating rsync synchronization script...${NC}"
cat <<'EOF' | sudo tee /opt/nfs-sync.sh
#!/bin/bash

# NFS Server Synchronization Script
# This script will be used for HA sync between NFS servers

LOG_FILE="/var/log/nfs-sync.log"
RSYNC_HOST="${SYNC_SERVER}"  # Set by Ansible
RSYNC_USER="rsync"
RSYNC_PASSWORD="${RSYNC_PASSWORD}"  # Set by Ansible

echo "[$(date)] Starting NFS synchronization" >> $LOG_FILE

if [ -z "$RSYNC_HOST" ]; then
    echo "[$(date)] RSYNC_HOST not set, skipping sync" >> $LOG_FILE
    exit 0
fi

# Sync shared directory to backup server
echo "$RSYNC_PASSWORD" | rsync -avz --delete \
    --password-file=/dev/stdin \
    /srv/nfs/shared/ \
    $RSYNC_USER@$RSYNC_HOST::nfs-shared/ \
    2>&1 | tee -a $LOG_FILE

echo "[$(date)] NFS synchronization completed" >> $LOG_FILE
EOF

sudo chmod +x /opt/nfs-sync.sh

# Enable NFS services
echo -e "${YELLOW}Enabling NFS services...${NC}"
sudo systemctl enable rpcbind
sudo systemctl enable nfs-server
sudo systemctl disable keepalived  # Will be enabled by Ansible if needed
sudo systemctl disable rsync || true

# Increase file descriptor limits for NFS
echo -e "${YELLOW}Configuring file descriptor limits...${NC}"
cat <<EOF | sudo tee /etc/security/limits.d/nfs.conf
*       soft    nofile  65536
*       hard    nofile  65536
*       soft    nproc   32768
*       hard    nproc   32768
root    soft    nofile  65536
root    hard    nofile  65536
root    soft    nproc   32768
root    hard    nproc   32768
EOF

# Configure network tuning for NFS
echo -e "${YELLOW}Tuning network for NFS...${NC}"
cat <<EOF | sudo tee /etc/sysctl.d/99-nfs-tuning.conf
# NFS Tuning
net.core.rmem_max=134217728
net.core.wmem_max=134217728
net.ipv4.tcp_rmem=4096 87380 67108864
net.ipv4.tcp_wmem=4096 65536 67108864
net.core.netdev_max_backlog=5000
net.ipv4.tcp_max_syn_backlog=5000
fs.nfs.nlm_tcpport=32768
fs.nfs.nlm_udpport=32768
fs.nfs.max_block_size=4194304
fs.nfs.max_rpciod_count=256
EOF

sudo sysctl -p /etc/sysctl.d/99-nfs-tuning.conf

# Setup log rotation
echo -e "${YELLOW}Setting up log rotation...${NC}"
cat <<EOF | sudo tee /etc/logrotate.d/nfs-server
/var/log/nfs-server.log {
    daily
    rotate 7
    missingok
    notifempty
    compress
    delaycompress
    copytruncate
}

/var/log/rsync.log {
    daily
    rotate 7
    missingok
    notifempty
    compress
    delaycompress
    copytruncate
}
EOF

# Clean up
echo -e "${YELLOW}Cleaning up...${NC}"
sudo apt-get clean
sudo apt-get autoclean
sudo apt-get autoremove -y

echo -e "${GREEN}=== NFS Server Preparation Completed Successfully ===${NC}"
echo -e "${GREEN}NFS server is ready for deployment${NC}"
