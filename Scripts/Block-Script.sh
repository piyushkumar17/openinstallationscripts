#!/bin/bash

echo CONGIGURING THE CONTROLLER NETWORK

echo -e "\nENABLING OPENSTACK REPOSITORY\n"

apt-get update
apt-get install ubuntu-cloud-keyring
echo "deb http://ubuntu-cloud.archive.canonical.com/ubuntu" \
"trusty-updates/juno main" > /etc/apt/sources.list.d/#cloudarchive-juno.list
apt-get update

echo -e "\nCONFIGURING THE NETWORK\n"

sed -i '$ a\\n#The Primary Network\n\nauto eth0\niface eth0 inet static\naddress 10.0.0.41\nnetmask 255.255.255.0\ngateway 10.0.0.1' /etc/network/interfaces
sed -i 's/false/true/' /etc/NetworkManager/NetworkManager.conf
service network-manager restart
sed -i 's/127.0.0.1/#127.0.0.1/' /etc/hosts
sed -i 's/127.0.1.1/#127.0.1.1/' /etc/hosts
sed -i '/ubuntu/a 10.0.0.11 controller' /etc/hosts
sed -i '/controller/a 10.0.0.31 compute1' /etc/hosts
sed -i '/compute1/a 10.0.0.41 block1' /etc/hosts
sed -i '/block1/a 10.0.0.51 object1' /etc/hosts
sed '/.*/d' /etc/hostname
sed -i 's/.*/block1/' /etc/hostname

echo -e "\nINSTALLING NTP SERVER\n"
apt-get install -y ntp
sed -i "s/server 0/#server 0/" /etc/ntp.conf
sed -i "s/server 1/#server 1/" /etc/ntp.conf
sed -i "s/server 2/#server 2/" /etc/ntp.conf
sed -i "s/server 3.*/server controller iburst/" /etc/ntp.conf
service ntp restart


apt-get install -y lvm2
echo -e "Enter Drive Partition Name For Block(example /dev/sdb)\n"
read drive
pvcreate $drive
vgcreate cinder-volumes $drive
sed -i 's/filter = \[ "a\/\.\*\/" \]/filter = \[ "a\/sda\/","a\/sdb\/", "r\/\.\*\/"\]/' /etc/lvm/lvm.conf

apt-get install -y cinder-volume python-mysqldb
echo -e "Enter Cinder Password\n"
read -s pass
sed -i "$ a [database]\nconnection = mysql:\/\/cinder:$pass@controller\/cinder" /etc/cinder/cinder.conf
echo -e "Enter Rabbit Password\n"
read -s pass1
sed -i "/\[DEFAULT\]/a rpc_backend = rabbit\nrabbit_host = controller\nrabbit_password = $pass1\nmy_ip=10.0.0.41\nglance_host=controller\nverbose=true" /etc/cinder/cinder.conf
sed -i "$ a [keystone_authtoken\]\nauth_uri = http:\/\/controller:5000\/v2.0\nidentity_uri = http:\/\/controller:35357\nadmin_tenant_name = service\nadmin_user = cinder\nadmin_password = $pass" /etc/cinder/cinder.conf
service tgt restart
service cinder-volume restart
rm -f /var/lib/cinder/cinder.sqlite