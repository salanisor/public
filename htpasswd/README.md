htpasswd -c -B -b </path/to/users.htpasswd> <user_name> <password>

# create htpasswd_file with user:password
$ htpasswd -cb htpasswd_file user password
Adding password for user user

# verify password for user
$ htpasswd -vb htpasswd_file user wrongpassword
password verification failed

$ htpasswd -vb htpasswd_file user password
Password for user user correct.

oc create secret generic htpass-secret --from-file=htpasswd=users.htpasswd -n openshift-config

apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
  - name: htpasswd_provider
    challenge: true
    login: true
    mappingMethod: claim
    type: HTPasswd
    htpasswd:
      fileData:
        name: htpass-secret

oc create --save-config or oc apply
