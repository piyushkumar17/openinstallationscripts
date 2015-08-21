#!/bin/bash

#This script Install all the component required to build controller node
#Please run this script under adminstrative rights
#This script install keystone,compute,heat,ceilometer,Horizon,swift and cinder

#keystone for authentication
#compute for compute resources like processor,memory etc
#Heat for orchestraton of cloud
#ceilometer for metering
#Horizon for dashboard or cloud portal
#swift for object storage
#cinder for block storage


echo -e "\nENABLING OPENSTACK REPOSITORY\n"
apt-get update
apt-get -y install ubuntu-cloud-keyring
echo "deb http://ubuntu-cloud.archive.canonical.com/ubuntu" \
"trusty-updates/juno main" > /etc/apt/sources.list.d/cloudarchive-juno.list
apt-get update


echo -e "\nCONGIGURING THE CONTROLLER NETWORK\n"
sed -i '$ a\\n#The Primary Network\n\nauto eth0\niface eth0 inet static\naddress 10.0.0.11\nnetmask 255.255.255.0\ngateway 10.0.0.1' /etc/network/interfaces
sed -i 's/false/true/' /etc/NetworkManager/NetworkManager.conf
service network-manager restart
sed -i 's/127.0.0.1/#127.0.0.1/' /etc/hosts
sed -i 's/127.0.1.1/#127.0.1.1/' /etc/hosts
sed -i '/ubuntu/a 10.0.0.11 controller' /etc/hosts
sed -i '/controller/a 10.0.0.31 compute1' /etc/hosts
sed -i '/compute1/a 10.0.0.41 block1' /etc/hosts
sed -i '/block1/a 10.0.0.51 object1' /etc/hosts
sed '/.*/d' /etc/hostname
sed -i 's/.*/controller/' /etc/hostname


echo -e "\nINSTALLING NTP SERVICE\n"
apt-get -y install ntp
sed -i 's/restrict -4 default kod notrap nomodify nopeer noquery/restrict -4 default kod notrap nomodify/' /etc/ntp.conf
sed -i 's/restrict -6 default kod notrap nomodify nopeer noquery/restrict -6 default kod notrap nomodify/' /etc/ntp.conf
service ntp restart


echo -e "\nINSTALLING DATABASE\n"
echo Enter Database Password
read -s pass1
echo Re-Enter Database Password
read -s pass2
while [ $pass1 -ne $pass2 ]
do
 echo -e "\nTry Again\n"
 echo Enter Database Password
 read -s pass1
 echo Re-Enter Database Password
 read -s pass2
done

export DEBIAN_FRONTEND=noninteractive
sudo debconf-set-selections <<< "mariadb-server-5.5.44 mysql-server/#root_password password $pass1"
sudo debconf-set-selections <<< "mariadb-server-5.5.44 mysql-server/root_password_again password $pass2"
apt-get -y install mariadb-server python-mysqldb
sed -i "s/bind-address.*/bind-address = 10.0.0.11/" /etc/mysql/my.cnf
mysql_secure_installation
service mysql restart


echo -e "\nINSTALLING MESSAGING SERVER\n"

apt-get -y install rabbitmq-server
echo Enter Rabbit-mq Server Password
read -s pass3
rabbitmqctl change_password guest $pass3
service rabbitmq-server restart


echo -e "\nINSTALLING OPENSTACK KEYSTONE\n"

echo Enter Your Keystone Password
read -s pass4
mysql -u root -p$pass1 << EOF
CREATE DATABASE keystone;
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '$pass4';
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '$pass4';
EOF

