# eea.docker.rancher.clairscanner
Docker image to scan existing containers on host from rancher environment.

Will not work in a non-rancher environment because it uses the Rancher metadata service.

Must be mounted with access to hosts' /var/run/docker.sock, and with start_once flag. 

When it runs, produces a json message containing clair scan result for each docker image present on host. 

This message can be:

* Written to STDOUT
* Sent to a GELF TCP graylog input
* Sent to a SYSLOG TCP graylog input


The json format is:
```
{
   "environment_name":"",
   "environment_uuid":"",
   "hostname":"",
   "stack":"",
   "service":""
   "container":"",
   "image":"",
   "clair-scan-status":"OK"/"ERROR"/"WARNING",
   "result":""
}
```

For GELF, 2 extra fields are added - message and source.

First three fields are the same per rancher host and can be used to identify it.

All conectivity to clair server issues are treated with retries.

After scanning all local images, the container stops.

### Environment variables

* CLAIR_URL - the url of the Clair server, defaults to http://clair:6060
* LEVEL - the minimal level of CVEs that send an error, default "Critical"
* DOCKER_API_VERSION - to be set if there are hosts with older docker versions
* RETRY_NR - Number of times to retry scanning in case of resubmittable result
* RETRY_INTERVAL - Number of seconds to wait between clair re-scannings
* LOGGING - Logging method - GELF, TCPSYSLOG or DOCKERLOGS
* GRAYLOG_HOST - Graylog host
* GRAYLOG_PORT - Graylog port
* GRAYLOG_RETRY - Number of times to retry graylog sending if error
* GRAYLOG_WAIT - Seconds to wait between sendings to graylog



### clair-scan-status 

* "OK" - when the scan was done, no unapproved CVEs found
* "ERROR" - when the scan was done, unapproved CVEs were found 
* "WARNING" - there is a problem with the scanning of the image ( the scan was not done )
