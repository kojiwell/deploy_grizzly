#!/bin/bash -xe
#
# setup_controller.sh - installs Keystone, Glance, Cinder, Nova, 
# Horizon of OpenStack Grizzly on Ubuntu 13.04.
#

source setuprc

HTTP_PROXY=$http_proxy
unset http_proxy

#=============================================================================
# Common services
#=============================================================================

#-----------------------------------------------------------------------------
# Operating System
#-----------------------------------------------------------------------------
function setup_operating_system() {
CONF=/etc/sysctl.conf
test -f $CONF.orig || cp $CONF $CONF.orig
echo 'net.ipv6.conf.all.disable_ipv6 = 1' >> /etc/sysctl.conf
echo 'net.ipv4.conf.all.rp_filter = 0' >> /etc/sysctl.conf
echo 'net.ipv4.conf.default.rp_filter = 0' >> /etc/sysctl.conf
service networking restart
sysctl -e -p /etc/sysctl.conf

/usr/bin/aptitude -y update
/usr/bin/aptitude -y upgrade
/usr/bin/aptitude -y install ntp
}

#-----------------------------------------------------------------------------
# MySQL Database Service
#-----------------------------------------------------------------------------
function setup_mysql_database() {
export DEBIAN_FRONTEND=noninteractive
/usr/bin/aptitude -y install python-mysqldb mysql-server

mysqladmin -u root password $MYSQL_ROOT_PASSWORD
sed -i 's/127.0.0.1/0.0.0.0/g' /etc/mysql/my.cnf
service mysql restart

mysql -u root -p$MYSQL_ROOT_PASSWORD <<EOF
CREATE DATABASE nova;
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' \
	IDENTIFIED BY '$MYSQL_DB_PASSWORD';
CREATE DATABASE cinder;
GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'localhost' \
	IDENTIFIED BY '$MYSQL_DB_PASSWORD';
CREATE DATABASE glance;
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' \
	IDENTIFIED BY '$MYSQL_DB_PASSWORD';
CREATE DATABASE keystone;
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' \
	IDENTIFIED BY '$MYSQL_DB_PASSWORD';
CREATE DATABASE quantum;
GRANT ALL PRIVILEGES ON quantum.* TO 'quantum'@'localhost' \
	IDENTIFIED BY '$MYSQL_DB_PASSWORD';
GRANT ALL PRIVILEGES ON quantum.* TO 'quantum'@'$MYSQL_ALLOWED_SUBNET' \
	IDENTIFIED BY '$MYSQL_DB_PASSWORD';
FLUSH PRIVILEGES;
EOF
}

#-----------------------------------------------------------------------------
# RabbitMQ Messaging Service
#-----------------------------------------------------------------------------
function setup_rabbitmq() {
apt-get install -y rabbitmq-server
rabbitmqctl change_password guest $RABBITMQ_PASSWORD
}

#=============================================================================
# OpenStack Identity Service
#=============================================================================
function setup_keystone() {
apt-get install -y keystone python-keystone python-keystoneclient
CONF=/etc/keystone/keystone.conf
test -f $CONF.orig || cp $CONF $CONF.orig
/bin/sed \
        -e "s/^#*connection *=.*/connection = mysql:\/\/keystone:$MYSQL_DB_PASSWORD@$CONTROLLER_INTERNAL_ADDRESS\/keystone/" \
        -e "s/^#* *admin_token *=.*/admin_token = $KEYSTONE_ADMIN_TOKEN/" \
        $CONF.orig > $CONF

}

function old_scripts() {
##############################################################################
## Configure memcached
##############################################################################
sed -i "s/127.0.0.1/$CONTROLLER_ADMIN_ADDRESS/" /etc/memcached.conf
service memcached restart

##############################################################################
## Make a script to start/stop all services
##############################################################################

/bin/cat << EOF > openstack.sh
#!/bin/bash

NOVA="conductor compute network scheduler cert consoleauth novncproxy api"
GLANCE="registry api"
KEYSTONE=""
CINDER="scheduler volume api"

case "\$1" in
start|restart|status)
	/sbin/\$1 keystone
	for i in \$GLANCE; do
		/sbin/\$1 glance-\$i
	done
	for i in \$NOVA; do
		/sbin/\$1 nova-\$i
	done
	for i in \$CINDER; do
		/sbin/\$1 cinder-\$i
	done
	;;