apt-get install -y keystone python-keystoneclient
echo Please Enter Admin Token Value
read -s pass5
sed -i "s/#admin_token.*/admin_token = $pass5/" /etc/keystone/keystone.conf
sed -i "s/connection=s.*/connection = mysql:\/\/keystone:$pass4@controller\/keystone/" /etc/keystone/keystone.conf
sed -i "s/#provider.*/provider = keystone.token.providers.uuid.Provider/" /etc/keystone/keystone.conf
sed -i "s/#driver=keystone.token.persistence.backends.sql.Token/driver=keystone.token.persistence.backends.sql.Token/" /etc/keystone/keystone.conf
sed -i "s/#driver=keystone.contrib.revoke.backends.kvs.Revoke/driver = keystone.contrib.revoke.backends.sql.Revoke/" /etc/keystone/keystone.conf
sed -i "s/#verbose=.*/verbose=true/" /etc/keystone/keystone.conf
su -s /bin/sh -c "keystone-manage db_sync" keystone
service keystone restart
rm -f /var/lib/keystone/keystone.db
(crontab -l -u keystone 2>&1 | grep -q token_flush) || echo '@hourly /usr/bin/keystone-manage token_flush >/var/log/keystone/keystone-tokenflush.log 2>&1' >> /var/spool/cron/crontabs/keystone

export OS_SERVICE_TOKEN=$pass5
export OS_SERVICE_ENDPOINT=http://controller:35357/v2.0
keystone tenant-create --name admin --description "Admin Tenant"
keystone user-create --name admin --pass $pass5 --email xyz@gmail.com
keystone role-create --name admin
keystone user-role-add --user admin --tenant admin --role admin
keystone tenant-create --name demo --description "Demo Tenant"

echo Enter Name To Create User
read user1
echo Enter Password Of $user1
read -s user2
echo Enter E-mail Of $user1
read user3
keystone user-create --name $user1 --pass $user2 --email $user3
keystone tenant-create --name service --description "Service Tenant"
keystone service-create --name keystone --type identity --description "OpenStack Identity"
keystone endpoint-create --service-id $(keystone service-list | awk '/ identity / {print $2}') --publicurl http://controller:5000/v2.0 --internalurl http://controller:5000/v2.0 --adminurl http://controller:35357/v2.0 --region regionOne

touch admin-openrc.sh
echo -e "export OS_TENANT_NAME=admin\nexport OS_USERNAME=admin\nexport OS_PASSWORD=$pass5\nexport OS_AUTH_URL=http://controller:5000/v2.0" > admin-openrc.sh
unset OS_SERVICE_TOKEN OS_SERVICE_ENDPOINT
source admin-openrc.sh


echo -e "\nINSTALLING OPENSTACK GLANCE\n"

source admin-openrc.sh
echo Enter Your Glance Password
read -s pass6
mysql -u root -p$pass1<< EOF
CREATE DATABASE glance;
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '$pass6';
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY '$pass6';
EOF

keystone user-create --name glance --pass $pass6
keystone user-role-add --user glance --tenant service --role admin
keystone service-create --name glance --type image --description "OpenStack Image Service"
keystone endpoint-create --service-id $(keystone service-list | awk '/ image / {print$2}') --publicurl http://controller:9292 --internalurl http://controller:9292 --adminurl http://controller:9292 --region regionOne

apt-get install -y glance python-glanceclient
sed -i "s/#connection =.*/connection = mysql:\/\/glance:$pass6@controller\/glance/" /etc/glance/glance-api.conf
sed -i "s/admin_tenant_name = %SERVICE_TENANT_NAME%/admin_tenant_name = service/" /etc/glance/glance-api.conf
sed -i "s/admin_user = %SERVICE_USER%/admin_user = glance/" /etc/glance/glance-api.conf
sed -i "s/admin_password = %.*/admin_password = $pass6/" /etc/glance/glance-api.conf
sed -i '/\[keystone_authtoken\]/a auth_uri = http:\/\/controller:5000\/v2.0' /etc/glance/glance-api.conf
sed -i "s/identity_uri =.*/identity_uri = http:\/\/controller:35357/" /etc/glance/glance-api.conf
sed -i "s/#flavor.*/flavor = keystone/" /etc/glance/glance-api.conf
sed -i "s/# notification_driver/notification_driver/" /etc/glance/glance-api.conf
sed -i "s/#verbose =.*/verbose = true/" /etc/glance/glance-api.conf
sed -i "s/#connection =.*/connection = mysql:\/\/glance:$pass6@controller\/glance/" /etc/glance/glance-registry.conf
sed -i "s/admin_tenant_name = %SERVICE_TENANT_NAME%/admin_tenant_name = service/" /etc/glance/glance-registry.conf
sed -i "s/admin_user = %.*/admin_user = glance/" /etc/glance/glance-registry.conf
sed -i "s/admin_password = %.*/admin_password = $pass6/" /etc/glance/glance-registry.conf
sed -i "s/identity_uri =.*/identity_uri = http:\/\/controller:35357/" /etc/glance/glance-registry.conf
sed -i '/\[keystone_authtoken\]/a auth_uri = http:\/\/controller:5000\/v2.0' /etc/glance/glance-registry.conf
sed -i "s/#flavor.*/flavor = keystone/" /etc/glance/glance-registry.conf
sed -i "s/# notification_driver/notification_driver/" /etc/glance/glance-registry.conf
sed -i "s/#verbose =.*/verbose = true/" /etc/glance/glance-registry.conf
su -s /bin/sh -c "glance-manage db_sync" glance
service glance-registry restart
service glance-api restart
rm -f /var/lib/glance/glance.sqlite
mkdir /tmp/images


