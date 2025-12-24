# Packer Section - VM Template Creation

## Overview

This section uses HashiCorp Packer to create reusable VM templates in vSphere. Two templates are created:

1. **K3s Node Template** - For Kubernetes cluster nodes (master and worker)
2. **NFS Server Template** - For high-availability NFS storage servers

## 📋 Prerequisites

- **Packer** >= 1.8.0 installed and in PATH
- **vSphere Access** with credentials and appropriate permissions
- **Debian ISO** uploaded to vSphere datastore
- **Network Access** from Packer host to vSphere and Debian installation network

### Required vSphere Permissions

Ensure your vSphere user has the following permissions:

- **Datastore**
  - Allocate space
  - Browse datastore
  - Delete file
  - Low-level file operations
  - Update virtual machine files

- **Virtual Machine**
  - Change Configuration
  - Provisioning
  - State

- **Network**
  - Assign network

- **Resource**
  - Assign virtual machine to resource pool

## 📁 File Structure

```
packer/
├── templates/
│   ├── debian-k3s-node.json           # k3s node template definition
│   └── debian-nfs-server.json         # NFS server template definition
├── scripts/
│   ├── base-setup.sh                  # Common OS setup (runs for all templates)
│   ├── k3s-prep.sh                    # k3s-specific preparation
│   └── nfs-prep.sh                    # NFS-specific preparation
├── http/
│   └── preseed.cfg                    # Debian unattended installation config
└── README.md                          # This file
```

## 🛠️ Template Specifications

### K3s Node Template

**Features:**
- Debian 12 base OS
- Docker container runtime pre-installed
- k3s-specific dependencies (CNI plugins, kubelet tools)
- Helm pre-installed
- kubectl pre-installed
- Network kernel modules configured
- System limits optimized for containers

**Default Hardware:**
- vCPU: 2 cores (configurable)
- Memory: 4 GB (configurable)
- Disk: 40 GB (configurable)

**Network:**
- DHCP enabled by default
- hostname: k3s-node (will be customized per instance)

### NFS Server Template

**Features:**
- Debian 12 base OS
- NFS server (nfs-kernel-server) installed and configured
- Keepalived for HA virtual IP
- Rsync for server-to-server synchronization
- Health check scripts
- Network tuning for NFS performance

**Default Hardware:**
- vCPU: 2 cores (configurable)
- Memory: 4 GB (configurable)
- OS Disk: 40 GB (configurable)
- Storage Disk: 500 GB (configurable, additional disk)

**Network:**
- DHCP enabled by default
- hostname: nfs-server (will be customized per instance)

## 🚀 Usage

### 1. Via Main Orchestration Script

The easiest way to create templates is through the main deployment script:

```bash
cd ..
python3 deploy.py
# Select "Create new template" option
# Follow the interactive prompts
```

### 2. Manual Packer Build

If you prefer to run Packer directly:

#### Prepare Variables File

```bash
cat > packer/vars.pkrvars.hcl << EOF
vcenter_host           = "vcenter.example.com"
vcenter_user           = "administrator@vsphere.local"
vcenter_password       = "your_password"
vcenter_datacenter     = "Datacenter"
vcenter_cluster        = "Cluster"
vcenter_datastore      = "Datastore1"
vcenter_network        = "VM Network"
vcenter_folder         = "/vm/k3s-infrastructure"
template_name          = "debian-k3s-node-template"
iso_datastore          = "Datastore1"
iso_path               = "/iso/debian-12.6.0-amd64-netinst.iso"
cpu_cores              = 2
memory_mb              = 4096
disk_size_gb           = 40
EOF
```

#### Validate Template

```bash
packer validate -var-file=vars.pkrvars.hcl templates/debian-k3s-node.json
```

#### Build Template

```bash
packer build -var-file=vars.pkrvars.hcl templates/debian-k3s-node.json
```

### 3. Build NFS Template

```bash
cat > packer/vars-nfs.pkrvars.hcl << EOF
vcenter_host           = "vcenter.example.com"
vcenter_user           = "administrator@vsphere.local"
vcenter_password       = "your_password"
vcenter_datacenter     = "Datacenter"
vcenter_cluster        = "Cluster"
vcenter_datastore      = "Datastore1"
vcenter_network        = "VM Network"
vcenter_folder         = "/vm/k3s-infrastructure"
template_name          = "debian-nfs-server-template"
iso_datastore          = "Datastore1"
iso_path               = "/iso/debian-12.6.0-amd64-netinst.iso"
cpu_cores              = 2
memory_mb              = 4096
disk_size_gb           = 40
additional_disk_size_gb = 500
EOF

packer validate -var-file=vars-nfs.pkrvars.hcl templates/debian-nfs-server.json
packer build -var-file=vars-nfs.pkrvars.hcl templates/debian-nfs-server.json
```

## 🔧 Customization

### Modify Hardware Specifications

Edit the variables when running Packer:

