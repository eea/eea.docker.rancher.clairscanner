#!/bin/bash


CLAIR_URL=${CLAIR_URL:-"http://clair:6060"}
LEVEL=${LEVEL:-"Critical"}
image="0"
host=$(curl -s  http://rancher-metadata/latest/self/host/hostname)
environment_uuid=$(curl -s  http://rancher-metadata/latest/self/host/environment_uuid)

#clean-up
rm -rf clair-scanner-*

for cont in $(docker ps --format '{{.Image}} {{.Names}}')
do
if [[ "$image" == "0" ]]; then
   image=$cont
   continue
else
   name=$cont
   
   # skip busybox images
   if [[ "$image" == "busybox" ]]; then
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
   TMPDIR=`pwd` clair-scanner --ip=`hostname` --clair=$CLAIR_URL -t=$LEVEL --all=false  $image >/tmp/scan_result 2>&1
   if [ $? -eq 0 ]; then
     echo "{\"environment_name\": \"$environment_name\", \"environment_uuid\": \"$environment_uuid\", \"hostname\": \"$host\", \"stack\": \"$stack\", \"service\": \"$service\", \"container\": \"$container\", \"image\": \"$image\", \"clair-scan-status\": \"OK\", \"result\": \"$(cat /tmp/scan_result | tail -n 2 | tr '\n' ';' | sed 's/;/\\n/g' | tr -d '[:cntrl:]' )\"}"

   else
    if [ $(grep -ci Unapproved /tmp/scan_result) -gt 0 ]; then
      echo "{\"environment_name\": \"$environment_name\", \"environment_uuid\": \"$environment_uuid\", \"hostname\": \"$host\", \"stack\": \"$stack\", \"service\": \"$service\", \"container\": \"$container\", \"image\": \"$image\", \"clair-scan-status\": \"ERROR\", \"result\": \"$(cat /tmp/scan_result | grep -i unapproved | tr '\n' ';' | sed 's/;/\\n/g' |  tr -d '[:cntrl:]' )\"}"
    else
      echo "{\"environment_name\": \"$environment_name\", \"environment_uuid\": \"$environment_uuid\", \"hostname\": \"$host\", \"stack\": \"$stack\", \"service\": \"$service\", \"container\": \"$container\", \"image\": \"$image\", \"clair-scan-status\": \"WARNING\", \"result\": \"$(cat /tmp/scan_result | tr '\n' ';' | sed 's/;/\\n/g' |  tr -d '[:cntrl:]' )\"}"
    fi    
   fi
   # reset image for next loop
   image="0"
   # clean up
   rm -rf clair-scanner-*
fi
done

