# Destroy and clean up
sudo virsh destroy worker-1
sudo virsh undefine worker-1 --remove-all-storage
sudo virsh destroy worker-2
sudo virsh undefine worker-2 --remove-all-storage

# Recreate overlay disks
sudo qemu-img create \
  -f qcow2 \
  -b /var/lib/libvirt/images/ovs-lab/fedora-base.qcow2 \
  -F qcow2 \
  /var/lib/libvirt/images/ovs-lab/worker-1.qcow2 20G

sudo qemu-img create \
  -f qcow2 \
  -b /var/lib/libvirt/images/ovs-lab/fedora-base.qcow2 \
  -F qcow2 \
  /var/lib/libvirt/images/ovs-lab/worker-2.qcow2 20G
