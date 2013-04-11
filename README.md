Installation Script of OpenStack Folsom for Ubuntu-12.10
======================================================

This script installs OpenStack Folsom on Ubuntu-12.10

* setuprc - is configuration file
* setup_controller.sh - Installs Keystone, Glance, Cinder and Nova.
* setup_compute - Installs nova-compute and nova-network.

How to
------
Download.
```
git clone https://github.com/kjtanaka/deploy_folsom.git
cd deploy_folsom
```

Create setuprc:
```
cp setuprc-example setuprc
```

Modify setuprc:
```
# setuprc - configuration file for deploying OpenStack

PASSWORD="DoNotMakeThisEasy"
export ADMIN_PASSWORD=$PASSWORD
export SERVICE_PASSWORD=$PASSWORD
export ENABLE_ENDPOINTS=1
MYSQLPASS=$PASSWORD
RABBIT_PASS=$PASSWORD
CONTROLLER="192.168.1.1"
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

Log
--------------------------
* Originally written by Akira Yoshiyama, under Apache License,
as a single node installation for beginers to try Folsom.
* I(Koji Tanaka) modified it for making it work for multiple nodes, and 
  added Cinder configuration.
* Changed the messaging system from QPID to RabbitMQ.
* Added the script to install a separate nova-compute node.
