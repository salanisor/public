How to update the alertmanager configuration?

1) extract the alertmanager configuration => 

~~~
oc get secret alertmanager-main -o go-template='{{ index .data "alertmanager.yaml"|base64decode}}' -n openshift-monitoring > alertmanager.yaml
~~~

2) update the alertmanager configuration =>

~~~
oc create secret generic alertmanager-main --from-file=alertmanager.yaml --dry-run=client -o=yaml -n openshift-monitoring | oc replace secret --filename=-
~~~

https://access.redhat.com/solutions/6612991 <= sending alerts to multiple receivers

How to send the alerts to the multiple receivers in RHOCP 4? - Red Hat Alertmanager is not sending the critical alerts Alertmanager was configured to send the critical alerts but it's not working Alertmanager is not sending the alerts to all the routes It was configured


https://access.redhat.com/solutions/6828481 <= sending dummy alerts to alertmanager 

Send dummy alerts to alertmanager in OpenShift 4 - A receiver has to be tested, for instance, with a Critical alert. A real critical alert cannot be forced in production.