test:
	docker-compose -f docker-compose.test.yml -p ci build
	docker-compose -f docker-compose.test.yml -p ci up -d
	docker logs -f ci_sut_1
	echo "Exited with status code: $(docker wait ci_sut_1)"