test:
	docker-compose -f docker-compose.test.yml -p ci build
	docker-compose -f docker-compose.test.yml -p ci up -d
	cd test && ./test.sh