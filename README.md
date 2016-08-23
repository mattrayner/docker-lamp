# ![Docker-LAMP][logo]
Docker-LAMP is a set of docker images that include the phusion baseimage (both 14.04 and 16.04 varieties), along with a LAMP stack ([Apache][apache], [MySQL][mysql] and [PHP][php]) all in one handy package.

With both Ubuntu **16.04** and **14.04** images on the latest-1604 and latest-1404 tags, Docker-LAMP is flexible enough to use with all of your LAMP projects.

[![Build Status][shield-build-status]][info-build-status]
[![Docker Hub][shield-docker-hub]][info-docker-hub]
[![Quay Status][shield-quay]][info-quay]
[![License][shield-license]][info-license]


### Contents
<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->


- [Introduction](#introduction)
- [Component Versions](#component-versions)
- [Using the image](#using-the-image)
  - [On the command line](#on-the-command-line)
  - [With a Dockerfile](#with-a-dockerfile)
  - [MySQL Databases](#mysql-databases)
    - [Creating a database](#creating-a-database)
      - [PHPMyAdmin](#phpmyadmin)
      - [Command Line](#command-line)
- [Adding your own content](#adding-your-own-content)
  - [Adding your app](#adding-your-app)
  - [Persisting your MySQL](#persisting-your-mysql)
  - [Doing both](#doing-both)
    - [`.bash_profile` alias examples](#bash_profile-alias-examples)
      - [Example usage](#example-usage)
- [Developing the image](#developing-the-image)
  - [Building and running](#building-and-running)
  - [Testing](#testing)
  - [One-line testing command](#one-line-testing-command)
    - [`docker-compose -f docker-compose.test.yml -p ci build;`](#docker-compose--f-docker-composetestyml--p-ci-build)
    - [`docker-compose -f docker-compose.test.yml -p ci up -d;`](#docker-compose--f-docker-composetestyml--p-ci-up--d)
    - [`docker logs -f ci_sut_1;`](#docker-logs--f-ci_sut_1)
    - [`echo "Exited with status code: $(docker wait ci_sut_1)"`](#echo-exited-with-status-code-docker-wait-ci_sut_1)
- [Inspiration](#inspiration)
- [Contributing](#contributing)
- [License](#license)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## Introduction
As a developer, part of my day to day role is to build LAMP applications. I searched in vein for an image that had everything I wanted, up-to-date packages, a simple interface, good documentation and active support. 

To complicate things even further I needed an image, or actually two, that would run my applications on both 14.04 and 16.04. Having two entirely separate workflows didn't make any sense to me, and Docker-LAMP was born.

Designed to be a single interface that just 'gets out of your way', and works on both 14.04 and 16.04, you can move between both bases without changing how you work with Docker.

## Component Versions
Component | 14.04 Version | 16.04 Version
---|---|---
[Apache][apache] | `2.4.7` | `2.4.18`
[MySQL][mysql] | `5.5.50-0ubuntu0.14.04.1` | `5.7.13-0ubuntu0.16.04.2`
[PHP][php] | `5.5.9-1ubuntu4.19` | `5.6.25-1+deb.sury.org~xenial+1`
[phpMyAdmin][phpmyadmin] | `4.6.4` | `4.6.4`


## Using the image
### On the command line
This is the quickest way
```bash
# Launch a 16.04 based image
docker run -p "80:80" -v ${PWD}/app:/app mattrayner/lamp:latest-1604

# Launch a 14.04 based image
docker run -p "80:80" -v ${PWD}/app:/app mattrayner/lamp:latest-1404
```

### With a Dockerfile
```docker
FROM mattrayner/lamp:latest-1604

# Your custom commands

CMD ["/run.sh"]
```

### MySQL Databases
By default, the image comes with a `root` MySQL account that has no password. This account is only available locally, i.e. within your application. It is not available from outside your docker image or through phpMyAdmin.

When you first run the image you'll see a message showing your `admin` user's password. This user can be used locally and externally, either by connecting to your MySQL port (default 3306) and using a tool like MySQL Workbench or Sequel Pro, or through phpMyAdmin.

If you need this login later, you can run `docker logs CONTAINER_ID` and you should see it at the top of the log.

#### Creating a database
So your application needs a database - you have two options...

1. PHPMyAdmin
2. Command line

##### PHPMyAdmin
Docker-LAMP comes pre-installed with phpMyAdmin available from `http://DOCKER_ADDRESS/phpmyadmin`.

**NOTE:** you cannot use the `root` user with PHPMyAdmin. We recommend logging in with the admin user mentioned in the introduction to this section.

##### Command Line
First, get the ID of your running container with `docker ps`, then run the below command replacing `CONTAINER_ID` and `DATABASE_NAME` with your required values:
```bash
docker exec CONTAINER_ID  mysql -uroot -e "create database DATABASE_NAME"
```


## Adding your own content
The 'easiest' way to add your own content to the lamp image is using Docker volumes. This will effectively 'sync' a particular folder on your machine with that on the docker container.

The below examples assume the following project layout and that you are running the commands from the 'project root'.
```
/ (project root)
/app/ (your PHP files live here)
/mysql/ (docker will create this and store your MySQL data here)
```

In english, your project should contain a folder called `app` containing all of your app's code. That's pretty much it.

### Adding your app
The below command will run the docker image `mattrayner/lamp` interactively, exposing port `80` on the host machine with port `80` on the docker container. It will then create a volume linking the `app/` directory within your project to the `/app` directory on the container. This is where Apache is expecting your PHP to live.
```bash
docker run -i -t -p "80:80" -v ${PWD}/app:/app mattrayner/lamp
```

### Persisting your MySQL
The below command will run the docker image `mattrayner/lamp`, creating a `mysql/` folder within your project. This folder will be linked to `/var/lib/mysql` where all of the MySQL files from container lives. You will now be able to stop/start the container and keep your database changes.

You may also add `-p 3306:3306` after `-p 80:80` to expose the mysql sockets on your host machine. This will allow you to connect an external application such as SequelPro or MySQL Workbench.
```bash
docker run -i -t -p "80:80" -v ${PWD}/mysql:/var/lib/mysql mattrayner/lamp
```

### Doing both
The below command is our 'recommended' solution. It both adds your own PHP and persists database files. We have created a more advanced alias in our `.bash_profile` files to enable the short commands `ldi` and `launchdocker`. See the next section for an example.
```bash
docker run -i -t -p "80:80" -v ${PWD}/app:/app -v ${PWD}/mysql:/var/lib/mysql mattrayner/lamp:latest
```

#### `.bash_profile` alias examples
The below example can be added to your `~/.bash_profile` file to add the alias commands `ldi` and `launchdocker`. By default it will launch the 16.04 image - if you need the 14.04 image, simply change the `docker run` command to use `mattrayner/lamp:latest-1404` instead of `mattrayner/lamp:latest`.
```bash
# A helper function to launch docker container using mattrayner/lamp with overrideable parameters
#
# $1 - Apache Port (optional)
# $2 - MySQL Port (optional - no value will cause MySQL not to be mapped)
function launchdockerwithparams {
    APACHE_PORT=80
    MYSQL_PORT_COMMAND=""
    
    if ! [[ -z "$1" ]]; then
        APACHE_PORT=$1
    fi
    
    if ! [[ -z "$2" ]]; then
        MYSQL_PORT_COMMAND="-p \"$2:3306\""
    fi

    docker run -i -t -p "$APACHE_PORT:80" $MYSQL_PORT_COMMAND -v ${PWD}/app:/app -v ${PWD}/mysql:/var/lib/mysql mattrayner/lamp:latest
}
alias launchdocker='launchdockerwithparams $1 $2'
alias ldi='launchdockerwithparams $1 $2'
```

##### Example usage
```bash
# Launch docker and map port 80 for apache
ldi

# Launch docker and map port 8080 for apache
ldi 8080

# Launch docker and map port 3000 for apache along with 3306 for MySQL
ldi 3000 3306
```


## Developing the image
### Building and running
```bash
# Clone the project from Github
git clone https://github.com/mattrayner/docker-lamp.git
cd docker-lamp

# Build both the 16.04 image and the 14.04 iamge
docker build -t=mattrayner/lamp:latest -f Dockerfile .
docker build -t=mattrayner/lamp:latest-1404 -f Dockerfile1404 .

# Run the 14.04 image as a container
docker run -p "3000:80" mattrayner/lamp:latest-1404 -d

# Sleep to allow the container to boot
sleep 5

# Curl out the contents of our new container
curl "http://$(docker-machine ip):3000/"
```

### Testing
We use `docker-compose` to setup, build and run our testing environment. It allows us to offload a large amount of the testing overhead to Docker, and to ensure that we always test our image in a consistent way thats not affected by the host machine.

### One-line testing command
We've developed a single-line test command you can run on your machine within the `docker-lamp` directory. This will test any changes that may have been made, as well as comparing installed versions of Apache, MySQL, PHP and phpMyAdmin against those expected.
```bash
docker-compose -f docker-compose.test.yml -p ci build; docker-compose -f docker-compose.test.yml -p ci up -d; docker logs -f ci_sut_1; echo "Exited with status code: $(docker wait ci_sut_1)";
```

So what does this command do?

#### `docker-compose -f docker-compose.test.yml -p ci build;`
First, build that latest version of our docker-compose images.

#### `docker-compose -f docker-compose.test.yml -p ci up -d;`
Launch our docker containers (`web1604`, `web1404` and `sut` or *system under tests*) in daemon mode.

#### `docker logs -f ci_sut_1;`
Display all of the logging output from the `sut` container (extremely useful for debugging)

#### `echo "Exited with status code: $(docker wait ci_sut_1)"`
Report back the status code that the `sut` container ended with.


## Inspiration
This image was originally based on [dgraziotin/lamp][dgraziotin-lamp], with a few changes to make it compatible with the Concrete5 CMS.

I also changed the setup to create ubuntu (well, baseimage, but you get what I'm saying) 14.04 and 16.04 images so that this project could be as useful as possible to as many people as possible.


## Contributing
If you wish to submit a bug fix or feature, you can create a pull request and it will be merged pending a code review.

1. Clone/fork it
2. Create your feature branch (git checkout -b my-new-feature)
3. Commit your changes (git commit -am 'Add some feature')
4. Test your changes using the steps in [Testing](#testing)
5. Push to the branch (git push origin my-new-feature)
6. Create a new Pull Request


## License
Docker-LAMP is licensed under the [Apache 2.0 License][info-license].


[logo]: https://cdn.rawgit.com/mattrayner/docker-lamp/831976c022782e592b7e2758464b2a9efe3da042/docs/logo.svg

[apache]: http://www.apache.org/
[mysql]: https://www.mysql.com/
[php]: http://php.net/
[phpmyadmin]: https://www.phpmyadmin.net/

[info-build-status]: https://circleci.com/gh/mattrayner/docker-lamp
[info-docker-hub]: https://hub.docker.com/r/mattrayner/lamp
[info-quay]: https://quay.io/repository/mattrayner/docker-lamp
[info-license]: LICENSE

[shield-build-status]: https://img.shields.io/circleci/project/mattrayner/docker-lamp.svg
[shield-docker-hub]: https://img.shields.io/badge/docker%20hub-mattrayner%2Flamp-brightgreen.svg
[shield-quay]: https://quay.io/repository/mattrayner/docker-lamp/status
[shield-license]: https://img.shields.io/badge/license-Apache%202.0-blue.svg

[dgraziotin-lamp]: https://github.com/dgraziotin/osx-docker-lamp
