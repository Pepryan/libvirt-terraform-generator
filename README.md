# VM Generator untuk KVM dengan Terraform

Sebuah tool powerful dan user-friendly untuk mengotomatisasi pembuatan Virtual Machine (VM) menggunakan KVM/QEMU dengan Terraform dan cloud-init. Tool ini mendukung deployment single VM maupun multiple VM sekaligus dengan konfigurasi YAML yang mudah dipahami.

## 🚀 Fitur Utama

- ✅ **Multiple VM Deployment**: Deploy beberapa VM sekaligus dengan satu konfigurasi
- ✅ **YAML Configuration**: Konfigurasi yang mudah dibaca dan dipahami
- ✅ **Cloud-init Integration**: Otomatis setup user, SSH keys, packages, dan custom commands
- ✅ **Smart Networking**: Static IP tanpa DHCP waiting, DHCP dengan proper lease handling
- ✅ **Base Volume Architecture**: Efisiensi storage dengan Copy-on-Write, base image aman
- ✅ **Storage Pool Support**: Terintegrasi dengan virsh storage pools
- ✅ **Interactive Mode**: Mode interaktif untuk VM tunggal
- ✅ **Auto SSH Key Detection**: Otomatis deteksi SSH public key
- ✅ **Makefile Integration**: Command shortcuts untuk workflow Terraform
- ✅ **Deployment Isolation**: Setiap deployment dibuat dalam folder terpisah
- ✅ **Error Handling**: Validasi konfigurasi dan error handling yang robust
- ✅ **Overwrite Protection**: Perlindungan terhadap deployment folder yang sudah ada

## 📋 Prerequisites

### Sistem Requirements
- Ubuntu/Debian Linux
- KVM/QEMU terinstall dan berjalan
- libvirt terinstall dan dikonfigurasi
- Terraform >= 0.13
- Akses sudo untuk mengelola VM

### Dependencies
```bash
# Install KVM/QEMU dan libvirt
sudo apt update
sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils

# Install Terraform
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt update && sudo apt install terraform

# Install yq (optional, untuk parsing YAML yang lebih akurat)
sudo apt install yq

# Tambahkan user ke grup libvirt
sudo usermod -a -G libvirt $USER
```

### Setup Storage Pools
```bash
# Buat storage pools jika belum ada
virsh pool-define-as --name images --type dir --target /var/lib/libvirt/images
virsh pool-define-as --name vms --type dir --target /var/lib/libvirt/vms
virsh pool-start images
virsh pool-start vms
virsh pool-autostart images
virsh pool-autostart vms
```

### Download Cloud Images
```bash
# Download Ubuntu cloud image
cd /var/lib/libvirt/images
sudo wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
sudo wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
```

## 🛠️ Instalasi

```bash
# Clone atau download project
git clone <repository-url>
cd vm-generator

# Atau download manual
chmod +x vm-generator.sh
```

## 📖 Penggunaan

### 1. Mode YAML (Multiple VMs)

#### Buat Konfigurasi YAML
```bash
# Generate example config
./vm-generator.sh --example

# Edit sesuai kebutuhan
nano vms-config.yaml
```

#### Generate dan Deploy
```bash
# Generate Terraform files (akan dibuat di deployment-vms-config/)
./vm-generator.sh vms-config.yaml

# Masuk ke deployment directory dan deploy VMs
cd deployment-vms-config
make init
make plan
make apply
```

### 2. Mode Interactive (Single VM)
```bash
# Jalankan mode interactive
./vm-generator.sh

# Ikuti prompt untuk konfigurasi
# Deploy VM (masuk ke deployment folder yang dibuat)
cd deployment-<vm-name>
make init && make apply
```

## 📝 Konfigurasi YAML

### Struktur Konfigurasi
```yaml
# Global settings
global:
  image_pool: "images"           # Pool untuk cloud images
  vm_pool: "vms"                # Pool untuk VM disks
  cloud_image: "jammy-server-cloudimg-amd64.img"
  network_name: "default"       # Network name
  domain: "local"
  
  # User configuration
  ssh_user: "ubuntu"
  ssh_password: "ubuntu"
  ssh_password_auth: false
  timezone: "Asia/Jakarta"
  ssh_public_key: ""            # Auto-detect jika kosong
  
  # Global packages
  packages:
    - qemu-guest-agent
    - curl
    - vim

# VM definitions
vms:
  - name: "web-server"
    cpu: 2
    ram_gb: 4
    disk_gb: 20
    network_type: "static"       # static atau dhcp
    ip: "192.168.122.10"
    gateway: "192.168.122.1"
    netmask: "24"
    dns: ["8.8.8.8", "8.8.4.4"]
    packages:                    # Additional packages
      - nginx
      - mysql-server
    commands:                    # Custom commands
      - "systemctl enable nginx"
      - "ufw allow 80,443/tcp"
```

