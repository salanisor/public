Stuff for vSphere

no DHCP - static `install-config.yaml`
https://docs.redhat.com/en/documentation/openshift_container_platform/4.16/html-single/installing/index#installation-vsphere-installer-infra-requirements_ipi-vsphere-installation-reqs

Infrastructure provider URL
https://console.redhat.com/openshift/install

~~~
cp certs/lin/* /etc/pki/ca-trust/source/anchors

update-ca-trust extract

https://console.redhat.com/openshift/install/pull-secret

`exports`
~~~
export Domain={Your base domain name}
export Cluster_Name={Your OCP cluster name}
export Cluster_MachineNetwork={Your OCP cluster subnet}
export Control_Plane_Count={Set number of Control Nodes}
export Control_Plane_CPU={Set CPU Sockets for Control Node}
export Control_Plane_Cores={Set CPU Cores per Socket for Control Node}
export Control_Plane_MemoryMB={Set Memory (in MB) for Control Node}
export Control_Plane_OSDiskGB={Set OS Disk Size (inGB) for Control Node}
export Compute_Plane_Count={Set number of Compute Nodes}
export Compute_Plane_CPU={Set CPU Sockets for Compute Node}
export Compute_Plane_Cores={Set CPU Cores per Socket for Compute Node}
export Compute_Plane_Memory={Set Memory (in MB) for Compute Node}
export Compute_Plane_OSDisk={Set OS Disk Size (inGB) for Compute Node}
export vCenter={Set vCenter FQDN/IP}
export vCenter_User={Set vCenter User}
export vCenter_Pass={Set vCenter Password}
export vCenter=Datacenter={Set vCenter Datacenter}
export vCenter_Cluster={Set vCenter Cluster name}
export vCenter_Datastore={Set datastore to deploy OCP VMs to}
export VM_Network={Set network for OCP VMs}
export apiVIP={Set api IP address}
export ingressVIP={Set ingress IP address}
export pullsecret= $(&lt; ~/{location}/pull-secret.json)
export SSH_KEY= $(&lt; ~/.ssh/id_rsa.pub)
~~~


`install-config.yaml`
~~~
cat << EOF > install-config.yaml
apiVersion: v1
baseDomain: $Domain
compute: 
- hyperthreading: Enabled 
  name: worker
  replicas: $Compute_Plane_Count
  platform:
    vsphere: 
      cpus: $Compute_Plane_CPU
      coresPerSocket: $Compute_Plane_Cores
      memoryMB: $Compute_Plane_Memory
      osDisk:
        diskSizeGB: $Compute_Plane_OSDisk
controlPlane: 
  hyperthreading: Enabled 
  name: master
  replicas: $Control_Plane_Count
  platform:
    vsphere: 
      cpus: $Control_Plane_CPU
      coresPerSocket: $Control_Plane_Cores
      memoryMB: $Control_Plane_Memory
      osDisk:
        diskSizeGB: $Control_Plane_OSDisk
metadata:
  name: $CLuster_Name
networking:
  clusterNetwork:
  - cidr: 10.120.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: $Cluster_MachineNetwork
  networkType: OVNKubernetes
  serviceNetwork:
  - 172.28.0.0/16
platform:
  vsphere:
    apiVIP: $apiVIP
    cluster: $vCenter_Cluster
    datacenter: $vCenter_datacenter
    defaultDatastore: $vCenter_Datastore
    ingressVIP: $ingressVIP
    network: $VM_Network
    password: $vCenter_Pass
    username: $vCenter_User
    vCenter: $vCenter
publish: External
pullSecret: $pullsecret
sshKey: $SSH_Key
EOF
~~~
