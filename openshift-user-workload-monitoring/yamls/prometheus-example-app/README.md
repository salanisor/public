In the OpenShift console, under the observe > metrics > run the following query using the following app label `http_requests_total{job="prometheus-example-app"}`

* Using the curl command, you can generate traffic to trigger the Prometheus alert.

Command
~~~
for x in {1..10}; do curl -kI https://$(oc get route prom-example-app-route -n ns1 -o jsonpath='{.spec.host}');done
~~~

You can confirm the firing of the alert by browsing to `Observe` > `Alerting` > `Alerts` > click `Filter` > select for the `Alert State` > `Firing` & `User`.

![Screenshot](xxx)

A good high-level work through example => https://developers.redhat.com/articles/2023/10/03/how-configure-openshift-application-monitoring-and-alerts#