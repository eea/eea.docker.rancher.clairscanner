#!/bin/bash


CLAIR_URL=${CLAIR_URL:-"http://clair:6060"}
LEVEL=${LEVEL:-"Critical"}
LOGGING=${LOGGING:-"DOCKERLOGS"}
RETRY_RESULT="could not find layer|no route to host|i/o timeout|failed to respond within the configured timeout"
RETRY_INTERVAL=${RETRY_INTERVAL:-20}
RETRY_NR=${RETRY_NR:-3}

GRAYLOG_HOST=${GRAYLOG_HOST:-"logcentral.eea.europa.eu"}

if [[ "$LOGGING" == "GELF" ]]; then
   GRAYLOG_PORT=${GRAYLOG_PORT:-"12201"}
else
   GRAYLOG_PORT=${GRAYLOG_PORT:-"1514"}
fi
GRAYLOG_RETRY=${GRAYLOG_RETRY:-3}
GRAYLOG_WAIT=${GRAYLOG_WAIT:-20}


log_tcp_graylog(){

  retry=0
  graylog_nc_result=0
  while [ $retry -lt $GRAYLOG_RETRY ];
  do
    let retry=$retry+1
    echo "$1" | nc -w 5 $GRAYLOG_HOST $GRAYLOG_PORT
    graylog_nc_result=$?
    if [ $graylog_nc_result -eq 0 ]; then
      retry=$GRAYLOG_RETRY
    else
      echo "Received $graylog_nc_result result from nc, will do $retry retry in $GRAYLOG_WAIT s"
      sleep $GRAYLOG_WAIT
    fi
  done
  
  if [ $graylog_nc_result -ne 0 ]; then
      # did not manage to send to graylog
      echo "$1"
  else
      echo "Succesfully sent to graylog for $image, status - $clair_scan_status, result - $clair_result" 
  fi   

}


log_syslog(){
  
  log_tcp_graylog " $1"

}



log_gelf(){

 log_tcp_graylog "$1\0"

}

log_scan_result(){

   #prepare json
   create_json
 

   if [[ "$LOGGING" == "GELF" ]]; then
      log_gelf "$clair_json"
   else
     if [[ "$LOGGING" == "TCPSYSLOG" ]]; then
        log_syslog "$clair_json"
     else
        echo "$clair_json"
     fi
   fi
}

create_json(){

  clair_json="{"

  #for GELF we need an extra field, message
  if [[ "$LOGGING" == "GELF" ]]; then
      clair_json="{\"message\": \"Clair scan status for $image - $clair_scan_status\", \"source\":\"$(hostname)\","
  fi

  clair_json="$clair_json \"environment_name\": \"$environment_name\", \"environment_uuid\": \"$environment_uuid\", \"hostname\": \"$host\", \"stack\": \"$stack\", \"service\": \"$service\", \"container\": \"$container\", \"image\": \"$image\", \"clair_scan_status\": \"$clair_scan_status\", \"result\": \"$clair_result\"}"
 
}



#clean-up
rm -rf clair-scanner-*


image="0"
host=$(curl -s  http://rancher-metadata/latest/self/host/hostname)
environment_uuid=$(curl -s  http://rancher-metadata/latest/self/host/environment_uuid)


for cont in $(docker ps --format '{{.Image}} {{.Names}}')
do
if [[ "$image" == "0" ]]; then
   image=$cont
   continue
else
   name=$cont
  
   if [ $( echo $image | grep -c ":" ) -ne 1 ]; then
     if [ $( docker images $image | grep latest | wc -l ) -eq 1 ]; then 
           image="$image:latest"
     fi
   fi

   # skip busybox images
   if [[ "$image" == "busybox:latest" ]]; then
      # reset image for next loop
      image="0"
      continue
   fi
   
   if [ $(echo "$name" | grep -c "^r-") -eq 0 ]; then
      container=$name;
   else
       container=$(echo $name | awk -F "-" '{ final=$2; for (i=3;i<NF;i++) { final=final"-"$i};  print final} ')
   fi
   
   stack=$(curl -s http://rancher-metadata/latest/containers/$container/stack_name)
   if [ -z "$environment_name" ]; then
      environment_name=$(curl -s http://rancher-metadata/latest/stacks/$stack/environment_name)
   fi

   service=$(curl -s  http://rancher-metadata/latest/containers/$container/labels/io.rancher.stack_service.name)
   
   retry_times=0
  
   while [ $retry_times -lt $RETRY_NR ]
   do

   TMPDIR=`pwd` clair-scanner --ip=`hostname` --clair=$CLAIR_URL -t=$LEVEL --all=false  $image >/tmp/scan_result 2>&1
   
   clair_status=$?
   
   if [ $clair_status -ne 0 ] && [ $(grep -ci Unapproved /tmp/scan_result) -eq 0 ] && [ $(grep -E "$RETRY_RESULT" /tmp/scan_result | wc -l ) -gt 0 ]; then
        let retry_times=$retry_times+1
        echo "Will retry the scanning of $image, retry nr $retry_times"
        sleep $RETRY_INTERVAL
   else
        retry_times=$RETRY_NR

   fi
   done
  
   clair_json=""
   
   # in case there are any double quotes
   sed -i 's/"/\\"/g' /tmp/scan_result
   
   if [ $clair_status -eq 0 ]; then
      clair_scan_status="OK"
      clair_result="$(cat /tmp/scan_result | tail -n 2 | tr '\n' ';' | sed 's/;/\\n/g' | tr -d '[:cntrl:]' )"     
   else
    if [ $(grep -ci Unapproved /tmp/scan_result) -gt 0 ]; then
      clair_scan_status="ERROR"
      clair_result="$(cat /tmp/scan_result | grep -i unapproved | sort | uniq | tr '\n' ';' | sed 's/;/\\n/g' |  tr -d '[:cntrl:]' )"
    else
      clair_scan_status="WARNING"
      clair_result="$(cat /tmp/scan_result | tr '\n' ';' | sed 's/;/\\n/g' |  tr -d '[:cntrl:]' )"
    fi
   fi

   log_scan_result

   # reset image for next loop
   image="0"
   # clean up
   rm -rf clair-scanner-*
fi
done

