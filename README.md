Host Check
==========
Get latency and distance information of players in peer hosted Xbox Live matchmaking.

Developed for Linux Servers (Debian based) routing Xbox Live traffic.	

Tested using Ubuntu and Debian, but should work on other Linux distros with some slight modifications.

For guides on how to turn machines running Ubuntu into routers, [use google](https://www.google.com/#q=ubuntu+as+a+router).

Features
--------
* Host detection
* Latency measurements to all players (traceroute)
* Address based location lookups for all players
* Distance calculations to host and between all players
* Option to disconnect from host

Additional Software Requirements
--------------------------------
1. tcpdump
2. conntrack
3. traceroute
4. lynx
5. geoiplookup

#### Install

	sudo apt-get install tcpdump conntrack traceroute lynx geoip-bin -y

#### Download, extract and move GeoLiteCity database

	wget -N http://geolite.maxmind.com/download/geoip/database/GeoLiteCity.dat.gz
	gunzip GeoLiteCity.dat.gz
	mv GeoLiteCity.dat /usr/share/GeoIP/GeoIPCity.dat

Notes
-----
1. Outgoing traceroute requests must not be blocked.
			
2. Xbox IP address must be a private address as described in [RFC 1918](https://tools.ietf.org/html/rfc1918)