### Contoh Konfigurasi Complete
```yaml
global:
  image_pool: "images"
  vm_pool: "vms" 
  cloud_image: "jammy-server-cloudimg-amd64.img"
  network_name: "default"
  domain: "local"
  ssh_user: "ubuntu"
  ssh_password: "ubuntu"
  ssh_password_auth: false
  timezone: "Asia/Jakarta"
  packages:
    - qemu-guest-agent
    - curl
    - wget
    - vim
    - htop

vms:
  # Web Server dengan static IP
  - name: "web-01"
    cpu: 2
    ram_gb: 4
    disk_gb: 20
    network_type: "static"
    ip: "192.168.122.10"
    gateway: "192.168.122.1"
    netmask: "24"
    dns: ["8.8.8.8", "8.8.4.4"]
    packages:
      - nginx
    commands:
      - "systemctl enable nginx"
      
  # Database Server
  - name: "db-01"
    cpu: 4
    ram_gb: 8
    disk_gb: 50
    network_type: "static"
    ip: "192.168.122.20"
    gateway: "192.168.122.1"
    netmask: "24"
    dns: ["8.8.8.8"]
    packages:
      - postgresql
      - postgresql-contrib
    commands:
      - "systemctl enable postgresql"
      
  # App Server dengan DHCP
  - name: "app-01"
    cpu: 2
    ram_gb: 6
    disk_gb: 30
    network_type: "dhcp"
    packages:
      - docker.io
      - docker-compose
    commands:
      - "systemctl enable docker"
      - "usermod -aG docker ubuntu"
```

## 🎯 Makefile Commands

Setelah generate files dengan `./vm-generator.sh`, masuk ke deployment directory dan gunakan commands berikut:

```bash
# Masuk ke deployment directory
cd deployment-<nama-config>
# atau untuk interactive mode:
cd deployment-<vm-name>

# Terraform workflow
make init          # Initialize Terraform
make plan          # Show deployment plan
make apply         # Deploy VMs
make destroy       # Destroy all VMs

# Utility commands
make validate      # Validate Terraform files
make fmt           # Format Terraform files
make output        # Show all outputs
make ips           # Show VM IP addresses only
make clean         # Clean temporary files

# SSH commands (auto-generated)
make ssh-web-01    # SSH to web-01 VM
make ssh-db-01     # SSH to db-01 VM
make ssh-app-01    # SSH to app-01 VM

# Complete workflow
make all           # init + plan + apply

# Help
make help          # Show available commands
```

## 🔧 Advanced Configuration

### Custom Networks
```bash
# Buat custom network
virsh net-define-as mynet 192.168.100.0/24
virsh net-start mynet
virsh net-autostart mynet

# Update YAML config
network_name: "mynet"
```

### Multiple Storage Pools
```bash
# Setup custom storage pools
virsh pool-define-as ssd-pool dir /mnt/ssd/vms
virsh pool-start ssd-pool

# Update YAML
vm_pool: "ssd-pool"
```

### SSH Key Management
```bash
# Generate SSH key jika belum ada
ssh-keygen -t rsa -b 4096 -C "your_email@example.com"

# Script akan auto-detect key dari ~/.ssh/id_rsa.pub
# Atau specify manual di YAML:
ssh_public_key: "ssh-rsa AAAAB3NzaC1yc2E..."
```

## 🔄 Base Volume Architecture

### Konsep Base Volume
Script ini menggunakan **base volume architecture** yang memberikan keuntungan signifikan:

- ✅ **Efisiensi Storage**: VM disk dibuat sebagai copy-on-write dari base image
- ✅ **Keamanan Data**: Base image tidak pernah dimodifikasi atau terhapus
- ✅ **Fast Deployment**: Tidak perlu copy full image, hanya membuat reference
- ✅ **Safe Destroy**: `terraform destroy` hanya menghapus VM disk, bukan base image

### Terraform Volume Configuration
```hcl
# Generated volume configuration
resource "libvirt_volume" "vm_disk" {
  name               = "vm-name-disk.qcow2"
  pool               = "vms"                    # Target pool untuk VM disk
  base_volume_name   = "noble-server-cloudimg-amd64.img"
  base_volume_pool   = "isos"                  # Source pool untuk base image
  size               = 20000000000             # 20GB
  format             = "qcow2"
}
```

