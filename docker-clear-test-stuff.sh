#!/bin/bash
# Cleans up the images and stopped containers after testing

IFS=$'\n'

# Stop any running test containers
echo "Stopping Test containers"
for line in $( docker ps -a | sed -n '1!p' ); do
    containerID=$(echo ${line} | awk '{print $1}')
    containerStatus=$(echo ${line} | awk '{print $1}')
    imageName=$(echo ${line} | awk '{print $2}')
    [[ ${imageName} =~ (ci_|\<none\>) ]] && \
        echo "Stoping container: ${imageName} - ${containerID}" && \
        docker stop ${containerID}
done

# Removing test containers
echo "Removing Test containers"
for line in $( docker ps -a | sed -n '1!p' ); do
    containerID=$(echo ${line} | awk '{print $1}')
    imageName=$(echo ${line} | awk '{print $2}')
    [[ ${imageName} =~ (ci_|\<none\>) ]] && \
        echo "Removing container: ${imageName} - ${containerID}" && \
        docker rm ${containerID}
done

# Remove Test images
echo "Removing Test images"
for line in $( docker images | sed -n '1!p' ); do
    imageName=$(echo ${line} | awk '{print $1}')
    imageID=$(echo ${line} | awk '{print $3}')
    [[ ${imageName} =~ ^(ci_|\<none\>) ]] && \
        echo "Removing image: ${imageName} - ${imageID}" && \
        docker rmi ${imageID}
done
