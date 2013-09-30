#!/bin/bash -xe
#
# setup_quantum.sh - installs Quantum.
# Horizon of OpenStack Grizzly on Ubuntu 13.04.
#
# Not ready yet. 
#

source setuprc

HTTP_PROXY=$http_proxy
unset http_proxy

##############################################################################
## Install necessary packages
##############################################################################

export DEBIAN_FRONTEND=noninteractive

/usr/bin/aptitude -y update
/usr/bin/aptitude -y upgrade
/usr/bin/aptitude -y install \
    ntp \
    python-mysqldb \
    python-memcache \
    quantum-server \
    quantum-plugin-openvswitch

##############################################################################
## Make a script to start/stop all services
##############################################################################

/bin/cat << EOF > glance.sh
#!/bin/bash

GLANCE="registry api"

case "\$1" in
start|restart|status)
	for i in \$GLANCE; do
		/sbin/\$1 glance-\$i
	done
	;;
stop)
	for i in \$GLANCE; do
		/sbin/stop glance-\$i
	done
	;;
esac
exit 0
EOF
/bin/chmod +x glance.sh

##############################################################################
## Stop all services.
##############################################################################

./glance.sh stop

##############################################################################
## Modify configuration files of Nova, Glance and Keystone
##############################################################################

CONF=/etc/quantum/plugins/openvswitch/ovs_quantum_plugin.ini
test -f $CONF.orig || /bin/cp $CONF $CONF.orig
/bin/sed \
	-e "s#^sql_connection *=.*#sql_connection = mysql://openstack:$MYSQLPASS@$CONTROLLER_INTERNAL_ADDRESS/quantum#" \
	$CONF.orig > $CONF


CONF=/etc/quantum/quantum.conf
test -f $CONF.orig || /bin/cp $CONF $CONF.orig
/bin/sed \
        -e "s/^auth_host *=.*/auth_host = $CONTROLLER_ADMIN_ADDRESS/" \
	-e 's/%SERVICE_TENANT_NAME%/service/' \
	-e 's/%SERVICE_USER%/quantum/' \
	-e "s/%SERVICE_PASSWORD%/$ADMIN_PASSWORD/" \
        -e "s/127.0.0.1/$CONTROLLER_PUBLIC_ADDRESS/" \
        -e "s/localhost/$CONTROLLER_PUBLIC_ADDRESS/" \
	$CONF.orig > $CONF

chown -R quantum /etc/quantum

##############################################################################
## Create MySQL accounts and databases of Nova, Glance, Keystone and Cinder
##############################################################################

/bin/cat << EOF | /usr/bin/mysql -uroot -p$MYSQLPASS
DROP DATABASE IF EXISTS quantum;
CREATE DATABASE quantum;
GRANT ALL ON quantum.*   TO 'openstack'@'localhost'   IDENTIFIED BY '$MYSQLPASS';
GRANT ALL ON quantum.*   TO 'openstack'@'$CONTROLLER_ADMIN_ADDRESS'   IDENTIFIED BY '$MYSQLPASS';
GRANT ALL ON quantum.*   TO 'openstack'@'$MYSQL_ACCESS'   IDENTIFIED BY '$MYSQLPASS';
EOF

##############################################################################
## Initialize databases of Nova, Glance and Keystone
##############################################################################

/usr/bin/glance-manage db_sync

##############################################################################
## Start Glance
##############################################################################

./glance.sh start
sleep 5

##############################################################################
## Register Ubuntu-12.10 image on Glance
##############################################################################

http_proxy=$HTTP_PROXY /usr/bin/wget \
http://cloud-images.ubuntu.com/raring/current/raring-server-cloudimg-amd64-disk1.img

source admin_credential
/usr/bin/glance image-create \
	--name ubuntu-13.04 \
	--disk-format qcow2 \
	--container-format bare \
	--file raring-server-cloudimg-amd64-disk1.img

/bin/rm -f raring-server-cloudimg-amd64-disk1.img
