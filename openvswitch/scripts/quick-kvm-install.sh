cat << 'EOF' > /tmp/worker1-user-data
#cloud-config
hostname: worker-1
manage_etc_hosts: true
users:
  - name: fedora
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
chpasswd:
  expire: false
  users:
    - name: fedora
      password: fedora
      type: text
EOF

cat << 'EOF' > /tmp/worker1-network-config
version: 2
ethernets:
  enp1s0:
    addresses:
      - 192.168.100.10/24
    gateway4: 192.168.100.1
    nameservers:
      addresses:
        - 8.8.8.8
EOF

cloud-localds /tmp/worker1-seed.iso \
  /tmp/worker1-user-data \
  --network-config /tmp/worker1-network-config

# Same for worker-2
cat << 'EOF' > /tmp/worker2-user-data
#cloud-config
hostname: worker-2
manage_etc_hosts: true
users:
  - name: fedora
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
chpasswd:
  expire: false
  users:
    - name: fedora
      password: fedora
      type: text
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
