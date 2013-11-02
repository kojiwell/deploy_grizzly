Installation Script of OpenStack Grizzly for Ubuntu-13.04
======================================================

This script installs OpenStack Grizzly on Ubuntu-13.04

* setuprc - is configuration file
* setup_controller.sh - Installs Keystone, Glance, Cinder and Nova.
* setup_compute - Installs nova-compute and nova-network.

How to
------
First of all, update ```/etc/hosts```. If the hostname isn't resolvable,
Nova Network will fail to create a bridge.

Download.
```
git clone https://github.com/kjtanaka/deploy_grizzly.git
cd deploy_grizzly
```

Create setuprc:
```
cp setuprc-example setuprc
```

Modify setuprc.

Two NICs:
```
# setuprc - configuration file for deploying OpenStack

export PASSWORD=DoNotMakeThisEasy
export ADMIN_PASSWORD=$PASSWORD
export SERVICE_PASSWORD=$PASSWORD
export ENABLE_ENDPOINTS=1
MYSQLPASS=$PASSWORD
RABBIT_PASS=$PASSWORD
export CONTROLLER_PUBLIC_ADDRESS="xxx.xxx.xxx.xxx"
export CONTROLLER_ADMIN_ADDRESS="192.168.1.1"
export CONTROLLER_INTERNAL_ADDRESS=$CONTROLLER_ADMIN_ADDRESS
FIXED_RANGE="192.168.201.0/24"
MYSQL_ACCESS="192.168.1.%"
PUBLIC_INTERFACE="eth1"
FLAT_INTERFACE="eth0"
```
One NIC:
```
# setuprc - configuration file for deploying OpenStack

export PASSWORD=DoNotMakeThisEasy
export ADMIN_PASSWORD=$PASSWORD
export SERVICE_PASSWORD=$PASSWORD
export ENABLE_ENDPOINTS=1
MYSQLPASS=$PASSWORD
RABBIT_PASS=$PASSWORD
export CONTROLLER_PUBLIC_ADDRESS="192.168.1.1"
export CONTROLLER_ADMIN_ADDRESS="192.168.1.1"
export CONTROLLER_INTERNAL_ADDRESS=$CONTROLLER_ADMIN_ADDRESS
FIXED_RANGE="192.168.201.0/24"
MYSQL_ACCESS="192.168.1.%"
PUBLIC_INTERFACE="br101"
FLAT_INTERFACE="eth0"
```

For controller node.
```
bash -ex setup_controller.sh
```
The node will reboot after the installation. The script installs nova-compute 
on the controller, so you can run your first instance(VM) when the node finish reboot.
The command is like this.
```
. admin_credential
nova boot --image ubuntu-12.10 --flavor 1 --key-name key1 vm001
```
You can check the status with this command.
```
nova list
```
Once your instance become ACTIVE, you can login to it.
```
ssh -i key1.pem ubuntu@192.168.201.2
```

For nova-compute node, use the same setuprc and execute setup_compute.sh
like this.
```
bash -ex setup_compute.sh
```

If you want stop nova-compute on the controller, you can disable it by this.
```
nova-manage service disable --service nova-compute --host <hostname of your controller>
```

License
--------------------------
The scripts are developed under Apache License.

Authors
--------------------------
* Akira Yoshiyama
* Koji Tanaka, Indiana University
