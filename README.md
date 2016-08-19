# ![Docker-LAMP][logo]
Docker-LAMP is a docker image that includes the phusion base image, [Apache][apache], [MySQL][mysql] and [PHP][php] all in one handy package.

[![Build Status][shield-build-status]][info-build-status]
[![Dokcer Status][shield-quay]][info-quay]
[![License][shield-license]][info-license]


### Contents
<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->


- [Component Versions](#component-versions)
- [Using the image](#using-the-image)
  - [Building from source](#building-from-source)
  - [Using with a Dockerfile](#using-with-a-dockerfile)
  - [MySQL Details](#mysql-details)
- [Adding your own content](#adding-your-own-content)
  - [Adding your own 'php'](#adding-your-own-php)
  - [Persisting your MySQL](#persisting-your-mysql)
  - [Doing both (recommended)](#doing-both-recommended)
    - [`.bash_profile` alias examples](#bash_profile-alias-examples)
- [Credits](#credits)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->


## Component Versions
Component | Version
---|---
[Apache][apache] | `2.4.7`
[MySQL][mysql] | `5.5.49-0ubuntu0.14.04.1`
[PHP][php] | `5.5.9-1ubuntu4.19`


## Using the image
### Building from source
```
docker build -t=mattrayner/lamp .
docker run -d -p 80:80 -p 3306:3306 mattrayner/lamp
````

### Using with a Dockerfile
```
FROM mattrayner/lamp:latest

# Your custom commands

CMD ["/run.sh"]
```

### MySQL Details
The default image comes with a `root` MySQL account that has no password. This account is only available locally though i.e. within your application. It is not availzble from outside your docker image.

When you first run the image you'll see a message showing your `admin` user password. This user can be used locally and externally. Either by connecting to port 3306 using a tool like MySQL Workbench or Sequel Pro. If you need this login later, you can run `docker logs CONTAINER_ID` and you should see it at the top of the log.

The image comes pre-installed with PHPMyAdmin available from `/phpmyadmin`. **NOTE:** you cannot use the `root` user with PHPMyAdmin. 


## Adding your own content
The 'easiest' way to add your own content to the lamp image is using Docker volumes. This will effectively 'sync' a particular folder on your machine with that on the docker machine.

The below examples assume the following project layout and that you are running the commands from the 'project root'.

```
/ (project root)
/app/ (your PHP files live here)
```

That is to say that your project contains a folder called `app` containing all of your app's code.

### Adding your own 'php'
```
docker run -i -t -p "80:80" -v ${PWD}/app:/app mattrayner/lamp
```

The above will run the docker image `mattrayner/lamp` interactively, exposeing port `80` on the host machine with port `80` on the docker container. It will then create a volume linking `app/` within the project directory to `/app` on the containers file directory. This will load your PHP into apache.

### Persisting your MySQL
```
docker run -i -t -p "80:80" -v ${PWD}/mysql:/var/lib/mysql mattrayner/lamp
```

The above will run the docker image, creating a `mysql/` folder within our project. This folder will contain all of the MySQL files from the docker container. Therefore you will be able to stop/start the container and keep your databases.

You may also add `-p 3306:3306` after `-p 80:80` to expose the mysql sockets on your host machine.

### Doing both (recommended)
```
docker run -i -t -p "80:80" -p "3306:3306" -v ${PWD}/app:/app -v ${PWD}/mysql:/var/lib/mysql mattrayner/lamp:latest
```

The above is our 'recommended' solution. It both adds your own PHP and persists database files. We have created an alias in our `.bash_profile` files to enable the short command `ld` or `launch-docker`.

#### `.bash_profile` alias examples
```
alias launch-docker='docker run -i -t -p "80:80" -p "3306:3306" -v ${PWD}/app:/app -v ${PWD}/mysql:/var/lib/mysql mattrayner/lamp:latest'
alias ld=launch-docker
```



## Credits
Inspiration for this container has come from [tutum-lamp][tutum-lamp].


[logo]: https://cdn.rawgit.com/mattrayner/docker-lamp/831976c022782e592b7e2758464b2a9efe3da042/docs/logo.svg

[apache]: http://www.apache.org/
[mysql]: https://www.mysql.com/
[php]: http://php.net/

[info-build-status]: https://circleci.com/gh/mattrayner/docker-lamp
[info-quay]: https://quay.io/repository/mattrayner/docker-lamp
[info-license]: LICENSE

[shield-build-status]: https://img.shields.io/circleci/project/mattrayner/docker-lamp.svg
[shield-quay]: https://quay.io/repository/mattrayner/docker-lamp/status
[shield-license]: https://img.shields.io/badge/license-MIT-blue.svg

[tutum-lamp]: https://github.com/tutumcloud/lamp
