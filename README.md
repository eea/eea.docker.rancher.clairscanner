# eea.docker.rancher.clairscanner
Docker image to scan existing containers on host from rancher environment.

Will not work in a non-rancher environment because it uses the Rancher metadata service.

Must be mounted with access to hosts' /var/run/docker.sock, and with start_once flag. 

When it runs, it outputs a json message containing clair scan result for each docker image present on host.

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

First three fields are the same per rancher host and can be used to identify it.

After scanning all local images, the container stops.

### Environment variables

* CLAIR_URL - the url of the Clair server, defaults to http://clair:6060
* LEVEL - the minimal level of CVEs that send an error, default "Critical"

### clair-scan-status 

* "OK" - when the scan was done, no unapproved CVEs found
* "ERROR" - when the scan was done, unapproved CVEs were found 
* "WARNING" - there is a problem with the scanning of the image ( the scan was not done )
