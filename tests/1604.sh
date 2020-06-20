#!/bin/bash
source _helpers.sh

waitForSupervisordProgram web1604-php7 apache2
waitForSupervisordProgram web1604-php7 mysqld

testimage 1604-php7 3010
testmysql web1604-php7 3011