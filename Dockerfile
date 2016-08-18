FROM ubuntu:trusty
MAINTAINER Matthew Rayner <mattrayner1@gmail.com>

# Install packages
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update && apt-get -y install software-properties-common && sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 4F4EA0AAE5267A6C && \
  add-apt-repository -y ppa:ondrej/php && apt-get update && apt-get -y install python-software-properties && apt-get update
RUN apt-get -y install supervisor git apache2 libapache2-mod-php5 mysql-server php5.6 php5.6-mysql pwgen php5.6-apc php5.6-mcrypt && \
  echo "ServerName localhost" >> /etc/apache2/apache2.conf

# Add image configuration and scripts
ADD scripts/start-apache2.sh /start-apache2.sh
ADD scripts/start-mysqld.sh /start-mysqld.sh
ADD scripts/run.sh /run.sh
RUN chmod 755 /*.sh
ADD config/my.cnf /etc/mysql/conf.d/my.cnf
ADD supervisord/supervisord-apache2.conf /etc/supervisor/conf.d/supervisord-apache2.conf
ADD supervisord/supervisord-mysqld.conf /etc/supervisor/conf.d/supervisord-mysqld.conf

# Remove pre-installed database
RUN rm -rf /var/lib/mysql/*

# Add MySQL utils
ADD scripts/create_mysql_admin_user.sh /create_mysql_admin_user.sh
RUN chmod 755 /*.sh

# config to enable .htaccess
ADD config/apache_default /etc/apache2/sites-available/000-default.conf
RUN a2enmod rewrite

# Configure /app folder with sample app
COPY app /app
RUN mkdir -p /app && rm -fr /var/www/html && ln -s /app /var/www/html

#Environment variables to configure php
ENV PHP_UPLOAD_MAX_FILESIZE 10M
ENV PHP_POST_MAX_SIZE 10M

# Add volumes for MySQL
VOLUME  ["/etc/mysql", "/var/lib/mysql" ]

EXPOSE 80 3306
CMD ["/run.sh"]
