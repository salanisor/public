# Should show br-ovs with two ports — one per VM
sudo ovs-vsctl show

# List the ports explicitly
sudo ovs-vsctl list-ports br-ovs

# Show detailed port info including VM association
sudo ovs-vsctl list interface

# Both VMs should show as running
sudo virsh list --all

# Give cloud-init ~60 seconds to finish, then test connectivity
sleep 60
ping -c 3 192.168.100.10
ping -c 3 192.168.100.20