### How to mount an NFS export to OpenShift.

Step 1) First we must create a dummy `storageClass` for the NFS export that will be provided to us and mounted in pods running on OpenShift. For this purpose, we give it the name of `nfs`. Can be named anything..

~~~
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: nfs
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: Immediate
~~~

Step 2) With the export details, we'll now create a `PersistentVolume` representing the NFS export object inside of OpenShift. ***Note***: you must set the `accessModes`, `mountOptions`, and `nfs` details accordingly to your requirements.

~~~
apiVersion: v1
kind: PersistentVolume
metadata:
  name: nfs-ftm-pv-001
  labels:
    ftmvolume: 001
spec:
  capacity:
    storage: 5Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Recycle
  storageClassName: nfs
  mountOptions:
    - hard
    - nfsvers=4.1
  nfs:
    path: /tmp
    server: 172.17.0.2
~~~

Step 3) To claim the NFS export in the desired namespace, we'll now create a `PersistentVolumeClaim`. ***Note***: we can use the `storageClassName` as the indicator. But to be more precise we'll use the `selectorLabel` we provided in Step 2) as `ftmvolume: 001` - this can be anything and is optional however, recommended. 

~~~
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nfs-ftm-pvc-001
spec:
  storageClassName: nfs
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  selector: 
    matchLabels: 
      ftmvolume: 001
~~~

Step 4) As the final step, we'll now mount the NFS export to our pods via a `Deployment` using the `volumes` and `volumeMounts` directives using the `persistentVolumeClaim` name, given during step 3).

~~~
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mysql
  labels:
    app: mysql
spec:
  selector:
    matchLabels:
      app: mysql
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
      - image: mysql:5.6
        name: mysql
        env:
        - name: MYSQL_ROOT_PASSWORD
          Value: "password"
        ports:
        - containerPort: 3306
          name: mysql
        volumeMounts:
        - name: ftm-001-export
          mountPath: /var/lib/mysql
      volumes:
      - name: ftm-001-export
        persistentVolumeClaim:
          claimName: nfs-ftm-pvc-001
~~~
