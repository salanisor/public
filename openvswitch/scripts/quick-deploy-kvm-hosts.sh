sudo virt-install \
  --name worker-1 \
  --ram 2048 \
  --vcpus 2 \
  --disk path=/var/lib/libvirt/images/ovs-lab/worker-1.qcow2,format=qcow2,bus=virtio \
  --disk path=/tmp/worker1-seed.iso,device=cdrom,bus=sata \
  --os-variant fedora40 \
  --network network=ovs-network,model=virtio \
  --graphics none \
  --console pty,target_type=serial \
  --noautoconsole \
  --import

sudo virt-install \
  --name worker-2 \
  --ram 2048 \
  --vcpus 2 \
  --disk path=/var/lib/libvirt/images/ovs-lab/worker-2.qcow2,format=qcow2,bus=virtio \
  --disk path=/tmp/worker2-seed.iso,device=cdrom,bus=sata \
  --os-variant fedora40 \
  --network network=ovs-network,model=virtio \
  --graphics none \
  --console pty,target_type=serial \
  --noautoconsole \
  --import
