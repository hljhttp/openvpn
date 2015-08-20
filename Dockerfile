# OpenVPN Server based on https://github.com/kylemanna/docker-openvpn

FROM kylemanna/openvpn

RUN apt-get update && \
	apt-get install -y net-tools vim
