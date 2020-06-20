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
    echo "=> Querying image ($1)"
    curl --retry 10 --retry-delay 5 -o actual/$1.html http://localhost:$2 --stderr -
    checkstatus $?

    echo "=> Checking against expected values ($1)"
    diff -b actual/$1.html expected/$1.html
    checkstatus $?
    echo
}

function testmysql {
    echo "=> Connecting to MySQL: ($1:$2)"
    mysql -h 127.0.0.1 -P $2 -u admin -ppassword -e"quit"
    checkstatus $?
}

function waitForSupervisordProcess {
    while true; do
        echo "=> Waiting for $2 on the service $1..."
        docker-compose -f ../docker-compose.test.yml -p ci exec $1 supervisorctl status $2
        [ $? -ne 0 ] || break
        sleep 5
    done
}