echo -e "\nINSTALLING OPENSTACK NOVA\n"

echo Enter Your nova Password
read -s pass7
mysql -u root -p$pass1 << EOF
CREATE DATABASE nova;
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY '$pass7';
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY '$pass7';
EOF

source admin-openrc.sh
keystone user-create --name nova --pass $pass7
keystone user-role-add --user nova --tenant service --role admin
keystone service-create --name nova --type compute --description "OpenStack Compute"
keystone endpoint-create --service_id $(keystone service-list | awk '/ compute / {print $2}') --publicurl http://controller:8774/v2/%\(tenant_id\)s --internalurl http://controller:8774/v2/%\(tenant_id\)s --adminurl http://controller:8774/v2/%\(tenant_id\)s --region regionOne

apt-get install -y nova-api nova-cert nova-conductor nova-consoleauth nova-novncproxy nova-scheduler python-novaclient
sed -i "$ a [database]\nconnection = mysql://nova:$pass7@controller/nova" /etc/nova/nova.conf
sed -i "/\[DEFAULT\]/a rpc_backend = rabbit\nrabbit_host = controller\nrabbit_password = $pass3\nauth_strategy = keystone\nmy_ip = 10.0.0.11\nvncserver_listen = 10.0.0.11\nvncserver_proxyclient_address = 10.0.0.11\nverbose = True" /etc/nova/nova.conf
sed -i "$ a [keystone_authtoken]\nauth_uri = http://controller:5000/v2.0\nidentity_uri = http://controller:35357\nadmin_tenant_name = service\nadmin_user = nova\nadmin_password = $pass7\n[glance]\nhost = controller" /etc/nova/nova.conf
su -s /bin/sh -c "nova-manage db sync" nova
service nova-api restart
service nova-cert restart
service nova-consoleauth restart
service nova-scheduler restart
service nova-conductor restart
service nova-novncproxy restart

sed -i "/\[DEFAULT\]/a network_api_class = nova.network.api.API\nsecurity_group_api = nova" /etc/nova/nova.conf
service nova-api restart
service nova-scheduler restart
service nova-conductor restart


echo -e "\nINSTALLING OPENSTACK HORIZON\n"

apt-get install -y openstack-dashboard apache2 libapache2-mod-wsgi memcached python-memcache
sed -i "s/OPENSTACK_HOST = .*/OPENSTACK_HOST = \"controller\"/" /etc/openstack-dashboard/local_settings.py
service apache2 restart
service memcached restart


echo -e "\nINSTALLING OPENSTACK HEAT\n"

echo Enter Your Heat Password
read -s pass8
mysql -u root -p$pass1 << EOF
CREATE DATABASE heat;
GRANT ALL PRIVILEGES ON heat.* TO 'heat'@'localhost' IDENTIFIED BY '$pass8';
GRANT ALL PRIVILEGES ON heat.* TO 'heat'@'%' IDENTIFIED BY '$pass8';
EOF
source admin-openrc.sh

