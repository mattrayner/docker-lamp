#!/bin/bash
source _helpers.sh

echo "=> Querying image"
mkdir -p actual/
curl --retry 10 --retry-delay 5 -o actual/1604.html --silent http://localhost:3000 --stderr -
checkstatus $?

echo "=> Checking against expected values"
diff -q -b actual/1604.html expected/1604.html
checkstatus $?