stop)
	for i in \$NOVA; do
		/sbin/stop nova-\$i
	done
	for i in \$GLANCE; do
		/sbin/stop glance-\$i
	done
	for i in \$CINDER; do
		/sbin/stop cinder-\$i
	done
	/sbin/stop keystone
	;;
esac
exit 0
EOF
/bin/chmod +x openstack.sh

##############################################################################
## Stop all services.
##############################################################################

./openstack.sh stop

##############################################################################
## Modify configuration files of Nova, Glance and Keystone
##############################################################################

for i in /etc/nova/nova.conf \
         /etc/nova/api-paste.ini \
	 /etc/glance/glance-api.conf \
	 /etc/glance/glance-registry.conf \
	 /etc/keystone/keystone.conf \
         /etc/cinder/cinder.conf \
         /etc/cinder/api-paste.ini \
         /etc/openstack-dashboard/local_settings.py
do
	test -f $i.orig || /bin/cp $i $i.orig
done

/bin/cat << EOF > /etc/nova/nova.conf
[DEFAULT]
verbose=True
multi_host=True
allow_admin_api=True
api_paste_config=/etc/nova/api-paste.ini
instances_path=/var/lib/nova/instances
compute_driver=libvirt.LibvirtDriver
rootwrap_config=/etc/nova/rootwrap.conf
send_arp_for_ha=True
ec2_private_dns_show_ip=True
start_guests_on_host_boot=True
resume_guests_state_on_host_boot=True

# LOGGING
logdir=/var/log/nova
state_path=/var/lib/nova
lock_path=/var/lock/nova

# NETWORK
libvirt_use_virtio_for_bridges = True
network_manager=nova.network.manager.FlatDHCPManager
firewall_driver=nova.virt.libvirt.firewall.IptablesFirewallDriver
dhcpbridge_flagfile=/etc/nova/nova.conf
dhcpbridge=/usr/bin/nova-dhcpbridge
public_interface=$PUBLIC_INTERFACE
flat_interface=$FLAT_INTERFACE
flat_network_bridge=br101
fixed_range=$FIXED_RANGE
#flat_network_dhcp_start=
#network_size=255
force_dhcp_release = True
flat_injected=false
use_ipv6=false

# VNC
vncserver_proxyclient_address=\$my_ip
vncserver_listen=\$my_ip
keymap=en-us

#scheduler
scheduler_driver=nova.scheduler.filter_scheduler.FilterScheduler

# OBJECT
s3_host=$CONTROLLER_PUBLIC_ADDRESS
use_cow_images=yes

# GLANCE
image_service=nova.image.glance.GlanceImageService
glance_api_servers=$CONTROLLER_PUBLIC_ADDRESS:9292

# RABBIT
rabbit_host=$CONTROLLER_INTERNAL_ADDRESS
rabbit_virtual_host=/nova
rabbit_userid=nova
rabbit_password=$RABBIT_PASS

# DATABASE
sql_connection=mysql://openstack:$MYSQLPASS@$CONTROLLER_INTERNAL_ADDRESS/nova

#use cinder
enabled_apis=ec2,osapi_compute,metadata
volume_api_class=nova.volume.cinder.API

#keystone
auth_strategy=keystone
keystone_ec2_url=http://$CONTROLLER_PUBLIC_ADDRESS:5000/v2.0/ec2tokens
EOF

/bin/cat << EOF >> /etc/cinder/cinder.conf
# LOGGING
log_file=cinder.log
log_dir=/var/log/cinder

# OSAPI
osapi_volume_extension = cinder.api.openstack.volume.contrib.standard_extensions
osapi_max_limit = 2000

# RABBIT
rabbit_host=$CONTROLLER_INTERNAL_ADDRESS
rabbit_virtual_host=/nova
rabbit_userid=nova
rabbit_password=$RABBIT_PASS

# MYSQL
sql_connection = mysql://openstack:$MYSQLPASS@$CONTROLLER_INTERNAL_ADDRESS/cinder
EOF

