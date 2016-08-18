# ![Docker-LAMP][logo]
Docker-LAMP is a docker image that includes [Ubuntu][ubuntu], [Apache][apache], [MySQL][mysql] and [PHP][php] all in one handy package.

[![Build Status][shield-build-status]][info-build-status]
[![Dokcer Status][shield-quay]][info-quay]
[![License][shield-license]][info-license]


### Contents
<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->


- [Component Versions](#component-versions)
- [Using the image](#using-the-image)
  - [Building from source](#building-from-source)
  - [Using within your `Dockerfile`](#using-within-your-dockerfile)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->


## Component Versions
Component | Version
---|---
[Ubuntu][ubuntu] | `14.04`
[Apache][apache] | `2.4.7`
[MySQL][mysql] | `5.5.50`
[PHP][php] | `5.5.9`


## Using the image
### Building from source
```
docker build -t=mattrayner/lamp .
docker run -d -p 80:80 mattrayner/lamp
````

Now you should be able to visit the container at `http://localhost/` and see the welcome screen

## Using with a Dockerfile
```
FROM mattrayner/lamp:latest
RUN rm -fr /app
ADD . /app
EXPOSE 80 3306
CMD ["/run.sh"]
```

## Credits
Inspiration for this container has come from [tutum-lamp][tutum-lamp].


[logo]: https://cdn.rawgit.com/mattrayner/docker-lamp/831976c022782e592b7e2758464b2a9efe3da042/docs/logo.svg

[ubuntu]: http://www.ubuntu.com/
[apache]: http://www.apache.org/
[mysql]: https://www.mysql.com/
[php]: http://php.net/

[info-build-status]: https://circleci.com/gh/mattrayner/docker-lamp
[info-quay]: https://quay.io/repository/mattrayner/docker-lamp
[info-license]: LICENSE

[shield-build-status]: https://img.shields.io/circleci/project/mattrayner/docker-lamp.svg?maxAge=2592000
[shield-quay]: https://quay.io/repository/mattrayner/docker-lamp/status
[shield-license]: https://img.shields.io/badge/license-MIT-blue.svg

[tutum-lamp]: https://github.com/tutumcloud/lamp
