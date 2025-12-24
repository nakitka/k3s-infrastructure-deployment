#!/usr/bin/env python3
"""
K3s Infrastructure Deployment Orchestration Script

Automates the entire process of:
1. Creating VM templates with Packer
2. Provisioning infrastructure with Terraform
3. Configuring systems with Ansible
4. Deploying services with Helm
"""

import os
import sys
import json
import yaml
import argparse
import subprocess
import shutil
from pathlib import Path
from typing import Dict, List, Any, Optional, Tuple
from dataclasses import dataclass
from enum import Enum
import logging
from datetime import datetime

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(f'deployment_{datetime.now().strftime("%Y%m%d_%H%M%S")}.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)


class Color:
    """Terminal color codes"""
    HEADER = '\033[95m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'


class DeploymentSection(Enum):
    """Deployment sections"""
    PACKER = "packer"
    TERRAFORM = "terraform"
    ANSIBLE = "ansible"
    HELM = "helm"


@dataclass
class PackerConfig:
    """Packer configuration dataclass"""
    template_name: str
    template_type: str  # 'k3s-node' or 'nfs-server'
    vcenter_host: str
    vcenter_user: str
    vcenter_password: str
    vcenter_datacenter: str
    vcenter_cluster: str
    vcenter_datastore: str
    vcenter_network: str
    vcenter_folder: str
    iso_datastore: str
    iso_path: str
    guest_os_type: str = "debian10_64Guest"
    cpu_cores: int = 2
    memory_mb: int = 4096
    disk_size_gb: int = 40
    additional_disk_size_gb: Optional[int] = None  # For NFS servers


class ConfigManager:
    """Manages configuration files and parameters"""

    def __init__(self, config_path: Optional[str] = None):
        self.config_path = Path(config_path) if config_path else None
        self.config: Dict[str, Any] = {}
        self.temp_config: Dict[str, Any] = {}

    def load_config(self, path: Path) -> Dict[str, Any]:
        """Load configuration from YAML file"""
        try:
            with open(path, 'r') as f:
                config = yaml.safe_load(f)
            logger.info(f"Loaded configuration from {path}")
            return config
        except FileNotFoundError:
            logger.error(f"Configuration file not found: {path}")
            return {}
        except yaml.YAMLError as e:
            logger.error(f"Error parsing YAML: {e}")
            return {}

    def save_config(self, config: Dict[str, Any], path: Path) -> bool:
        """Save configuration to YAML file"""
        try:
            path.parent.mkdir(parents=True, exist_ok=True)
            with open(path, 'w') as f:
                yaml.dump(config, f, default_flow_style=False, sort_keys=False)
            logger.info(f"Saved configuration to {path}")
            return True
        except Exception as e:
            logger.error(f"Error saving configuration: {e}")
            return False

    def print_config(self, config: Dict[str, Any], indent: int = 0) -> None:
        """Pretty print configuration"""
        for key, value in config.items():
            if isinstance(value, dict):
                print(f"{'  ' * indent}{Color.CYAN}{key}:{Color.ENDC}")
                self.print_config(value, indent + 1)
            else:
                print(f"{'  ' * indent}{Color.BOLD}{key}:{Color.ENDC} {value}")

    def prompt_yes_no(self, message: str) -> bool:
        """Prompt user for yes/no input"""
        while True:
            response = input(f"{Color.YELLOW}{message} (y/n): {Color.ENDC}").lower().strip()
            if response in ['y', 'yes']:
                return True
            elif response in ['n', 'no']:
                return False
            else:
                print("Please enter 'y' or 'n'")

    def prompt_choice(self, message: str, choices: List[str]) -> str:
        """Prompt user to select from a list of choices"""
        while True:
            print(f"\n{Color.YELLOW}{message}{Color.ENDC}")
            for i, choice in enumerate(choices, 1):
                print(f"  {i}. {choice}")
            try:
                selection = int(input(f"\n{Color.BOLD}Enter selection (1-{len(choices)}): {Color.ENDC}"))
                if 1 <= selection <= len(choices):
                    return choices[selection - 1]
                else:
                    print(f"Please enter a number between 1 and {len(choices)}")
            except ValueError:
                print("Please enter a valid number")

    def prompt_value(self, prompt: str, default: Optional[str] = None) -> str:
        """Prompt user for a value with optional default"""
        if default:
            prompt_text = f"{prompt} [{Color.GREEN}{default}{Color.ENDC}]"
        else:
            prompt_text = prompt
        
        value = input(f"{Color.YELLOW}{prompt_text}: {Color.ENDC}").strip()
        return value if value else default or ""


class PackerManager:
    """Manages Packer operations"""

    def __init__(self, packer_dir: Path):
        self.packer_dir = Path(packer_dir)
        self.templates_dir = self.packer_dir / "templates"
        self.scripts_dir = self.packer_dir / "scripts"
        self.http_dir = self.packer_dir / "http"

    def get_available_templates(self) -> List[str]:
        """Get list of available Packer template files"""
        if not self.templates_dir.exists():
            return []
        return [f.stem for f in self.templates_dir.glob("*.json")]

    def get_required_parameters(self, template_type: str) -> Dict[str, Any]:
        """Get required parameters for a specific template type"""
        base_params = {
            'template_name': 'Name for the VM template',
            'vcenter_host': 'vCenter host FQDN',
            'vcenter_user': 'vCenter username',
            'vcenter_password': 'vCenter password',
            'vcenter_datacenter': 'vCenter datacenter name',
            'vcenter_cluster': 'vCenter cluster name',
            'vcenter_datastore': 'vCenter datastore for OS disk',
            'vcenter_network': 'vCenter network name',
            'vcenter_folder': 'vCenter folder path',
            'iso_datastore': 'Datastore containing ISO',
            'iso_path': 'Path to Debian ISO file',
            'cpu_cores': 'Number of CPU cores (default: 2)',
            'memory_mb': 'Memory in MB (default: 4096)',
            'disk_size_gb': 'OS disk size in GB (default: 40)',
        }

        if template_type == 'nfs-server':
            base_params['additional_disk_size_gb'] = 'Additional storage disk size in GB (for NFS)'

        return base_params

    def generate_packer_config(self, config: PackerConfig) -> Dict[str, Any]:
        """Generate Packer configuration dictionary"""
        packer_config = {
            'variables': {
                'vcenter_host': config.vcenter_host,
                'vcenter_user': config.vcenter_user,
                'vcenter_password': config.vcenter_password,
                'vcenter_datacenter': config.vcenter_datacenter,
                'vcenter_cluster': config.vcenter_cluster,
                'vcenter_datastore': config.vcenter_datastore,
                'vcenter_network': config.vcenter_network,
                'vcenter_folder': config.vcenter_folder,
                'template_name': config.template_name,
                'iso_datastore': config.iso_datastore,
                'iso_path': config.iso_path,
                'cpu_cores': str(config.cpu_cores),
                'memory_mb': str(config.memory_mb),
                'disk_size_gb': str(config.disk_size_gb),
            },
            'builders': [
                {
                    'type': 'vsphere-iso',
                    'vcenter_server': '{{ user `vcenter_host` }}',
                    'username': '{{ user `vcenter_user` }}',
                    'password': '{{ user `vcenter_password` }}',
                    'datacenter': '{{ user `vcenter_datacenter` }}',
                    'cluster': '{{ user `vcenter_cluster` }}',
                    'datastore': '{{ user `vcenter_datastore` }}',
                    'vm_name': '{{ user `template_name` }}',
                    'network': '{{ user `vcenter_network` }}',
                    'folder': '{{ user `vcenter_folder` }}',
                    'iso_datastore': '{{ user `iso_datastore` }}',
                    'iso_path': '{{ user `iso_path` }}',
                    'cpus': '{{ user `cpu_cores` }}',
                    'memory': '{{ user `memory_mb` }}',
                    'disk_size': '{{ user `disk_size_gb` }}',
                    'disk_thin_provisioned': True,
                    'guest_os_type': config.guest_os_type,
                    'notes': f'Template created for {config.template_type}',
                    'boot_wait': '10s',
                    'boot_command': [
                        '<esc><esc><esc>',
                        '<enter><wait>',
                        'install <wait>',
                        'preseed/url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed.cfg <wait>',
                        'debian-installer=en_US.UTF-8 <wait>',
                        'auto locale=en_US.UTF-8 <wait>',
                        'kbd-chooser/method=us <wait>',
                        'netcfg/get_hostname={{ .Name }} <wait>',
                        'netcfg/get_domain=local <wait>',
                        'fb=false debconf/verbose=false <wait>',
                        'console-setup/ask_detect=false console-keymaps-at/keymap=us <wait>',
                        '<enter><wait>'
                    ],
                    'http_directory': str(self.http_dir),
                    'http_port_min': 8000,
                    'http_port_max': 9000,
                    'shutdown_command': 'echo \'packer\' | sudo -S shutdown -P now',
                    'communicator': 'ssh',
                    'ssh_username': 'root',
                    'ssh_password': 'packer',
                    'ssh_port': 22,
                    'ssh_timeout': '20m',
                    'ssh_pty': True,
                }
            ],
            'provisioners': [
                {
                    'type': 'shell',
                    'inline': ['sleep 5']
                },
                {
                    'type': 'file',
                    'source': str(self.scripts_dir),
                    'destination': '/tmp/scripts'
                },
                {
                    'type': 'shell',
                    'script': str(self.scripts_dir / 'base-setup.sh')
                }
            ]
        }

        # Add template-specific provisioners
        if config.template_type == 'k3s-node':
            packer_config['provisioners'].append({
                'type': 'shell',
                'script': str(self.scripts_dir / 'k3s-prep.sh')
            })
        elif config.template_type == 'nfs-server':
            packer_config['provisioners'].append({
                'type': 'shell',
                'script': str(self.scripts_dir / 'nfs-prep.sh')
            })

        return packer_config

    def run_packer_build(self, template_file: Path, var_file: Optional[Path] = None) -> bool:
        """Run Packer build"""
        try:
            cmd = ['packer', 'build', str(template_file)]
            if var_file:
                cmd.extend(['-var-file', str(var_file)])
            
            logger.info(f"Running Packer build: {' '.join(cmd)}")
            result = subprocess.run(cmd, cwd=self.packer_dir, check=True)
            logger.info("Packer build completed successfully")
            return True
        except subprocess.CalledProcessError as e:
            logger.error(f"Packer build failed: {e}")
            return False
        except FileNotFoundError:
            logger.error("Packer not found. Please install Packer.")
            return False


class DeploymentOrchestrator:
    """Main orchestration class"""

    def __init__(self, base_dir: Optional[str] = None):
        self.base_dir = Path(base_dir) if base_dir else Path.cwd()
        self.config_dir = self.base_dir / "config"
        self.packer_dir = self.base_dir / "packer"
        self.terraform_dir = self.base_dir / "terraform"
        self.ansible_dir = self.base_dir / "ansible"
        self.helm_dir = self.base_dir / "helm"
        
        self.config_manager = ConfigManager()
        self.packer_manager = PackerManager(self.packer_dir)
        self.current_config: Dict[str, Any] = {}

    def print_header(self, text: str) -> None:
        """Print formatted header"""
        print(f"\n{Color.HEADER}{Color.BOLD}{'=' * 70}")
        print(f"{text.center(70)}")
        print(f"{'=' * 70}{Color.ENDC}\n")

    def print_section(self, text: str) -> None:
        """Print formatted section"""
        print(f"\n{Color.CYAN}{Color.BOLD}>>> {text}{Color.ENDC}\n")

    def packer_section(self) -> bool:
        """Handle Packer section"""
        self.print_header("PACKER SECTION - VM TEMPLATE CREATION")
        
        choices = [
            "Create new template",
            "Create new configuration",
            "Use existing template"
        ]
        
        selection = self.config_manager.prompt_choice(
            "What would you like to do?",
            choices
        )

        if selection == "Create new template":
            return self._create_from_existing_config()
        elif selection == "Create new configuration":
            return self._create_new_config()
        elif selection == "Use existing template":
            return self._use_existing_template()

    def _create_from_existing_config(self) -> bool:
        """Create template from existing configuration"""
        self.print_section("Create New Template from Existing Config")
        
        config_path = Path(self.config_manager.prompt_value(
            "Enter configuration file path",
            str(self.config_dir / "default.yaml")
        ))

        if not config_path.exists():
            logger.error(f"Configuration file not found: {config_path}")
            return False

        config = self.config_manager.load_config(config_path)
        if not config:
            return False

        # Display current configuration
        self.print_section("Current Configuration Parameters")
        self.config_manager.print_config(config)

        if not self.config_manager.prompt_yes_no("\nDo you want to modify any parameters?"):
            return self._proceed_with_packer_build(config)

        return self._handle_parameter_changes(config, config_path)

    def _create_new_config(self) -> bool:
        """Create new configuration from scratch"""
        self.print_section("Create New Configuration")
        
        save_path = Path(self.config_manager.prompt_value(
            "Enter path where to save the configuration",
            str(self.config_dir / "custom-config.yaml")
        ))

        config = self._gather_template_parameters()
        if not config:
            return False

        # Display new configuration
        self.print_section("New Configuration Parameters")
        self.config_manager.print_config(config)

        if self.config_manager.prompt_yes_no("\nSave this configuration?"):
            if self.config_manager.save_config(config, save_path):
                self.current_config = config
                return self._proceed_with_packer_build(config)
        
        return False

    def _gather_template_parameters(self) -> Dict[str, Any]:
        """Interactively gather template parameters"""
        self.print_section("Template Configuration Wizard")
        
        config = {}
        
        # Template type selection
        template_type = self.config_manager.prompt_choice(
            "Select template type",
            ["k3s-node", "nfs-server"]
        )
        config['template_type'] = template_type
        
        # Get required parameters
        params = self.packer_manager.get_required_parameters(template_type)
        
        # Gather each parameter
        print(f"\n{Color.BOLD}Enter template parameters:{Color.ENDC}\n")
        
        for param, description in params.items():
            value = self.config_manager.prompt_value(f"{description} ({param})")
            if value:
                # Try to convert numeric values
                if param.endswith('_mb') or param.endswith('_gb') or param == 'cpu_cores':
                    try:
                        config[param] = int(value)
                    except ValueError:
                        config[param] = value
                else:
                    config[param] = value
        
        return config

    def _handle_parameter_changes(self, config: Dict[str, Any], config_path: Path) -> bool:
        """Handle parameter modification options"""
        while True:
            # Edit parameters
            param_to_edit = self.config_manager.prompt_value(
                "Enter parameter name to change (or 'done' to continue)"
            )
            
            if param_to_edit.lower() == 'done':
                break
            
            if param_to_edit in config:
                new_value = self.config_manager.prompt_value(
                    f"Enter new value for {param_to_edit}",
                    str(config[param_to_edit])
                )
                config[param_to_edit] = new_value
                print(f"{Color.GREEN}Parameter updated{Color.ENDC}\n")
            else:
                print(f"{Color.RED}Parameter not found{Color.ENDC}\n")
        
        # Ask what to do with changes
        choices = [
            "Write changes to config permanently",
            "Use changes only for this run",
            "Return to editing",
            "Discard changes"
        ]
        
        decision = self.config_manager.prompt_choice(
            "What would you like to do with these changes?",
            choices
        )
        
        if decision == "Write changes to config permanently":
            if self.config_manager.save_config(config, config_path):
                return self._proceed_with_packer_build(config)
        elif decision == "Use changes only for this run":
            return self._proceed_with_packer_build(config)
        elif decision == "Return to editing":
            return self._handle_parameter_changes(config, config_path)
        else:  # Discard changes
            logger.info("Changes discarded")
            original_config = self.config_manager.load_config(config_path)
            return self._proceed_with_packer_build(original_config)

    def _use_existing_template(self) -> bool:
        """Use existing template and proceed to Terraform"""
        self.print_section("Use Existing Template")
        
        available_templates = self.packer_manager.get_available_templates()
        
        if not available_templates:
            logger.error("No Packer templates found")
            return False
        
        selected = self.config_manager.prompt_choice(
            "Select template to use",
            available_templates
        )
        
        print(f"{Color.GREEN}Using template: {selected}{Color.ENDC}")
        logger.info(f"Selected existing template: {selected}")
        
        # Store template selection
        self.current_config['selected_template'] = selected
        
        # Ask if user wants to proceed with actual build or just testing
        if self.config_manager.prompt_yes_no("\nProceed to Terraform section?"):
            return True
        return False

    def _proceed_with_packer_build(self, config: Dict[str, Any]) -> bool:
        """Proceed with Packer build"""
        self.current_config = config
        
        if self.config_manager.prompt_yes_no("\nProceed with Packer template creation?"):
            self.print_section("Building Packer Template")
            
            # For now, just simulate
            print(f"{Color.GREEN}Packer build would run here{Color.ENDC}")
            print(f"Template Type: {config.get('template_type', 'unknown')}")
            print(f"Template Name: {config.get('template_name', 'unknown')}")
            
            logger.info(f"Packer build configured: {config.get('template_name')}")
            
            if self.config_manager.prompt_yes_no("\nProceed to Terraform section?"):
                return True
        
        return False

    def run(self) -> None:
        """Run the deployment orchestration"""
        self.print_header("K3s INFRASTRUCTURE DEPLOYMENT ORCHESTRATION")
        
        print(f"{Color.BOLD}Base Directory:{Color.ENDC} {self.base_dir}")
        print(f"{Color.BOLD}Config Directory:{Color.ENDC} {self.config_dir}")
        print(f"{Color.BOLD}Packer Directory:{Color.ENDC} {self.packer_dir}\n")
        
        # Run Packer section
        if self.packer_section():
            self.print_header("PACKER SECTION COMPLETED")
            print(f"{Color.GREEN}✓ Ready to proceed to next section{Color.ENDC}\n")
        else:
            self.print_header("PACKER SECTION CANCELLED")
            print(f"{Color.YELLOW}Deployment cancelled by user{Color.ENDC}\n")
            return


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description='K3s Infrastructure Deployment Orchestration',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 deploy.py                  # Run with default paths
  python3 deploy.py --base /path     # Specify base directory
        """
    )
    
    parser.add_argument(
        '--base',
        type=str,
        help='Base directory for deployment (default: current directory)',
        default=None
    )
    
    parser.add_argument(
        '--config',
        type=str,
        help='Configuration file path',
        default=None
    )
    
    args = parser.parse_args()
    
    try:
        orchestrator = DeploymentOrchestrator(args.base)
        orchestrator.run()
    except KeyboardInterrupt:
        print(f"\n\n{Color.YELLOW}Deployment interrupted by user{Color.ENDC}")
        sys.exit(0)
    except Exception as e:
        logger.error(f"Fatal error: {e}", exc_info=True)
        print(f"\n{Color.RED}Fatal error: {e}{Color.ENDC}")
        sys.exit(1)


if __name__ == "__main__":
    main()
