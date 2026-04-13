Here's a clear, detailed explanation of OVN ACLs for Kubernetes NetworkPolicy in the context of OpenShift (using the modern distributed OVN-Kubernetes CNI, 4.14+).What are OVN ACLs?ACL stands for Access Control List. In OVN (Open Virtual Network), ACLs are the primary mechanism for enforcing security rules at the logical network layer.They act like firewall rules but are defined on logical objects (logical switches, logical ports, or port groups) rather than physical devices.
OVN translates these ACLs into OpenFlow rules that run efficiently inside Open vSwitch (OVS) on every node.
Enforcement happens very early in the packet path — often before traffic even enters a pod's network namespace — making it fast and scalable.

How OVN-Kubernetes Maps Kubernetes NetworkPolicy to OVN ACLsKubernetes NetworkPolicy is a declarative object that selects pods and defines allowed ingress/egress traffic. By default, if no NetworkPolicy selects a pod, all traffic is allowed. Once any NetworkPolicy selects a pod, it switches to a default-deny model for the directions specified (Ingress, Egress, or both).OVN-Kubernetes implements this as follows:Port Groups
When you create a NetworkPolicy that selects certain pods (via podSelector + namespaceSelector), OVN-Kubernetes creates an OVN Port Group.  All matching pod logical ports (one per pod) are dynamically added to this group.  
This makes rule application efficient — rules attach to the group instead of individual ports.

Default Drop Rule
A high-priority drop ACL (typically priority 1000) is added to the port group.  Direction: to-lport (ingress) and/or from-lport (egress).  
This enforces the implicit deny: "If traffic doesn't match any allow rule → drop."

Allow Rules
For each ingress or egress rule in your NetworkPolicy, OVN creates one or more allow ACLs with higher priority than the drop rule (e.g., 1001+).  These match on: source/destination (pods via address sets, namespaces, ipBlocks), ports/protocols, etc.  
Special handling for ARP (always allowed at slightly higher priority to keep networking healthy).

ipBlock handling
CIDR-based rules (ipBlock) translate to allow/drop ACLs with specific labels. Exceptions inside except create higher-priority drop rules.
Tiered Evaluation (OpenShift 4.14+ and later)
OVN uses ACL tiers for precedence:  Tier 1: AdminNetworkPolicy (ANP) — cluster-wide, highest priority.  
Tier 2: Regular NetworkPolicy objects (what most users create).  
Tier 3: BaselineAdminNetworkPolicy (BANP) — lowest.
An allow or deny decision in a higher tier can short-circuit lower tiers.

Example Traffic Flow with ACLsUsing the IP examples from our previous diagram:Pod A (10.128.10.5) on Node 1 has a NetworkPolicy allowing ingress only from pods in the same namespace on port 8080.
Incoming packet from Pod B (10.128.10.7) (same namespace, allowed):Hits br-int on the destination node.
OVN logical switch processes the packet.
Matches an allow ACL on the destination port group → permitted.

Incoming packet from Pod C (10.130.20.8) in a different namespace (not allowed):Matches the default drop ACL → packet is dropped silently (no response).

For cross-node traffic, the Geneve tunnel carries the packet, but ACL evaluation still happens on the destination node's OVS (ingress rules) or source node's (egress rules).Key Advantages of OVN ACLsDistributed & scalable — Each node only programs ACLs relevant to its local pods (thanks to the per-node distributed design).
Efficient — Rules compile to OpenFlow; no iptables explosion.
Observable — You can enable audit logging per namespace with the annotation:yaml

k8s.ovn.org/acl-logging: |
  {"deny": "alert", "allow": "notice"}

Logs go to /var/log/ovn/acl-audit-log.log on each node (and can be forwarded).
Direction-specific — Ingress ACLs protect incoming traffic to the pod; egress ACLs protect outgoing traffic from the pod.

Practical Notes for OpenShift UsersCreating the first NetworkPolicy in a namespace that selects pods immediately isolates them (default-deny kicks in).
You can combine multiple NetworkPolicies — they are additive (union of all allow rules).
For cluster-wide control, use AdminNetworkPolicy (stronger, admin-only).
Egress rules in NetworkPolicy are more limited than dedicated EgressFirewall CRs in OpenShift.

Would you like me to:Show a concrete YAML NetworkPolicy example and what OVN ACLs it generates?
Explain how to view/debug the actual ACLs on a node (ovn-nbctl commands)?
Add a visual diagram focused only on ACL flow for NetworkPolicy?
Compare it with legacy OpenShift SDN behavior?

Just let me know how deep you'd like to go!

37 web pages

Debug OVN ACLs with ovn-nbctl

Compare OVN ACLs to Calico

Debug OVN ACLs with ovn-nbctl

Searching the web

26 results

Here's a practical, step-by-step guide to debugging OVN ACLs for Kubernetes NetworkPolicy (and related features like AdminNetworkPolicy) using ovn-nbctl in OpenShift with the distributed OVN-Kubernetes architecture (4.14+).1. Access the Northbound Database (NBDB)In modern OpenShift, each node runs its own local NBDB inside the ovnkube-node pod. You must exec into the nbdb container on a relevant worker node.bash

# Find a worker node (or the node where the affected pod runs)
oc get nodes -l node-role.kubernetes.io/worker

# Exec into the nbdb container on that node
oc exec -n openshift-ovn-kubernetes -it ovnkube-node-<XXXXX> -c nbdb -- bash

Once inside the container, you can run ovn-nbctl commands directly (no extra flags needed in most cases).Alternative one-liner (without entering the shell):bash

oc exec -n openshift-ovn-kubernetes -it ovnkube-node-<XXXXX> -c nbdb -- ovn-nbctl <command>

2. Basic Commands to Explore ACLsCommand
Purpose
Example
ovn-nbctl list acl
List all ACLs in the cluster (can be long)
ovn-nbctl list acl
ovn-nbctl acl-list <logical-switch>
List ACLs applied to a specific logical switch (most common for pod networking)
ovn-nbctl acl-list <node-name>
ovn-nbctl acl-list <port-group>
List ACLs on a port group (NetworkPolicies often attach here)
ovn-nbctl acl-list @my-port-group
ovn-nbctl find ACL external_ids:key=value
Search ACLs by external_ids (best for Kubernetes objects)
See examples below

3. Useful Debugging Patterns for NetworkPolicyA. Find ACLs related to a specific NetworkPolicyNetworkPolicies add external_ids like:"k8s.ovn.org/owner-type"=NetworkPolicy
"k8s.ovn.org/name"=my-policy
"k8s.ovn.org/owner-controller"=default-network-controller

bash

# Find all ACLs belonging to a specific NetworkPolicy
ovn-nbctl find ACL external_ids:"k8s.ovn.org/name"="my-networkpolicy-name"

# Broader search (shows owner-type)
ovn-nbctl find ACL 'external_ids{>=}{"k8s.ovn.org/owner-type"=NetworkPolicy}'

# For AdminNetworkPolicy (higher tier)
ovn-nbctl find ACL 'external_ids{>=}{"k8s.ovn.org/owner-type"=AdminNetworkPolicy}'

B. Look at a pod's logical switch and its ACLsPods on the same node share a logical switch (often named after the node).bash

# List all logical switches
ovn-nbctl ls-list

# Show details of a specific switch (includes attached ACLs indirectly)
ovn-nbctl show <logical-switch-name>

# List ACLs specifically on that switch
ovn-nbctl acl-list <logical-switch-name>

C. Examine Port Groups (used heavily by NetworkPolicy)bash

ovn-nbctl list port-group | grep -E 'name|ports'

Port groups contain the logical ports of pods selected by the policy.D. Key fields to look for in an ACLWhen you run ovn-nbctl list acl or find, look at these columns:direction: to-lport (ingress to pod) or from-lport (egress from pod)
action: allow-related (stateful allow), allow, drop, reject
priority: Higher number = higher priority. Default drop is usually ~1000; allow rules are 1001+
match: The actual condition (e.g., outport == @port-group && ip4.src == $address-set)
external_ids: Contains the Kubernetes mapping (policy name, direction, index)
log: Whether logging is enabled for this rule

Example output snippet (simplified):

_uuid               : abc123...
action              : allow-related
direction           : to-lport
priority            : 1002
match               : "outport == @a123456789 && (ip4.src == $a987654321 || ip4.src == 10.0.0.0/8)"
external_ids        : {direction=Ingress, "k8s.ovn.org/name"="allow-from-frontend", "k8s.ovn.org/owner-type"=NetworkPolicy}

4. Practical Debugging WorkflowIdentify the affected pod → note its node.
Exec into the nbdb container on that node.
Find the logical switch for the pod/node.
List ACLs on that switch or use find ACL with the policy name.
Check if the expected allow rules exist and have higher priority than any drop.
Verify Address Sets and Port Groups referenced in the match field:bash

ovn-nbctl list address_set | grep <part-of-uuid>
ovn-nbctl list port_group | grep <part-of-uuid>

5. Enable & Check ACL LoggingTo see which rules are hitting (very useful for debugging):Add this annotation to the namespace:yaml

