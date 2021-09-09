#!/bin/bash
source _helpers.sh

echo
echo "Testing mattrayner/lamp"

if [ -d actual ]; then
     rm -R actual
fi
mkdir actual

echo
echo "=> Testing 18.04 images"
. 1804.sh
