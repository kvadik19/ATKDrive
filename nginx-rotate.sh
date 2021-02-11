#!/bin/sh
# Called from crontab
home="/var/www/atk"
rename -f -e 's/nginx\.(\w+)\.log$/nginx.$1.log.0/' ${home}/log/nginx*
# nginx -s reload
kill -USR1 `cat /var/run/nginx.pid`
sleep 1
chown www-data:www-data ${home}/log/nginx*
