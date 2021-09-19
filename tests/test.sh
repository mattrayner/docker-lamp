#!/bin/bash
source _helpers.sh

echo
echo "Testing mattrayner/lamp"

if [ -d actual ]; then
     rm -R actual
fi
mkdir actual

echo
echo "=> Testing 20.04 PHP 7 images"
. 2004-php7.sh

echo "=> Testing 20.04 PHP 8 images"
. 2004-php8.sh

echo "=> Testing 18.04 PHP 7 images"
. 1804-php7.sh

echo "=> Testing 18.04 PHP 8 images"
. 1804-php8.sh
