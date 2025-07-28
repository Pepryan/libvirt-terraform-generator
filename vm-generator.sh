#!/bin/bash

# Script untuk generate Terraform files dan cloud-init config untuk Multiple KVM VM
# Usage: ./vm-generator.sh [config.yaml]

set -e

# Warna untuk output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function untuk print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function untuk check dependencies
check_dependencies() {
    if ! command -v yq &> /dev/null; then
        print_warning "yq tidak ditemukan, menggunakan manual parsing"
        USE_YQ=false
    else
        USE_YQ=true
    fi
}

# Function untuk generate example YAML config
generate_example_yaml() {
    cat > vms-config.yaml << 'EOF'
# Konfigurasi Multiple VM untuk KVM Terraform
global:
  # Storage pools
  image_pool: "images"      # Pool untuk cloud images
  vm_pool: "vms"           # Pool untuk VM disks
  
  # Default cloud image
  cloud_image: "ubuntu-22.04-server-cloudimg-amd64.img"
  
  # Network defaults
  network_name: "default"   # atau custom network name
  domain: "local"
  
  # User defaults
  ssh_user: "ubuntu"
  ssh_password: "ubuntu"
  ssh_password_auth: true
  timezone: "Asia/Jakarta"
  
  # SSH public key (akan dicari otomatis jika kosong)
  ssh_public_key: ""
  
  # Default packages untuk semua VM
  packages:
    - qemu-guest-agent
    - curl
    - wget
    - vim
    - htop
    - net-tools
    - git

# Definisi VM
vms:
  - name: "web-server-01"
    cpu: 2
    ram_gb: 4                # Input dalam GB, otomatis convert ke MB
    disk_gb: 20             # Input dalam GB
    network_type: "static"   # dhcp atau static
    ip: "192.168.122.10"
    gateway: "192.168.122.1"
    netmask: "24"
    dns: ["8.8.8.8", "8.8.4.4"]
    packages:               # Package tambahan selain global
      - nginx
      - mysql-server
    commands:               # Custom commands
      - "systemctl enable nginx"
      - "ufw allow 22,80,443/tcp"

  - name: "web-server-02"
    cpu: 2
    ram_gb: 4
    disk_gb: 20
    network_type: "static"
    ip: "192.168.122.11"
    gateway: "192.168.122.1"
    netmask: "24"
    dns: ["8.8.8.8", "8.8.4.4"]
    packages:
      - nginx
    commands:
      - "systemctl enable nginx"

  - name: "db-server-01"
    cpu: 4
    ram_gb: 8
    disk_gb: 50
    network_type: "static"
    ip: "192.168.122.20"
    gateway: "192.168.122.1"
    netmask: "24"
    dns: ["8.8.8.8", "8.8.4.4"]
    packages:
      - postgresql
      - postgresql-contrib
    commands:
      - "systemctl enable postgresql"

  - name: "app-server-01"
    cpu: 2
    ram_gb: 6
    disk_gb: 30
    network_type: "dhcp"     # Menggunakan DHCP
    packages:
      - docker.io
      - docker-compose
    commands:
      - "systemctl enable docker"
      - "usermod -aG docker ubuntu"

  # Contoh untuk load balancer
  - name: "lb-server-01"
    cpu: 1
    ram_gb: 2
    disk_gb: 20
    network_type: "static"
    ip: "192.168.122.5"
    gateway: "192.168.122.1"
    netmask: "24"
    dns: ["8.8.8.8", "8.8.4.4"]
    packages:
      - haproxy
    commands:
      - "systemctl enable haproxy"
EOF

    print_success "Generated example vms-config.yaml"
}

