#!/bin/bash
source _helpers.sh

waitForSupervisordProgram web1804-php7 apache2
waitForSupervisordProgram web1804-php7 mysqld

testimage 1804-php7 3000
testmysql web1804-php7 3001