```bash
packer build \
  -var 'cpu_cores=4' \
  -var 'memory_mb=8192' \
  -var 'disk_size_gb=50' \
  -var-file=vars.pkrvars.hcl \
  templates/debian-k3s-node.json
```

### Modify Installed Packages

Edit `packer/scripts/base-setup.sh` to add or remove packages:

```bash
# In base-setup.sh, modify the apt-get install section
sudo apt-get install -y \
  # your-new-package \
  existing-package
```

### Modify Preseed Configuration

Edit `packer/http/preseed.cfg` to change:
- Keyboard layout
- Timezone
- Partition layout
- Installed packages during OS installation

## 📊 Build Process

When Packer builds a template:

1. **Boot Phase**
   - vSphere ISO is attached to VM
   - Debian boot menu is accessed
   - Preseed configuration is served via HTTP
   - Unattended installation begins

2. **Installation Phase**
   - Debian OS is installed
   - Partitions are formatted and mounted
   - Basic packages are installed
   - Network is configured

3. **Provisioning Phase**
   - SSH connection established
   - Provisioning scripts are uploaded
   - Base OS setup runs (base-setup.sh)
   - Template-specific scripts run (k3s-prep.sh or nfs-prep.sh)
   - System cleanup and optimization
   - SSH keys are cleared
   - Machine is shut down

4. **Finalization Phase**
   - VM is converted to template
   - Manifest is generated with metadata

## 📝 Build Output

After a successful build:

- **VM Template** created in vSphere under specified folder
- **Manifest File** generated: `manifest-k3s-node.json` or `manifest-nfs-server.json`
- **Log File** created: `packer-manifest.log`

Example manifest:

```json
{
  "builds": [
    {
      "name": "vsphere-iso",
      "builder_type": "vsphere-iso",
      "build_time": 1234567890,
      "files": null,
      "artifact_id": "debian-k3s-node-template",
      "packer_run_uuid": "abc-123-def-456",
      "custom_data": {
        "template_type": "k3s-node",
        "created_at": "2024-12-24T13:30:00Z"
      }
    }
  ]
}
```

## 🔐 Security Considerations

### SSH Security

- Default SSH credentials (root:packer, debian:packer) are cleaned after template creation
- SSH host keys are regenerated on first boot
- SSH key-based authentication is configured for cloud-init

### System Hardening

- Swap is disabled (Kubernetes requirement)
- SELinux is not used (Debian default)
- UFW firewall configuration should be done in Terraform/Ansible

### Data Cleanup

The template cleanup process removes:
- SSH keys and authorized_keys
- Command history
- Temporary files
- Log files
- cloud-init configuration

## 🐛 Troubleshooting

### Build Fails at Boot

**Issue:** Packer can't establish SSH connection

**Solutions:**
1. Check ISO path is correct
2. Verify preseed.cfg is being served via HTTP
3. Check SSH credentials in template variables
4. Review vSphere VM console for error messages

### Build Hangs at Provisioning

**Issue:** SSH connection times out

**Solutions:**
1. Check network connectivity from Packer to VM
2. Verify SSH port (22) is not blocked
3. Increase ssh_timeout in template
4. Check vSphere VM console for system state

### Template Not Found in vSphere

**Issue:** Packer reports success but template not visible

**Solutions:**
1. Check vSphere folder path exists
2. Verify folder path syntax (use full path: /vm/folder/subfolder)
3. Check user permissions on folder
4. Search vSphere for template by exact name

### Disk Space Issues

**Issue:** Packer build fails with "disk full" error

**Solutions:**
1. Increase datastore free space
2. Reduce disk_size_gb parameter
3. Clean up old templates in vSphere

## 📦 Dependencies

### External Tools
- Packer >= 1.8.0
- vSphere >= 6.7

### Debian Packages (Pre-installed)
- docker-ce
- podman
- nfs-common
- keepalived
- rsync
- curl
- git

### ISO Requirements
- Debian 12 (or compatible)
- Netinstall ISO recommended (smaller, faster)
- Must be in ISO format (.iso)

## 🔄 Workflow Integration

After templates are created:

1. **Next Step:** Terraform uses these templates to create VMs
2. **Terraform** reads template names from configuration
3. **Terraform** clones templates for each node
4. **Ansible** configures the cloned VMs

## 📚 References

- [Packer vSphere ISO Documentation](https://www.packer.io/plugins/builders/vsphere/vsphere-iso)
- [Debian Preseed Documentation](https://www.debian.org/releases/stable/amd64/preseed-using.en.html)
- [k3s Installation Guide](https://docs.k3s.io/installation)
- [NFS Server Configuration](https://wiki.debian.org/NFS/Server)

## 📞 Support

For issues or questions:

1. Check Packer logs: `packer build -debug`
2. Review vSphere VM console during build
3. Check preseed configuration for Debian installer errors
4. Verify all variables are set correctly

---

**Status:** ✅ Production Ready

**Last Updated:** 2024-12-24

**Next Section:** [Terraform](../terraform/README.md)
