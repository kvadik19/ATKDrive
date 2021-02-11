#!/bin/sh
# Must be run as sudo
home="/var/www/atk"
eport="9209"
db_name="atk"
db_host="localhost"
db_port="3306"
db_login="vdk"
db_pass="14rucoO"

CUR_USER=$(ls -ld ${home} | awk '{print $3}')
CUR_GROUP=$(ls -ld ${home} | awk '{print $4}')

rm -f ${home}/script/engined

echo "#!/bin/sh

if [ \$# -ne 1 ]
then
	echo \"Start/restart Drive as daemon on port ${ls_port}. Alternate usage: \`basename \$0\` stop\";
	cmd=\"\";
else
	cmd=\$1;
fi

export eport=\"${eport}\"
export db_name=\"${db_name}\"
export db_host=\"${db_host}\"
export db_port=\"${db_port}\"
export db_login=\"${db_login}\"
export db_pass=\"${db_pass}\"

if [ -r '${home}/script/engine' ]
then
	if [ \"\$cmd\" = \"stop\" ]
	then
		hypnotoad -s ${home}/script/engine
	else
		hypnotoad ${home}/script/engine

# Launch server in interactive mode for develope purposes
#		morbo -l http://127.0.0.1:${eport} ${home}/script/engine
	fi
else
	echo Server script does not exist or is not readable. Exit.;
	exit 1;
fi

" > "${home}/script/engined"

chown $CUR_USER:$CUR_GROUP ${home}/script/engined
chmod a+x ${home}/script/engined

### Write unique Drive startup script into init.d #############################
rm -f /etc/init.d/hypnotoad-${eport}
update-rc.d -f hypnotoad-${eport} remove

echo "#!/bin/sh
# Drive Server as a nginx backend
#

### BEGIN INIT INFO
# Provides:          engined
# Required-Start:    \$local_fs \$network \$syslog mysql
# Required-Stop:     \$local_fs \$network \$syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start engined for port ${eport}
### END INIT INFO
. /lib/lsb/init-functions

PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

case \"\$1\" in
start)
	cd ${home}
	su $CUR_USER -c '${home}/script/engined'
;;
stop)
	su $CUR_USER -c '${home}/script/engined stop'
;;
restart|reload|force-reload)
	su $CUR_USER -c '${home}/script/engined'
;;
esac
exit 0
" > "/etc/init.d/hypnotoad-${eport}"

chmod u+x /etc/init.d/hypnotoad-${eport}
update-rc.d hypnotoad-${eport} defaults

### nginx log files rotator ###############################################
echo "#!/bin/sh
# Called from crontab
home=\"${home}\"
rename -f -e 's/nginx\.(\w+)\.log$/nginx.$1.log.0/' ${home}/log/nginx*
# nginx -s reload
kill -USR1 \`cat /var/run/nginx.pid\`
sleep 1
chown www-data:www-data \${home}/log/nginx*
" > "${home}/nginx-rotate.sh"

chown $CUR_USER:$CUR_GROUP ${home}/nginx-rotate.sh
chmod a+x ${home}/nginx-rotate.sh

### restart ###############################################

su $CUR_USER ${home}/script/engined

# /etc/init.d/nginx restart
