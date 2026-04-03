# Create image directory
sudo mkdir -p /var/lib/libvirt/images/ovs-lab

# Download Fedora 39 cloud image (small, fast)
sudo curl -L -o /var/lib/libvirt/images/ovs-lab/fedora-base.qcow2 \
  https://ftp2.osuosl.org/pub/fedora/linux/releases/43/Cloud/x86_64/images/Fedora-Cloud-Base-Generic-43-1.6.x86_64.qcow2