#/bin/cat << EOF >> /etc/openstack-dashboard/local_settings.py
#DATABASES = {
#    'default': {
#        'ENGINE': 'django.db.backends.mysql',
#        'NAME': 'horizon',
#        'USER': 'openstack',
#        'PASSWORD': '$MYSQLPASS',
#        'HOST': '$CONTROPPER',
#        'default-character-set': 'utf8'
#    }
#}
#HORIZON_CONFIG = {
#    'dashboards': ('nova', 'syspanel', 'settings',),
#    'default_dashboard': 'nova',
#    'user_home': 'openstack_dashboard.views.user_home',
#}
#SESSION_ENGINE = 'django.contrib.sessions.backends.cached_db'
#EOF

CONF=/etc/nova/api-paste.ini
/bin/sed \
        -e "s/^auth_host *=.*/auth_host = $CONTROLLER_ADMIN_ADDRESS/" \
	-e 's/%SERVICE_TENANT_NAME%/service/' \
	-e 's/%SERVICE_USER%/nova/' \
	-e "s/%SERVICE_PASSWORD%/$ADMIN_PASSWORD/" \
	$CONF.orig > $CONF

CONF=/etc/glance/glance-api.conf
/bin/sed \
        -e "s/^auth_host *=.*/auth_host = $CONTROLLER_ADMIN_ADDRESS/" \
	-e 's/%SERVICE_TENANT_NAME%/service/' \
	-e 's/%SERVICE_USER%/glance/' \
	-e "s/%SERVICE_PASSWORD%/$ADMIN_PASSWORD/" \
	-e "s#^sql_connection *=.*#sql_connection = mysql://openstack:$MYSQLPASS@$CONTROLLER_INTERNAL_ADDRESS/glance#" \
	-e 's[^#* *config_file *=.*[config_file = /etc/glance/glance-api-paste.ini[' \
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

CONF=/etc/keystone/keystone.conf
/bin/sed \
	-e "s/^#*connection *=.*/connection = mysql:\/\/openstack:$MYSQLPASS@$CONTROLLER_INTERNAL_ADDRESS\/keystone/" \
	-e "s/^#* *admin_token *=.*/admin_token = $ADMIN_PASSWORD/" \
	$CONF.orig > $CONF

CONF=/etc/cinder/api-paste.ini
/bin/sed \
        -e "s/^service_host *=.*/service_host = $CONTROLLER_PUBLIC_ADDRESS/" \
        -e "s/^auth_host *=.*/auth_host = $CONTROLLER_ADMIN_ADDRESS/" \
	-e 's/%SERVICE_TENANT_NAME%/service/' \
	-e 's/%SERVICE_USER%/cinder/' \
	-e "s/%SERVICE_PASSWORD%/$ADMIN_PASSWORD/" \
	$CONF.orig > $CONF

for i in nova keystone glance cinder
do
	chown -R $i /etc/$i
done

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
DROP DATABASE IF EXISTS glance;
DROP DATABASE IF EXISTS nova;
DROP DATABASE IF EXISTS cinder;
DROP DATABASE IF EXISTS horizon;
CREATE DATABASE keystone;
CREATE DATABASE glance;
CREATE DATABASE nova;
CREATE DATABASE cinder;
CREATE DATABASE horizon;
GRANT ALL ON keystone.* TO 'openstack'@'localhost'   IDENTIFIED BY '$MYSQLPASS';
GRANT ALL ON glance.*   TO 'openstack'@'localhost'   IDENTIFIED BY '$MYSQLPASS';
GRANT ALL ON nova.*     TO 'openstack'@'localhost'   IDENTIFIED BY '$MYSQLPASS';
GRANT ALL ON cinder.*   TO 'openstack'@'localhost'   IDENTIFIED BY '$MYSQLPASS';
GRANT ALL ON horizon.*   TO 'openstack'@'localhost'   IDENTIFIED BY '$MYSQLPASS';
GRANT ALL ON keystone.* TO 'openstack'@'$CONTROLLER_ADMIN_ADDRESS'   IDENTIFIED BY '$MYSQLPASS';
GRANT ALL ON glance.*   TO 'openstack'@'$CONTROLLER_ADMIN_ADDRESS'   IDENTIFIED BY '$MYSQLPASS';
GRANT ALL ON nova.*     TO 'openstack'@'$CONTROLLER_ADMIN_ADDRESS'   IDENTIFIED BY '$MYSQLPASS';
GRANT ALL ON cinder.*   TO 'openstack'@'$CONTROLLER_ADMIN_ADDRESS'   IDENTIFIED BY '$MYSQLPASS';
GRANT ALL ON horizon.*   TO 'openstack'@'$CONTROLLER_ADMIN_ADDRESS'   IDENTIFIED BY '$MYSQLPASS';
GRANT ALL ON keystone.* TO 'openstack'@'$MYSQL_ACCESS'   IDENTIFIED BY '$MYSQLPASS';
GRANT ALL ON glance.*   TO 'openstack'@'$MYSQL_ACCESS'   IDENTIFIED BY '$MYSQLPASS';
GRANT ALL ON nova.*     TO 'openstack'@'$MYSQL_ACCESS'   IDENTIFIED BY '$MYSQLPASS';
GRANT ALL ON cinder.*   TO 'openstack'@'$MYSQL_ACCESS'   IDENTIFIED BY '$MYSQLPASS';
GRANT ALL ON horizon.*   TO 'openstack'@'$MYSQL_ACCESS'   IDENTIFIED BY '$MYSQLPASS';
EOF

