# Base our image from a specific dgraziotin/lamp build - this way if he updates it we won't break right away
FROM dgraziotin/lamp

# Install an additional PHP library for use with Concrete5
RUN apt-get update && apt-get -y install php5-gd && apt-get -y upgrade && apt-get -y autoremove

# Copy our updated 'app' directory
COPY app /app

# Remove any mysql.sock files that might be hanging around
RUN rm -rf /var/run/mysqld/mysqld.sock

# Launch the Apache and MySQL servers
CMD ["/run.sh"]
