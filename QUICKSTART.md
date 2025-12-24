# Quick Start Guide - K3s Infrastructure Deployment

## 🚀 5-Minute Setup

### 1. Clone the Repository

```bash
git clone https://github.com/nakitka/k3s-infrastructure-deployment.git
cd k3s-infrastructure-deployment
chmod +x deploy.py packer/scripts/*.sh
```

### 2. Install Dependencies

#### System Dependencies

**On Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install -y python3 python3-pip packer terraform ansible
pip install -r requirements.txt
```

**On macOS (with Homebrew):**
```bash
brew install python3 packer terraform ansible
pip3 install -r requirements.txt
```

**On CentOS/RHEL:**
```bash
sudo yum install python3 python3-pip
pip install -r requirements.txt
# Install Packer, Terraform, Ansible from official downloads or repos
```

#### Verify Installation

```bash
python3 --version   # Python 3.9+
packer version      # Packer 1.8.0+
terraform version   # Terraform 1.5.0+
ansible --version   # Ansible 2.10.0+
helm version        # Helm 3.0.0+
kubectl version     # kubectl 1.25.0+
```

### 3. Prepare Configuration

```bash
# Copy default configuration
cp config/default.yaml config/my-cluster.yaml

# Edit with your vSphere details
vim config/my-cluster.yaml
```

**Required vSphere Information:**
- vCenter host (FQDN)
- Username and password
- Datacenter name
- Cluster name
- Datastore names
- Network name
- ISO datastore location

### 4. Run the Orchestration Script

```bash
python3 deploy.py
```

The script will:
1. Present interactive menu
2. Ask about template creation/usage
3. Gather configuration parameters
4. Allow parameter modifications
5. Proceed to Packer build (or skip if using existing template)

### 5. Watch the Build Progress

The script will show real-time output. For detailed logs:

```bash
cat deployment_*.log
```

## 📚 Full Workflow

### Step 1: Packer - Create VM Templates (≈ 15-20 minutes)

```
Packer Section
  └─ Choose: "Create new template"
     └─ Configure vSphere parameters
     └─ Review parameters
     └─ Build templates (automated)
     └─ Verify in vSphere
```

**What it does:**
- Creates k3s-node template
- Creates nfs-server template
- Installs Docker, k3s tools, NFS server software
- Optimizes system settings

### Step 2: Terraform - Create Infrastructure (≈ 5-10 minutes)

```
Terraform Section (Coming Next)
  └─ Select templates created in Step 1
  └─ Configure node counts and sizing
  └─ Configure NFS server settings
  └─ Deploy infrastructure (automated)
```

**What it does:**
- Creates VM network
- Clones VMs from templates
- Configures networking
- Creates storage volumes

### Step 3: Ansible - Configure Systems (≈ 10-15 minutes)

```
Ansible Section (Coming Later)
  └─ Configure cluster parameters
  └─ Deploy automatically
```

**What it does:**
- Installs k3s on all nodes
- Forms k3s cluster
- Configures NFS servers with HA
- Sets up monitoring

### Step 4: Helm - Deploy Services (≈ 5-10 minutes)

```
Helm Section (Coming Later)
  └─ Configure replica counts
  └─ Deploy services
```

**What it does:**
- Deploys PostgreSQL
- Deploys Gitea with LDAP
- Deploys Prometheus
- Deploys Grafana
- Deploys Kubernetes Dashboard

## 🗓️ Configuration File Format

Key sections in `config/my-cluster.yaml`:

```yaml
vsphere:
  host: vcenter.example.com
  user: administrator@vsphere.local
  password: your_password  # Use env vars in production!
  datacenter: Datacenter
  cluster: Cluster

packer:
  iso_datastore: Datastore1
  iso_path: /iso/debian-12.6.0-amd64-netinst.iso
  # ... other packer settings

terraform:
  cluster:
    name: k3s-prod
  master:
    count: 1
    cpu: 4
    memory_mb: 8192
  worker:
    count: 3
    cpu: 4
    memory_mb: 8192
  nfs_servers:
    count: 2
    storage_disk_size_gb: 500

ansible:
  k3s:
    version: v1.27.0

helm:
  services:
    postgresql:
      replicas: 3
    gitea:
      replicas: 2
    # ... other services
