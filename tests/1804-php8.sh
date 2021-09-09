#!/bin/bash
source _helpers.sh

waitForSupervisordProcess web1804-php8 apache2
waitForSupervisordProcess web1804-php8 mysqld

testimage 1804-php8 3020
testmysql web1804-php8 3021