keystone user-create --name heat --pass $pass8
keystone user-role-add --user heat --tenant service --role admin
keystone role-create --name heat_stack_owner
keystone user-role-add --user demo --tenant demo --role heat_stack_owner
keystone role-create --name heat_stack_user
keystone service-create --name heat --type orchestration --description "Orchestration"
keystone service-create --name heat-cfn --type cloudformation --description "Orchestration"
keystone endpoint-create --service-id $(keystone service-list | awk '/ orchestration / {print$2}') --publicurl http://controller:8004/v1/%\(tenant_id\)s --internalurl http://controller:8004/v1/%\(tenant_id\)s --adminurl http://controller:8004/v1/%\(tenant_id\)s --region regionOne
keystone endpoint-create --service-id $(keystone service-list | awk '/ cloudformation / {print$2}') --publicurl http://controller:8000/v1 --internalurl http://controller:8000/v1 --adminurl http://controller:8000/v1 --region regionOne

apt-get install -y heat-api heat-api-cfn heat-engine python-heatclient
sed -i "s/#connection.*/connection = mysql:\/\/heat:$pass8@controller\/heat/" /etc/heat/heat.conf
sed -i "s/#rpc_backend/rpc_backend/" /etc/heat/heat.conf
sed -i "s/#rabbit_host=.*/rabbit_host = controller/" /etc/heat/heat.conf
sed -i "s/#rabbit_password.*/#rabbit_password = $pass3/" /etc/heat/heat.conf
sed -i "s/#auth_uri=<None>/auth_uri = http:\/\/controller:5000\/v2.0/" /etc/heat/heat.conf
sed -i "/\[keystone_authtoken\]/a identity_uri = http:\/\/controller:35357\nauth_uri = http://controller:5000/v2.0\nadmin_tenant_name = service\nadmin_user = heat\nadmin_password = $pass8" /etc/heat/heat.conf
sed -i "s/#heat_metadata_server_url=/heat_metadata_server_url = http:\/\/controller:8000/" /etc/heat/heat.conf
sed -i "s/#heat_waitcondition_server_url=/heat_waitcondition_server_url = http:\/\/controller:8000\/v1\/waitcondition/" /etc/heat/heat.conf
sed -i "s/#verbose=.*/verbose = True/" /etc/heat/heat.conf

su -s /bin/sh -c "heat-manage db_sync" heat
service heat-api restart
service heat-api-cfn restart
service heat-engine restart

echo -e "\nINSTALLING OPENSTACK CEILOMETER\n"

apt-get install -y mongodb-server mongodb-clients python-pymongo
sed -i "s/bind_ip =.*/bind_ip = 10.0.0.11/" /etc/mongodb.conf
service mongodb stop
rm /var/lib/mongodb/journal/prealloc.*
service mongodb start
service mongodb restart
echo Enter Password For MONGODB
read -s pass9

mongo --host controller --eval "
db = db.getSiblingDB('ceilometer');
db.addUser({user: 'ceilometer',
pwd: "$pass9",
roles: [ 'readWrite', 'dbAdmin' ]})"

source admin-openrc.sh
keystone user-create --name ceilometer --pass $pass9
keystone user-role-add --user ceilometer --tenant service --role admin
keystone service-create --name ceilometer --type metering --description "Telemetry"
keystone endpoint-create --service-id $(keystone service-list | awk '/ metering / {print $2}') --publicurl http://controller:8777 --internalurl http://controller:8777 --adminurl http://controller:8777 --region regionOne

