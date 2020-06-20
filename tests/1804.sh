#!/bin/bash
source _helpers.sh

waitForSupervisordProcess web1804-php7 apache2
waitForSupervisordProcess web1804-php7 mysqld

testimage 1804-php7 3000
testmysql web1804-php7 3001