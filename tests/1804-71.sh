#!/bin/bash
source _helpers.sh

waitForSupervisordProcess web1804-php71 apache2
waitForSupervisordProcess web1804-php71 mysqld

testimage 1804-php71 3020
testmysql web1804-php71 3021
