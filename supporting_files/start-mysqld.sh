#!/bin/bash
exec /usr/bin/pidproxy /var/run/mysqld/mysqld.pid /usr/bin/mysqld_safe
