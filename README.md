Docker-LAMP is a set of docker images that include the phusion baseimage (16.04 and 18.04 varieties), along with a LAMP stack all in one handy package.
Forked from mattrayner/docker-lamp

# Adding custom startup commands
It is possible to have a persistent "startup folder" /start with a script named `/start/execute.sh` that is called at the end of the container initialization.
In this script you can enter commands like:
- crontab population and cron service starts
- installing php extensions
- installing apt packages
- apt-get update and upgrade on container start

If you want to use this script you have to mount the start directory into the container
This is done like with all the other mounts:
```bash
docker run -i -t -p "80:80" -v ${PWD}/start:/start -v ${PWD}/app:/app -v ${PWD}/mysql:/var/lib/mysql grhangelone/lamp:latest
```

In your `${PWD}/start` folder you can now create a bash script named `execute.sh` which could look like this:
```bash
#!/bin/bash

# Populate the root contab with a script from the app directory
(crontab -l 2>/dev/null; echo "*/5 * * * * /var/www/html/cron.sh") | crontab -
/etc/init.d/cron start

# Install a php extension
apt-get -y update
apt-get -y install php-intl
phpenmod intl
service apache2 restart
```

# Building and running
```bash
# Clone the project from Github
git clone https://github.com/mattrayner/docker-lamp.git
cd docker-lamp

# Build the images
docker build -t=grhangelone/lamp:latest -f ./1804/Dockerfile .
docker build -t=grhangelone/lamp:latest-1604 -f ./1604/Dockerfile .
docker build -t=grhangelone/lamp:latest-1804 -f ./1804/Dockerfile .

# Run the image as a container
docker run -d -p "3000:80" grhangelone/lamp:latest-1804