# Function untuk parse YAML (simple parser jika yq tidak ada)
parse_yaml() {
    local yaml_file="$1"
    local prefix="$2"
    
    if [ "$USE_YQ" = true ]; then
        # Menggunakan yq untuk parsing yang lebih akurat
        case "$prefix" in
            "global")
                IMAGE_POOL=$(yq -r '.global.image_pool' "$yaml_file")
                VM_POOL=$(yq -r '.global.vm_pool' "$yaml_file")
                CLOUD_IMAGE=$(yq -r '.global.cloud_image' "$yaml_file")
                NETWORK_NAME=$(yq -r '.global.network_name' "$yaml_file")
                DOMAIN=$(yq -r '.global.domain' "$yaml_file")
                SSH_USER=$(yq -r '.global.ssh_user' "$yaml_file")
                SSH_PASSWORD=$(yq -r '.global.ssh_password' "$yaml_file")
                SSH_PASSWORD_AUTH=$(yq -r '.global.ssh_password_auth' "$yaml_file")
                TIMEZONE=$(yq -r '.global.timezone' "$yaml_file")
                SSH_PUBLIC_KEY=$(yq -r '.global.ssh_public_key' "$yaml_file")
                ;;
        esac
    else
        # Simple grep-based parsing untuk basic cases
        print_warning "Menggunakan simple YAML parser. Untuk hasil terbaik, install yq"
        IMAGE_POOL=$(grep "image_pool:" "$yaml_file" | cut -d'"' -f2)
        VM_POOL=$(grep "vm_pool:" "$yaml_file" | cut -d'"' -f2)
        CLOUD_IMAGE=$(grep "cloud_image:" "$yaml_file" | cut -d'"' -f2)
        NETWORK_NAME=$(grep "network_name:" "$yaml_file" | cut -d'"' -f2)
        DOMAIN=$(grep "domain:" "$yaml_file" | cut -d'"' -f2)
        SSH_USER=$(grep "ssh_user:" "$yaml_file" | cut -d'"' -f2)
        SSH_PASSWORD=$(grep "ssh_password:" "$yaml_file" | cut -d'"' -f2)
        SSH_PASSWORD_AUTH=$(grep "ssh_password_auth:" "$yaml_file" | cut -d' ' -f2)
        TIMEZONE=$(grep "timezone:" "$yaml_file" | cut -d'"' -f2)
    fi
    
    # Auto-detect SSH public key jika kosong
    if [ -z "$SSH_PUBLIC_KEY" ] || [ "$SSH_PUBLIC_KEY" = "null" ]; then
        if [ -f "$HOME/.ssh/id_rsa.pub" ]; then
            SSH_PUBLIC_KEY=$(cat "$HOME/.ssh/id_rsa.pub")
            print_info "Auto-detected SSH public key"
        else
            print_warning "SSH public key tidak ditemukan di $HOME/.ssh/id_rsa.pub"
        fi
    fi
}

# Function untuk get VM count dari YAML
get_vm_count() {
    local yaml_file="$1"
    if [ "$USE_YQ" = true ]; then
        yq -r '.vms | length' "$yaml_file"
    else
        grep -c "^  - name:" "$yaml_file" || echo "0"
    fi
}

# Function untuk get VM data
get_vm_data() {
    local yaml_file="$1"
    local vm_index="$2"
    
    if [ "$USE_YQ" = true ]; then
        VM_NAME=$(yq -r ".vms[$vm_index].name" "$yaml_file")
        VM_CPU=$(yq -r ".vms[$vm_index].cpu" "$yaml_file")
        VM_RAM_GB=$(yq -r ".vms[$vm_index].ram_gb" "$yaml_file")
        VM_DISK_GB=$(yq -r ".vms[$vm_index].disk_gb" "$yaml_file")
        VM_NETWORK_TYPE=$(yq -r ".vms[$vm_index].network_type" "$yaml_file")
        VM_IP=$(yq -r ".vms[$vm_index].ip" "$yaml_file")
        VM_GATEWAY=$(yq -r ".vms[$vm_index].gateway" "$yaml_file")
        VM_NETMASK=$(yq -r ".vms[$vm_index].netmask" "$yaml_file")
        
        # Convert GB to MB untuk RAM
        VM_RAM_MB=$((VM_RAM_GB * 1024))
        
        # Convert GB to bytes untuk disk (dalam Terraform libvirt)
        VM_DISK_BYTES=$((VM_DISK_GB * 1073741824))
    else
        print_error "Simple parser tidak support multiple VM. Gunakan yq atau mode interactive."
        return 1
    fi
}

