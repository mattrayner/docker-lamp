#!/bin/bash
source _helpers.sh

echo "Testing mattrayner/lamp"
echo "=> Sleeping to allow boot of containers"
sleep 10

echo "=> Testing 16.04 images"
. 1604.sh

echo "=> Testing 14.04 images"
. 1404.sh
