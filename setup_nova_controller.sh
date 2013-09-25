#!/bin/bash -xe
#
# setup_controller.sh - installs Keystone, Glance, Cinder, Nova, 
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
    bridge-utils \
    nova-api \
    nova-cert \
    nova-objectstore \
    nova-scheduler \
    nova-conductor \
    nova-doc \
    nova-console \
    nova-consoleauth \
    nova-novncproxy \
    websockify \
    novnc \
    openstack-dashboard \
    libapache2-mod-wsgi

##############################################################################
## Make a script to start/stop all services
##############################################################################

/bin/cat << EOF > nova.sh
#!/bin/bash

NOVA="conductor scheduler cert consoleauth novncproxy api"

case "\$1" in
start|restart|status)
	for i in \$NOVA; do
		/sbin/\$1 nova-\$i
	done
	;;
stop)
	for i in \$NOVA; do
		/sbin/stop nova-\$i
	done
	;;
esac
exit 0
EOF
/bin/chmod +x nova.sh

##############################################################################
## Stop all services.
##############################################################################

./nova.sh stop

##############################################################################
## Modify configuration files of Nova, Glance and Keystone
##############################################################################

for i in /etc/nova/nova.conf \
         /etc/nova/api-paste.ini
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
network_api_class=nova.network.quantumv2.api.API
quantum_url=http://$CONTROLLER_INTERNAL_ADDRESS:9696
quantum_auth_strategy=keystone
quantum_admin_tenant_name=service
quantum_admin_username=quantum
quantum_admin_password=$PASSWORD
quantum_admin_auth_url=http://$CONTROLLER_INTERNAL_ADDRESS:35357/v2.0
libvirt_vif_driver=nova.virt.libvirt.vif.LibvirtHybridOVSBridgeDriver
linuxnet_interface_driver=nova.network.linux_net.LinuxOVSInterfaceDriver
firewall_driver=nova.virt.libvirt.firewall.IptablesFirewallDriver

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

CONF=/etc/nova/api-paste.ini
/bin/sed \
        -e "s/^auth_host *=.*/auth_host = $CONTROLLER_ADMIN_ADDRESS/" \
	-e 's/%SERVICE_TENANT_NAME%/service/' \
	-e 's/%SERVICE_USER%/nova/' \
	-e "s/%SERVICE_PASSWORD%/$ADMIN_PASSWORD/" \
	$CONF.orig > $CONF

chown -R /etc/nova

##############################################################################
## Create MySQL accounts and databases of Nova, Glance, Keystone and Cinder
##############################################################################

/bin/cat << EOF | /usr/bin/mysql -uroot -p$MYSQLPASS
DROP DATABASE IF EXISTS nova;
CREATE DATABASE nova;
GRANT ALL ON nova.*     TO 'openstack'@'localhost'   IDENTIFIED BY '$MYSQLPASS';
GRANT ALL ON nova.*     TO 'openstack'@'$CONTROLLER_ADMIN_ADDRESS'   IDENTIFIED BY '$MYSQLPASS';
GRANT ALL ON nova.*     TO 'openstack'@'$MYSQL_ACCESS'   IDENTIFIED BY '$MYSQLPASS';
EOF

##############################################################################
## Initialize databases of Nova, Glance and Keystone
##############################################################################

/usr/bin/nova-manage db sync

##############################################################################
## Start all srevices
##############################################################################

./nova.sh start
sleep 5


##############################################################################
## Add a key pair
##############################################################################

source admin_credential
/usr/bin/nova keypair-add key1 > key1.pem
/bin/chmod 600 key1.pem
/bin/chgrp adm key1.pem

