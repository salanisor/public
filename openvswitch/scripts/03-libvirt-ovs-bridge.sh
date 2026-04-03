cat << 'EOF' | sudo tee /etc/libvirt/qemu/networks/ovs-network.xml
<network>
  <name>ovs-network</name>
  <forward mode='bridge'/>
  <bridge name='br-ovs'/>
  <virtualport type='openvswitch'/>
</network>
EOF

# Define and start the network
sudo virsh net-define /etc/libvirt/qemu/networks/ovs-network.xml
sudo virsh net-start ovs-network
sudo virsh net-autostart ovs-network

# Verify
sudo virsh net-list --all