#!/bin/bash

#This script Install all the component required to build compute node
#----->Please run this script under adminstrative rights<-----
#This script install compute,ceilometer,swift and cinder


echo -e "\nCONGIGURING THE CONTROLLER NETWORK\n"

echo -e "\nENABLING OPENSTACK REPOSITORY\n"
apt-get update
apt-get install ubuntu-cloud-keyring
echo "deb http://ubuntu-cloud.archive.canonical.com/ubuntu" \
"trusty-updates/juno main" > /etc/apt/sources.list.d/#cloudarchive-juno.list
apt-get update

sed -i '$ a\\n#The Primary Network\n\nauto eth0\niface eth0 inet static\naddress 10.0.0.31\nnetmask 255.255.255.0\ngateway 10.0.0.1' /etc/network/interfaces
sed -i 's/false/true/' /etc/NetworkManager/NetworkManager.conf
service network-manager restart
sed -i 's/127.0.0.1/#127.0.0.1/' /etc/hosts
sed -i 's/127.0.1.1/#127.0.1.1/' /etc/hosts
sed -i '/ubuntu/a 10.0.0.11 controller' /etc/hosts
sed -i '/controller/a 10.0.0.31 compute1' /etc/hosts
sed -i '/compute1/a 10.0.0.41 block1' /etc/hosts
sed -i '/block1/a 10.0.0.51 object1' /etc/hosts
sed '/.*/d' /etc/hostname
sed -i 's/.*/compute1/' /etc/hostname


echo -e "\nINSTALLING NTP SERVICE\n"
apt-get install -y ntp
sed -i "s/server 0/#server 0/" /etc/ntp.conf
sed -i "s/server 1/#server 1/" /etc/ntp.conf
sed -i "s/server 2/#server 2/" /etc/ntp.conf
sed -i "s/server 3.*/server controller iburst/" /etc/ntp.conf
service ntp restart

apt-get install -y nova-compute sysfsutils
echo Enter The Rabbitmq Password
read -s pass1
sed -i "/\[DEFAULT\]/a rpc_backend = rabbit\nrabbit_host = controller\nrabbit_password = $pass1\nauth_strategy = keystone" /etc/nova/nova.conf

echo Enter The Nova Password
read -s pass2
sed -i "$ a [keystone_authtoken]\nauth_uri = http://controller:5000/v2.0\nidentity_uri = http://controller:35357\nadmin_tenant_name = service\nadmin_user = nova\nadmin_password = $pass2" /etc/nova/nova.conf
sed -i "/\[DEFAULT\]/a my_ip = 10.0.0.31\nvnc_enabled = True\nvncserver_listen = 0.0.0.0\nvncserver_proxyclient_address = 10.0.0.31\nnovncproxy_base_url = http://controller:6080/vnc_auto.html" /etc/nova/nova.conf
sed -i "$ a [glance]\nhost = controller" /etc/nova/nova.conf
val=$(egrep -c '(vmx|svm)' /proc/cpuinfo)
if [ $val=0 ]
then
  sed -i "s/virt_type=.*/virt_type = qemu/" /etc/nova/nova-compute.conf
fi
service nova-compute restart
rm -f /var/lib/nova/nova.sqlite


echo -e "\nCONFIGURING NETWORKING\n"
 
apt-get install -y nova-network nova-api-metadata
sed -i "/\[DEFAULT\]/a network_api_class = nova.network.api.API\nsecurity_group_api = nova\nfirewall_driver = nova.virt.libvirt.firewall.IptablesFirewallDriver\nnetwork_manager = nova.network.manager.FlatDHCPManager\nnetwork_size = 254\nallow_same_net_traffic = False\nmulti_host = True\nsend_arp_for_ha = True\nshare_dhcp_address = True\nflat_network_bridge = br100\nflat_interface = eth0\npublic_interface = eth0" /etc/nova/nova.conf
service nova-network restart
service nova-api-metadata restart


apt-get install -y ceilometer-agent-compute
echo Enter The Metering Sceret
read -s pass3
sed -i "s/#metering_secret.*/metering_secret=$pass3/" /etc/ceilometer/ceilometer.conf
sed -i "s/#rabbit_host=.*/rabbit_host=controller/" /etc/ceilometer/ceilometer.conf
sed -i "s/#rabbit_password=.*/rabbit_password=$pass1/" /etc/ceilometer/ceilometer.conf
sed -i "s/#auth_uri=<None>/auth_uri = http:\/\/controller:5000\/v2.0/" /etc/ceilometer/ceilometer.conf
sed -i "s/#identity_uri=<None>/identity_uri = http:\/\/controller:35357/" /etc/ceilometer/ceilometer.conf
sed -i "s/#admin_tenant_name.*/admin_tenant_name = service/" /etc/ceilometer/ceilometer.conf
sed -i "s/#admin_user.*/admin_user = ceilometer/" /etc/ceilometer/ceilometer.conf
echo Enter Ceilometer Password
read -s cel
sed -i "s/#admin_password.*/admin_password = $cel/" /etc/ceilometer/ceilometer.conf
sed -i "s/#os_auth_url=.*/os_auth_url = http:\/\/controller:5000\/v2.0/" /etc/ceilometer/ceilometer.conf
sed -i "s/#os_username=.*/os_username = ceilometer/" /etc/ceilometer/ceilometer.conf
sed -i "s/#os_tenant_name.*/os_tenant_name = service/" /etc/ceilometer/ceilometer.conf
sed -i "s/#os_password.*/os_password = $cel/" /etc/ceilometer/ceilometer.conf
sed -i "s/#os_endpoint_type.*/os_endpoint_type = internalURL/" /etc/ceilometer/ceilometer.conf
sed -i "s/#os_region_name.*/os_region_name = regionOne/" /etc/ceilometer/ceilometer.conf
sed -i "s/#verbose=.*/verbose = true/" /etc/ceilometer/ceilometer.conf
sed -i "s/#notification_driver=/notification_driver = messagingv2/" /etc/ceilometer/ceilometer.conf
sed -i "/\[DEFAULT\]/a instance_usage_audit = True\ninstance_usage_audit_period = hour\nnotify_on_state_change = vm_and_task_state" /etc/ceilometer/ceilometer.conf

service nova-compute restart
service ceilometer-agent-compute restart