### Network Configuration
Script secara otomatis mengatur network interface berdasarkan tipe yang dipilih:

#### Static IP Configuration
```hcl
network_interface {
  network_name   = "net-192.168.100"
  wait_for_lease = false                # Tidak menunggu DHCP lease
  addresses      = ["192.168.100.88"]  # Set IP address langsung
}
```
**Keuntungan**:
- Deployment lebih cepat (tidak ada DHCP waiting time)
- IP address predictable dan konsisten
- Cocok untuk production dan services

#### DHCP Configuration  
```hcl
network_interface {
  network_name   = "default"
  wait_for_lease = true    # Menunggu DHCP server assign IP
}
```
**Keuntungan**:
- Setup mudah, tidak perlu planning IP
- Automatic network configuration
- Cocok untuk development dan testing

### Keuntungan Architecture Ini
1. **Base Image Preservation**: File asli cloud images tetap aman
2. **Fast Provisioning**: VM baru menggunakan CoW (Copy-on-Write)
3. **Storage Efficiency**: Multiple VM share base image
4. **Safe Cleanup**: Destroy VM tidak affect base image

## 📁 Deployment Folder Management

### Konsep Deployment Isolation
Script ini menggunakan konsep **deployment isolation** dimana setiap deployment dibuat dalam folder terpisah. Ini memberikan beberapa keuntungan:

- ✅ **Isolasi Deployment**: Setiap konfigurasi VM terpisah satu sama lain
- ✅ **Parallel Development**: Bisa mengembangkan multiple environment bersamaan
- ✅ **Version Control**: Mudah untuk track dan backup deployment
- ✅ **Clean Management**: Mudah untuk menghapus seluruh deployment

### Naming Convention
```bash
# YAML mode: deployment-{config-filename}
./vm-generator.sh web-servers.yaml
# Creates: deployment-web-servers/

# Interactive mode: deployment-{vm-name}
# VM Name: "my-app"
# Creates: deployment-my-app/
```

### Overwrite Protection
Script memberikan perlindungan jika deployment folder sudah ada:

```bash
[WARNING] Deployment directory 'deployment-web-servers' already exists!
Do you want to overwrite? (y/N): 
```

- **N (default)**: Membatalkan deployment untuk mencegah overwrite
- **Y**: Menghapus folder lama dan membuat yang baru

### Multiple Deployment Management
```bash
# Buat multiple deployment
./vm-generator.sh web-servers.yaml    # -> deployment-web-servers/
./vm-generator.sh db-cluster.yaml     # -> deployment-db-cluster/
./vm-generator.sh monitoring.yaml     # -> deployment-monitoring/

# Manage setiap deployment independen
cd deployment-web-servers && make apply
cd deployment-db-cluster && make apply
cd deployment-monitoring && make apply

# Cleanup specific deployment
cd deployment-web-servers && make destroy
rm -rf deployment-web-servers/
```

### Best Practices
1. **Naming**: Gunakan nama deskriptif untuk config file (e.g., `production-web.yaml`)
2. **Documentation**: Simpan notes di deployment folder untuk referensi
3. **Backup**: Backup deployment folder sebelum major changes
4. **Cleanup**: Hapus deployment folder yang tidak digunakan

```bash
# Backup deployment
tar -czf deployment-web-servers-backup.tar.gz deployment-web-servers/

# List semua deployment
ls -d deployment-*/

# Cleanup unused deployment
cd deployment-old-test && make destroy
cd .. && rm -rf deployment-old-test/
```

## 🚨 Troubleshooting

### Common Issues

#### 1. Permission Denied
```bash
# Pastikan user ada di grup libvirt
sudo usermod -a -G libvirt $USER
# Logout dan login kembali
```

#### 2. Cloud Image Not Found
```bash
# Check available images in pool
virsh vol-list images

# Download missing images
cd /var/lib/libvirt/images
sudo wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
```

#### 3. Network Issues
```bash
# Check available networks
virsh net-list --all

# Start default network if stopped
virsh net-start default
virsh net-autostart default
```

#### 4. Terraform Provider Issues
```bash
# Clean dan reinitialize
make clean
make init
```

#### 5. VM tidak dapat SSH
- Pastikan cloud-init selesai (tunggu 2-3 menit)
- Check console: `virsh console vm-name`
- Verify SSH service: `systemctl status ssh`

