#!/bin/bash
# Runs the Ubuntu 18.04 image
containerName='ci_web1604-php73-3001'
echo "Launching image with container name: ${containerName}"
docker run -d --name ${containerName} -p "3001:80" ci_web1604-php7.3:latest

# Sleep to allow the container to boot
x=30
echo "Waiting ${x} seconds for the container to launch..."
sleep ${x}

echo "Check if ${containerName} is running"
docker ps -a | grep ${containerName}

echo "Using curl to check: ${containerName}"
# Curl out the contents of our new container
curl -sSL "http://localhost:3001/"

sleep 2

# stop and remove the container
echo "Stopping and removing: ${containerName}"
docker stop ${containerName} && docker rm ${containerName}
