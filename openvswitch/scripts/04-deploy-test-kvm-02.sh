# User data
PUBKEY=$(cat /home/salanis/.ssh/id_ed25519.pub)

cat << EOF > /tmp/worker2-user-data
#cloud-config
hostname: worker-1
manage_etc_hosts: true
users:
  - name: fedora
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - ${PUBKEY}
EOF

cat << 'EOF' > /tmp/worker2-network-config
version: 2
ethernets:
  enp1s0:
    addresses:
      - 192.168.100.20/24
    gateway4: 192.168.100.1
    nameservers:
      addresses:
        - 8.8.8.8
EOF

cloud-localds /tmp/worker2-seed.iso \
  /tmp/worker2-user-data \
  --network-config /tmp/worker2-network-config

sudo qemu-img create \
  -f qcow2 \
  -b /var/lib/libvirt/images/ovs-lab/fedora-base.qcow2 \
  -F qcow2 \
  /var/lib/libvirt/images/ovs-lab/worker-2.qcow2 20G

# Verify both look correct
sudo qemu-img info /var/lib/libvirt/images/ovs-lab/worker-2.qcow2

sudo virt-install \
  --name worker-2 \
  --ram 2048 \
  --vcpus 2 \
  --disk path=/var/lib/libvirt/images/ovs-lab/worker-2.qcow2,format=qcow2 \
  --disk path=/tmp/worker2-seed.iso,device=cdrom \
  --os-variant fedora40 \
  --network network=ovs-network,model=virtio \
  --graphics none \
  --console pty,target_type=serial \
  --noautoconsole \
  --import