### Debug Mode
```bash
# Enable verbose output
export TF_LOG=DEBUG
make apply

# Check cloud-init logs di VM
sudo tail -f /var/log/cloud-init-output.log
```

## 📁 Struktur File

```
vm-generator/
├── vm-generator.sh              # Main script
├── vms-config.yaml             # VM configuration template
├── README.md                   # Documentation
├── LICENSE                     # License file
└── deployment-<config-name>/   # Generated deployment folder
    ├── vms-config.yaml         # Copy of config file
    ├── main.tf                 # Generated Terraform file
    ├── Makefile                # Build commands
    ├── cloudinit_*.cfg        # Cloud-init configs per VM
    └── network_*.cfg          # Network configs per VM
```

## 🔄 Workflow Example

```bash
# 1. Setup
./vm-generator.sh --example
nano vms-config.yaml  # Edit configuration

# 2. Generate (creates deployment-vms-config/)
./vm-generator.sh vms-config.yaml

# 3. Deploy
cd deployment-vms-config
terraform init
terraform plan     # Review plan
terraform apply    # Deploy

# 4. Verify
make ips      # Get VM IPs
make ssh-n8n-server  # SSH to VM

# 5. Manage
virsh list    # List running VMs
make destroy  # Clean up when done
```

## 🛡️ Security Notes

- Script menggunakan SSH key authentication secara default
- Password authentication dapat diaktifkan tapi tidak direkomendasikan untuk production
- VM menggunakan user dengan sudo access
- Firewall dikonfigurasi sesuai commands di YAML
- Cloud-init dijalankan dengan privilege root

## 📊 Resource Management

### Estimasi Resource Usage
```
Per VM Base:
- RAM: Minimum 1GB, Recommended 2GB+
- Disk: Minimum 10GB, Recommended 20GB+
- CPU: Minimum 1 vCPU, Recommended 2+

Host Requirements:
- RAM: (Total VM RAM) + 2GB untuk host
- Disk: (Total VM Disk) + space untuk images
- CPU: Total vCPU tidak boleh > Physical CPU cores
```

## 🔄 Updates dan Maintenance

### Update Cloud Images
```bash
# Download latest Ubuntu images
cd /var/lib/libvirt/images
sudo wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
sudo wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img

# Update YAML config dengan image name yang baru
```

### Backup VMs
```bash
# Backup VM disk
virsh dumpxml vm-name > vm-name.xml
cp /var/lib/libvirt/vms/vm-name-disk.qcow2 /backup/

# Restore
virsh define vm-name.xml
```

## 🤝 Contributing

1. Fork repository
2. Buat feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push ke branch (`git push origin feature/amazing-feature`)
5. Buat Pull Request

## 📞 Support

Jika mengalami issues atau membutuhkan bantuan:
1. Check troubleshooting section di atas
2. Buat issue di GitHub repository
3. Sertakan output error dan konfigurasi YAML

## 📝 Changelog

### v1.2.0 (Latest)
- ✅ **NEW**: Base volume architecture untuk efisiensi dan keamanan storage
- ✅ **NEW**: Smart static IP handling (tidak menunggu DHCP lease)
- ✅ **IMPROVED**: Volume configuration menggunakan `base_volume_name` dan `base_volume_pool`
- ✅ **IMPROVED**: Network interface conditional generation berdasarkan tipe network
- ✅ **FIXED**: Safe destroy - base images tidak terhapus saat `terraform destroy`
- ✅ **FIXED**: Duplicate disk blocks di interactive mode
- ✅ **ENHANCED**: Deployment lebih cepat untuk static IP VMs

### v1.1.0
- ✅ **NEW**: Deployment folder isolation
- ✅ **NEW**: Overwrite protection untuk deployment
- ✅ **NEW**: Auto-copy config ke deployment folder
- ✅ **IMPROVED**: Better path management
- ✅ **IMPROVED**: Enhanced error handling

### v1.0.0
- ✅ Initial release
- ✅ Multiple VM support
- ✅ YAML configuration
- ✅ Cloud-init integration
- ✅ Interactive mode
- ✅ Makefile automation
- ✅ Storage pool support
- ✅ Auto SSH key detection
- ✅ Error handling dan validation

## 📄 License

Project ini dilisensikan under MIT License - lihat file [LICENSE](LICENSE) untuk detail lengkap.

## 👨‍💻 Author

**Febryan Ramadhan**
- Email: [febryanramadhan@gmail.com]
- GitHub: [github.com/pepryan]

---

⭐ **Jika project ini berguna, jangan lupa berikan star di GitHub!** ⭐
