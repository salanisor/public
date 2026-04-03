# KVM and virtualisation stack
sudo dnf install -y @virtualization virt-manager virt-install \
  libvirt libvirt-client qemu-kvm

# OVS and OVN packages
sudo dnf install -y openvswitch ovn ovn-central ovn-host

# Useful networking tools
sudo dnf install -y tcpdump wireshark-cli net-tools bridge-utils

# Enable and start services
sudo systemctl enable --now libvirtd
sudo systemctl enable --now openvswitch

# Verify both are running
sudo systemctl status libvirtd --no-pager
sudo systemctl status openvswitch --no-pager