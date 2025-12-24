# K3s Infrastructure Deployment Automation

Automated infrastructure deployment for Kubernetes (k3s) clusters with NFS servers using Packer, Terraform, Ansible, and Helm.

## 📋 Table of Contents

- [Project Overview](#project-overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Project Structure](#project-structure)
- [Workflow](#workflow)
- [Quick Start](#quick-start)
- [Sections](#sections)

## 📌 Project Overview

This project automates the entire infrastructure deployment process:

1. **Packer** - Create VM templates with preconfigured OS
2. **Terraform** - Deploy Kubernetes nodes and NFS servers
3. **Ansible** - Install and configure k3s, NFS, and system utilities
4. **Helm** - Deploy production-ready services (PostgreSQL, Gitea, Prometheus, Grafana, Kubernetes Dashboard)

## 🏗️ Architecture

```
┌─────────────────────────────────────────┐
│        Packer (VM Templates)             │
│   ┌──────────────────────────────────┐  │
│   │ Template Configuration           │  │
│   │ - Node Template                  │  │
│   │ - NFS Server Template            │  │
│   └──────────────────────────────────┘  │
└─────────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│    Terraform (Infrastructure)            │
│   ┌──────────────────────────────────┐  │
│   │ - K3s Cluster Nodes              │  │
│   │ - NFS Servers                    │  │
│   │ - Networks & Storage             │  │
│   └──────────────────────────────────┘  │
└─────────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│      Ansible (Configuration)             │
│   ┌──────────────────────────────────┐  │
│   │ - System Setup                   │  │
│   │ - k3s Installation               │  │
│   │ - k3s Cluster Formation          │  │
│   │ - NFS Configuration              │  │
│   └──────────────────────────────────┘  │
└─────────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│      Helm (Service Deployment)           │
│   ┌──────────────────────────────────┐  │
│   │ - PostgreSQL                     │  │
│   │ - Gitea (with LDAP)              │  │
│   │ - Prometheus                     │  │
│   │ - Grafana                        │  │
│   │ - Kubernetes Dashboard           │  │
│   └──────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

## 📦 Prerequisites

- **Packer** >= 1.8.0
- **Terraform** >= 1.5.0
- **Ansible** >= 2.10.0
- **Helm** >= 3.0.0
- **kubectl** >= 1.25.0
- **vSphere** access with appropriate permissions
- **SSH keys** for authentication
- **Python 3.9+** for the orchestration script

### Required vSphere Permissions

- Datastore: Read, Write
- Virtual Machine: Create, Modify, Delete
- Network: Read, Modify
- Folder: Create, Modify, Delete
- Resource Pool: Read

## 📁 Project Structure

```
k3s-infrastructure-deployment/
├── README.md                              # This file
├── deploy.py                              # Main orchestration script
├── config/
│   └── default.yaml                       # Default configuration template
├── packer/
│   ├── templates/
│   │   ├── debian-k3s-node.json          # k3s node template
│   │   └── debian-nfs-server.json        # NFS server template
│   ├── scripts/
│   │   ├── base-setup.sh                 # Base OS setup
│   │   ├── k3s-prep.sh                   # k3s preparation
│   │   └── nfs-prep.sh                   # NFS preparation
│   └── http/
│       └── preseed.cfg                    # Debian preseed configuration
├── terraform/
│   ├── main.tf                            # Main configuration
│   ├── variables.tf                       # Variable definitions
│   ├── outputs.tf                         # Output definitions
│   ├── vsphere.tf                         # vSphere provider configuration
│   └── modules/
│       ├── k3s-node/                      # k3s node module
│       └── nfs-server/                    # NFS server module
├── ansible/
│   ├── playbooks/
│   │   ├── cluster-setup.yml              # Cluster configuration playbook
│   │   ├── nfs-setup.yml                  # NFS configuration playbook
│   │   └── k3s-deploy.yml                 # k3s deployment playbook
│   ├── roles/
│   │   ├── k3s-master/                    # k3s master role
│   │   ├── k3s-worker/                    # k3s worker role
│   │   ├── nfs-server/                    # NFS server role
│   │   └── common/                        # Common setup role
│   ├── inventory.ini                      # Dynamic inventory
│   └── ansible.cfg                        # Ansible configuration
└── helm/
    ├── values/
    │   ├── postgresql.yaml                # PostgreSQL Helm values
    │   ├── gitea.yaml                     # Gitea Helm values
    │   ├── prometheus.yaml                # Prometheus Helm values
    │   ├── grafana.yaml                   # Grafana Helm values
    │   └── dashboard.yaml                 # Kubernetes Dashboard Helm values
    └── deployments/
        └── services.yaml                  # Service deployment script
```

## 🔄 Workflow

### Step 1: Configuration
```bash
python3 deploy.py
# Select: Create new template or Use existing template
# Configure parameters for your environment
```

### Step 2: Template Creation (Packer)
Automatic VM template creation in vSphere

### Step 3: Infrastructure Provisioning (Terraform)
Automatic creation of cluster nodes and NFS servers

### Step 4: Configuration Management (Ansible)
Automatic installation and configuration of k3s and NFS

### Step 5: Service Deployment (Helm)
Deploy PostgreSQL, Gitea, Prometheus, Grafana, and Kubernetes Dashboard

## 🚀 Quick Start

1. **Clone the repository**
   ```bash
   git clone https://github.com/nakitka/k3s-infrastructure-deployment.git
   cd k3s-infrastructure-deployment
   ```

2. **Install dependencies**
   ```bash
   pip install -r requirements.txt
   ```

3. **Configure your environment**
   ```bash
   cp config/default.yaml config/my-cluster.yaml
   # Edit config/my-cluster.yaml with your settings
   ```

4. **Run the deployment**
   ```bash
   python3 deploy.py
   ```

## 📚 Sections

### [Packer Section](./packer/)
Creates reusable VM templates in vSphere with:
- Base OS configuration (Debian)
- Pre-installed dependencies
- Networking configuration
- Ready for k3s or NFS installation

**Status**: 🔨 IN PROGRESS - Initial setup

### [Terraform Section](./terraform/)
Provisions infrastructure components:
- K3s cluster nodes (customizable CPU, RAM, count)
- NFS servers (customizable storage, CPU, RAM, count)
- Virtual networks
- Storage configurations

**Status**: ⏳ PLANNED

### [Ansible Section](./ansible/)
Configures deployed infrastructure:
- System packages and tools
- k3s cluster installation and bootstrap
- NFS server setup with HA
- Network configuration

**Status**: ⏳ PLANNED

### [Helm Section](./helm/)
Deploys production services:
- PostgreSQL database
- Gitea with LDAP integration
- Prometheus monitoring
- Grafana dashboards
- Kubernetes Dashboard

**Status**: ⏳ PLANNED

## 📝 Configuration Format

The configuration file follows YAML format with sections for each component:

```yaml
# vSphere Configuration
vsphere:
  host: vcenter.example.com
  user: user@vsphere.local
  password: password
  datacenter: DC1
  cluster: Cluster1

# Packer Configuration
packer:
  template_name: debian-k3s-template
  iso_datastore: Datastore1
  iso_path: /path/to/debian.iso

# Terraform Configuration
terraform:
  nodes:
    cpu: 4
    ram: 8192
    count: 3
  nfs_servers:
    cpu: 2
    ram: 4096
    storage: 500
    count: 2

# Helm Services
helm:
  postgresql:
    replicas: 3
  gitea:
    replicas: 2
  # ... other services
```

## 🔗 Links

- [Packer Documentation](https://www.packer.io/docs)
- [Terraform Documentation](https://www.terraform.io/docs)
- [Ansible Documentation](https://docs.ansible.com/)
- [Helm Documentation](https://helm.sh/docs/)
- [k3s Documentation](https://docs.k3s.io/)

## 📄 License

MIT License

## 👤 Author

Nikita Iavorovych

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

---

**Status**: 🔨 Active Development - Packer Section in Progress
