# moovel OpenVPN
## Introduction
The purpose of this repository is to provide tools and instructions to setup an OpenVPN server in an AWS VPC. This OpenVPN Server can connect clients to the VPC. Clients typically are developer notebooks (roadwarriors). The solution could however also be used to connect an entire network with the VPC.

Note that the following instructions are based on this [tutorial](https://www.digitalocean.com/community/tutorials/how-to-run-openvpn-in-a-docker-container-on-ubuntu-14-04). This document also contains information on how to setup the client on Windows, Linux or Mac.

## Installation AWS
[Cloudformation](https://aws.amazon.com/de/cloudformation) is used to setup the OpenVPN server. In the directory _deploy_ execute the following command:

```
./infrastructure.sh start
```

This script will start a cloudformation stack described by the file _cloudformation.json_. Note that it can be configured using environment variables described at the beginning of the script. The following resources are created:
- _Elastic IP_ that allows to address the OpenVPN server through DNS (e.g. Route 53)
- _AutoScalingGroup_ that ensures that exactly one OpenVPN server is running (i.e. it is restarted after crash)
- Security Group that allows incoming OpenVPN and SSH traffic
- IAM Role and Policies required by the server to run

At boot time of the OpenVPN EC2 instance the following steps are performed:
1. the instance is associated with the _Elastic IP_
2. The OpenVPN configuration and certificates are loaded from an S3 bucket
3. Configurations are written based on the network topology
4. a [Consul](https://www.consul.io/) agent [docker](https://www.docker.com/) container is started that joins a consul cluster
5. a OpenVPN docker container is started

## Installation non-AWS
in non AWS environments, you don't need consul, nor cloudformation to run the docker container.
However, you have to make sure, that the S3 Bucket is mapped via S3 Port mapping. Reading only suffices, as no write is required.
OpenVPN initialisation and PKI management should be retrieved via the S3 Bucket.

The image being used is now: [mrbobbytables/openvpn-ldap](https://hub.docker.com/r/mrbobbytables/openvpn-ldap/) as it uses natively PAM and LDAP for authorisation.

## Configuration of the Consul Agent
For the Consul Agent to work it must be able to communicate to the Consul Servers. This is ensured by the tag _consul-cluster_ that all consul servers and agents have in common. It is defined in the _AutoScalingGroup_ section of the _cloudformation.json_ file.

## Initial OpenVPN configuration
For an initial creation of the configuration files decide under which [FQDN](https://en.wikipedia.org/wiki/Fully_qualified_domain_name) the OpenVPN server should be reachable and initialize the OpenVPN configuration files in _/etc/openvpn_. Execute the following command on the server:

```
sudo docker run -v /etc/openvpn:/etc/openvpn --rm moovel/openvpn ovpn_genconfig -u udp://openvpn.dev.moovel-app.com:1194
mv /etc/openvpn/openvpn.conf /etc/openvpn/openvpn.conf.template
```

Note that the command above uses _openvpn.dev.moovel-app.com_ as FQDN. All dhcp _push_ commands should be removed from the _openvpn.conf.template_ file.
The office VPN should use: _stuttgart.office.moovel.com_ as FQDN.

### Generate the EasyRSA PKI certificate authority
Execute the following command on the server to generate the server certificates (only do that once, per server):

```
sudo docker run -v /etc/openvpn:/etc/openvpn --rm -it moovel/openvpn ovpn_initpki
```

## Configuration of the OpenVPN Server
A current limitation of the cloudformation is the fact that the default security group of the VPC must be added manually to the EC2 instance after starting the stack.

The actual OpenVPN configuration is located in a file _openvpn.tgz_ that is downloaded from an S3 bucket. The name of the bucket is defined in the _LauchConfiguration_ section of the _cloudformation.json_ file. The contents of the archive is the folder _/etc/openvpn_.

### Define the IP range of the clients
The folder contains the file _/etc/openvpn/openvpn.conf.template_. In the _server_ option in this file make sure that the CIDR is not part of the target VPC's CIDR and that it is not yet in use for your local network: This IPs of the OpenVPN clients will be taken from this range.

### Configure paths to the certificate files
Make sure that the options _key_, _ca_, _cert_ and _dh_ point to existing files. Note that the path contains the FQDN that was selected above.

## Generate client certificates
Each client will need a dedicated certificate to connect to the OpenVPN server. Note that reusing a single certificate on two clients will give errors! The certificates can be embedded in a _.ovpn_ file that can be imported into the client's OpenVPN software.

First generate the required certificates for the user in the folder _/etc/openvpn_. Note that _Max Muster_ is used as an example for the username.

```
sudo docker run -v /etc/openvpn:/etc/openvpn --rm -it moovel/openvpn easyrsa build-client-full max.muster nopass
```

Then export the file into an _.ovpn_ file that can be passed to the user:

```
sudo docker run -v /etc/openvpn:/etc/openvpn --rm moovel/openvpn ovpn_getclient max.muster > max.muster.ovpn
```

## Limitations
The current solution performs a [Network Address Translation (NAT)](https://de.wikipedia.org/wiki/Network_Address_Translation) of the clients IP address. This means that the clients can connect to services in the VPC but not vice versa. The instantiation of an EC2 instance that acts as a forwarding proxy could however be used as a workaround.
