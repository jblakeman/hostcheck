#!/bin/bash

IPT=/sbin/iptables
TRACERT=/usr/bin/traceroute
CONN=/usr/sbin/conntrack
IP=/bin/ip
CAP=/usr/sbin/tcpdump
GEO=/usr/bin/geoiplookup
shm=/dev/shm/host
null=/dev/null
game_cap=$shm/game_cap.pcap
game_cap1=$shm/game_cap1.pcap
location=$shm/geo
if [ $EUID -ne 0 ]; then
	printf "\nThis script must be run as root\n\n"
	exit 1
fi
while read line; do
	if [[ $line =~ src=65.55. ]]; then
		live=($(sed 's/\([a-zA-Z]\|\[\|\]\|=\|_\)//g' <<< "$line" ))
		for i in 0 1 6 7 12 13 14 15; do
			unset live[$i]
		done
		live=(${live[@]})
		break
	fi
done < <($CONN -L -p udp 2>$null)
track ()
{
	local i max
	conn_pack=()
	while read -a line; do
		if [[ ${line[@]} =~ sport=3074 ]] && ! [[ ${line[@]} =~ src=65.59. ]] && ! [[ ${line[@]} =~ src=65.55. ]]; then
			for i in ${line[@]}; do
				[[ $i =~ packets=[0-9]+ ]] && conn_pack+=(${BASH_REMATCH:8})
			done
		fi
	done < <($CONN -L -p udp 2>$null)
	[[ $1 == count ]] && players=${#conn_pack[@]}
	[[ $1 == pack ]] && packets=$(max=${conn_pack[0]}
					for i in ${conn_pack[@]/${conn_pack[0]}/}; do
						if [ $i -gt $max ]; then
							max=$i
						fi
					done
					echo $max)
}
if ! [[ ${live[0]} ]]; then
	printf "\nYou are not connected to Xbox Live\n\n"
	exit 0
else
	if [[ ${live[1]} == ${live[4]} ]]; then
		xbox=${live[0]}
		xport=${live[2]}
		wan_ip=${live[5]}
		nat_port=${live[7]}
	else
		xbox=${live[4]}
		xport=${live[6]}
		wan_ip=${live[1]}
		nat_port=${live[3]}

	fi
	track count
fi
proc_kill ()
{
	if [ -e /proc/$1 ]; then
		disown $1
		kill -9 $1
	fi
}
control_c ()
{
	local i
	printf "\r\nScript interrupted\n\n"
	rm -rf $shm
	for i in ${pids[@]}; do
		proc_kill $i
	done
	exit 0
}
wheel ()
{
	printf " $col${green}m|$end\r"; sleep ".15"
	printf " $col${green}m/$end\r"; sleep ".15"
	printf " $col${green}m-$end\r"; sleep ".15"
	printf " $col${green}m\ $end\r"; sleep ".15"
}
unban ()
{
	read -p "Would you like to unblock The Host after disconnect? " yn
		case $yn in
			[Yy]*)
				(sleep 20 && ip rule del from $xbox to $host blackhole) &
				;;
			[Nn]*);;
			*)
				printf "Please answer yes or no.\n"
				unban;;
		esac
}
disconnect ()
{
	read -p "Do you wish to disconnect from The Host? " yn
		case $yn in
			[Yy]*)
				$IPT -I FORWARD -p udp -d $host -m statistic --mode random --probability .2 -j DROP
				printf "\nRandomizing packet loss before disconnect\n\n"
				sleep 7
				ip rule add from $xbox to $host blackhole
				$CONN -D -d $host &>$null
				$IPT -D FORWARD -p udp -d $host -m statistic --mode random --probability .2 -j DROP
				unban;;
			[Nn]*);;
			*)
				printf "Please answer yes or no.\n"
				disconnect;;
		esac
}
wheel2 ()
{
	printf " $col${green}m|>    |$end\r"; sleep ".15"
	printf " $col${green}m|=>   |$end\r"; sleep ".15"
	printf " $col${green}m|==>  |$end\r"; sleep ".15"
	printf " $col${green}m|===> |$end\r"; sleep ".15"
	printf " $col${green}m|====>|$end\r"; sleep ".15"
	printf " $col${green}m|    <|$end\r"; sleep ".15"
	printf " $col${green}m|   <=|$end\r"; sleep ".15"
	printf " $col${green}m|  <==|$end\r"; sleep ".15"
	printf " $col${green}m| <===|$end\r"; sleep ".15"
	printf " $col${green}m|<====|$end\r"; sleep ".15"
}
lookup ()
{
	$GEO $1 > $location
}
geofind ()
{
	local n
	lookup $1
	n=0
	while IFS=,  read -a line; do
		((n++))
		if [ $n -eq 2 ]; then
			lat=${line[$((${#line[@]}-3))]}
			long=${line[$((${#line[@]}-2))]}
		fi
	done < $location
}
tudes ()
{
	if [[ $wan_lat && $wan_long && $1 == $pub_ip ]]; then
		lat1="$wan_lat"
		long1="$wan_long"
	else
		geofind $1
		lat1="$lat"
		long1="$long"
	fi
	if [[ $2 ]]; then
		geofind $2
		lat2="$lat"
		long2="$long"
	fi
}
haversine ()
{
	local rad d_lat d_long a e f c
	lat1=$(echo "$lat1*(3.14159265/180)"|bc -l)
	long1=$(echo "$long1*(3.14159265/180)"|bc -l)
	lat2=$(echo "$lat2*(3.14159265/180)"|bc -l)
	long2=$(echo "$long2*(3.14159265/180)"|bc -l)
	rad=$(echo "6371.0072*0.6214"|bc -l)
	d_lat=$(echo "$lat1 - $lat2"|bc -l)
	d_long=$(echo "$long1 - $long2"|bc -l)
	a=$(echo "s($d_lat/2)^2+c($lat1)*c($lat2)*s($d_long/2)^2"|bc -l)
	e=$(echo "sqrt($a)"|bc -l)
	f=$(echo "sqrt(1 - $a)"|bc -l)
	c=$(awk -v x=$e -v y=$f 'BEGIN{print 2*atan2(x,y);}')
	d=$(printf "%1.0f" $(echo "$rad*$c"|bc -l))
}
info_state ()
{
	printf "\t$col$teal${underline}Country$end: ${country[$p]}\n"
	printf "\t$col$teal${underline}Region$end: ${city[$p]}, ${state[$p]}\n"
	printf "\t$col$teal${underline}Connection$end: ${speed[$p]}\n"
	printf "\t$col$teal${underline}Average RTT$end: $col$bold${avg_rtt[$p]}$end ms\n"
	printf "\t$col$teal${underline}Mean RTT Deviation$end: $col$bold${jitter[$p]}$end ms\n"
	printf "\t$col$teal${underline}Average speed -> me$end: $col$bold${avg_mpm[$p]}$end miles/ms\n"
	printf "\t$col$teal${underline}Total Distance -> Players$end: $col$bold${total_dist[$p]}$end miles\n"
}
info_call ()
{
	for p in ${!client[@]} ${#client[@]}; do
		if [ $p -eq 0 ]; then
			printf "\n\n$col${bold}Host$end\n"
			info_state
		elif [ $p -lt ${#client[@]} ]; then
			printf "\n\n$col${bold}Player #$p$end\n\n"
			info_state
			printf "\t$col$teal${underline}Distance -> Host$end: $col$bold${host_dist[$((p-1))]}$end miles\n"
		else
			printf "\nOverall RTT Deviation: $col$teal$bold$avg_jitter$end ms\n"
			printf "Distance -> Host: $col$teal$bold${host_dist[$((p-1))]}$end miles\n"
			printf "Total Distance -> Players: $col$teal$bold${total_dist[$p]}$end miles\n"
			printf "Average Speed -> Players: $col$teal$bold$avg_avg_mpm$end miles/ms\n"
		fi
	done
}
ip_tracker ()
{
	lynx -dump "http://www.ip-tracker.org/locator/ip-lookup.php?ip=$1"
}
average ()
{
	local sum a
	sum=0
	for a in $@; do
		sum=$(echo "scale=3; $a+$sum"|bc)
	done
	echo "scale=3; $sum/$#"|bc
}
traceout ()
{
	local trace i
	trace=()
	while read -a line; do
		if ! [[ $line =~ "*" ]]; then
			for i in ${line[@]}; do
				if [[ $i =~ [0-9]+\.[0-9]+ ]] && ! [[ $i =~ [0-9]+\.[0-9]+\. ]]; then
					trace+=($i)
				fi
			done
		fi
	done < <($TRACERT $player -q 3 -n -f 5 -m 25)
	echo "${trace[$((${#trace[@]}-1))]} ${trace[$((${#trace[@]}-2))]} ${trace[$((${#trace[@]}-3))]}"
}
dump_read ()
{
	local i
	while read -a line; do
		for i in ${line[@]}; do
			if [[ $i =~ [0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3} ]]; then
				if [[ $BASH_REMATCH != $xbox ]]; then
					echo $BASH_REMATCH
				fi
			fi
		done
		[[ $2 ]] && break
	done < <($CAP -n -r $1 2>$null)
}
regions ()
{
	local n
	n=0
	while IFS=,  read -a reg; do
		((n++))
		if [ $n -eq 2 ]; then
			echo ${reg[$((${#reg[@]}-$1))]}
			break
		fi
	done < $location
}
if [ $players -gt 0 ]; then
	trap control_c SIGINT
	while IFS=. read f1 f2 f3 _; do
		lan_sub="$f1.$f2.$f3"
	done <<< "$xbox"
	while read line; do
		if [[ $line =~ $lan_sub ]]; then
  			read _ lan_if _ <<< "$line"
		fi
	done < <(ip -o addr show)
	col="\x1b["
	end="\x1b[0m"
	teal="1;36"
	green="1;32"
	blackbg="40m"
	underline="4m"
	bold="1m"
	printf "Waiting for Host to be detected\n\n"
	[ ! -d "$shm" ] && mkdir $shm
	while [ ! -f "$shm/fin1" ]; do
		wheel
	done &
	pids=($!)
	$CONN -D -p udp -s $xbox --sport $xport &>$null
	$CONN -D -p udp -d $wan_ip --dport $nat_port &>$null
	sleep 15
	while [ $(track pack; echo $packets) -lt 800 ]; do
		sleep 3
	done &
	pids+=($!)
	$CAP -c 4 -vvv -i $lan_if udp port $xport and length = 306 or length = 146 and not host 65.55 and not host 65.59 -w $game_cap &> $null &
	pids+=($!)
	wait ${pids[1]}
	track count
	pack_num=0
	for i in ${conn_pack[@]}; do
		if [ $i -gt 550 ]; then
			((pack_num+=1))
		fi
	done
	if [ $pack_num -gt 0 ]; then
		host_bool=$(echo "$players/$pack_num <= 1.5"|bc)
		if [ $host_bool -eq 1 ]; then
			printf "You Have Host!\n\nHave fun!\n\n"
			$CONN -D -p udp -s $xbox &> $null
			control_c
			exit 0
		fi
	fi
	wait ${pids[2]}
	$CAP -c 38 -vvv -i $lan_if udp port $xport and length = 66 or length = 68 -w $game_cap1 &> $null
	host=$(dump_read $game_cap 0)
	client=($host $(dump_read $game_cap1|sort -u))
	echo 1 > $shm/fin1	
	wait ${pids[0]}
	rm $shm/fin1
	read pub_ip _ < <(lynx -dump icanhazip.com)
	tudes $pub_ip
	wan_lat="$lat1"
	wan_long="$long1"
	printf "Performing latency measurements\n\n"
	while [ ! -f "$shm/fin2" ]; do
		wheel2
	done &
	pids+=($!)
	for player in ${client[@]}; do
		traceout > $shm/$player &
		trace_pids+=($!)
	done
	wait ${trace_pids[@]}
	for i in ${!client[@]}; do
		read t < $shm/${client[$i]}
		trace_ms[$i]=$t
	done
	seq_num=0
	for player in ${client[@]}; do
		lookup $player
		avg_rtt+=($(printf "%1.3f" $(average ${trace_ms[$seq_num]})))
		diff+=("$(for i in ${trace_ms[$seq_num]}; do
				echo "($i - ${avg_rtt[$seq_num]})^2"|bc
			done)")
		diff_avg+=($(average ${diff[$seq_num]}))
		jitter+=($(printf "%1.3f" $(echo "sqrt(${diff_avg[$seq_num]})"|bc)))
		n=0
		while IFS=,  read _ land _ ; do
			((n++))
			if [ $n -eq 1 ]; then
				country+=("$land")
				break
			fi
		done < $location
		state+=("$(regions 7)")
		city+=("$(regions 6)")
		while read line; do
			if [[ $line =~ Address\ Speed ]]; then
				while IFS=: read _ fast _; do
					speed+=("$fast")
				done <<< "$line"
				break
			fi
		done < <(ip_tracker $player)
		if [[ ${country[$seq_num]} == "Address not found" ]]; then
			while read line; do
				if [[ $line =~ Country: ]]; then
					read -a c <<< "$line"
					for i in ${c[@]}; do
						if ! [[ $i =~ : || $i =~ \[\] || $i =~ \(\) ]]; then
							land+=($i)
						fi
					done
					break
				fi
			done < <(ip_tracker $player)
			country[$seq_num]=${land[@]}
		fi
		tudes $pub_ip $player
		haversine
		my_dist+=($d)
		avg_mpm+=($(printf "%1.0f" $(echo "($d*2)/${avg_rtt[$seq_num]}"|bc)))
		total_d=0
		for l in ${client[@]/$player/} $pub_ip; do
			tudes $l $player
			haversine
			((total_d+=$d))
		done
		total_dist+=($total_d)
		((seq_num++))
	done
	avg_jitter=$(printf "%1.3f" $(average ${jitter[@]}))
	avg_avg_mpm=$(printf "%1.0f" $(average ${avg_mpm[@]}))
	for n in ${my_dist[@]}; do
		((dist+=$n))
	done
	total_dist+=($dist)
	for i in ${client[@]/$host/} $pub_ip; do
		tudes $i $host
		haversine
		host_dist+=($d)
	done
	echo 1 > $shm/fin2
	wait ${pids[3]}
	rm $shm/fin2
	date_time="$(date +%m-%d-%Y-%H.%M)"
	file="/tmp/hostcheck.$date_time"
	info_call|tee "$file"
	printf "\nA copy of this report is saved at '$file'\n\n"
	disconnect
else
	printf "\nPlease wait to be matched in a game\n\n"
fi
exit
