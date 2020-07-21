test: build up run-tests clean

test-no-cache: build-no-cache up run-tests clean

build:
	docker-compose -f docker-compose.test.yml -p ci build

build-no-cache:
	docker-compose -f docker-compose.test.yml -p ci build --no-cache

up:
	docker-compose -f docker-compose.test.yml -p ci up -d

run-tests:
	cd tests && ./test.sh

clean:
	docker-compose -f docker-compose.test.yml -p ci down
