#!/bin/bash
source _helpers.sh

echo
echo "Testing mattrayner/lamp"
echo "=> Sleeping to allow boot of containers"
sleep 60

mkdir actual

echo
echo "=> Testing 18.04 images"
. 1804.sh

echo "=> Testing 16.04 images"
. 1604.sh
