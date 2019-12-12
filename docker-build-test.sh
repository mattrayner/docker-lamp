#!/bin/bash
# Runs the commands to test the images.

docker-compose -f docker-compose.test.yml -p ci build && \
docker-compose -f docker-compose.test.yml -p ci up -d && \
docker logs -f ci_sut && echo "Exited with status code: $(docker wait ci_sut)";

# Stop and remove the containers.
docker stop ci_sut && docker rm ci_sut
docker stop ci_1804-73 && docker rm ci_1804-73
docker stop ci_1604-73 && docker rm ci_1604-73
