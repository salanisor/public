In the OpenShift console, under the observe > metrics > run the following query using the following app label `http_requests_total{job="prometheus-example-app"}`

* Using the curl command, you can generate traffic to trigger the Prometheus alert.

Command
~~~
for x in {1..10}; do curl -kI https://$(oc get route prom-example-app-route -n ns1 -o jsonpath='{.spec.host}');done
~~~

As a cluster-admin you can confirm the firing of the alert by browsing to `Observe` > `Alerting` > `Alerts` > click `Filter` > select for the `Alert State` > `Firing` & `User`.

As a developer you can confirm the alert firing by browsing to > `Observe` > `Alerts`

* In order for users with the edit role to be able to view alerts at the namespace level. One will need to add the `monitoring-edit` role to the user's AD group.

~~~
oc policy add-role-to-user monitoring-edit ldapuser -n ns1
~~~

* Alternatively, you can enable view-only on alerts removing the capability to silence alerts in the Observe console.

~~~
oc apply -f monitoring-api-reader.yaml
~~~


![Screenshot](https://github.com/salanisor/public/blob/main/images/alerting.png)

A good high-level work through example => [link](https://developers.redhat.com/articles/2023/10/03/how-configure-openshift-application-monitoring-and-alerts#)