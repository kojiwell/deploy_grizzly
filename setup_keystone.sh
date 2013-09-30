#!/bin/bash -xe
#
# setup_keystone.sh - installs Keystone.
# Horizon of OpenStack Grizzly on Ubuntu 13.04.
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
    rabbitmq-server \
    mysql-server \
    memcached \
    keystone

##############################################################################
## Disable IPv6
##############################################################################
#echo '127.0.0.1 localhost' > /etc/hosts
echo 'net.ipv6.conf.all.disable_ipv6 = 1' >> /etc/sysctl.conf

##############################################################################
## Configure memcached
##############################################################################
sed -i "s/127.0.0.1/$CONTROLLER_ADMIN_ADDRESS/" /etc/memcached.conf
service memcached restart

##############################################################################
## Stop all services.
##############################################################################

stop keystone

##############################################################################
## Modify configuration files of Nova, Glance and Keystone
##############################################################################

CONF=/etc/keystone/keystone.conf
test -f $CONF.orig || /bin/cp $CONF $CONF.orig
/bin/sed \
	-e "s/^#*connection *=.*/connection = mysql:\/\/openstack:$MYSQLPASS@$CONTROLLER_INTERNAL_ADDRESS\/keystone/" \
	-e "s/^#* *admin_token *=.*/admin_token = $ADMIN_PASSWORD/" \
	$CONF.orig > $CONF
chown keystone $CONF

##############################################################################
## Configure RabbitMQ
##############################################################################

rabbitmqctl add_vhost /nova
rabbitmqctl add_user nova $RABBIT_PASS
rabbitmqctl set_permissions -p /nova nova ".*" ".*" ".*"
rabbitmqctl delete_user guest

##############################################################################
## Modify MySQL configuration
##############################################################################

mysqladmin -u root password $MYSQLPASS
/sbin/stop mysql

CONF=/etc/mysql/my.cnf
test -f $CONF.orig || /bin/cp $CONF $CONF.orig
/bin/sed -e 's/^bind-address[[:space:]]*=.*/bind-address = 0.0.0.0/' \
	$CONF.orig > $CONF

/sbin/start mysql
sleep 5

##############################################################################
## Create MySQL accounts and databases of Nova, Glance, Keystone and Cinder
##############################################################################

/bin/cat << EOF | /usr/bin/mysql -uroot -p$MYSQLPASS
DROP DATABASE IF EXISTS keystone;
CREATE DATABASE keystone;
GRANT ALL ON keystone.* TO 'openstack'@'localhost'   IDENTIFIED BY '$MYSQLPASS';
GRANT ALL ON keystone.* TO 'openstack'@'$CONTROLLER_ADMIN_ADDRESS'   IDENTIFIED BY '$MYSQLPASS';
GRANT ALL ON keystone.* TO 'openstack'@'$MYSQL_ACCESS'   IDENTIFIED BY '$MYSQLPASS';
EOF

##############################################################################
## Initialize databases of Nova, Glance and Keystone
##############################################################################

/usr/bin/keystone-manage db_sync

##############################################################################
## Start Keystone
##############################################################################

/sbin/start keystone
sleep 5
/sbin/status keystone

##############################################################################
## Create a sample data on Keystone
##############################################################################

/bin/sed -e "s/pass=secrete/pass=$ADMIN_PASSWORD/g" \
         -e "s/pass=glance/pass=$ADMIN_PASSWORD/g" \
         -e "s/pass=nova/pass=$ADMIN_PASSWORD/g" \
         -e "s/pass=ec2/pass=$ADMIN_PASSWORD/g" \
         -e "s/pass=swiftpass/pass=$ADMIN_PASSWORD/g" \
         /usr/share/keystone/sample_data.sh > /tmp/sample_data.sh
/bin/bash -x /tmp/sample_data.sh

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

/bin/cat << EOF > demo_credential
export OS_USERNAME=demo
export OS_PASSWORD=$ADMIN_PASSWORD
export OS_TENANT_NAME=demo
export OS_AUTH_URL=http://$CONTROLLER_PUBLIC_ADDRESS:5000/v2.0
export OS_NO_CACHE=1
EOF

/sbin/restart keystone
sleep 5
/sbin/status keystone
