#!/bin/bash
# Echo success or cause an exit if the value passed != 0
function checkstatus {
    if [ $1 -eq 0 ]; then
        echo "=> Success"
    else
        echo "=> Failed"
        exit $1
    fi
}

# Test our image, first curling our container and then checking the result against our expectations
function testimage {
    echo "=> Querying image"
    curl --retry 10 --retry-delay 5 -o actual/$1.html $2 --stderr -
    checkstatus $?

    echo "=> Checking against expected values"
    diff -b actual/$1.html expected/$1.html
    checkstatus $?
}