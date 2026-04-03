# Stop and delete both VMs and their storage
sudo virsh destroy worker-1 2>/dev/null; sudo virsh undefine worker-1 --remove-all-storage
sudo virsh destroy worker-2 2>/dev/null; sudo virsh undefine worker-2 --remove-all-storage

# Verify they're gone
sudo virsh list --all

sudo rm -rf /var/lib/libvirt/images/ovs-lab/worker-1.qcow2
sudo rm -rf /var/lib/libvirt/images/ovs-lab/worker-2.qcow2

# Confirm only the base image remains
ls -lh /var/lib/libvirt/images/ovs-lab/
