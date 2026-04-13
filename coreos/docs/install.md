# fedora
sudo dnf install -y coreos-installer butane

# Download and decompress the qcow2 image
STREAM=stable
coreos-installer download -s $STREAM -p qemu -f qcow2.xz --decompress -C /var/lib/libvirt/images/

# Step 2: Create a Basic Ignition Config (for SSH Access)
# FCOS requires an Ignition config on first boot for customization (SSH key, hostname, etc.). Use Butane (human-readable) to generate it.
# Create a file named fcos.bu:

`butane --pretty --strict fcos.bu -o fcos.ign`

example:
```
variant: fcos
version: 1.7.0
passwd:
  users:
    - name: core
      ssh_authorized_keys:
        - ssh-rsa YOUR_PUBLIC_SSH_KEY_HERE   # Paste your ~/.ssh/id_rsa.pub or id_ed25519.pub
storage:
  files:
    - path: /etc/hostname
      mode: 0644
      contents:
        inline: my-fcos-vm
```

# Step 3: Launch the FCOS VM with virt-install (Recommended)
# This is the cleanest way using libvirt:
# Bash
IGNITION_CONFIG="$(pwd)/fcos.ign"
IMAGE_PATH="/var/lib/libvirt/images/fedora-coreos-43.20260316.3.1-qemu.x86_64.qcow2"   # Use tab-complete or exact name

sudo virt-install \
  --name fcos-vm \
  --memory 4096 \
  --vcpus 2 \
  --disk path=${IMAGE_PATH},size=20,format=qcow2 \
  --os-variant fedora-coreos-stable \
  --network network=default,model=virtio \
  --graphics none \
  --console pty,target_type=serial \
  --qemu-commandline="-fw_cfg name=opt/com.coreos/config,file=${IGNITION_CONFIG}" \
  --import