# Create the main OVS bridge
sudo ovs-vsctl add-br br-ovs

# Bring it up
sudo ip link set br-ovs up

# Assign an IP to the host side so the host can also communicate
sudo ip addr add 192.168.100.1/24 dev br-ovs

# Verify
sudo ovs-vsctl show
ip addr show br-ovs