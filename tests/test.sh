#!/bin/bash
source _helpers.sh

echo Initialising tests

echo "=> Starting containers"
echo "=> Starting 16.04 image"
CONTAINER_1_ID=$(docker run -d -p 3000:80 mattrayner/lamp:latest-1604)
checkstatus $?

echo "=> Starting 14.04 image"
CONTAINER_2_ID=$(docker run -d -p 3001:80 mattrayner/lamp:latest-1404)
checkstatus $?

echo "=> Sleeping to allow boot"
sleep 20

echo "=> Testing 16.04 image"
. 1604.sh

echo "=> Testing 14.04 image"
. 1404.sh

echo "=> Stopping 16.04 image"
docker stop $CONTAINER_1_ID

echo "=> Stopping 14.04 image:"
docker stop $CONTAINER_2_ID

echo "=> Cleaning test artifacts"
rm -rf actual/
