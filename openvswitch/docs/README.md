# OVS state
sudo ovs-vsctl show                          # overall topology
sudo ovs-vsctl list-br                       # list bridges
sudo ovs-vsctl list-ports br-ovs             # ports on a bridge
sudo ovs-ofctl dump-flows br-ovs             # all flow rules
sudo ovs-ofctl dump-ports br-ovs             # port stats (packet counts)

┌─────────────────────────────────────────────────────┐
│  Fedora 43 Host (your bare metal)                   │
│                                                     │
│  ┌─────────────────────────────────────────────┐   │
│  │  OVS Bridge: br-ovs  (your "cluster fabric")│   │
│  │                                             │   │
│  │  port: vm1-tap    port: vm2-tap             │   │
│  └────────┬─────────────────┬───────────────── ┘   │
│           │                 │                       │
│  ┌────────▼───┐    ┌────────▼───┐                  │
│  │  VM1       │    │  VM2       │                  │
│  │ "worker-1" │    │ "worker-2" │                  │
│  │ 192.168.   │    │ 192.168.   │                  │
│  │ 100.10     │    │ 100.20     │                  │
│  └────────────┘    └────────────┘                  │
└─────────────────────────────────────────────────────┘

# Real-time packet tracing
sudo tcpdump -i br-ovs -n                    # all traffic on bridge
sudo tcpdump -i vnet0 -n icmp               # ICMP on worker-1's tap

# VM management
sudo virsh list --all                        # VM state
sudo virsh console worker-1                  # serial console (Ctrl+] to exit)
sudo virsh start worker-1
sudo virsh shutdown worker-1

# Cleanup
sudo ovs-vsctl del-br br-ovs               # remove bridge
sudo virsh destroy worker-1 && sudo virsh undefine worker-1 --remove-all-storage


# Add a DROP rule — block worker-1 from reaching worker-2:
# Replace vnetxx with worker-1's actual port name
# Remove the simple stateless rule
sudo ovs-ofctl del-flows br-ovs \
  "ip,in_port=vnet6,nw_src=192.168.100.10,nw_dst=192.168.100.20"

# Table 0: send all traffic through connection tracker first
sudo ovs-ofctl add-flow br-ovs \
  "priority=50,ip,action=ct(table=1)"

# Table 1: allow established/related connections through (replies)
sudo ovs-ofctl add-flow br-ovs \
  "priority=100,ip,table=1,ct_state=+est+trk,action=NORMAL"
sudo ovs-ofctl add-flow br-ovs \
  "priority=100,ip,table=1,ct_state=+rel+trk,action=NORMAL"

# Table 1: drop NEW connections from worker-1 to worker-2 only
sudo ovs-ofctl add-flow br-ovs \
  "priority=100,ip,table=1,ct_state=+new+trk,in_port=vnet6,nw_src=192.168.100.10,nw_dst=192.168.100.20,action=drop"

# Table 1: allow everything else
sudo ovs-ofctl add-flow br-ovs \
  "priority=0,table=1,action=NORMAL"