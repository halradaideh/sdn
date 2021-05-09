#!/bin/bash -

set -e

function isinstalled {
  if yum list installed "$@" >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

function isactive {
  if systemctl is-active "$@" >/dev/null 2>&1; then
    echo "$@ IS ON"
  else
    systemctl start "$@"
  fi
}

yum update -y && yum -y upgrade
yum install -y subscription-manager
yum group install -y "Development Tools"
yum install -y make gcc openssl-devel rpm-build yum-utils wget ant wget java-1.8.0-openjdk net-tools

echo "=== INSTALLING OVS DEPENDENCIES ==="
yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
yum install -y centos-release-openstack-ussuri
dnf config-manager --set-enabled powertools
if [ $? -ne 0 ]; then
    echo "FAILED TO DOWNLOAD OVS DEPENDENCIES"
    exit 1
fi

yum -y upgrade

if isinstalled "openvswitch"; then
    echo "=== OVS IS ALREADY INSTALLED"
else
    echo "=== INSTALLING OVS ==="
    output=$(yum install -y libibverbs openvswitch)
    if [ $? -ne 0 ]; then
        echo "FAILED TO INSTALL OVS : ${output}"
        exit 1
    fi
fi

echo "=== TURNING ON OVS ==="
isactive "openvswitch"

systemctl enable --now openvswitch

echo "=== CHECKING OVS VERSION ==="
output=$(ovs-vsctl show)
if [ $? -ne 0 ]; then
    echo "NEED TO CHANGE PATH FOR OVS : ${output}"
    exit 1
fi

yum-config-manager \
    --add-repo \
    https://download.docker.com/linux/centos/docker-ce.repo

if isinstalled "docker"; then
    echo "=== DOCKER IS ALREADY INSTALLED"
else
    echo "=== INSTALLING DOCKER ==="
    output=$(yum install -y docker-ce docker-ce-cli containerd.io)
    if [ $? -ne 0 ]; then
        echo "FAILED TO INSTALL DOCKER : ${output}"
        exit 1
    fi
fi

echo "=== TURNING ON DOCKER ==="
isactive "docker"

echo "=== CHECKING DOCKER DAEMON ==="
output=$(docker ps)
if [ $? -ne 0 ]; then
    echo "FAILED TO SHOW DOCKER INFORMATION : ${output}"
    exit 1
fi

systemctl enable docker

echo "=== INSTALLING OVS-DOCKER ==="
pushd /usr/bin
wget https://raw.githubusercontent.com/openvswitch/ovs/master/utilities/ovs-docker
if [ $? -ne 0 ]; then
    echo "FAILED TO GET OVS-DOCKER UTILITY"
    exit 1
fi
chmod a+rwx ovs-docker
popd

echo "=== CHECKING OVS-DOCKER ==="
output=$(ls /usr/bin | grep ovs-docker)
if [ -z "${output}" ]; then
    echo "FAILED TO INSTALL OVS-DOCKER"
    exit 1
fi

echo "=== INSTALLING FloodLight ==="
if [ ! -d "/opt/floodlight" ]
then
  git clone --branch v1.2 git://github.com/floodlight/floodlight.git /opt/floodlight
  pushd /opt/floodlight
  ant
  if [ -z "${output}" ]; then
      echo "FAILED TO INSTALL OVS-DOCKER"
      exit 1
  fi
  popd
  useradd floodlight
  echo 'export JAVA_HOME=/usr/lib/jvm/jre-openjdk' >> /home/floodlight/.bash_profile
fi

mkdir -p /var/lib/floodlight
mkdir -p /etc/floodlight
mkdir -p /var/log/floodlight/

chown -R floodlight:floodlight /opt/floodlight
chown -R floodlight:floodlight /var/lib/floodlight
chown -R floodlight:floodlight /var/log/floodlight
chown -R floodlight:floodlight /etc/floodlight

usermod -s /sbin/nologin floodlight

cat <<EOT > /opt/floodlight/logback.xml
<configuration scan="true">
<appender name="FILE" class="ch.qos.logback.core.FileAppender">
<file>/var/log/floodlight/floodlight.log</file>
<encoder>
<pattern>%date %level [%thread] %logger{10} [%file:%line] %msg%n</pattern>
</encoder>
</appender>
<root level="INFO">
<appender-ref ref="FILE" />
</root>
<logger name="org" level="WARN"/>
<logger name="LogService" level="WARN"/> <!-- Restlet access logging -->
<logger name="net.floodlightcontroller" level="INFO"/>
<logger name="net.floodlightcontroller.logging" level="WARN"/>
</configuration>
EOT

cat <<EOT > /etc/systemd/system/floodlight.service
[Unit]
Description=FloodLight Service
After=network.target
[Service]
EnvironmentFile=/etc/sysconfig/floodlight
User=floodlight
WorkingDirectory=/etc/floodlight
ExecStart=/usr/bin/java -Dlogback.configurationFile=/opt/floodlight/logback.xml -jar  /opt/floodlight/target/floodlight.jar -cf /opt/floodlight/src/main/resources/floodlightdefault.properties
Restart=on-abort
[Install]
WantedBy=multi-user.target
EOT

cat <<EOT > /etc/sysconfig/floodlight
JAVA_HOME=/usr/lib/jvm/jre-openjdk
EOT

systemctl start floodlight.service
isactive "floodlight.service"
systemctl enable floodlight.service


echo "=== Configure OVS ==="

echo "=== Create Bridge ==="
sudo ovs-vsctl add-br ovs-br1 || true
sudo ovs-vsctl set bridge ovs-br1 protocols=OpenFlow10,OpenFlow11,OpenFlow12,OpenFlow13
sudo ovs-vsctl show

echo "=== NAT mode: Configure the internal IP ==="
sudo ifconfig ovs-br1 192.168.0.1 netmask 255.255.0.0 up
ifconfig ovs-br1

echo "=== Configure Firewall to aredirect all connections from ovs-br1 through eth0 as NAT ==="

export pubintf=eth0
export privateintf=ovs-br1
sudo iptables -t nat -A POSTROUTING -o $pubintf -j MASQUERADE
sudo iptables -A FORWARD -i $privateintf -j ACCEPT
sudo iptables -A FORWARD -i $privateintf -o $pubintf -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -S

echo "=== create two containers for DEMO ==="
sudo docker run -d --name=container1 --net=none nginx
sudo docker run -d --name=container2 --net=none nginx

sudo ovs-docker add-port ovs-br1 eth0 container1 --ipaddress=192.168.1.1/16 --gateway=192.168.0.1
sudo ovs-docker add-port ovs-br1 eth0 container2 --ipaddress=192.168.1.2/16 --gateway=192.168.0.1

echo "=== Connect controller to OVS bridge ==="
HOST_IP=$(ifconfig eth1 | awk '/inet / {print $2}')
sudo ovs-vsctl set-controller ovs-br1 tcp:${HOST_IP}:6653

echo "=== list all ovs bridge port ==="

sudo ovs-vsctl list-ports ovs-br1

echo "=== ping through contianers to create flow entry ( auto-generated ) ==="
sudo docker exec container1 curl 192.168.1.2

echo "=== BOOTSTRAP COMPLETED SUCCESSFULLY! ==="

echo -e "\nYou can Access floodlight controller on \n\t${HOST_IP}:8080/ui/index.html"

exit 0