```

## 🔐 Security Best Practices

### 1. Use Environment Variables

Instead of storing passwords in config files:

```bash
# Create .env file (not in git)
cat > .env << EOF
export VSPHERE_PASSWORD="your_password"
export DB_ROOT_PASSWORD="secure_password"
export GITEA_ADMIN_PASSWORD="secure_password"
export GRAFANA_ADMIN_PASSWORD="secure_password"
EOF

# Load before running
source .env
python3 deploy.py
```

### 2. SSH Key Authentication

Set up SSH keys before deployment:

```bash
# Generate SSH key if not already done
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""

# Verify in config
grep -A 3 'ssh:' config/my-cluster.yaml
```

### 3. Network Security

- Restrict vSphere network access
- Use VPN for remote access
- Configure firewall rules before deployment
- Enable TLS/HTTPS for all services

## 🚰️ Troubleshooting

### Script Won't Start

```bash
# Check Python version
python3 --version  # Must be 3.9+

# Check dependencies
pip install -r requirements.txt

# Run with verbose output
python3 -u deploy.py 2>&1 | tee deployment.log
```

### Packer Build Fails

1. **Check ISO path:**
   ```bash
   # Verify ISO exists in vSphere
   ```

2. **Check vSphere credentials:**
   ```bash
   # Test connectivity
   ping vcenter.example.com
   ```

3. **Check network connectivity:**
   - Ensure Packer host can reach vSphere
   - Ensure vSphere VM can reach Debian installation network

4. **Review logs:**
   ```bash
   cat deployment_*.log | grep -i error
   ```

### SSH Connection Issues

```bash
# Test SSH connectivity to created VMs
ssh -i ~/.ssh/id_rsa debian@<vm-ip>

# Check if SSH service is running
sudo systemctl status ssh

# Check SSH logs
sudo journalctl -u ssh -n 50
```

## 💰 Resource Requirements

### Minimum for Testing

```
Packer:     4 vCPU, 8 GB RAM (host)
k3s Cluster: 1 master (2 vCPU, 4 GB RAM)
            2 workers (2 vCPU, 4 GB RAM each)
NFS Servers: 1 server (2 vCPU, 4 GB RAM)
Total:      ~10 vCPU, 24 GB RAM
```

### Recommended for Production

```
k3s Cluster: 3 masters (4 vCPU, 8 GB RAM each)
            3+ workers (4 vCPU, 8 GB RAM each)
NFS Servers: 2 servers (2 vCPU, 4 GB RAM each)
            500 GB+ storage each
Total:      ~24 vCPU, 72 GB RAM, 1 TB+ storage
```

## 🔘 Next Steps

Once the Packer section is complete:

1. **Verify templates** in vSphere
2. **Review Packer README**: `packer/README.md`
3. **Prepare for Terraform** (coming next)
4. **Plan node distribution** across cluster
5. **Prepare Ansible inventory**

## 📝 Environment Variable Reference

```bash
# Required
export VSPHERE_HOST="vcenter.example.com"
export VSPHERE_USER="administrator@vsphere.local"
export VSPHERE_PASSWORD="password"

# Optional (with defaults)
export ANSIBLE_INVENTORY="inventory.ini"
export HELM_NAMESPACE="default"
export KUBECTL_CONFIG="~/.kube/config"
```

## 🔍 Common Tasks

### View Deployment Logs

```bash
# Latest deployment
tail -f deployment_*.log

# Search for errors
grep -i error deployment_*.log

# View packer build output
packer build -debug templates/debian-k3s-node.json
```

### Clean Up (Remove Templates)

```bash
# In vSphere, right-click template and select "Delete"
# Or use Terraform destroy (when available)
terraform destroy
```

### Reset Configuration

```bash
# Start fresh
rm config/my-cluster.yaml
cp config/default.yaml config/my-cluster.yaml
vim config/my-cluster.yaml
python3 deploy.py
```

## 🌟 Getting Help

1. **Check Logs**: `deployment_*.log`
2. **Read Packer Docs**: `packer/README.md`
3. **Review Config**: `config/default.yaml`
4. **Check vSphere**: Verify VM creation in vSphere UI
5. **Test Connectivity**: `ping`, `ssh`, `curl` to test services

## 📄 Additional Resources

- **Packer**: https://www.packer.io/docs
- **Terraform**: https://www.terraform.io/docs
- **Ansible**: https://docs.ansible.com/
- **k3s**: https://docs.k3s.io/
- **vSphere**: https://docs.vmware.com/en/VMware-vSphere/

---

**Ready to get started?**

```bash
python3 deploy.py
```

Good luck! 🚀