##############################################################################
## Initialize databases of Nova, Glance and Keystone
##############################################################################

#if [ -n $CINDER_VOL ]; then
#    pvcreate $CINDER_VOL
#    vgcreate cinder-volumes $CINDER_VOL
#fi

/usr/bin/keystone-manage db_sync
/usr/bin/glance-manage db_sync
/usr/bin/nova-manage db sync
/usr/bin/cinder-manage db sync

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

##############################################################################
## Add Cinder on Keystone
##############################################################################

source admin_credential
keystone endpoint-delete $(keystone endpoint-list | grep 8776 | awk '{print $2}')
keystone service-delete $(keystone service-list | grep volume | awk '{print $2}')
SERVICE_PASSWORD=$ADMIN_PASSWORD
SERVICE_HOST=$CONTROLLER_PUBLIC_ADDRESS

function get_id () {
    echo `"$@" | awk '/ id / { print $4 }'`
}
ADMIN_ROLE=$(keystone role-list | grep " admin" | awk '{print $2}')
SERVICE_TENANT=$(keystone tenant-list | grep service | awk '{print $2}')

CINDER_USER=$(get_id keystone user-create \
        --name=cinder \
        --pass="$SERVICE_PASSWORD" \
        --tenant_id $SERVICE_TENANT \
        --email=cinder@example.com)
keystone user-role-add \
        --tenant_id $SERVICE_TENANT \
        --user_id $CINDER_USER \
        --role_id $ADMIN_ROLE
CINDER_SERVICE=$(get_id keystone service-create \
        --name=cinder \
        --type=volume \
        --description="Cinder Service")
keystone endpoint-create \
        --region RegionOne \
        --service_id $CINDER_SERVICE \
        --publicurl "http://$CONTROLLER_PUBLIC_ADDRESS:8776/v1/\$(tenant_id)s" \
        --adminurl "http://$CONTROLLER_ADMIN_ADDRESS:8776/v1/\$(tenant_id)s" \
        --internalurl "http://$CONTROLLER_INTERNAL_ADDRESS:8776/v1/\$(tenant_id)s"

##############################################################################
## Create a nova network
##############################################################################

/usr/bin/nova-manage network create \
	--label private \
	--num_networks=1 \
	--fixed_range_v4=$FIXED_RANGE \
        --bridge_interface=$FLAT_INTERFACE \
	--network_size=256 \
        --multi_host=T

#CONF=/etc/rc.local
#test -f $CONF.orig || cp $CONF $CONF.orig
#/bin/cat << EOF > $CONF
##!/bin/sh -e
##
## rc.local
##
## This script is executed at the end of each multiuser runlevel.
## Make sure that the script will "exit 0" on success or any other
## value on error.
#
#iptables -A POSTROUTING -t mangle -p udp --dport 68 -j CHECKSUM --checksum-fill
#
#exit 0
#EOF

##############################################################################
## Start all srevices
##############################################################################

./openstack.sh start
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

##############################################################################
## Add a key pair
##############################################################################

/usr/bin/nova keypair-add key1 > key1.pem
/bin/chmod 600 key1.pem
/bin/chgrp adm key1.pem

##############################################################################
## Reboot
##############################################################################

/sbin/reboot
}