apt-get install -y ceilometer-api ceilometer-collector ceilometer-agent-central ceilometer-agent-notification ceilometer-alarm-evaluator ceilometer-alarm-notifier python-ceilometerclient
sed -i "s/#connection=<None>/connection = mongodb:\/\/ceilometer:$pass9@controller:27017\/ceilometer/" /etc/ceilometer/ceilometer.conf
sed -i "s/#rpc_backend.*/rpc_backend = rabbit/" /etc/ceilometer/ceilometer.conf
sed -i "s/#rabbit_host=.*/rabbit_host = controller/" /etc/ceilometer/ceilometer.conf
sed -i "s/#rabbit_password=.*/rabbit_password=#pass2/" /etc/ceilometer/ceilometer.conf
sed -i "s/#verbose.*/verbose = true/" /etc/ceilometer/ceilometer.conf
sed -i "/verbose = true/a auth_strategy = keystone" /etc/ceilometer/ceilometer.conf
sed -i "s/#auth_uri=<None>/auth_uri = http:\/\/controller:5000\/v2.0/" /etc/ceilometer/ceilometer.conf
sed -i "s/#identity_uri=<None>/identity_uri = http:\/\/controller:35357/" /etc/ceilometer/ceilometer.conf
sed -i "s/#admin_tenant_name=.*/admin_tenant_name = service/" /etc/ceilometer/ceilometer.conf
sed -i "s/#admin_user=.*/admin_user = ceilometer/" /etc/ceilometer/ceilometer.conf
sed -i "s/#admin_password=.*/admin_password = $pass9/" /etc/ceilometer/ceilometer.conf
sed -i "s/#os_auth_url=.*/os_auth_url = http:\/\/controller:5000\/v2.0/" /etc/ceilometer/ceilometer.conf
sed -i "s/#os_username.*/os_username = ceilometer/" /etc/ceilometer/ceilometer.conf
sed -i "s/#os_tenant_name.*/os_tenant_name = service/" /etc/ceilometer/ceilometer.conf
sed -i "s/#os_password=.*/admin_password = $pass9/" /etc/ceilometer/ceilometer.conf


echo "Enter The Metering Secert"
read -s sec
sed -i "s/#metering_secret=.*/metering_secret= $sec/" /etc/ceilometer/ceilometer.conf
service ceilometer-agent-central restart
service ceilometer-agent-notification restart
service ceilometer-api restart
service ceilometer-collector restart
service ceilometer-alarm-evaluator restart
service ceilometer-alarm-notifier restart


echo -e "\nINSTALLING OPENSTACK CINDER\n"

echo Enter Your Cinder Password
read -s pass10
mysql -u root -p$pass1 << EOF
CREATE DATABASE cinder;
GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'localhost' IDENTIFIED BY '$pass10';
GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'%' IDENTIFIED BY '$pass10';
EOF
keystone user-create --name cinder --pass $pass10
keystone user-role-add --user cinder --tenant service --role admin
keystone service-create --name cinder --type volume --description "OpenStack Block Storage"
keystone service-create --name cinderv2 --type volumev2 --description "OpenStack Block Storage"
keystone endpoint-create --service-id $(keystone service-list | awk '/ volume / {print $2}') --publicurl http://controller:8776/v1/%\(tenant_id\)s --internalurl http://controller:8776/v1/%\(tenant_id\)s --adminurl http://controller:8776/v1/%\(tenant_id\)s --region regionOne
keystone endpoint-create --service-id $(keystone service-list | awk '/ volumev2 / {print $2}') --publicurl http://controller:8776/v2/%\(tenant_id\)s --internalurl http://controller:8776/v2/%\(tenant_id\)s --adminurl http://controller:8776/v2/%\(tenant_id\)s --region regionOne

apt-get install -y cinder-api cinder-scheduler python-cinderclient
sed -i "$ a \[database\] \nconnection = mysql:\/\/cinder:$pass10@controller\/cinder" /etc/cinder/cinder.conf
sed -i "/\[DEFAULT\]/a rpc_backend = rabbit\nrabbit_host = controller\nrabbit_password = $pass3\nmy_ip = 10.0.0.11\nverbose = True" /etc/cinder/cinder.conf
sed -i "$ a\[keystone_authtoken\]\nauth_uri = http:\/\/controller:5000\/v2.0\nidentity_uri = http://controller:35357\nadmin_tenant_name = service\nadmin_user = cinder\nadmin_password = $pass10" /etc/cinder/cinder.conf

su -s /bin/sh -c "cinder-manage db sync" 
service cinder-scheduler restart
service cinder-api restart
rm -f /var/lib/cinder/cinder.sqlite

echo -e "\nINSTALLING OPENSTACK SWIFT\n"

