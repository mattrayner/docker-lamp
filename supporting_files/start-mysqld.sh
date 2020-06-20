#!/bin/bash
exec /usr/local/bin/pidproxy /var/run/mysqld/mysqld.pid /usr/bin/mysqld_safe
