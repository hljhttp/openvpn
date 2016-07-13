# OpenVPN Server based on https://hub.docker.com/r/mrbobbytables/openvpn-ldap/
# New Image is then moovel/openvpn-ldap

FROM mrbobbytables/openvpn-ldap

RUN apt-get update && \
	apt-get install -y net-tools vim