source admin-openrc.sh
echo Enter The Swift Password
read -s $pass11
keystone user-create --name swift --pass $pass11
keystone user-role-add --user swift --tenant service --role admin
keystone service-create --name swift --type object-store --description "OpenStack Object Storage"
keystone endpoint-create --service-id $(keystone service-list | awk '/ object-store / {print $2}') --publicurl 'http://controller:8080/v1/AUTH_%(tenant_id)s' --internalurl 'http://controller:8080/v1/AUTH_%(tenant_id)s' --adminurl http://controller:8080 --region regionOne

apt-get install swift swift-proxy python-swiftclient python-keystoneclient python-keystonemiddleware memcached

mkdir /etc/swift

curl -o /etc/swift/proxy-server.conf https://raw.githubusercontent.com/openstack/swift/stable/juno/etc/proxyserver.conf-sample

sed -i "s/# user =/user =/" /etc/swift/proxy-server.conf
sed -i "s/# swift_dir =/swift_dir =/" /etc/swift/proxy-server.conf
sed -i "s/pipeline =.*/pipeline = authtoken cache healthcheck keystoneauth proxy-logging proxy-server/" /etc/swift/proxy-server.conf
sed -i "s/# allow_account_management =.*/allow_account_management = true/" /etc/swift/proxy-server.conf
sed -i "s/# account_autocreate =.*/account_autocreate = true/" /etc/swift/proxy-server.conf
sed -i "s/# use =/use =/" /etc/swift/proxy-server.conf
sed -i "s/# operator_roles =.*/operator_roles = admin,_member_/" /etc/swift/proxy-server.conf
sed -i "s/# paste.filter_factory =/paste.filter_factory =/" /etc/swift/proxy-server.conf
sed -i "s/# auth_uri =.*/auth_uri = http:\/\/controller:5000\/v2.0/" /etc/swift/proxy-server.conf
sed -i "s/# identity_uri =.*/identity_uri = http:\/\/controller:35357/" /etc/swift/proxy-server.conf
sed -i "s/# admin_tenant_name =.*/admin_tenant_name = service/" /etc/swift/proxy-server.conf
sed -i "s/# admin_user =.*/admin_user = swift/" /etc/swift/proxy-server.conf
sed -i "s/# admin_password =.*/admin_password =$pass11/" /etc/swift/proxy-server.conf
sed -i "s/# delay_auth_decision =.*/delay_auth_decision = true/" /etc/swift/proxy-server.conf
sed -i "s/# memcache_servers =/ memcache_servers =/" /etc/swift/proxy-server.conf


echo -e "\nCONFIGURING STORAGE NODE\n"

cd /etc/swift

echo -e "\nEnter The IP Addrees Of Storage Node\n"
read ip
echo -e "Enter Partiton Name\n"
read part

swift-ring-builder account.builder create 10 3 1
swift-ring-builder account.builder add r1z1-$ip:6002/$part 100
swift-ring-builder account.builder
swift-ring-builder account.builder rebalance

swift-ring-builder container.builder create 10 3 1
swift-ring-builder container.builder add r1z1-$ip:6001/$part 100
swift-ring-builder container.builder
swift-ring-builder container.builder rebalance

swift-ring-builder object.builder create 10 3 1
swift-ring-builder object.builder add r1z1-$ip:6000/$part 100
swift-ring-builder object.builder
swift-ring-builder object.builder rebalance


echo -e "\nEnter The code Carefully and insert the same code in storage in all the storage nodes\n"
echo -e "\nEnter Hash Path Suffix\n"
read -s hash1
echo -e "\nEnter Hash Path Prefix\n"
read -s hash2

sed -i "s/swift_hash_path_suffix =.*/swift_hash_path_suffix = $hash1/" /etc/openstack/swift.conf
sed -i "s/swift_hash_path_prefix =.*/swift_hash_path_prefix = $hash2/" /etc/openstack/swift.conf
chown -R swift:swift /etc/swift
service memcached restart
service swift-proxy restart

echo "\nCopy All The Files To The Storage Nodes Which Are Generated On The Your Desktop\n"
cp account.ring.gz container.ring.gz object.ring.gz swift.conf /home/openstack/Desktop/