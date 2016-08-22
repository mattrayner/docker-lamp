#!/bin/bash
# A function to echo success or cause an exit if the value passed != 0
function checkstatus {
    if [ $1 -eq 0 ]; then
        echo "=> Success"
    else
        echo "=> Failed"
        exit $1
    fi
}