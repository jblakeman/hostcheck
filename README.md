Host Check
==========
Get latency and distance information of players in peer hosted Xbox Live matchmaking.

Developed for Ubuntu or Debian servers routing Xbox Live traffic.	

Features
--------
* Host detection
* Latency measurements to all players (traceroute)
* Address based location lookups for all players
* Distance calculations for all players
* Option to disconnect from host

Additional Software Requirements
--------------------------------
1. conntrack
2. traceroute
3. geoiplookup
4. whois

#### Install Packages

	sudo apt-get install conntrack traceroute geoip-bin whois -y

#### Download GeoLiteCity database

	wget -N http://geolite.maxmind.com/download/geoip/database/GeoLiteCity.dat.gz
	gunzip GeoLiteCity.dat.gz
	mv GeoLiteCity.dat /usr/share/GeoIP/GeoIPCity.dat

Notes
-----
1. Outgoing traceroute requests must not be blocked.
			
2. Xbox IP address must be in private address space as described in [RFC 1918](https://tools.ietf.org/html/rfc1918)
