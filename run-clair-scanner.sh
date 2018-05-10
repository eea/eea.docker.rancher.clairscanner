#!/bin/bash


CLAIR_URL=${CLAIR_URL:-"http://clair:6060"}
LEVEL=${LEVEL:-"Critical"}
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
   #echo "Am citit $image $name"
   if [ $(echo "$name" | grep -c "^r-") -eq 0 ]; then
      container=$name;
   else
       container=$(echo $name | awk -F "-" '{ final=$2; for (i=3;i<NF;i++) { final=final"-"$i};  print final} ')
   fi
   #echo $container
   stack=$(curl -s http://rancher-metadata/latest/containers/$container/stack_name)
   if [ -z "$environment_name" ]; then
      environment_name=$(curl -s http://rancher-metadata/latest/stacks/$stack/environment_name)
   fi

   service=$(curl -s  http://rancher-metadata/latest/containers/$container/labels/io.rancher.stack_service.name)
   result=$(TMPDIR=`pwd` clair-scanner --ip=`hostname` --clair=$CLAIR_URL -t=$LEVEL --all=false  $image 2>&1)
   if [ $? -eq 0 ]; then
     echo "{\"environment_name\": \"$environment_name\", \"environment_uuid\": \"$environment_uuid\", \"hostname\": \"$host\", \"stack\": \"$stack\", \"service\": \"$service\", \"container\": \"$container\", \"image\": \"$image\", \"status\": \"OK\", \"result\": \"$(echo $result| tail -n 2 | tr '\n' ';' | sed 's/;/\\n/g' )\"}"

   else
    echo "{\"environment_name\": \"$environment_name\", \"environment_uuid\": \"$environment_uuid\", \"hostname\": \"$host\", \"stack\": \"$stack\", \"service\": \"$service\", \"container\": \"$container\", \"image\": \"$image\", \"status\": \"ERROR\", \"result\": \"$(echo $result | tr '\n' ';' | sed 's/;/\\n/g'  )\"}"

   fi
   # reset image for next loop
   image="0"
fi
done

