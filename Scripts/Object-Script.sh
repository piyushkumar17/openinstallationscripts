#!/bin/bash

echo -e "\nENABLING OPENSTACK REPOSITORY\n"
apt-get update
apt-get install ubuntu-cloud-keyring
echo "deb http://ubuntu-cloud.archive.canonical.com/ubuntu" \
"trusty-updates/juno main" > /etc/apt/sources.list.d/#cloudarchive-juno.list
apt-get update


echo -e "\nCONGIGURING THE CONTROLLER NETWORK\n"
sed -i '$ a\\n#The Primary Network\n\nauto eth0\niface eth0 inet static\naddress 10.0.0.51\nnetmask 255.255.255.0\ngateway 10.0.0.1' /etc/network/interfaces
sed -i 's/false/true/' /etc/NetworkManager/NetworkManager.conf
service network-manager restart
sed -i 's/127.0.0.1/#127.0.0.1/' /etc/hosts
sed -i 's/127.0.1.1/#127.0.1.1/' /etc/hosts
sed -i '/ubuntu/a 10.0.0.11 controller' /etc/hosts
sed -i '/controller/a 10.0.0.31 compute1' /etc/hosts
sed -i '/compute1/a 10.0.0.41 block1' /etc/hosts
sed -i '/controller/a 10.0.0.51 object1' /etc/hosts
sed '/.*/d' /etc/hostname
sed -i 's/.*/object1/' /etc/hostname


echo -e "\nINSTALLING NTP SERVER\n"
apt-get -y install ntp
sed -i "s/server 0/#server 0/" /etc/ntp.conf
sed -i "s/server 1/#server 1/" /etc/ntp.conf
sed -i "s/server 2/#server 2/" /etc/ntp.conf
sed -i "s/server 3.*/server controller iburst/" /etc/ntp.conf
service ntp restart

apt-get -y install xfsprogs rsync
echo -e "\nEnter The Partition Name For Use\n(e.g. sdb)"
read part
mkfs.xfs /dev/$part
mkdir -p /srv/node/$part
sed -i "$ a /dev/$part /srv/node/$part xfs noatime,nodiratime,nobarrier,logbufs=8 0 2" /etc/fstab
mount /srv/node/$part
touch /etc/rsyncd.conf
echo -e "uid = swift\ngid = swift\nlog file = /var/log/rsyncd.log\npid file = /var/run/rsyncd.pid\naddress = 10.0.0.51\n[account]\nmax connections =2\npath = /srv/node/\nread only = false\nlock file = /var/lock/account.lock\n[container]\nmax connections = 2\npath = /srv/node/\nread only = false\nlock file = /var/lock/container.lock\n[object]\nmax_connections = 2\npath = /srv/node/\nread only = false\nlock file = /var/lock/object.lock\n" > /etc/rsyncd.conf
sed -i "s/RSYNC_ENABLE.*/RSYNC_ENABLE=true/" /etc/default/rsync
service rsync start

apt-get install -y swift swift-account swift-container swift-object

curl -o /etc/swift/account-server.conf https://raw.githubusercontent.com/openstack/swift/stable/juno/etc/account-server.conf-sample
curl -o /etc/swift/container-server.conf https://raw.githubusercontent.com/openstack/swift/stable/juno/etc/container-server.conf-sample
curl -o /etc/swift/object-server.conf https://raw.githubusercontent.com/openstack/swift/stable/juno/etc/object-server.conf-sample


sed -i "s/# bind_ip.*/bind_ip=10.0.0.51/" /etc/swift/account-server.conf
sed -i "s/# user/user/" /etc/swift/account-server.conf
sed -i "s/# swift_dir/swift_dir/" /etc/swift/account-server.conf
sed -i "s/# devices/devices/" /etc/swift/account-server.conf
sed -i "/use = egg:swift#recon/a recon_cache_path = \/var\/cache\/swift" /etc/swift/account-server.conf

sed -i "s/# bind_ip.*/bind_ip=10.0.0.51/" /etc/swift/container-server.conf
sed -i "s/# user/user/" /etc/swift/container-server.conf
sed -i "s/# swift_dir/swift_dir/" /etc/swift/container-server.conf
sed -i "s/# devices/devices/" /etc/swift/container-server.conf
sed -i "/use = egg:swift#recon/a recon_cache_path = \/var\/cache\/swift" /etc/swift/container-server.conf

sed -i "s/# bind_ip.*/bind_ip=10.0.0.51/" /etc/swift/object-server.conf
sed -i "s/# user/user/" /etc/swift/object-server.conf
sed -i "s/# swift_dir/swift_dir/" /etc/swift/object-server.conf
sed -i "s/# devices/devices/" /etc/swift/object-server.conf
sed -i "/use = egg:swift#recon/a recon_cache_path = \/var\/cache\/swift" /etc/swift/object-server.conf

chown -R swift:swift /srv/node
mkdir -p /var/cache/swift
chown -R swift:swift /var/cache/swift