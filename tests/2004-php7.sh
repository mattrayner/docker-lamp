#!/bin/bash
source _helpers.sh

waitForSupervisordProcess web2004-php7 apache2
waitForSupervisordProcess web2004-php7 mysqld

testimage 2004-php7 3030
testmysql web2004-php7 3031