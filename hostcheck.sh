#!/bin/bash

ipt=$(which iptables)
tracert=$(which traceroute)
conn=$(which conntrack)
ip=$(which ip)
cap=$(which tcpdump)
geo=$(which geoiplookup)
shm=/dev/shm/host
null=/dev/null
g_cap=$shm/g_cap.pcap
g_cap1=$shm/g_cap1.pcap
location=$shm/geo

if [ $EUID -ne 0 ]; then
    printf "This script must be run as root\n"
    exit 1
fi
while read line; do
    if [[ $line == *"src=65.55."* ]]; then
        for re in [a-zA-Z] \[\] \= \_; do
            line=${line//$re/}
        done
        live=($line)
        for i in 0 1 6 7 12 13 14 15; do
            unset live[$i]
        done
        live=(${live[@]})
        break
    fi
done < <($conn -L -p udp 2>$null)
acct=/proc/sys/net/netfilter/nf_conntrack_acct
[ $(< $acct) -ne 1 ] && echo 1 > $acct
d="[0-9]"
track ()
{
    local i
    c_pack=()
    while read line; do
        if [[ $line == *"sport=$xport"* &&
                ! $line == *"src=65.59."* &&
                ! $line == *"src=65.55."* ]]; then
            [[ $line =~ packets=($d+) ]] && c_pack+=(${BASH_REMATCH[1]})
        fi
    done < <($conn -L -p udp 2>$null)
    if [[ $1 == count ]]; then
        players=${#c_pack[@]}
    elif [[ $1 == pack ]]; then
        max_pack=${c_pack[0]}
        for i in ${c_pack[@]/${c_pack[0]}/}; do
            if [ $i -gt $max_pack ]; then
                max_pack=$i
            fi
        done
    fi
}
if ! [[ ${live[0]} ]]; then
    printf "You are not connected to Xbox Live\n"
    exit 1
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
    local i
    for i in ${pids[@]}; do
        if [ -e /proc/$i ]; then
            disown $i
            kill -9 $i
        fi
    done
}
control_c ()
{
    printf "\rScript interrupted\n"
    rm -rf $shm
    proc_kill
    exit 1
}
wheel ()
{
    local arr
    arr=('|' '/' '-' '\ ')
    for i in "${arr[@]}"; do
        printf " $col${green}m%s$end\r" "$i"
        sleep ".15"
    done
}
unban ()
{
    local yn
    read -p "Would you like to unblock The Host after disconnect? (Yy|Nn) " yn
        case $yn in
            [Yy]*)
                { sleep 20 && ip rule del from $xbox to $host blackhole; } &
                pids+=($!)
                ;;
            [Nn]*);;
            *)
                printf "Please answer yes or no.\n"
                unban;;
        esac
}
disconnect ()
{
    local yn
    read -p "Do you wish to disconnect from The Host? (Yy|Nn) " yn
        case $yn in
            [Yy]*)
                ip rule add from $xbox to $host blackhole
                unban;;
            [Nn]*);;
            *)
                printf "Please answer yes or no.\n"
                disconnect;;
        esac
}
wheel2 ()
{
    local arr
    arr=('|>    |' '|=>   |' '|==>  |' '|===> |' '|====>|'\
         '|    <|' '|   <=|' '|  <==|' '| <===|' '|<====|')
    for i in "${arr[@]}"; do
        printf " $col${green}m%s$end\r" "$i"
        sleep ".15"
    done
}
lookup ()
{
    $geo $1 > $location
}
geofind ()
{
    local re
    lookup $1
    re="[-0-9\.]{8,11}"
    while read -a line; do
        if [[ ${line[@]} =~ ($re),\ ($re) ]]; then
            lat=${BASH_REMATCH[1]}
            long=${BASH_REMATCH[2]}
            break
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
    local pi rad d_lat d_long a b
    pi="$(echo "4*a(1)"|bc -l)"
    lat1=$(echo "$lat1*($pi/180)"|bc -l)
    long1=$(echo "$long1*($pi/180)"|bc -l)
    lat2=$(echo "$lat2*($pi/180)"|bc -l)
    long2=$(echo "$long2*($pi/180)"|bc -l)
    rad=$(echo "6371.0072*0.6214"|bc -l)
    d_lat=$(echo "$lat1 - $lat2"|bc -l)
    d_long=$(echo "$long1 - $long2"|bc -l)
    a="$(echo "sqrt(s($d_lat/2)^2+c($lat1)*c($lat2)*s($d_long/2)^2)"|bc -l)"
    b="$(awk -v a=$a 'BEGIN{print 2*atan2(a,sqrt(1-a*a));}')"
    d=$(printf "%1.0f" $(echo "$rad*$b"|bc -l))
}
info ()
{
    printf "\t$col${underline}Country$end: \t${country[$1]}\n"
    printf "\t$col${underline}Region$end: \t${city[$1]}, ${state[$1]}\n"
    printf "\t$col${underline}ISP$end: \t${isp[$1]}\n"
    printf "\t$col${underline}Average RTT$end: \t$col$bold${avg_rtt[$1]}$end ms\n"
    printf "\t$col${underline}Mean RTT Deviation$end: \t$col$bold${jitter[$1]}$end ms\n"
    printf "\t$col${underline}Average speed -> me$end: \t$col$bold${avg_mpm[$1]}$end miles/ms\n"
    printf "\t$col${underline}Total Distance -> Players$end: \t$col$bold${total_dist[$1]}$end miles\n"
}
info_call ()
{
    local n player
    n=1
    for player in ${client[@]}; do
        if [[ $player == $host ]]; then
            printf "\n$col${bold}Host$end\n"
            info $player
        elif [[ $player != $pub_ip ]]; then
            printf "\n$col${bold}Player #$n$end\n\n"
            info $player
            printf "\t$col${underline}Distance -> Host$end: \t$col$bold${host_dist[$player]}$end miles\n"
            ((n++))
        else
            printf "\n$col${underline}Overall RTT Deviation$end: \t$col$bold$avg_jitter$end ms\n"
            printf "$col${underline}Distance -> Host$end: \t$col$bold${host_dist[$player]}$end miles\n"
            printf "$col${underline}Total Distance -> Players$end: \t$col$bold${my_dist}$end miles\n"
            printf "$col${underline}Average Speed -> Players$end: \t$col$bold$avg_avg_mpm$end miles/ms\n"
        fi
    done
}
average ()
{
    local sum a
    sum=0
    for a; do
        sum=$(echo "$a+$sum"|bc -l)
    done
    echo "scale=3; $sum/$#"|bc
}
traceout ()
{
    local trace i
    trace=()
    while read -a line; do
        if [[ ${line[@]} != *"*"* && ${line[@]} != *"!"* ]]; then
            trace=()
            for i in ${line[@]}; do
                if [[ $i =~ $d+\.$d+ && ! $i =~ $d+\.$d+\. ]]; then
                    trace+=($i)
                fi
            done
        fi
    done < <($tracert $player -q 3 -n -f 5 -m 25)
    echo "${trace[@]}"
}
dump_read ()
{
    local i d3 ip
    d3="$d{1,3}"
    ip="$d3\.$d3\.$d3\.$d3"
    while read -a line; do
        for i in ${line[@]}; do
            if [[ $i =~ $ip ]]; then
                if [[ $BASH_REMATCH != $xbox ]]; then
                    echo $BASH_REMATCH
                fi
            fi
        done
        [[ $2 ]] && break
    done < <($cap -n -r $1 2>$null)
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
getData ()
{
    local n i t d player
    my_dist=0
    for player in ${client[@]}; do
        lookup $player
        read t < $shm/$player
        trace_ms[$player]="$t"
        avg_rtt[$player]="$(printf "%1.3f" $(average ${trace_ms[$player]}))"
        diff[$player]="$(for i in ${trace_ms[$player]}; do
                             echo "($i - ${avg_rtt[$player]})^2"|bc
                         done)"
        diff_avg[$player]="$(average ${diff[$player]})"
        jitter[$player]="$(printf "%1.3f" $(echo "sqrt(${diff_avg[$player]})"|bc))"
        n=0
        while IFS=,  read _ land _ ; do
            ((n++))
            if [ $n -eq 1 ]; then
                country[$player]="${land/[[:space:]]/}"
                break
            fi
        done < $location
        city[$player]="$(regions 6)"
        state[$player]="$(regions 7)"
        while read ref org; do
            if [[ ${country[$player]} == "United States" ||
                    ${country[$player]} == "Canada" ]]; then
                if [[ $ref == "CustName:" || $ref == "OrgName:" ]]; then
                    isp[$player]="$org"
                    break
                fi
            elif [[ $ref == "descr:" || $ref == "owner:" ]]; then
                isp[$player]="$org"
                break
            fi
        done < <(whois $player)
        [[ ! ${isp[$player]} ]] && isp[$player]="N/A"
        tudes $pub_ip $player
        haversine
        ((my_dist+=$d))
        avg_mpm[$player]=$(printf "%1.0f" $(echo "($d*2)/${avg_rtt[$player]}"|bc))
        total_d=0
        for l in ${client[@]/$player/} $pub_ip; do
            tudes $l $player
            haversine
            ((total_d+=$d))
        done
        total_dist[$player]=$total_d
    done
    avg_jitter=$(printf "%1.3f" $(average ${jitter[@]}))
    avg_avg_mpm=$(printf "%1.0f" $(average ${avg_mpm[@]}))
    total_dist[$pub_ip]=$dist
    for player in ${client[@]/$host/} $pub_ip; do
        tudes $player $host
        haversine
        host_dist[$player]=$d
    done
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
    green="1;32"
    blackbg="40m"
    underline="4m"
    bold="1m"
    printf "Waiting for Host to be detected\n"
    [ ! -d "$shm" ] && mkdir $shm
    while [ ! -f "$shm/fin1" ]; do
        wheel
    done &
    pids=($!)
    $conn -D -p udp -s $xbox --sport $xport &>$null
    $conn -D -p udp -d $wan_ip --dport $nat_port &>$null
    sleep 15
    track pack
    while [ $max_pack -lt 700 ]; do
        sleep 3
        track pack
    done &
    pids+=($!)
    $cap -c 4 -vvv -i $lan_if udp port $xport and \
        length = 306 or length = 146 and not host 65.55 and \
        not host 65.59 -w $g_cap &> $null &
    pids+=($!)
    wait ${pids[1]}
    track count
    p_num=0
    for i in ${c_pack[@]}; do
        if [ $i -gt 550 ]; then
            ((p_num++))
        fi
    done
    if [ $p_num -gt 0 ]; then
        h_bool=$(echo "${#c_pack[@]}/$p_num <= 1.5"|bc)
        if [ $h_bool -eq 1 ]; then
            printf "You Have Host! Have fun!\n"
            proc_kill
            exit 0
        fi
    fi
    wait ${pids[2]}
    # Capture heartbeat packets to eliminate false positives
    $cap -c 38 -vvv -i $lan_if udp port $xport and length = 66 \
        or length = 68 -w $g_cap1 &> $null
    host=$(dump_read $g_cap 0)
    client=($host $(dump_read $g_cap1|sort -u))
    echo 1 > $shm/fin1  
    wait ${pids[0]}
    rm $shm/fin1
    pub_ip=$(curl -4 icanhazip.com 2>$null)
    tudes $pub_ip
    wan_lat="$lat1"
    wan_long="$long1"
    printf "Performing latency tests using traceroutes\n"
    while [ ! -f "$shm/fin2" ]; do
        wheel2
    done &
    pids+=($!)
    for player in ${client[@]}; do
        traceout > $shm/$player &
        trace_pids+=($!)
    done
    wait ${trace_pids[@]}
    declare -A trace_ms avg_rtt diff diff_avg jitter \
               country city state isp avg_mpm total_dist host_dist
    getData
    echo 1 > $shm/fin2
    wait ${pids[3]}
    rm $shm/fin2
    date_time="$(date +%m-%d-%Y-%H.%M)"
    file="/tmp/hostcheck.$date_time"
    info_call|tee "$file"
    printf "\nA copy of this report is saved at '$file'\n"
    disconnect
else
    printf "Please wait to be matched in a game\n"
    exit 1
fi
exit 0
