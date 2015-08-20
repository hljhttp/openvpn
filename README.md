# moovel OpenVPN

## Introduction
The purpose of this repository is to provide tools and instructions to setup an OpenVPN server in an AWS VPC.
This OpenVPN Server can connect clients to the VPC.
Clients typically are developer notebooks (roadwarriors).
The solution could however also be used to connect an entire network with the VPC.

Note that the following instructions are based on this 
[tutorial](https://www.digitalocean.com/community/tutorials/how-to-run-openvpn-in-a-docker-container-on-ubuntu-14-04).
This document also contains information on how to setup the client on Windows, Linux or Mac. 

## Installation

### Create EC2 instance
The OpenVPN server will be installed on an EC2 instance that is located in one of the subnets of the target VPC.
The EC2 console can be used to launch the instance.

* Select the current _Amazon Linux AMI_ (e.g. _Amazon Linux AMI 2015.03 (HVM), SSD Volume Type - ami-a10897d6_)
* Select _t2.small_ as instance type and click _Configure Instance Details_
* Select the appropriate VPC, check _Protect against accidental termination_ and click _Add Storage_
* Leave default and click _Tag Instance_
* As _Name_ select _OpenVPN_ and click _Configure Security Group_
* Add a Custom UDP rule to allow traffic from _0.0.0.0/0_ to port 1194 and store the security group under the name _OpenVPN_
* Preview and Launch the instance
* Add the _default VPC security group_ to the instance (EC2 table -> Context Menu -> Networking -> Change Security Groups)

### Install and start docker
Connect to the instance through ssh and execute the following commands:

```
ssh ec2-user@public-ip-of-the-instance
yum -y install docker
service docker start
```

### Initialize the configuration files
Decide under which [FQDN](https://en.wikipedia.org/wiki/Fully_qualified_domain_name) the OpenVPN server should
be reachable and initialize the OpenVPN configuration files in _/etc/openvpn_.
Execute the following command on the server:

```
docker run -v /etc/openvpn:/etc/openvpn --rm moovel/openvpn ovpn_genconfig -u udp://openvpn.dev.moovel-app.com:1194
```

Note that the command above uses _openvpn.dev.moovel-app.com_ as FQDN.

### Generate the EasyRSA PKI certificate authority

Execute the following command on the server to generate the server certificates:

```
docker run -v /etc/openvpn:/etc/openvpn --rm -it moovel/openvpn ovpn_initpki
```
 
### Configure the OpenVPN server

The OpenVPN server is configured with the file _/etc/openvpn/openvpn.conf_.
A template is located in this repository and can be copied to the server:

```
scp openvpn.conf ec2-user@public-ip-of-the-instance:/etc/openvpn
```

#### Define the IP range of the clients
In the _server_ option make sure that the CIDR is not part of the target VPC's CIDR and that it is not yet in use for your local network:
This IPs of the OpenVPN clients will be taken from this range.

#### Configure paths to the certificate files
Make sure that the options _key_, _ca_, _cert_ and _dh_ point to existing files.
Note that the path contains the FQDN that was selected above.
  
#### Configure the DNS-Server
Change the IP address in the line _push "dhcp-option DNS 172.31.0.2"_ to the correct DNS server.
The IP address can be identified by executing the following command on the server:

```
cat /etc/resolv.conf | grep nameserver | head -1 | awk '{print $2}'
```
#### Configure the routes to push to the client
The routes to the subnets that are associated with the VPC must be pushed to the routing table of the client.
Adjust the entries to the subnets of the target VPC.
 
### Install startup script
Copy the file _docker-openvpn.conf_ into the folder _/etc/init_ using scp.
Execute the following command locally:

```
scp docker-openvpn.conf ec2-user@public-ip-of-the-instance:/etc/init
```

### Start the server
The server can be started with the command

```
start docker-openvpn
```

### Setup Network Address Translation
The following NAT rule is necessary to route the OpenVPN traffic through the VPN.
Execute this statement on the OpenVPN server:

```
iptables -t nat -A POSTROUTING -s 172.20.0.0/20 -o eth0 -j MASQUERADE
```

Note that the network _172.20.0.0/20_ must be the same as specified in the 
_server_ section of the file _/etc/openvpn/openvpn.conf_ 

## Generate client certificates
Each client will need a dedicated certificate to connect to the OpenVPN server.
Note that reusing a single certificate on two clients will give errors!
The certificates can be embedded in a _.ovpn_ file that can be imported into the client's OpenVPN software.

First generate the required certificates for the user in the folder _/etc/openvpn_.
Note that _Max Muster_ is used as an example for the username.

```
docker run -v /etc/openvpn:/etc/openvpn --rm -it moovel/openvpn easyrsa build-client-full max.muster nopass
```

Then export the file into an _.ovpn_ file that can be passed to the user:

```
docker run -v /etc/openvpn:/etc/openvpn --rm moovel/openvpn ovpn_getclient max.muster > max.muster.ovpn
```

## Limitations
The current solution performs a [Network Address Translation (NAT)](https://de.wikipedia.org/wiki/Network_Address_Translation)
of the clients IP address. This means that the clients can connect to services in the VPC but not vice versa.
The instantiation of an EC2 instance that acts as a forwarding proxy could however be used as a workaround.
