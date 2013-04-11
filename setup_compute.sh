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
    open-iscsi \
    open-iscsi-utils \
    kvm \
    kvm-ipxe \
    libvirt-bin \
    bridge-utils \
    python-libvirt \
    python-cinderclient \
    nova-api \
    nova-compute \
    nova-compute-kvm \
    nova-network \
    python-keystone

##############################################################################
## Disable IPv6
##############################################################################
echo '127.0.0.1 localhost' > /etc/hosts
echo 'net.ipv6.conf.all.disable_ipv6 = 1' >> /etc/sysctl.conf

##############################################################################
## Make a script to start/stop all services
##############################################################################

/bin/cat << EOF > openstack.sh
#!/bin/bash

NOVA="api compute network"

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
/bin/chmod +x openstack.sh

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
s3_host=$CONTROLLER
use_cow_images=yes

# GLANCE
image_service=nova.image.glance.GlanceImageService
glance_api_servers=$CONTROLLER:9292

# RABBIT
rabbit_host=$CONTROLLER
rabbit_virtual_host=/nova
rabbit_userid=nova
rabbit_password=$RABBIT_PASS

# DATABASE
sql_connection=mysql://openstack:$MYSQLPASS@$CONTROLLER/nova

#use cinder
enabled_apis=ec2,osapi_compute,metadata
volume_api_class=nova.volume.cinder.API

#keystone
auth_strategy=keystone
keystone_ec2_url=http://$CONTROLLER:5000/v2.0/ec2tokens
EOF

CONF=/etc/nova/api-paste.ini
/bin/sed \
        -e "s/^auth_host *=.*/auth_host = $CONTROLLER/" \
	-e 's/%SERVICE_TENANT_NAME%/service/' \
	-e 's/%SERVICE_USER%/nova/' \
	-e "s/%SERVICE_PASSWORD%/$ADMIN_PASSWORD/" \
	$CONF.orig > $CONF

chown -R nova /etc/nova

CONF=/etc/rc.local
test -f $CONF.orig || cp $CONF $CONF.orig
/bin/cat << EOF > $CONF
#!/bin/sh -e
#
# rc.local
#
# This script is executed at the end of each multiuser runlevel.
# Make sure that the script will "exit 0" on success or any other
# value on error.

iptables -A POSTROUTING -t mangle -p udp --dport 68 -j CHECKSUM --checksum-fill

exit 0
EOF

##############################################################################
## Start all srevices
##############################################################################

./openstack.sh start
sleep 5

##############################################################################
## Reboot
##############################################################################

/sbin/reboot