k8s.ovn.org/acl-logging: |
  {"deny": "alert", "allow": "notice"}

Then check logs on the node:bash

oc logs -n openshift-ovn-kubernetes -c ovn-controller ovnkube-node-<XXXXX> | grep acl
# or look at /var/log/ovn/acl-audit-log.log inside the pod

6. Bonus CommandsFull overview: ovn-nbctl show (very verbose — pipe to less)
Logical flows in SBDB (what actually runs in OVS): ovn-sbctl lflow-list (run in sbdb container)
Clean up test ACLs (rarely needed): ovn-nbctl acl-del <switch>

Would you like me to:Provide a full example with a sample NetworkPolicy YAML + expected ovn-nbctl output?
Show commands to debug a specific traffic issue (e.g., "why is pod A not reaching service B")?
Explain how to correlate an ACL back to the exact NetworkPolicy rule?
Add a focused diagram showing the ACL debugging flow?

Just give me the scenario you're troubleshooting and I'll give you the exact commands!

26 web pages

Correlate ACLs to NetworkPolicy rules

OVN address sets debugging

can you kindly generate a README.md with the above and make it available as a download please

Searching the web

8 results

Here's a complete, well-structured README.md that compiles all the key content from our conversation about OVN/OVS in OpenShift (new distributed architecture), the technical diagrams, and especially the debugging of OVN ACLs for NetworkPolicy using ovn-nbctl.You can copy the entire markdown block below, paste it into a new file named README.md, and save it locally. Then open it in any Markdown viewer (VS Code, Typora, GitHub, Obsidian, etc.) for nice formatting.markdown

# OpenShift OVN-Kubernetes Networking Guide
## Distributed Architecture (4.14+), Components, Traffic Flows & Debugging OVN ACLs for NetworkPolicy

**Version:** 2026  
**Focus:** New per-node distributed OVN-Kubernetes in OpenShift, with detailed explanations of components, NetworkPolicy implementation via OVN ACLs, and practical debugging using `ovn-nbctl`.

