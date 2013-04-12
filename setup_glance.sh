#!/bin/bash -xe
#
# Author: Akira Yoshiyama
# 
# Modfied by Koji Tanaka for adjusting parameters 
# for FutureGrid Resources and also for FG Users
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
    glance

##############################################################################
## Disable IPv6
##############################################################################
echo '127.0.0.1 localhost' > /etc/hosts
echo 'net.ipv6.conf.all.disable_ipv6 = 1' >> /etc/sysctl.conf

##############################################################################
## Configure memcached
##############################################################################
sed -i "s/127.0.0.1/$CONTROLLER_ADMIN_ADDRESS/" /etc/memcached.conf
service memcached restart

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

for i in /etc/glance/glance-api.conf \
	 /etc/glance/glance-registry.conf
do
	test -f $i.orig || /bin/cp $i $i.orig
done

CONF=/etc/glance/glance-api.conf
/bin/sed \
        -e "s/^auth_host *=.*/auth_host = $CONTROLLER_ADMIN_ADDRESS/" \
	-e 's/%SERVICE_TENANT_NAME%/service/' \
	-e 's/%SERVICE_USER%/glance/' \
	-e "s/%SERVICE_PASSWORD%/$ADMIN_PASSWORD/" \
	-e "s/^sql_connection *=.*/sql_connection = mysql:\/\/openstack:$MYSQLPASS@$CONTROLLER_INTERNAL_ADDRESS\/glance/" \
	-e 's/^#* *config_file *=.*/config_file = \/etc\/glance\/glance-api-paste.ini/' \
	-e 's/^#*flavor *=.*/flavor = keystone/' \
        -e 's/^notifier_strategy *=.*/notifier_strategy = rabbit/' \
        -e "s/^rabbit_host *=.*/rabbit_host = $CONTROLLER_INTERNAL_ADDRESS/" \
        -e 's/^rabbit_userid *=.*/rabbit_userid = nova/' \
        -e "s/^rabbit_password *=.*/rabbit_password = $RABBIT_PASS/" \
        -e "s/^rabbit_virtual_host *=.*/rabbit_virtual_host = \/nova/" \
        -e "s/127.0.0.1/$CONTROLLER_PUBLIC_ADDRESS/" \
        -e "s/localhost/$CONTROLLER_PUBLIC_ADDRESS/" \
	$CONF.orig > $CONF

CONF=/etc/glance/glance-registry.conf
/bin/sed \
        -e "s/^auth_host *=.*/auth_host = $CONTROLLER_ADMIN_ADDRESS/" \
	-e 's/%SERVICE_TENANT_NAME%/service/' \
	-e 's/%SERVICE_USER%/glance/' \
	-e "s/%SERVICE_PASSWORD%/$ADMIN_PASSWORD/" \
	-e "s/^sql_connection *=.*/sql_connection = mysql:\/\/openstack:$MYSQLPASS@$CONTROLLER_INTERNAL_ADDRESS\/glance/" \
	-e 's/^#* *config_file *=.*/config_file = \/etc\/glance\/glance-registry-paste.ini/' \
	-e 's/^#*flavor *=.*/flavor=keystone/' \
        -e "s/127.0.0.1/$CONTROLLER_PUBLIC_ADDRESS/" \
        -e "s/localhost/$CONTROLLER_PUBLIC_ADDRESS/" \
	$CONF.orig > $CONF

chown -R glance /etc/glance
/usr/bin/glance-manage db_sync

##############################################################################
## Create credentials
##############################################################################

/bin/cat << EOF > admin_credential
export OS_USERNAME=admin
export OS_PASSWORD=$ADMIN_PASSWORD
export OS_TENANT_NAME=demo
export OS_AUTH_URL=http://$CONTROLLER_ADMIN_ADDRESS:35357/v2.0
export OS_NO_CACHE=1
EOF

##############################################################################
## Start all srevices
##############################################################################

./glance.sh start
sleep 5

##############################################################################
## Register Ubuntu-12.10 image on Glance
##############################################################################

http_proxy=$HTTP_PROXY /usr/bin/wget \
http://uec-images.ubuntu.com/releases/quantal/release/ubuntu-12.10-server-cloudimg-amd64-disk1.img

source admin_credential
/usr/bin/glance image-create \
	--name ubuntu-12.10 \
	--disk-format qcow2 \
	--container-format bare \
	--file ubuntu-12.10-server-cloudimg-amd64-disk1.img

/bin/rm -f ubuntu-12.10-server-cloudimg-amd64-disk1.img

echo "Glance installation finished."
