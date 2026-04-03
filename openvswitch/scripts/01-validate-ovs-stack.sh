# Layer 1 — OVS database and switching daemon
sudo systemctl enable --now ovsdb-server
sudo systemctl enable --now ovs-vswitchd

# Layer 2 — OVS convenience wrapper (depends on the two above)
sudo systemctl enable --now openvswitch

# Layer 3 — OVN northbound database + northd translator
sudo systemctl enable --now ovn-northd

# Layer 4 — OVN controller (programs OVS from southbound DB)
sudo systemctl enable --now ovn-controller

# Check all four at once
sudo systemctl status ovsdb-server ovs-vswitchd openvswitch ovn-northd ovn-controller --no-pager

sudo ovn-nbctl show
sudo ovs-vsctl show
sudo ovn-sbctl show