### Table of Contents
1. [Overview of New Distributed OVN-Kubernetes Architecture](#overview)
2. [Key Components & Interactions](#components)
3. [How NetworkPolicy Maps to OVN ACLs](#networkpolicy-acls)
4. [Example Traffic Paths with Sample IPs](#traffic-paths)
5. [Debugging OVN ACLs with ovn-nbctl](#debugging)
6. [Useful Commands Reference](#commands)
7. [ACL Logging & Observability](#logging)

---

### Overview of New Distributed OVN-Kubernetes Architecture (OpenShift 4.14+)

Starting with OpenShift 4.14, OVN-Kubernetes moved to a **fully distributed model** for better scaling and stability:

- **Lightweight Control Plane**: Only `ovnkube-cluster-manager` (runs on control-plane nodes) — responsible **only** for allocating non-overlapping pod subnets to nodes. No more centralized `ovnkube-master` or shared RAFT databases.
- **Per-Node Full Stack**: Everything else lives inside the `ovnkube-node` pod on **every worker node**:
  - `ovnkube-controller` (the "local brain")
  - Local NBDB (Northbound Database — standalone)
  - `ovn-northd`
  - Local SBDB (Southbound Database — standalone)
  - `ovn-controller`
- **Data Plane**: Open vSwitch (OVS) with `br-int` (integration bridge) and `br-ex` (external bridge). Overlay uses **Geneve tunnels**.

This design eliminates cross-node database chatter and improves reliability at scale.

---

### Key Components & Interactions

- **Kubernetes API Server** → `ovnkube-cluster-manager` (subnet allocation only)
- **Per Node**:
  - `ovnkube-controller` watches relevant K8s objects (Pods, NetworkPolicies, Services, Egress resources) for **this node only**.
  - Translates them into OVN logical objects (Logical Switches, Logical Routers, Load Balancers, ACLs).
  - Local databases + `ovn-northd` → `ovn-controller` programs OpenFlow rules into OVS.

**Features handled per node**:
- Pod networking & veth pairs
- **NetworkPolicy** → OVN ACLs
- **Services** (ClusterIP, NodePort, LoadBalancer) → OVN Logical Load Balancers
- **Egress** (EgressIP, EgressFirewall) → OVN Logical Router + SNAT + ACLs

---

### How NetworkPolicy Maps to OVN ACLs

OVN uses **Access Control Lists (ACLs)** to enforce Kubernetes `NetworkPolicy`:

- **Port Groups**: Dynamically created for pods selected by a NetworkPolicy.
- **Default Drop**: High-priority drop rule (priority ~1000) on the port group (implicit deny once any policy selects the pod).
- **Allow Rules**: Higher-priority ACLs (1001+) for each explicit `ingress`/`egress` rule.
- **Direction**: `to-lport` (ingress to pod) or `from-lport` (egress from pod).
- **Match**: Based on Address Sets, Port Groups, IP blocks, ports/protocols.
- **Action**: `allow-related` (stateful), `allow`, `drop`, `reject`.
- **Tiers** (newer OVN): AdminNetworkPolicy (highest) > regular NetworkPolicy > BaselineAdminNetworkPolicy.

ACLs are evaluated on the **destination node** for ingress and **source node** for egress. They compile efficiently to OpenFlow in OVS.

---

### Example Traffic Paths with Sample IP Addresses

Using typical OpenShift defaults:
- Pod CIDR: `10.128.0.0/14` (sliced per node)
- Service CIDR: `172.30.0.0/16`

**Examples**:
- **Same-node Pod-to-Pod**: `10.128.10.5` → veth → br-int → Logical Switch → `10.128.10.7`
- **Cross-node Pod-to-Pod**: `10.128.10.5` (Node1) → br-int → Geneve tunnel → remote br-int → `10.130.20.8`
- **Pod-to-Service**: `10.128.10.5` → Logical Load Balancer VIP `172.30.5.10` → backend `10.128.15.12:80`
- **Egress**: `10.128.10.5` → Logical Router SNAT (to EgressIP `192.168.1.100`) → br-ex → Internet

---

### Debugging OVN ACLs with ovn-nbctl

#### Step 1: Access the local NBDB
```bash
# On a worker node
oc exec -n openshift-ovn-kubernetes -it ovnkube-node-<XXXXX> -c nbdb -- bash

Step 2: Useful Commandsbash

# List all ACLs
ovn-nbctl list acl

# Find ACLs for a specific NetworkPolicy
ovn-nbctl find ACL external_ids:"k8s.ovn.org/name"="my-networkpolicy-name"

# Search by owner type
ovn-nbctl find ACL 'external_ids{>=}{"k8s.ovn.org/owner-type"=NetworkPolicy}'

# ACLs on a logical switch
ovn-nbctl acl-list <logical-switch-name>

# List port groups
ovn-nbctl list port-group

# Full view
ovn-nbctl show

Key ACL fields to check:direction, action, priority, match, external_ids

Useful Commands Referenceovn-nbctl ls-list — List logical switches
ovn-nbctl find ACL ... — Targeted searches
ovn-nbctl list address_set — Check IP groupings
ovn-sbctl lflow-list — View logical flows in SBDB (run in sbdb container)

ACL Logging & ObservabilityAdd to the namespace:yaml

k8s.ovn.org/acl-logging: |
  {"deny": "alert", "allow": "notice"}

Check logs:bash

oc logs -n openshift-ovn-kubernetes -c ovn-controller ovnkube-node-<XXXXX> | grep acl

Or inside the pod: /var/log/ovn/acl-audit-log.logCreated with assistance from Grok (xAI)
For learning OpenShift networking. Feel free to extend or contribute improvements.

### How to Get It as a Download
1. **Copy the entire markdown** above.
2. Paste into a text editor (Notepad, VS Code, etc.).
3. Save as `OVN-Kubernetes-Networking-README.md`.
4. (Optional) Push to a GitHub repo for nice rendered view + easy download.

If you want any modifications (add more sections, change title, include diagram descriptions, etc.), just tell me and I’ll regenerate an updated version instantly.

Would you like a shorter version, a version focused only on ACL debugging, or anything else added? 😊

8 web pages

Add OVN ACL examples

Include OVS flow debugging

Revise README for brevity

Include OVS flow debugging

Here's the updated and expanded README.md with a new dedicated section on OVS flow debugging (using ovn-sbctl and ovs-ofctl).I’ve integrated it cleanly after the ACL debugging section for logical flow.markdown

# OpenShift OVN-Kubernetes Networking Guide
## Distributed Architecture (4.14+), Components, Traffic Flows, OVN ACLs & OVS Flow Debugging

**Version:** April 2026  
**Focus:** New per-node distributed OVN-Kubernetes in OpenShift, NetworkPolicy via OVN ACLs, and practical debugging (ACLs + OVS flows).

### Table of Contents
1. [Overview of New Distributed OVN-Kubernetes Architecture](#overview)
2. [Key Components & Interactions](#components)
3. [How NetworkPolicy Maps to OVN ACLs](#networkpolicy-acls)
4. [Example Traffic Paths with Sample IPs](#traffic-paths)
5. [Debugging OVN ACLs with ovn-nbctl](#acl-debugging)
6. [Debugging OVS Flows with ovn-sbctl & ovs-ofctl](#ovs-debugging)
7. [Useful Commands Reference](#commands)
8. [ACL Logging & Observability](#logging)

---

### Overview of New Distributed OVN-Kubernetes Architecture (OpenShift 4.14+)

Starting with OpenShift 4.14, OVN-Kubernetes uses a **fully distributed model**:

- **Lightweight Control Plane**: Only `ovnkube-cluster-manager` (on control-plane nodes) — handles pod subnet allocation only.
- **Per-Node Full Stack** (inside `ovnkube-node` pod on every worker node):
  - `ovnkube-controller` (local brain)
  - Local NBDB (standalone Northbound DB)
  - `ovn-northd`
  - Local SBDB (standalone Southbound DB)
  - `ovn-controller`
- **Data Plane**: Open vSwitch (OVS) with `br-int` and `br-ex`. Overlay networking via **Geneve tunnels**.

This removes centralized RAFT databases and greatly improves scaling and stability.

---

### Key Components & Interactions

- Kubernetes API → `ovnkube-cluster-manager` (subnet allocation)
- Per node: `ovnkube-controller` watches relevant objects → creates OVN logical objects (switches, routers, load balancers, ACLs) → local NBDB → `ovn-northd` → local SBDB → `ovn-controller` programs **OpenFlow rules** into OVS.
- Features: Pod networking, **NetworkPolicy** (via ACLs), **Services** (via Logical Load Balancers), **Egress** (via Logical Router + SNAT).

---

### How NetworkPolicy Maps to OVN ACLs

OVN enforces `NetworkPolicy` using **Access Control Lists (ACLs)** attached to logical switches or port groups:

- **Port Groups**: Contain logical ports of selected pods.
- **Default Drop**: Priority ~1000 drop rule (enforces implicit deny).
- **Allow Rules**: Higher priority (1001+) `allow-related` or `allow` rules.
- **Direction**: `to-lport` (ingress) / `from-lport` (egress).
- **Tiers**: AdminNetworkPolicy > regular NetworkPolicy > BaselineAdminNetworkPolicy.
- ACLs compile to efficient OpenFlow rules in OVS.

---

### Example Traffic Paths with Sample IP Addresses

Typical OpenShift defaults:
- Pod CIDR: `10.128.0.0/14`
- Service CIDR: `172.30.0.0/16`

**Examples**:
- Same-node Pod-to-Pod: `10.128.10.5` → veth → br-int → Logical Switch → `10.128.10.7`
- Cross-node: `10.128.10.5` → Geneve tunnel → remote pod `10.130.20.8`
- Pod-to-Service: `10.128.10.5` → Logical LB VIP `172.30.5.10` → backend `10.128.15.12:80`
- Egress: `10.128.10.5` → SNAT to EgressIP `192.168.1.100` → br-ex → Internet

---

### Debugging OVN ACLs with ovn-nbctl

#### Access the local NBDB
```bash
oc exec -n openshift-ovn-kubernetes -it ovnkube-node-<XXXXX> -c nbdb -- bash

Key Commandsbash

# List all ACLs
ovn-nbctl list acl

# Find ACLs for a specific NetworkPolicy
ovn-nbctl find ACL external_ids:"k8s.ovn.org/name"="my-networkpolicy-name"

# ACLs by owner type
ovn-nbctl find ACL 'external_ids{>=}{"k8s.ovn.org/owner-type"=NetworkPolicy}'

# ACLs on a logical switch
ovn-nbctl acl-list <logical-switch-name>

# List port groups and address sets
ovn-nbctl list port-group
ovn-nbctl list address_set

Important ACL fields: direction, action, priority, match, external_idsDebugging OVS Flows with ovn-sbctl & ovs-ofctlOnce ACLs are translated, the actual packet forwarding happens via OpenFlow rules in OVS. Debug these on the same node where the traffic is being processed.Step 1: Access the SBDB containerbash

oc exec -n openshift-ovn-kubernetes -it ovnkube-node-<XXXXX> -c sbdb -- bash

Key Commands for Logical Flows (SBDB)bash

# List all logical flows (very useful)
ovn-sbctl lflow-list

# Filter for a specific logical datapath (switch/router)
ovn-sbctl lflow-list <datapath-uuid-or-name>

# Filter by logical switch name (e.g., the node's switch)
ovn-sbctl lflow-list <node-name>

# Show flows related to a port
ovn-sbctl lflow-list | grep <port-name>

Step 2: View Actual OpenFlow Rules in OVS (on the node)bash

# Exec into the ovn-controller container or use host network
oc exec -n openshift-ovn-kubernetes -it ovnkube-node-<XXXXX> -c ovn-controller -- bash

# Dump flows for br-int (most important bridge)
ovs-ofctl dump-flows br-int

# Dump flows with more detail and packet/byte counters
ovs-ofctl dump-flows br-int -O OpenFlow13 --sort=priority

# Filter flows containing a specific IP (very useful for debugging)
ovs-ofctl dump-flows br-int | grep 10.128.10.5

# Filter by table (ACLs are often in table 20-30, routing in higher tables)
ovs-ofctl dump-flows br-int table=21

Pro tips:Look at n_packets and n_bytes counters to see which rules are actually matching traffic.
Higher priority rules are evaluated first.
Use ovs-ofctl dump-flows br-int --no-stats for cleaner output.
To watch live: ovs-ofctl monitor br-int

Common Flow Tables in OVN (simplified)Table 0–10: Ingress pipeline (ACLs, classification)
Table 20–30: ACL enforcement
Higher tables: Routing, NAT, Egress

Useful Commands ReferenceNBDB (ACLs & logical config):ovn-nbctl show
ovn-nbctl ls-list
ovn-nbctl find ACL ...

SBDB (logical flows):ovn-sbctl lflow-list

OVS (actual OpenFlow):ovs-ofctl dump-flows br-int
ovs-ofctl dump-flows br-int | grep <IP>

ACL Logging & ObservabilityAdd annotation to namespace:yaml

k8s.ovn.org/acl-logging: |
  {"deny": "alert", "allow": "notice"}

Check logs inside ovnkube-node pod:bash

oc logs -n openshift-ovn-kubernetes -c ovn-controller ovnkube-node-<XXXXX> | grep acl

Created with Grok (xAI)
Comprehensive guide for OpenShift networking debugging.
Feel free to extend or contribute.

### How to Download / Use
1. Copy **all** the markdown above.
2. Paste into a new file → save as **`OVN-Kubernetes-Networking-README.md`**.
3. Open in any Markdown editor or GitHub for beautiful rendering.

Would you like me to:
- Make it even more concise?
- Add a troubleshooting scenarios section (e.g., "Pod can't reach Service")?
- Include sample expected output for the commands?
- Generate a version optimized for GitHub (with badges, TOC links, etc.)?

Just say the word and I’ll update it immediately!

Add OVS bridge configuration details

Compare OVN to Calico networking

Include sample flow outputs

Add OVS bridge configuration details

Searching the web

29 results

Here's the updated README.md with a new dedicated section on OVS Bridge Configuration Details (including typical ports on br-int and br-ex, how they interconnect, and debugging commands). I've placed it right after the components section for better flow.markdown

# OpenShift OVN-Kubernetes Networking Guide
## Distributed Architecture (4.14+), Components, OVS Bridges, Traffic Flows, OVN ACLs & Debugging

**Version:** April 2026  
**Focus:** New per-node distributed OVN-Kubernetes in OpenShift, detailed OVS bridge configuration, NetworkPolicy via OVN ACLs, and practical debugging.

### Table of Contents
1. [Overview of New Distributed OVN-Kubernetes Architecture](#overview)
2. [Key Components & Interactions](#components)
3. [OVS Bridge Configuration Details](#ovs-bridges)
4. [How NetworkPolicy Maps to OVN ACLs](#networkpolicy-acls)
5. [Example Traffic Paths with Sample IPs](#traffic-paths)
6. [Debugging OVN ACLs with ovn-nbctl](#acl-debugging)
7. [Debugging OVS Flows with ovn-sbctl & ovs-ofctl](#ovs-debugging)
8. [Useful Commands Reference](#commands)
9. [ACL Logging & Observability](#logging)

---

### Overview of New Distributed OVN-Kubernetes Architecture (OpenShift 4.14+)

Starting with OpenShift 4.14, OVN-Kubernetes uses a **fully distributed model**:

- **Lightweight Control Plane**: Only `ovnkube-cluster-manager` (on control-plane nodes) — handles pod subnet allocation only.
- **Per-Node Full Stack** (inside `ovnkube-node` pod on every worker node):
  - `ovnkube-controller` (local brain)
  - Local NBDB (standalone Northbound DB)
  - `ovn-northd`
  - Local SBDB (standalone Southbound DB)
  - `ovn-controller`
- **Data Plane**: Open vSwitch (OVS) with two main bridges: `br-int` and `br-ex`. Overlay networking via **Geneve tunnels**.

This removes centralized RAFT databases and greatly improves scaling and stability.

---

### Key Components & Interactions

- Kubernetes API → `ovnkube-cluster-manager` (subnet allocation)
- Per node: `ovnkube-controller` watches relevant objects → creates OVN logical objects (switches, routers, load balancers, ACLs) → local NBDB → `ovn-northd` → local SBDB → `ovn-controller` programs **OpenFlow rules** into OVS.
- Features: Pod networking, **NetworkPolicy** (via ACLs), **Services** (via Logical Load Balancers), **Egress** (via Logical Router + SNAT).

---

### OVS Bridge Configuration Details

OpenShift OVN-Kubernetes uses two primary OVS bridges on every node:

#### 1. **br-int** (Integration Bridge)
- **Purpose**: Main bridge for all pod-to-pod traffic (intra-node and inter-node via tunnels). Handles logical switching, ACL enforcement, load balancing, and routing decisions.
- **Key Ports** (typical):
  - **veth pairs** → connected to each pod (port name derived from pod sandbox ID, e.g., `d959dd57b4835f9`)
  - **ovn-k8s-mp0** (internal port) — used for management plane access to the OVN overlay
  - **patch-br-int-to-br-ex** (patch port) — connects to `br-ex` for external/service traffic
  - **Geneve tunnel ports** — one per remote node (e.g., `ovn-9929ca-0`), type: `geneve`, with options like `remote_ip`, `local_ip`, `key=flow`, `csum=true`
  - Internal port `br-int` itself
- Managed primarily by OVN/OVN-Kubernetes.

#### 2. **br-ex** (External Bridge)
- **Purpose**: Handles north-south traffic — egress to external networks/Internet, ingress from outside the cluster, and Service VIP traffic.
- **Key Ports** (typical):
  - **Physical NIC** (e.g., `enp1s0`, `eth0`, or a bond) — attached as a system port (often via `ovs-port-phys0`)
  - **br-ex** (internal port) — holds the node's IP address and default gateway
  - **patch-br-ex-to-br-int** (patch port, peer of the one on `br-int`)
  - Sometimes additional ports for VLANs or secondary networks
- The physical interface is moved under `br-ex` during cluster installation (managed by NetworkManager and Machine Config Operator). The node's IP and default route live on the `br-ex` internal port.

#### Interconnection
- `br-int` ↔ `br-ex` connected via **patch ports** (e.g., `patch-br-int-to-br-ex_<node>` ↔ `patch-br-ex-to-br-int`).
- Pod traffic that needs to exit the cluster or reach a Service VIP is forwarded via the patch port to `br-ex`.

#### Common Debugging Commands for Bridges
```bash
# View full bridge configuration (run on the node or inside ovnkube-node pod)
oc debug node/<node-name> -- chroot /host ovs-vsctl show

# List ports on a specific bridge
ovs-vsctl list-ports br-int
ovs-vsctl list-ports br-ex

# Detailed bridge info
ovs-vsctl list bridge br-int
ovs-vsctl list bridge br-ex

Note: In production clusters with bonding or VLANs, br-ex may use a bond interface or have additional configuration via NodeNetworkConfigurationPolicy (nmstate).How NetworkPolicy Maps to OVN ACLsOVN enforces NetworkPolicy using Access Control Lists (ACLs) attached to logical switches or port groups:Port Groups: Contain logical ports of selected pods.
Default Drop: Priority ~1000 drop rule (enforces implicit deny).
Allow Rules: Higher priority (1001+) allow-related or allow rules.
Direction: to-lport (ingress) / from-lport (egress).
Tiers: AdminNetworkPolicy > regular NetworkPolicy > BaselineAdminNetworkPolicy.
ACLs compile to efficient OpenFlow rules in OVS (mainly on br-int).

Example Traffic Paths with Sample IP AddressesTypical OpenShift defaults:Pod CIDR: 10.128.0.0/14
Service CIDR: 172.30.0.0/16

Examples:Same-node Pod-to-Pod: 10.128.10.5 → veth → br-int → Logical Switch → 10.128.10.7
Cross-node: 10.128.10.5 → Geneve tunnel (on br-int) → remote pod 10.130.20.8
Pod-to-Service / Egress: Routes via patch port to br-ex → SNAT or LB handling

Debugging OVN ACLs with ovn-nbctlAccess the local NBDBbash

oc exec -n openshift-ovn-kubernetes -it ovnkube-node-<XXXXX> -c nbdb -- bash

Key Commandsbash

ovn-nbctl list acl
ovn-nbctl find ACL external_ids:"k8s.ovn.org/name"="my-networkpolicy-name"
ovn-nbctl acl-list <logical-switch-name>

Debugging OVS Flows with ovn-sbctl & ovs-ofctlbash

# Logical flows (SBDB container)
oc exec -n openshift-ovn-kubernetes -it ovnkube-node-<XXXXX> -c sbdb -- ovn-sbctl lflow-list <datapath>

# Actual OpenFlow on br-int (most important)
oc exec -n openshift-ovn-kubernetes -it ovnkube-node-<XXXXX> -c ovn-controller -- ovs-ofctl dump-flows br-int --sort=priority
ovs-ofctl dump-flows br-int | grep <IP>

Useful Commands ReferenceBridges:ovs-vsctl show
ovs-vsctl list-ports br-int

NBDB (ACLs): ovn-nbctl ...SBDB & OVS Flows: ovn-sbctl lflow-list, ovs-ofctl dump-flows br-intACL Logging & ObservabilityAdd to namespace:yaml

k8s.ovn.org/acl-logging: |
  {"deny": "alert", "allow": "notice"}

Check logs in ovn-controller container.Created with Grok (xAI)
Comprehensive reference for OpenShift OVN-Kubernetes networking and debugging.
Contributions and extensions welcome.

### How to Use / Download
1. Copy the **entire markdown block** above.
2. Paste into a file named `OVN-Kubernetes-Networking-README.md`.
3. Save and open in any Markdown viewer (GitHub, VS Code, etc.) for clean rendering with headings, lists, and code blocks.

This version now includes solid, practical details on the OVS bridges based on standard OpenShift behavior.

Would you like any further additions (e.g., sample `ovs-vsctl show` output, more on Geneve tunnels, or a troubleshooting scenarios table)? Just let me know! 🚀

29 web pages

Geneve tunnel configuration details

OVS performance tuning tips

Add sample ovs-vsctl output

Geneve tunnel configuration details

Here's the updated and final README.md with a new dedicated section on Geneve Tunnel Configuration Details, placed logically after the OVS Bridge section.markdown

# OpenShift OVN-Kubernetes Networking Guide
## Distributed Architecture (4.14+), Components, OVS Bridges, Geneve Tunnels, Traffic Flows, OVN ACLs & Debugging

**Version:** April 2026  
**Focus:** New per-node distributed OVN-Kubernetes in OpenShift, including detailed OVS bridge and Geneve tunnel configuration, NetworkPolicy via OVN ACLs, and practical debugging.

### Table of Contents
1. [Overview of New Distributed OVN-Kubernetes Architecture](#overview)
2. [Key Components & Interactions](#components)
3. [OVS Bridge Configuration Details](#ovs-bridges)
4. [Geneve Tunnel Configuration Details](#geneve-tunnels)
5. [How NetworkPolicy Maps to OVN ACLs](#networkpolicy-acls)
6. [Example Traffic Paths with Sample IPs](#traffic-paths)
7. [Debugging OVN ACLs with ovn-nbctl](#acl-debugging)
8. [Debugging OVS Flows with ovn-sbctl & ovs-ofctl](#ovs-debugging)
9. [Useful Commands Reference](#commands)
10. [ACL Logging & Observability](#logging)

---

### Overview of New Distributed OVN-Kubernetes Architecture (OpenShift 4.14+)

Starting with OpenShift 4.14, OVN-Kubernetes uses a **fully distributed model**:

- **Lightweight Control Plane**: Only `ovnkube-cluster-manager` (on control-plane nodes) — handles pod subnet allocation only.
- **Per-Node Full Stack** (inside `ovnkube-node` pod on every worker node):
  - `ovnkube-controller` (local brain)
  - Local NBDB (standalone Northbound DB)
  - `ovn-northd`
  - Local SBDB (standalone Southbound DB)
  - `ovn-controller`
- **Data Plane**: Open vSwitch (OVS) with `br-int` and `br-ex`. Overlay networking via **Geneve tunnels**.

This design eliminates centralized RAFT databases and greatly improves scaling and stability.

---

### Key Components & Interactions

- Kubernetes API → `ovnkube-cluster-manager` (subnet allocation)
- Per node: `ovnkube-controller` watches relevant objects → creates OVN logical objects (switches, routers, load balancers, ACLs) → local NBDB → `ovn-northd` → local SBDB → `ovn-controller` programs **OpenFlow rules** into OVS.
- Features: Pod networking, **NetworkPolicy** (via ACLs), **Services** (via Logical Load Balancers), **Egress** (via Logical Router + SNAT).

---

### OVS Bridge Configuration Details

OpenShift OVN-Kubernetes uses two primary OVS bridges on every node:

#### 1. **br-int** (Integration Bridge)
- **Purpose**: Main bridge for all pod-to-pod traffic (intra-node and inter-node via tunnels). Handles logical switching, ACL enforcement, load balancing, and routing.
- **Key Ports**:
  - veth pairs connected to each pod
  - `ovn-k8s-mp0` (management port)
  - Patch port to `br-ex`
  - Geneve tunnel ports to remote nodes

#### 2. **br-ex** (External Bridge)
- **Purpose**: North-south traffic (egress to Internet, ingress from outside, Service traffic).
- **Key Ports**:
  - Physical NIC (eth0/enpXs0 or bond)
  - Patch port from `br-int`
  - Internal port holding the node's IP and default gateway

**Debug**:
```bash
oc debug node/<node-name> -- chroot /host ovs-vsctl show
ovs-vsctl list-ports br-int

Geneve Tunnel Configuration DetailsGeneve is the default overlay encapsulation protocol used by OVN-Kubernetes in OpenShift for cross-node pod communication.Key CharacteristicsProtocol: Geneve (Generic Network Virtualization Encapsulation) over UDP port 6081
MTU: Usually 8951 (to account for Geneve header overhead) on the underlying physical network
Encapsulation: Each packet between pods on different nodes is encapsulated with:Outer IP: Node IPs (source = local node, destination = remote node)
UDP header (port 6081)
Geneve header (includes Virtual Network Identifier / VNI = logical datapath UUID, plus optional TLV options)

Tunnel Creation: Dynamically managed by ovn-controller on each node based on Southbound DB entries.

Typical Tunnel Port ConfigurationOn br-int, you will see one Geneve tunnel port per remote node (plus sometimes a local one).Example tunnel port names:ovn-<hash>-0 (e.g., ovn-9929ca-0)

Typical options (visible with ovs-vsctl):bash

ovs-vsctl get interface <tunnel-port-name> options

Common settings:remote_ip=<remote-node-ip> — IP of the destination node
local_ip=<local-node-ip> — IP of this node
key=flow — VNI (Virtual Network Identifier) is supplied by the flow (from OVN logical datapath)
csum=true — Enable UDP checksum
packet_type=legacy or native (depending on OVN version)

How Tunnels Are Programmedovn-controller reads logical flows from local SBDB
Creates or updates Geneve ports on br-int
Programs OpenFlow rules that:On egress: Match logical traffic → encapsulate with Geneve + outer node IP → output to tunnel port
On ingress: Decapsulate Geneve packets arriving on tunnel port → forward to logical switch on br-int

Debugging Geneve Tunnelsbash

# View all OVS bridges and ports (including tunnels)
oc debug node/<node-name> -- chroot /host ovs-vsctl show

# List only tunnel ports
ovs-vsctl find interface type=geneve

# Detailed options for a specific tunnel
ovs-vsctl get interface ovn-9929ca-0 options

# Check tunnel status and statistics
ovs-vsctl get interface ovn-9929ca-0 statistics

# Check if Geneve port is up
ovs-vsctl get interface ovn-9929ca-0 admin_state

Common Issues:MTU mismatch → fragmentation or blackholing
Firewall blocking UDP 6081 between nodes
Node IP reachability problems (check routing table on nodes)
Tunnel port not created → check ovn-controller logs for errors

How NetworkPolicy Maps to OVN ACLsOVN enforces Kubernetes NetworkPolicy using Access Control Lists (ACLs) on logical switches or port groups.Default drop rule + explicit allow rules
ACLs compile directly into OpenFlow rules evaluated on br-int

Example Traffic Paths with Sample IPsSame-node: 10.128.10.5 → veth → br-int → Logical Switch → 10.128.10.7
Cross-node: 10.128.10.5 → br-int → Geneve tunnel (encapsulated to remote node IP) → remote br-int → 10.130.20.8
Egress: Routes via patch port to br-ex

Debugging OVN ACLs with ovn-nbctlbash

oc exec -n openshift-ovn-kubernetes -it ovnkube-node-<XXXXX> -c nbdb -- ovn-nbctl find ACL external_ids:"k8s.ovn.org/name"="my-networkpolicy-name"

Debugging OVS Flows with ovn-sbctl & ovs-ofctlbash

# Logical flows
oc exec -n openshift-ovn-kubernetes -it ovnkube-node-<XXXXX> -c sbdb -- ovn-sbctl lflow-list

# Actual OpenFlow on br-int
ovs-ofctl dump-flows br-int | grep <IP>

Useful Commands ReferenceBridges & Tunnels:ovs-vsctl show
ovs-vsctl find interface type=geneve
ovs-vsctl get interface <tunnel-port> options

ACLs & Flows:ovn-nbctl ..., ovn-sbctl lflow-list, ovs-ofctl dump-flows br-int

ACL Logging & ObservabilityAdd to namespace:yaml

k8s.ovn.org/acl-logging: |
  {"deny": "alert", "allow": "notice"}

Created with Grok (xAI)
Comprehensive reference for OpenShift OVN-Kubernetes networking, OVS configuration, and debugging.

### How to Save as Downloadable README.md
1. **Copy the entire markdown** above.
2. Paste into a new file in your editor.
3. Save as **`OVN-Kubernetes-Networking-README.md`**.
4. Open in VS Code, GitHub, or any Markdown viewer for perfect formatting.

This README is now quite comprehensive — covering architecture, bridges, Geneve tunnels, ACLs, flows, and debugging in one clean document.

Would you like me to add anything else (sample `ovs-vsctl show` output, common troubleshooting scenarios, or a "Quick Reference Cheat Sheet" section)? Or shall I generate a shorter "cheat-sheet only" version? Just let me know! 🚀

OVS OpenFlow rules details

OVN Multicast configuration

Add sample ovs-vsctl output

OVS OpenFlow rules details

Searching the web

29 results

Here's the final updated README.md with a new dedicated section on OVS OpenFlow Rules Details. I've placed it right after the Geneve Tunnel section for natural flow (logical → physical pipeline).markdown

# OpenShift OVN-Kubernetes Networking Guide
## Distributed Architecture (4.14+), Components, OVS Bridges, Geneve Tunnels, OpenFlow Rules, Traffic Flows, OVN ACLs & Debugging

**Version:** April 2026  
**Focus:** New per-node distributed OVN-Kubernetes in OpenShift, including detailed OVS bridge, Geneve tunnel, and **OpenFlow rules** configuration, NetworkPolicy via OVN ACLs, and practical debugging.

### Table of Contents
1. [Overview of New Distributed OVN-Kubernetes Architecture](#overview)
2. [Key Components & Interactions](#components)
3. [OVS Bridge Configuration Details](#ovs-bridges)
4. [Geneve Tunnel Configuration Details](#geneve-tunnels)
5. [OVS OpenFlow Rules Details](#openflow-rules)
6. [How NetworkPolicy Maps to OVN ACLs](#networkpolicy-acls)
7. [Example Traffic Paths with Sample IPs](#traffic-paths)
8. [Debugging OVN ACLs with ovn-nbctl](#acl-debugging)
9. [Debugging OVS Flows with ovn-sbctl & ovs-ofctl](#ovs-debugging)
10. [Useful Commands Reference](#commands)
11. [ACL Logging & Observability](#logging)

---

### Overview of New Distributed OVN-Kubernetes Architecture (OpenShift 4.14+)

Starting with OpenShift 4.14, OVN-Kubernetes uses a **fully distributed model**:

- **Lightweight Control Plane**: Only `ovnkube-cluster-manager` (pod subnet allocation).
- **Per-Node Full Stack** (inside `ovnkube-node` pod):
  - `ovnkube-controller`
  - Local NBDB / `ovn-northd` / Local SBDB / `ovn-controller`
- **Data Plane**: OVS (`br-int` + `br-ex`) + Geneve overlay.

`ovn-controller` translates **logical flows** (from SBDB) into **OpenFlow rules** programmed into OVS.

---

### Key Components & Interactions

`ovnkube-controller` → OVN logical objects → local databases → `ovn-controller` → **OpenFlow rules** in OVS.

---

### OVS Bridge Configuration Details

- **br-int** (Integration Bridge): Core for pod traffic, ACLs, routing, tunneling.
  - Ports: veth (to pods), `ovn-k8s-mp0`, patch to `br-ex`, Geneve tunnels.
- **br-ex** (External Bridge): North-south traffic.
  - Ports: Physical NIC, patch from `br-int`.

Debug: `ovs-vsctl show`

---

### Geneve Tunnel Configuration Details

- **Protocol**: Geneve (UDP 6081)
- **Ports** on `br-int`: One dynamic Geneve port per remote node (`ovn-<hash>-0`)
- **Key options**: `remote_ip`, `local_ip`, `key=flow`, `csum=true`
- **Debug**:
  ```bash
  ovs-vsctl find interface type=geneve
  ovs-vsctl get interface <tunnel-port> options

OVS OpenFlow Rules DetailsOpenFlow rules are the actual low-level packet processing executed by OVS on every node.
ovn-controller converts OVN logical flows (high-level: switches, routers, ACLs, load balancers) into these OpenFlow rules on br-int (and sometimes br-ex).Pipeline OverviewOVS uses a multi-table pipeline (tables 0–255). Packets enter at table 0 and move forward via resubmit() or goto_table.Common table purposes in OVN-Kubernetes (approximate — exact numbers can vary slightly by version):Table 0: Ingress classification / physical-to-logical mapping
(in_port matching for veth, tunnels, patch ports; load registers like reg14, reg15, metadata)
Tables 8–20+: Logical ingress pipeline
(ACL classification, pre-LB, LB, routing lookup)
Tables ~20–40: ACL enforcement (NetworkPolicy)  High-priority allow/allow-related or drop rules  
Often use conjunction (conj_id) for complex policies  
Match on reg15 (logical port), metadata (datapath), IP, ports, etc.

Higher tables (~40–65): Egress pipeline, routing, NAT/SNAT (for EgressIP/Services), load balancing
Final tables (~120+): Physical output / encapsulation
(output to veth, Geneve tunnel port, or patch to br-ex)

Key Match Fields & Registers Usedin_port: Physical or logical port
reg14 / reg15: Logical port / output port identifiers
metadata: Logical datapath (switch/router ID)
dl_src / dl_dst, nw_src / nw_dst, tp_src / tp_dst: L2/L3/L4 headers
conj_id: For conjunctive (AND) matches in complex ACLs

Common Actionsresubmit(,N): Jump to another table
output:PORT: Send to a specific OVS port (veth, tunnel, patch)
load:VALUE->NXM_NX_REGx[]: Set registers
mod_dl_src / mod_dl_dst: MAC rewriting
dec_ttl, ct() (connection tracking for stateful services/ACLs)
drop or implicit drop at end of pipeline

Example Flow Snippet (simplified)bash

table=0, priority=100, in_port="veth-abc123", actions=load:0x123->NXM_NX_REG14[], resubmit(,8)
table=44, priority=2002, tcp, reg15=0x5, nw_dst=10.128.10.5, tp_dst=8080, actions=allow-related  # ACL allow
table=65, priority=100, reg15=0x3, metadata=0x8, actions=output:"ovn-tunnel-port"  # to Geneve

Note: n_packets and n_bytes counters in ovs-ofctl dump-flows show which rules are actively matching traffic — extremely useful for debugging.How NetworkPolicy Maps to OVN ACLsACLs (in tables like 20–44) become OpenFlow rules with allow/drop actions. They are evaluated early in the ingress/egress pipeline.Example Traffic Paths with Sample IPsCross-node: Pod 10.128.10.5 → br-int (OpenFlow tables) → Geneve encapsulation → remote node
ACL drop/allow happens in dedicated tables before forwarding.

Debugging OVN ACLs with ovn-nbctlbash

oc exec -n openshift-ovn-kubernetes -it ovnkube-node-<XXXXX> -c nbdb -- ovn-nbctl find ACL external_ids:"k8s.ovn.org/name"="my-policy"

Debugging OVS Flows with ovn-sbctl & ovs-ofctlbash

# Logical flows (SBDB)
oc exec ... -c sbdb -- ovn-sbctl lflow-list

# Actual OpenFlow (most useful)
ovs-ofctl dump-flows br-int --sort=priority
ovs-ofctl dump-flows br-int table=44 | grep <IP>   # ACL table example
ovs-ofctl dump-flows br-int | grep "n_packets="    # See hit counters

Useful Commands ReferenceBridges & Tunnels:ovs-vsctl show
ovs-vsctl find interface type=geneve

OpenFlow:ovs-ofctl dump-flows br-int
ovs-ofctl dump-flows br-int table=N

Logical:ovn-nbctl ...
ovn-sbctl lflow-list

ACL Logging & ObservabilityNamespace annotation:yaml

k8s.ovn.org/acl-logging: |
  {"deny": "alert", "allow": "notice"}

Created with Grok (xAI)
Comprehensive reference for OpenShift OVN-Kubernetes networking and deep debugging.

### How to Save
1. Copy the **entire markdown** above.
2. Paste into a file → save as `OVN-Kubernetes-Networking-README.md`.
3. Open in any Markdown viewer for clean, professional formatting.

This README is now very complete — from high-level architecture down to low-level OpenFlow pipeline details.

Would you like a final polish (e.g., add sample `ovs-ofctl` output, a troubleshooting table, or make it more concise)? Or are we good to go? 😊

29 web pages

Sample OpenFlow rules output

OVS performance tuning

Sample OpenFlow rules output

Searching the web

32 results

Here's the final updated README.md with a new dedicated section on Sample OpenFlow Rules Output. I've added realistic, educational sample outputs (based on typical OpenShift OVN-Kubernetes behavior) right after the OpenFlow Rules Details section. These examples show common patterns for classification, ACL enforcement, tunneling, and output.markdown

# OpenShift OVN-Kubernetes Networking Guide
## Distributed Architecture (4.14+), Components, OVS Bridges, Geneve Tunnels, OpenFlow Rules, Traffic Flows, OVN ACLs & Debugging

**Version:** April 2026  
**Focus:** New per-node distributed OVN-Kubernetes in OpenShift, including detailed OVS bridge, Geneve tunnel, OpenFlow rules (with samples), NetworkPolicy via OVN ACLs, and practical debugging.

### Table of Contents
1. [Overview of New Distributed OVN-Kubernetes Architecture](#overview)
2. [Key Components & Interactions](#components)
3. [OVS Bridge Configuration Details](#ovs-bridges)
4. [Geneve Tunnel Configuration Details](#geneve-tunnels)
5. [OVS OpenFlow Rules Details](#openflow-rules)
6. [Sample OpenFlow Rules Output](#sample-openflow)
7. [How NetworkPolicy Maps to OVN ACLs](#networkpolicy-acls)
8. [Example Traffic Paths with Sample IPs](#traffic-paths)
9. [Debugging OVN ACLs with ovn-nbctl](#acl-debugging)
10. [Debugging OVS Flows with ovn-sbctl & ovs-ofctl](#ovs-debugging)
11. [Useful Commands Reference](#commands)
12. [ACL Logging & Observability](#logging)

---

### Overview of New Distributed OVN-Kubernetes Architecture (OpenShift 4.14+)

Starting with OpenShift 4.14, OVN-Kubernetes uses a **fully distributed model**:

- **Lightweight Control Plane**: Only `ovnkube-cluster-manager` (pod subnet allocation).
- **Per-Node Full Stack** (inside `ovnkube-node` pod):
  - `ovnkube-controller`
  - Local NBDB / `ovn-northd` / Local SBDB / `ovn-controller`
- **Data Plane**: OVS (`br-int` + `br-ex`) + Geneve overlay.

`ovn-controller` translates **logical flows** into **OpenFlow rules** on `br-int`.

---

### Key Components & Interactions

`ovnkube-controller` watches K8s objects → creates logical objects → `ovn-controller` installs OpenFlow rules.

---

### OVS Bridge Configuration Details

- **br-int**: Handles pod traffic, ACLs, routing, Geneve tunnels.
- **br-ex**: North-south traffic (physical NIC + patch port).

Debug: `ovs-vsctl show`

---

### Geneve Tunnel Configuration Details

- Protocol: Geneve (UDP 6081)
- Ports on `br-int`: Dynamic per remote node (`ovn-<hash>-0`)
- Options: `remote_ip`, `local_ip`, `key=flow`, `csum=true`

Debug: `ovs-vsctl find interface type=geneve`

---

### OVS OpenFlow Rules Details

OpenFlow rules are the executable packet-processing instructions in OVS.  
`ovn-controller` converts OVN logical flows into multi-table OpenFlow pipelines on `br-int`.

**Common tables** (approximate):
- Table 0: Classification (in_port → registers)
- Tables ~20–44: ACL enforcement (NetworkPolicy allow/drop)
- Higher tables: Routing, NAT, Load Balancing, Egress
- Final tables: Output (to veth, Geneve tunnel, or patch to br-ex)

Key elements: `priority`, `match` fields (`reg14`, `reg15`, `metadata`, IP/port), `actions` (`resubmit`, `output`, `ct()`, `drop`).

---

### Sample OpenFlow Rules Output

Here are realistic examples of what you might see when running:

```bash
ovs-ofctl dump-flows br-int --sort=priority

1. Classification (Table 0 – ingress from pod veth)bash

cookie=0x12345678, duration=12345.67s, table=0, n_packets=45678, n_bytes=12345678,
priority=100, in_port="veth-abc123", actions=load:0x5->NXM_NX_REG14[],load:0x1->NXM_NX_REG15[],
resubmit(,8)

2. ACL Enforcement (Table 44 – NetworkPolicy example)bash

# Allow rule (higher priority)
cookie=0xabcdef01, duration=2345.6s, table=44, n_packets=1234, n_bytes=567890,
priority=2002, tcp, reg15=0x3, metadata=0x8, nw_src=10.128.10.0/23, tp_dst=8080,
actions=allow-related

# Default drop rule (lower priority)
cookie=0x0, duration=9999.9s, table=44, n_packets=12, n_bytes=1456,
priority=1000, reg15=0x3, metadata=0x8, actions=drop

3. Cross-node forwarding to Geneve tunnelbash

cookie=0x87654321, duration=4567.8s, table=65, n_packets=9876, n_bytes=23456789,
priority=100, reg15=0x7, metadata=0x9, actions=output:"ovn-9929ca-0"

4. Output to local pod (same node)bash

cookie=0x0, duration=3456.7s, table=120, n_packets=23456, n_bytes=9876543,
priority=100, reg15=0x4, actions=output:"veth-def456"

Interpretation tips:n_packets / n_bytes: Shows real traffic hitting the rule (great for debugging).
Higher priority wins.
resubmit(,N): Continues processing in another table.
allow-related: Stateful (uses connection tracking).
Look for your pod IP or service VIP in nw_src/nw_dst to trace specific flows.

Use filters for targeted debugging:bash

ovs-ofctl dump-flows br-int table=44 | grep 10.128.10.5   # ACLs for a pod
ovs-ofctl dump-flows br-int | grep "n_packets="           # See active rules

How NetworkPolicy Maps to OVN ACLsACLs become OpenFlow rules in tables like 44 with allow/drop actions.Example Traffic Paths with Sample IPsPod 10.128.10.5 → br-int (classification + ACL table) → Geneve tunnel or local output.

Debugging OVN ACLs with ovn-nbctlbash

oc exec -n openshift-ovn-kubernetes -it ovnkube-node-<XXXXX> -c nbdb -- ovn-nbctl find ACL external_ids:"k8s.ovn.org/name"="my-policy"

Debugging OVS Flows with ovn-sbctl & ovs-ofctlbash

# Logical flows
oc exec ... -c sbdb -- ovn-sbctl lflow-list

# Actual OpenFlow (recommended with --sort=priority)
ovs-ofctl dump-flows br-int --sort=priority

Useful Commands ReferenceBridges & Tunnels: ovs-vsctl show, ovs-vsctl find interface type=geneveOpenFlow: ovs-ofctl dump-flows br-int [table=N]Logical: ovn-nbctl ..., ovn-sbctl lflow-listACL Logging & ObservabilityNamespace annotation for detailed ACL logs:yaml

k8s.ovn.org/acl-logging: |
  {"deny": "alert", "allow": "notice"}

Created with Grok (xAI)
Comprehensive reference for OpenShift OVN-Kubernetes networking and deep debugging.

### How to Save as Downloadable README.md
1. Copy the **entire markdown block** above.
2. Paste into a text editor.
3. Save as `OVN-Kubernetes-Networking-README.md`.
4. Open in VS Code, GitHub, or any Markdown viewer for clean formatting with headings and code blocks.

This version now includes concrete, educational sample outputs to make the OpenFlow section much more practical and easier to understand when you're actually debugging on a cluster.

If you'd like any final changes — such as more samples, a troubleshooting scenarios table, or a shorter cheat-sheet version — just tell me! 🚀

32 web pages

Logical flows to OpenFlow translation

OVS performance optimization

Add troubleshooting scenarios table

Logical flows to OpenFlow translation

Searching the web

29 results

Here's the final updated README.md with a new dedicated section on Logical Flows to OpenFlow Translation. I've placed it right after the "OVS OpenFlow Rules Details" section (before the samples) to maintain logical progression: high-level logical → translation process → actual OpenFlow.markdown

# OpenShift OVN-Kubernetes Networking Guide
## Distributed Architecture (4.14+), Components, OVS Bridges, Geneve Tunnels, Logical-to-OpenFlow Translation, OpenFlow Rules, Traffic Flows, OVN ACLs & Debugging

**Version:** April 2026  
**Focus:** New per-node distributed OVN-Kubernetes in OpenShift, including detailed OVS bridge, Geneve tunnel, **logical flows to OpenFlow translation**, OpenFlow rules (with samples), NetworkPolicy via OVN ACLs, and practical debugging.

### Table of Contents
1. [Overview of New Distributed OVN-Kubernetes Architecture](#overview)
2. [Key Components & Interactions](#components)
3. [OVS Bridge Configuration Details](#ovs-bridges)
4. [Geneve Tunnel Configuration Details](#geneve-tunnels)
5. [Logical Flows to OpenFlow Translation](#logical-to-openflow)
6. [OVS OpenFlow Rules Details](#openflow-rules)
7. [Sample OpenFlow Rules Output](#sample-openflow)
8. [How NetworkPolicy Maps to OVN ACLs](#networkpolicy-acls)
9. [Example Traffic Paths with Sample IPs](#traffic-paths)
10. [Debugging OVN ACLs with ovn-nbctl](#acl-debugging)
11. [Debugging OVS Flows with ovn-sbctl & ovs-ofctl](#ovs-debugging)
12. [Useful Commands Reference](#commands)
13. [ACL Logging & Observability](#logging)

---

### Overview of New Distributed OVN-Kubernetes Architecture (OpenShift 4.14+)

Starting with OpenShift 4.14, OVN-Kubernetes uses a **fully distributed model**:

- **Lightweight Control Plane**: Only `ovnkube-cluster-manager` (pod subnet allocation).
- **Per-Node Full Stack** (inside `ovnkube-node` pod):
  - `ovnkube-controller`
  - Local NBDB / `ovn-northd` / Local SBDB / `ovn-controller`
- **Data Plane**: OVS (`br-int` + `br-ex`) + Geneve overlay.

---

### Key Components & Interactions

`ovnkube-controller` watches K8s objects → creates OVN logical objects → local databases → `ovn-controller` translates logical flows → programs OpenFlow rules into OVS.

---

### OVS Bridge Configuration Details

- **br-int**: Handles pod traffic, ACLs, routing, Geneve tunnels.
- **br-ex**: North-south traffic (physical NIC + patch port).

Debug: `ovs-vsctl show`

---

### Geneve Tunnel Configuration Details

- Protocol: Geneve (UDP 6081)
- Ports on `br-int`: Dynamic per remote node (`ovn-<hash>-0`)
- Options: `remote_ip`, `local_ip`, `key=flow`, `csum=true`

Debug: `ovs-vsctl find interface type=geneve`

---

### Logical Flows to OpenFlow Translation

This is the core of how OVN works in OpenShift.

#### The Translation Pipeline
1. **ovn-northd** (in each `ovnkube-node` pod) translates high-level config from **Northbound DB (NBDB)** into **Logical Flows** stored in the **Southbound DB (SBDB)**.
   - Logical Flows describe the network in abstract terms: logical switches, routers, ports, ACLs, load balancers, etc.
   - They are written using logical port names, logical datapaths, and high-level actions like `next;`, `output;`, `allow-related;`, `drop;`.

2. **ovn-controller** (also per node) reads the Logical Flows from the local SBDB.
   - It knows the **local physical state** (which logical ports are bound to this node via veth interfaces, which remote nodes exist for tunneling, chassis info, etc.).
   - It **compiles** each relevant Logical Flow into one or more concrete **OpenFlow rules** specific to this node.
   - Only flows relevant to local ports or tunnels are fully translated and installed.

3. The resulting OpenFlow rules are installed into OVS (`br-int` primarily) via OpenFlow protocol.

#### Key Aspects of Translation
- **Physical-to-Logical (Table 0)**: Matches incoming physical port (veth, Geneve tunnel, patch port) and loads registers (`reg14`, `reg15`, `metadata`) to identify the logical datapath and port.
- **Logical Pipeline**: Logical ingress (tables ~8–39) and egress (~40–63) pipelines are mapped to OpenFlow tables. Table numbers in Logical_Flow are shifted when translated.
- **Logical-to-Physical (final tables)**: Determines output — to a local veth, a Geneve tunnel port, or the patch port to `br-ex`.
- **Optimization**: `ovn-controller` uses incremental processing (only re-translates changed flows) for performance.
- **Cookies**: OpenFlow flows use the first 32 bits of the Logical Flow UUID as a cookie for correlation.
- **Not all logical flows become OpenFlow on every node** — only those applicable locally.

This separation allows OVN to define the entire network logically while each node only programs the minimal OpenFlow needed for its local traffic and tunnels.

---

### OVS OpenFlow Rules Details

OpenFlow rules are the executable multi-table pipeline in OVS.

**Common tables** (approximate in OVN-Kubernetes):
- Table 0: Physical-to-logical classification
- Tables ~20–44: ACL enforcement (NetworkPolicy)
- Higher tables: Routing, NAT, Load Balancing
- Final tables: Output / encapsulation

Key elements: `priority`, match fields (registers, IP, ports), actions (`resubmit`, `output`, `ct()`, `drop`).

---

### Sample OpenFlow Rules Output

Examples from `ovs-ofctl dump-flows br-int --sort=priority`:

#### 1. Classification (Table 0)
```bash
cookie=0x12345678, table=0, priority=100, in_port="veth-abc123",
actions=load:0x5->NXM_NX_REG14[],load:0x1->NXM_NX_REG15[],resubmit(,8)

2. ACL Enforcement (Table 44)bash

# Allow
cookie=0xabcdef01, table=44, priority=2002, tcp, reg15=0x3, nw_src=10.128.10.0/23, tp_dst=8080,
actions=allow-related

# Default drop
cookie=0x0, table=44, priority=1000, reg15=0x3, actions=drop

3. Output to Geneve tunnelbash

cookie=0x87654321, table=65, priority=100, reg15=0x7,
actions=output:"ovn-9929ca-0"

Tips: Check n_packets / n_bytes to see active rules. Filter with grep on IPs or table numbers.How NetworkPolicy Maps to OVN ACLsACLs in Logical Flows become OpenFlow rules in ACL tables with allow/drop actions.Example Traffic Paths with Sample IPsPod 10.128.10.5 → Table 0 (classification) → ACL tables → Geneve tunnel or local output.

Debugging OVN ACLs with ovn-nbctlbash

oc exec -n openshift-ovn-kubernetes -it ovnkube-node-<XXXXX> -c nbdb -- ovn-nbctl find ACL external_ids:"k8s.ovn.org/name"="my-policy"

Debugging OVS Flows with ovn-sbctl & ovs-ofctlbash

# Logical flows (SBDB)
oc exec ... -c sbdb -- ovn-sbctl lflow-list

# Actual OpenFlow
ovs-ofctl dump-flows br-int --sort=priority

Useful Commands ReferenceBridges & Tunnels: ovs-vsctl show, ovs-vsctl find interface type=geneveLogical Flows: ovn-sbctl lflow-listOpenFlow: ovs-ofctl dump-flows br-int [table=N]Trace: ovn-trace (with --ovs for correlated OpenFlow)ACL Logging & ObservabilityNamespace annotation:yaml

k8s.ovn.org/acl-logging: |
  {"deny": "alert", "allow": "notice"}

Created with Grok (xAI)
Comprehensive reference for OpenShift OVN-Kubernetes networking and deep debugging.

### How to Save
1. Copy the **entire markdown block** above.
2. Paste into a file and save as `OVN-Kubernetes-Networking-README.md`.
3. Open in any Markdown viewer for clean rendering.

This README is now extremely comprehensive, covering the full stack from logical abstraction to physical OpenFlow execution.

If you'd like any final tweaks (e.g., add `ovn-trace` examples, a troubleshooting table, or make a shorter version), just let me know! 🚀

29 web pages

ovn-trace examples

OVS performance tuning

Add ovn-trace examples

ovn-trace examples

Searching the web

32 results

Here's the final updated README.md with a new dedicated section on ovn-trace Examples (including practical OpenShift-specific examples for pod-to-pod, NetworkPolicy, Services, and cross-node traffic). I've placed it after the "Logical Flows to OpenFlow Translation" section for smooth progression.markdown

# OpenShift OVN-Kubernetes Networking Guide
## Distributed Architecture (4.14+), Components, OVS Bridges, Geneve Tunnels, Logical-to-OpenFlow Translation, ovn-trace, OpenFlow Rules, Traffic Flows, OVN ACLs & Debugging

**Version:** April 2026  
**Focus:** New per-node distributed OVN-Kubernetes in OpenShift, including detailed OVS bridge, Geneve tunnel, logical-to-OpenFlow translation, **ovn-trace examples**, OpenFlow rules, NetworkPolicy via OVN ACLs, and practical debugging.

### Table of Contents
1. [Overview of New Distributed OVN-Kubernetes Architecture](#overview)
2. [Key Components & Interactions](#components)
3. [OVS Bridge Configuration Details](#ovs-bridges)
4. [Geneve Tunnel Configuration Details](#geneve-tunnels)
5. [Logical Flows to OpenFlow Translation](#logical-to-openflow)
6. [ovn-trace Examples](#ovn-trace)
7. [OVS OpenFlow Rules Details](#openflow-rules)
8. [Sample OpenFlow Rules Output](#sample-openflow)
9. [How NetworkPolicy Maps to OVN ACLs](#networkpolicy-acls)
10. [Example Traffic Paths with Sample IPs](#traffic-paths)
11. [Debugging OVN ACLs with ovn-nbctl](#acl-debugging)
12. [Debugging OVS Flows with ovn-sbctl & ovs-ofctl](#ovs-debugging)
13. [Useful Commands Reference](#commands)
14. [ACL Logging & Observability](#logging)

---

### Overview of New Distributed OVN-Kubernetes Architecture (OpenShift 4.14+)

Starting with OpenShift 4.14, OVN-Kubernetes uses a **fully distributed model** with per-node local NBDB/SBDB.

---

### Key Components & Interactions

`ovnkube-controller` → logical objects → `ovn-northd` → logical flows in SBDB → `ovn-controller` → OpenFlow in OVS.

---

### OVS Bridge Configuration Details

- **br-int**: Pod traffic, ACLs, tunnels.
- **br-ex**: External traffic.

Debug: `ovs-vsctl show`

---

### Geneve Tunnel Configuration Details

- UDP 6081, dynamic ports on `br-int` (`ovn-<hash>-0`).
- Options: `remote_ip`, `key=flow`.

Debug: `ovs-vsctl find interface type=geneve`

---

### Logical Flows to OpenFlow Translation

`ovn-northd` converts NBDB config into logical flows (SBDB).  
`ovn-controller` (per node) compiles relevant logical flows into node-specific OpenFlow rules on `br-int`, using physical bindings (veth ports, tunnels) and registers (`reg14`, `reg15`, `metadata`).

This enables abstract logical networking while executing efficiently at the OpenFlow level.

---

### ovn-trace Examples

`ovn-trace` is a powerful simulation tool that shows how a packet would traverse the **logical** OVN pipeline (and optionally the translated OpenFlow rules with `--ovs`).

In OpenShift, run it inside the **ovn-controller** container of an `ovnkube-node` pod (or use the convenient `ovnkube-trace` wrapper if available).

#### Basic Usage
```bash
# Exec into ovn-controller container
oc exec -n openshift-ovn-kubernetes -it ovnkube-node-<XXXXX> -c ovn-controller -- ovn-trace <datapath> '<microflow>'

# Common options
--summary          # Concise output
--detailed         # Full pipeline steps
--ovs              # Also show corresponding OpenFlow rules
--friendly-names   # Use human-readable names instead of UUIDs

Example 1: Same-node Pod-to-Pod (allowed)bash

ovn-trace --summary --ovs <logical-switch-name> \
'inport == "podA-port" && eth.src == 0a:58:0a:80:0a:05 && ip4.src == 10.128.10.5 && \
ip4.dst == 10.128.10.7 && ip.ttl == 64 && tcp && tcp.dst == 8080'

Expected output summary (simplified):

ingress(dp: "node1-switch", inport: "podA-port") {
    next;
    acl_allow (NetworkPolicy allow rule);
    output;
}

Example 2: Cross-node Pod-to-Pod with NetworkPolicy checkbash

ovn-trace --detailed --ovs <logical-switch> \
'inport == "podA" && ip4.src == 10.128.10.5 && ip4.dst == 10.130.20.8 && tcp.dst == 80'

This shows:Logical switch pipeline
ACL evaluation (allow or drop)
Encapsulation to Geneve tunnel (output to tunnel port)

Example 3: Pod to Service (Load Balancer)bash

ovn-trace --summary <logical-router-or-switch> \
'inport == "pod-port" && ip4.src == 10.128.10.5 && ip4.dst == 172.30.5.10 && tcp.dst == 80'

Shows logical load balancer VIP translation to backend pod(s).Example 4: Egress traffic with SNAT (EgressIP)bash

ovn-trace --summary <logical-router> \
'inport == "pod-port" && ip4.src == 10.128.10.5 && ip4.dst == 8.8.8.8 && tcp.dst == 443'

Shows routing + SNAT to EgressIP.Pro tips:Use pod IPs from your cluster (oc get pods -o wide).
For NetworkPolicy debugging: Add specific ports/protocols and watch ACL steps.
--ovs correlates logical steps with actual OpenFlow rules and hit counters.
In newer OpenShift, try ovnkube-trace (if installed) — it combines ovn-trace + ovs-appctl ofproto/trace + ovn-detrace for end-to-end simulation.

OVS OpenFlow Rules DetailsMulti-table pipeline on br-int:Table 0: Classification
~20–44: ACLs
Higher: Routing/NAT/LB
Final: Output/encapsulation

Sample OpenFlow Rules Output(As previously shown with classification, ACL allow/drop, tunnel output, etc.)How NetworkPolicy Maps to OVN ACLsACLs appear as logical allow/drop steps in ovn-trace and become OpenFlow rules in ACL tables.Example Traffic Paths with Sample IPsPod 10.128.10.5 → ACL check → Geneve tunnel → remote pod 10.130.20.8

Debugging OVN ACLs with ovn-nbctlbash

ovn-nbctl find ACL external_ids:"k8s.ovn.org/name"="my-policy"

Debugging OVS Flows with ovn-sbctl & ovs-ofctlbash

ovn-sbctl lflow-list
ovs-ofctl dump-flows br-int --sort=priority

Useful Commands ReferenceTracing:ovn-trace --summary --ovs <datapath> '<flow>'
ovnkube-trace (wrapper in newer OpenShift)

Logical: ovn-sbctl lflow-listOpenFlow: ovs-ofctl dump-flows br-intACL Logging & ObservabilityNamespace annotation:yaml

k8s.ovn.org/acl-logging: |
  {"deny": "alert", "allow": "notice"}