# Function untuk create deployment directory
create_deployment_directory() {
    local deployment_name="$1"
    local deployment_dir="deployment-${deployment_name}"
    
    if [ -d "$deployment_dir" ]; then
        print_warning "Deployment directory '$deployment_dir' already exists!"
        read -p "Do you want to overwrite? (y/N): " confirm
        if [[ ! $confirm =~ ^[Yy]$ ]]; then
            print_info "Deployment cancelled. Use different name or remove existing directory."
            exit 1
        fi
        print_warning "Overwriting existing deployment directory..."
        rm -rf "$deployment_dir"
    fi
    
    mkdir -p "$deployment_dir"
    DEPLOYMENT_DIR="$deployment_dir"
    print_success "Created deployment directory: $deployment_dir"
}

# Function untuk generate main.tf untuk multiple VMs
generate_main_tf_multiple() {
    local yaml_file="$1"
    local vm_count=$(get_vm_count "$yaml_file")
    
    # Get the actual path of cloud image from virsh pool
    local cloud_image_path=$(virsh vol-path "${CLOUD_IMAGE}" --pool "${IMAGE_POOL}" 2>/dev/null)
    if [ -z "$cloud_image_path" ]; then
        print_error "Cloud image '${CLOUD_IMAGE}' not found in pool '${IMAGE_POOL}'"
        print_info "Available images in pool '${IMAGE_POOL}':"
        virsh vol-list "${IMAGE_POOL}" --details
        exit 1
    fi
    
    cat > "${DEPLOYMENT_DIR}/main.tf" << EOF
terraform {
  required_version = ">= 0.13"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.8.3"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

# Base volumes are directly referenced from the image pool
# No need to copy the base image, volumes will use base_volume_name

EOF

    # Generate resources untuk setiap VM
    for ((i=0; i<vm_count; i++)); do
        get_vm_data "$yaml_file" "$i"
        
        if [ "$VM_NAME" = "null" ]; then
            continue
        fi
        
    cat >> "${DEPLOYMENT_DIR}/main.tf" << EOF
# VM ${VM_NAME} - Disk
resource "libvirt_volume" "${VM_NAME}_disk" {
  name               = "${VM_NAME}-disk.qcow2"
  pool               = "${VM_POOL}"
  base_volume_name   = "${CLOUD_IMAGE}"
  base_volume_pool   = "${IMAGE_POOL}"
  size               = ${VM_DISK_BYTES}  # ${VM_DISK_GB}GB
  format             = "qcow2"
}

# VM ${VM_NAME} - Cloud-init
resource "libvirt_cloudinit_disk" "${VM_NAME}_cloudinit" {
  name           = "${VM_NAME}-cloudinit.iso"
  pool           = "${VM_POOL}"
  user_data      = file("cloudinit_${VM_NAME}.cfg")
  network_config = file("network_${VM_NAME}.cfg")
}

# VM ${VM_NAME} - Domain
resource "libvirt_domain" "${VM_NAME}" {
  name   = "${VM_NAME}"
  memory = "${VM_RAM_MB}"  # ${VM_RAM_GB}GB
  vcpu   = ${VM_CPU}

  cloudinit = libvirt_cloudinit_disk.${VM_NAME}_cloudinit.id

EOF

        # Generate network interface berdasarkan tipe
        if [ "$VM_NETWORK_TYPE" = "static" ]; then
            cat >> "${DEPLOYMENT_DIR}/main.tf" << EOF
  network_interface {
    network_name   = "${NETWORK_NAME}"
    wait_for_lease = false
    addresses      = ["${VM_IP}"]
  }
EOF
        else
            cat >> "${DEPLOYMENT_DIR}/main.tf" << EOF
  network_interface {
    network_name   = "${NETWORK_NAME}"
    wait_for_lease = true
  }
EOF
        fi
        
        cat >> "${DEPLOYMENT_DIR}/main.tf" << EOF


  disk {
    volume_id = libvirt_volume.${VM_NAME}_disk.id
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
}

EOF
    done

    # Generate outputs
    cat >> "${DEPLOYMENT_DIR}/main.tf" << EOF

# Outputs
EOF

    for ((i=0; i<vm_count; i++)); do
        get_vm_data "$yaml_file" "$i"
        
        if [ "$VM_NAME" = "null" ]; then
            continue
        fi
        
        cat >> "${DEPLOYMENT_DIR}/main.tf" << EOF
output "${VM_NAME}_ip" {
  value = libvirt_domain.${VM_NAME}.network_interface[0].addresses[0]
}

output "${VM_NAME}_ssh" {
  value = "ssh ${SSH_USER}@\${libvirt_domain.${VM_NAME}.network_interface[0].addresses[0]}"
}

EOF
    done

    print_success "Generated main.tf with ${vm_count} VMs"
}

# Function untuk generate cloud-init config untuk specific VM
generate_cloudinit_vm() {
    local vm_name="$1"
    local vm_index="$2"
    local yaml_file="$3"
    
    # Get VM specific data
    get_vm_data "$yaml_file" "$vm_index"
    
    # Get packages untuk VM ini
    local vm_packages=""
    if [ "$USE_YQ" = true ]; then
        local package_count=$(yq -r ".vms[$vm_index].packages | length" "$yaml_file")
        if [ "$package_count" != "null" ] && [ "$package_count" -gt 0 ]; then
            for ((p=0; p<package_count; p++)); do
                local pkg=$(yq -r ".vms[$vm_index].packages[$p]" "$yaml_file")
                vm_packages="${vm_packages}  - ${pkg}\n"
            done
        fi
        
        # Get global packages
        local global_package_count=$(yq -r ".global.packages | length" "$yaml_file")
        if [ "$global_package_count" != "null" ] && [ "$global_package_count" -gt 0 ]; then
            for ((p=0; p<global_package_count; p++)); do
                local pkg=$(yq -r ".global.packages[$p]" "$yaml_file")
                vm_packages="${vm_packages}  - ${pkg}\n"
            done
        fi
        
        # Get custom commands
        local vm_commands=""
        local command_count=$(yq -r ".vms[$vm_index].commands | length" "$yaml_file")
        if [ "$command_count" != "null" ] && [ "$command_count" -gt 0 ]; then
            for ((c=0; c<command_count; c++)); do
                local cmd=$(yq -r ".vms[$vm_index].commands[$c]" "$yaml_file")
                vm_commands="${vm_commands}  - ${cmd}\n"
            done
        fi
    fi
    
    cat > "${DEPLOYMENT_DIR}/cloudinit_${vm_name}.cfg" << EOF
#cloud-config
hostname: ${vm_name}
fqdn: ${vm_name}.${DOMAIN}
manage_etc_hosts: true

# User configuration
users:
  - name: ${SSH_USER}
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: users, admin, wheel, sudo
    home: /home/${SSH_USER}
    shell: /bin/bash
    lock_passwd: false
    ssh_authorized_keys:
      - ${SSH_PUBLIC_KEY}

# Set password for user
chpasswd:
  list: |
    ${SSH_USER}:${SSH_PASSWORD}
  expire: False

# SSH configuration
ssh_pwauth: ${SSH_PASSWORD_AUTH}
disable_root: true

# Timezone
timezone: ${TIMEZONE}

# Package update and install
package_update: true
package_upgrade: true

packages:
$(echo -e "$vm_packages")

# Services and custom commands
runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - systemctl enable ssh
  - systemctl start ssh
$(echo -e "$vm_commands")

# Final message
final_message: "VM ${vm_name} setup completed successfully!"

# Reboot after setup
power_state:
  mode: reboot
  delay: "+1"
  timeout: 60
  condition: True
EOF

    print_success "Generated cloudinit_${vm_name}.cfg"
}

# Function untuk generate network config untuk specific VM
generate_network_config_vm() {
    local vm_name="$1"
    local vm_index="$2"
    local yaml_file="$3"
    
    get_vm_data "$yaml_file" "$vm_index"
    
    if [ "$VM_NETWORK_TYPE" = "static" ]; then
        # Get DNS servers
        local dns_servers=""
        if [ "$USE_YQ" = true ]; then
            local dns_count=$(yq -r ".vms[$vm_index].dns | length" "$yaml_file")
            if [ "$dns_count" != "null" ] && [ "$dns_count" -gt 0 ]; then
                for ((d=0; d<dns_count; d++)); do
                    local dns=$(yq -r ".vms[$vm_index].dns[$d]" "$yaml_file")
                    dns_servers="${dns_servers}        - ${dns}\n"
                done
            else
                dns_servers="        - 8.8.8.8\n        - 8.8.4.4\n"
            fi
        fi
        
        cat > "${DEPLOYMENT_DIR}/network_${vm_name}.cfg" << EOF
version: 2
ethernets:
  ens3:
    dhcp4: false
    addresses:
      - ${VM_IP}/${VM_NETMASK}
    gateway4: ${VM_GATEWAY}
    nameservers:
      addresses:
$(echo -e "$dns_servers")
      search:
        - ${DOMAIN}
EOF
    else
        cat > "${DEPLOYMENT_DIR}/network_${vm_name}.cfg" << EOF
version: 2
ethernets:
  ens3:
    dhcp4: true
    dhcp6: false
EOF
    fi

    print_success "Generated network_${vm_name}.cfg"
}

# Function untuk generate Makefile untuk multiple VMs
generate_makefile_multiple() {
    local yaml_file="$1"
    local vm_count=$(get_vm_count "$yaml_file")
    
    cat > "${DEPLOYMENT_DIR}/Makefile" << 'EOF'
.PHONY: init plan apply destroy clean validate fmt output help

# Terraform commands
init:
	terraform init

plan:
	terraform plan

apply:
	terraform apply -auto-approve

destroy:
	terraform destroy -auto-approve

# Validate and format
validate:
	terraform validate

fmt:
	terraform fmt

# Show outputs
output:
	terraform output

# Show all VM IPs
ips:
	@terraform output | grep "_ip" | cut -d'=' -f2 | tr -d ' "'

# Clean temporary files
clean:
	rm -f terraform.tfstate*
	rm -f .terraform.lock.hcl
	rm -rf .terraform/
	rm -f *.iso

# Complete workflow
all: init plan apply

EOF

    # Generate SSH commands untuk setiap VM
    echo "# SSH commands for each VM" >> "${DEPLOYMENT_DIR}/Makefile"
    for ((i=0; i<vm_count; i++)); do
        get_vm_data "$yaml_file" "$i"
        
        if [ "$VM_NAME" = "null" ]; then
            continue
        fi
        
        cat >> "${DEPLOYMENT_DIR}/Makefile" << EOF
ssh-${VM_NAME}:
	@terraform output -raw ${VM_NAME}_ssh | sh

EOF
    done

    cat >> "${DEPLOYMENT_DIR}/Makefile" << 'EOF'

help:
	@echo "Available commands:"
	@echo "  init     - Initialize Terraform"
	@echo "  plan     - Show Terraform plan" 
	@echo "  apply    - Apply Terraform configuration"
	@echo "  destroy  - Destroy all VMs"
	@echo "  ips      - Show all VM IP addresses"
	@echo "  clean    - Clean temporary files"
	@echo "  validate - Validate Terraform files"
	@echo "  fmt      - Format Terraform files"
	@echo "  output   - Show all outputs"
	@echo "  all      - Run init, plan, and apply"
	@echo ""
	@echo "SSH Commands:"
EOF

    # Add SSH help
    for ((i=0; i<vm_count; i++)); do
            get_vm_data "$yaml_file" "$i"
            [ "$VM_NAME" = "null" ] && continue
            printf '\t@echo "  ssh-%s  - SSH to %s"\n' "$VM_NAME" "$VM_NAME"
        done >> "${DEPLOYMENT_DIR}/Makefile"

    print_success "Generated Makefile with ${vm_count} VM commands"
}

# Interactive mode untuk single/few VMs
interactive_mode() {
    print_info "=== Interactive Mode - Untuk VM Tunggal/Sedikit ==="
    
    # VM Configuration
    print_info "Konfigurasi VM:"
    read -p "Nama VM [test-vm]: " VM_NAME
    VM_NAME=${VM_NAME:-test-vm}
    
    read -p "CPU count [2]: " CPU_COUNT
    CPU_COUNT=${CPU_COUNT:-2}
    
    read -p "RAM (GB) [4]: " RAM_GB
    RAM_GB=${RAM_GB:-4}
    RAM_MB=$((RAM_GB * 1024))
    
    read -p "Disk size (GB) [20]: " DISK_GB
    DISK_GB=${DISK_GB:-20}
    
    # Storage pools
    read -p "Image pool [images]: " IMAGE_POOL
    IMAGE_POOL=${IMAGE_POOL:-images}
    
    read -p "VM disk pool [vms]: " VM_POOL
    VM_POOL=${VM_POOL:-vms}
    
    read -p "Cloud image filename [ubuntu-22.04-server-cloudimg-amd64.img]: " CLOUD_IMAGE
    CLOUD_IMAGE=${CLOUD_IMAGE:-ubuntu-22.04-server-cloudimg-amd64.img}
    
    # Network
    read -p "Network type (dhcp/static) [dhcp]: " NETWORK_TYPE
    NETWORK_TYPE=${NETWORK_TYPE:-dhcp}
    
    if [ "$NETWORK_TYPE" = "static" ]; then
        read -p "Static IP [192.168.122.10]: " STATIC_IP
        STATIC_IP=${STATIC_IP:-192.168.122.10}
        read -p "Gateway [192.168.122.1]: " GATEWAY
        GATEWAY=${GATEWAY:-192.168.122.1}
        read -p "Netmask [24]: " NETMASK
        NETMASK=${NETMASK:-24}
    fi
    
    # User config
    read -p "SSH User [ubuntu]: " SSH_USER
    SSH_USER=${SSH_USER:-ubuntu}
    
    read -p "SSH Password [ubuntu]: " SSH_PASSWORD
    SSH_PASSWORD=${SSH_PASSWORD:-ubuntu}
    
    # Auto SSH key
    if [ -f "$HOME/.ssh/id_rsa.pub" ]; then
        SSH_PUBLIC_KEY=$(cat "$HOME/.ssh/id_rsa.pub")
        print_info "Auto-detected SSH public key"
    else
        read -p "SSH Public Key: " SSH_PUBLIC_KEY
    fi
    
    # Create deployment directory for single VM
    create_deployment_directory "${VM_NAME}"
    
    # Generate files
    generate_single_vm_files
}

# Function untuk generate files mode interactive
generate_single_vm_files() {
    print_info "Generating files for ${VM_NAME}..."
    
    # Get the actual path of cloud image from virsh pool
    local cloud_image_path=$(virsh vol-path "${CLOUD_IMAGE}" --pool "${IMAGE_POOL}" 2>/dev/null)
    if [ -z "$cloud_image_path" ]; then
        print_error "Cloud image '${CLOUD_IMAGE}' not found in pool '${IMAGE_POOL}'"
        print_info "Available images in pool '${IMAGE_POOL}':"
        virsh vol-list "${IMAGE_POOL}" --details
        exit 1
    fi
    
    # Generate main.tf untuk single VM
    cat > "${DEPLOYMENT_DIR}/main.tf" << EOF
terraform {
  required_version = ">= 0.13"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.8.3"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

# Base volumes are directly referenced from the image pool
# No need to copy the base image, volumes will use base_volume_name

# VM disk
resource "libvirt_volume" "${VM_NAME}_disk" {
  name               = "${VM_NAME}-disk.qcow2"
  pool               = "${VM_POOL}"
  base_volume_name   = "${CLOUD_IMAGE}"
  base_volume_pool   = "${IMAGE_POOL}"
  size               = $((DISK_GB * 1073741824))  # ${DISK_GB}GB
  format             = "qcow2"
}

# Cloud-init disk
resource "libvirt_cloudinit_disk" "${VM_NAME}_cloudinit" {
  name           = "${VM_NAME}-cloudinit.iso"
  pool           = "${VM_POOL}"
  user_data      = file("cloudinit_${VM_NAME}.cfg")
  network_config = file("network_${VM_NAME}.cfg")
}

# VM domain
resource "libvirt_domain" "${VM_NAME}" {
  name   = "${VM_NAME}"
  memory = "${RAM_MB}"  # ${RAM_GB}GB
  vcpu   = ${CPU_COUNT}
  cloudinit = libvirt_cloudinit_disk.${VM_NAME}_cloudinit.id

EOF

    # Generate network interface berdasarkan tipe
    if [ "$NETWORK_TYPE" = "static" ]; then
        cat >> "${DEPLOYMENT_DIR}/main.tf" << EOF
  network_interface {
    network_name   = "default"
    wait_for_lease = false
    addresses      = ["${STATIC_IP}"]
  }
EOF
    else
        cat >> "${DEPLOYMENT_DIR}/main.tf" << EOF
  network_interface {
    network_name   = "default"
    wait_for_lease = true
  }
EOF
    fi
    
    cat >> "${DEPLOYMENT_DIR}/main.tf" << EOF
  
  cpu {
    mode = "host-passthrough"
  }
  
  disk {
    volume_id = libvirt_volume.${VM_NAME}_disk.id
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }

  console {
        type        = "pty"
        target_port = "1"
        target_type = "virtio"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
}

# Outputs
output "${VM_NAME}_ip" {
  value = libvirt_domain.${VM_NAME}.network_interface[0].addresses[0]
}

output "${VM_NAME}_ssh" {
  value = "ssh ${SSH_USER}@\${libvirt_domain.${VM_NAME}.network_interface[0].addresses[0]}"
}
EOF

    # Generate cloud-init
    cat > "${DEPLOYMENT_DIR}/cloudinit_${VM_NAME}.cfg" << EOF
#cloud-config
hostname: ${VM_NAME}
fqdn: ${VM_NAME}.local
manage_etc_hosts: true

users:
  - name: ${SSH_USER}
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: users, admin, wheel, sudo
    home: /home/${SSH_USER}
    shell: /bin/bash
    lock_passwd: false
    ssh_authorized_keys:
      - ${SSH_PUBLIC_KEY}

chpasswd:
  list: |
    ${SSH_USER}:${SSH_PASSWORD}
  expire: False

ssh_pwauth: true
disable_root: true
timezone: Asia/Jakarta

package_update: true
package_upgrade: true

packages:
  - qemu-guest-agent
  - curl
  - wget
  - vim
  - htop
  - net-tools
  - git

runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - systemctl enable ssh
  - systemctl start ssh

final_message: "VM ${VM_NAME} setup completed!"

power_state:
  mode: reboot
  delay: "+1"
  timeout: 60
  condition: True
EOF

    # Generate network config
    if [ "$NETWORK_TYPE" = "static" ]; then
        cat > "${DEPLOYMENT_DIR}/network_${VM_NAME}.cfg" << EOF
version: 2
ethernets:
  ens3:
    dhcp4: false
    addresses:
      - ${STATIC_IP}/${NETMASK}
    gateway4: ${GATEWAY}
    nameservers:
      addresses:
        - 8.8.8.8
        - 8.8.4.4
      search:
        - local
EOF
    else
        cat > "${DEPLOYMENT_DIR}/network_${VM_NAME}.cfg" << EOF
version: 2
ethernets:
  ens3:
    dhcp4: true
    dhcp6: false
EOF
    fi

    # Generate simple Makefile untuk single VM
    cat > "${DEPLOYMENT_DIR}/Makefile" << 'EOF'
.PHONY: init plan apply destroy clean validate fmt output help

# Terraform commands
init:
	terraform init

plan:
	terraform plan

apply:
	terraform apply -auto-approve

destroy:
	terraform destroy -auto-approve

# Utility commands
validate:
	terraform validate

fmt:
	terraform fmt

output:
	terraform output

# Clean temporary files
clean:
	rm -f terraform.tfstate*
	rm -f .terraform.lock.hcl
	rm -rf .terraform/
	rm -f *.iso

# Complete workflow
all: init plan apply

help:
	@echo "Available commands:"
	@echo "  init     - Initialize Terraform"
	@echo "  plan     - Show Terraform plan"
	@echo "  apply    - Apply Terraform configuration"
	@echo "  destroy  - Destroy VM"
	@echo "  clean    - Clean temporary files"
	@echo "  validate - Validate Terraform files"
	@echo "  fmt      - Format Terraform files"
	@echo "  output   - Show outputs"
	@echo "  all      - Run init, plan, and apply"
EOF

    # Add SSH command to Makefile
    cat >> "${DEPLOYMENT_DIR}/Makefile" << EOF
# SSH to VM
ssh-${VM_NAME}:
	@terraform output -raw ${VM_NAME}_ssh | sh
EOF

    # Update help with SSH command
    sed -i '/all      - Run init, plan, and apply/a\t@echo "  ssh-'${VM_NAME}' - SSH to '${VM_NAME}'"' "${DEPLOYMENT_DIR}/Makefile"

    print_success "Generated files for ${VM_NAME} in ${DEPLOYMENT_DIR}/"
    print_success "RAM: ${RAM_GB}GB (${RAM_MB}MB), Disk: ${DISK_GB}GB"
    print_info "Next: cd ${DEPLOYMENT_DIR} && make init && make apply"
}

# Main script
main() {
    check_dependencies
    
    if [ $# -eq 1 ]; then
        CONFIG_FILE="$1"
        if [ ! -f "$CONFIG_FILE" ]; then
            print_error "Config file $CONFIG_FILE tidak ditemukan"
            exit 1
        fi
        
        print_info "=== YAML Mode - Multiple VM Deployment ==="
        print_info "Using config file: $CONFIG_FILE"
        
        # Parse global config
        parse_yaml "$CONFIG_FILE" "global"
        
        # Create deployment directory
        local deployment_name=$(basename "$CONFIG_FILE" .yaml)
        create_deployment_directory "$deployment_name"
        
        # Copy config file to deployment directory
        cp "$CONFIG_FILE" "${DEPLOYMENT_DIR}/"
        
        # Generate files
        print_info "Generating Terraform files..."
        generate_main_tf_multiple "$CONFIG_FILE"
        
        # Generate cloud-init dan network config untuk setiap VM
        local vm_count=$(get_vm_count "$CONFIG_FILE")
        print_info "Processing $vm_count VMs..."
        
        for ((i=0; i<vm_count; i++)); do
            get_vm_data "$CONFIG_FILE" "$i"
            if [ "$VM_NAME" != "null" ]; then
                print_info "Processing VM: $VM_NAME (${VM_RAM_GB}GB RAM, ${VM_DISK_GB}GB Disk)"
                generate_cloudinit_vm "$VM_NAME" "$i" "$CONFIG_FILE"
                generate_network_config_vm "$VM_NAME" "$i" "$CONFIG_FILE"
            fi
        done
        
        # Generate Makefile
        generate_makefile_multiple "$CONFIG_FILE"
        
        print_success "=== Generated files for $vm_count VMs ==="
        print_info "Storage: Images pool='$IMAGE_POOL', VM pool='$VM_POOL'"
        print_info "Deployment directory: ${DEPLOYMENT_DIR}/"
        print_info "Next: cd ${DEPLOYMENT_DIR} && make init && make apply"
        
    elif [ "$1" = "--example" ] || [ "$1" = "-e" ]; then
        print_info "Generating example YAML config..."
        generate_example_yaml
        print_info "Edit vms-config.yaml, then run: $0 vms-config.yaml"
        
    else
        print_info "VM Generator untuk KVM dengan Terraform"
        echo
        print_info "Usage:"
        echo "  $0                     # Interactive mode (single VM)"
        echo "  $0 config.yaml        # YAML mode (multiple VMs)"  
        echo "  $0 --example          # Generate example YAML"
        echo
        
        read -p "Pilih mode (i)nteractive / (e)xample YAML / (q)uit [i]: " choice
        choice=${choice:-i}
        
        case "$choice" in
            i|I|interactive)
                interactive_mode
                ;;
            e|E|example)
                generate_example_yaml
                print_info "Edit vms-config.yaml, then run: $0 vms-config.yaml"
                ;;
            q|Q|quit)
                print_info "Goodbye!"
                exit 0
                ;;
            *)
                print_error "Invalid choice"
                exit 1
                ;;
        esac
    fi
}

# Run main function
main "$@"

