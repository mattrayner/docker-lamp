#!/bin/bash
source _helpers.sh

waitForSupervisordProcess web2004-php8 apache2
waitForSupervisordProcess web2004-php8 mysqld

testimage 2004-php8 3040
testmysql web2004-php8 3041