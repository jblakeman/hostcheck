#!/bin/bash

ipt=$(which iptables)
tracert=$(which traceroute)
conn=$(which conntrack)
ip=$(which ip)
cap=$(which tcpdump)
geo=$(which geoiplookup)
shm=/dev/shm/host
null=/dev/null
host_cap=$shm/h.pcap
client_cap=$shm/c.pcap

if [ $EUID -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

# Find Xbox Live connection track
while read -r line; do
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

# Enable conntrack packet counter 
acct=/proc/sys/net/netfilter/nf_conntrack_acct
if [ $(< $acct) -ne 1 ]; then
    echo 1 > $acct
    echo "Enabling netfilter's packet counter"
    conntrack -D -p udp
    sleep 3
fi

d="[0-9]"
track ()
{
    # Count packets of players
    local i
    c_pack=()
    while read -r line; do
        # Don't count packets with Xbox Live IP ranges
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
    echo "You are not connected to Xbox Live"
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
procKill ()
{
    local i
    for i; do
        if [ -e /proc/$i ]; then
            disown $i
            kill -9 $i
        fi
    done
}
controlC ()
{
    echo -e "\rScript interrupted"
    rm -rf $shm
    procKill ${pids[@]}
    exit 1
}
finishedBG ()
{
    # Signal end of process by creating file in shared memory

    local shared
    shared=$shm/$1
    echo 1 > $shared
    wait $2
    rm $shared
}
wheel ()
{
    local i
    for i; do
        printf " $col${green}m%s$end\r" "$i"
        sleep ".15"
    done
}
yorn="Please answer yes or no"
unban ()
{
    local yn
    read -p "Unblock Host after disconnect? (Yy|Nn) " yn
        case $yn in
            [Yy]*)
                { sleep 20 && ip rule del from $xbox to $host blackhole; } &
                pids+=($!)
                ;;
            [Nn]*);;
            *)
                echo "$yorn"
                unban;;
        esac
}
disconnect ()
{
    local yn
    read -p "Disconnect from Host? (Yy|Nn) " yn
        case $yn in
            [Yy]*)
                ip rule add from $xbox to $host blackhole
                unban;;
            [Nn]*);;
            *)
                echo "$yorn"
                disconnect;;
        esac
}
haversine ()
{
    # Find distance between two points on the globe

    local pi rad d_lat d_long a b
    pi=$(echo "4*a(1)"|bc -l)
    radians=$(echo "$pi/180"|bc -l)
    lat1=$(echo "${lat[$1]}*$radians"|bc -l)
    long1=$(echo "${long[$1]}*$radians"|bc -l)
    lat2=$(echo "${lat[$2]}*$radians"|bc -l)
    long2=$(echo "${long[$2]}*$radians"|bc -l)
    rad=$(echo "6371.0072*0.6214"|bc -l)
    d_lat=$(echo "$lat1 - $lat2"|bc -l)
    d_long=$(echo "$long1 - $long2"|bc -l)
    a="$(echo "sqrt(s($d_lat/2)^2+c($lat1)*c($lat2)*s($d_long/2)^2)"|bc -l)"
    b="$(awk -v a=$a 'BEGIN{print 2*atan2(a,sqrt(1-a*a));}')"
    dist=$(printf "%1.0f" $(echo "$rad*$b"|bc -l))
}
info ()
{
    echo -e "\t$col${underline}Country$end:           ${country[$1]}"
    echo -e "\t$col${underline}Region$end:            ${city[$1]}, ${state[$1]}"
    echo -e "\t$col${underline}Provider$end:          ${isp[$1]}"
    echo -e "\t$col${underline}Average Ping$end:      ${avg_rtt[$1]} ms"
    echo -e "\t$col${underline}Ping Deviation$end:    ${jitter[$1]}$end ms"
    echo -e "\t$col${underline}Average speed$end:     ${mpm[$1]}$end miles/ms"
    echo -e "\t$col${underline}Total Distance$end:    ${total_dist[$1]}$end miles"
}
infoCall ()
{
    # Output statistics for each player

    local n player
    n=1
    for player; do
        if [[ $player == $host ]]; then
            echo -e "\n$col${bold}Host$end"
            info $player
        elif [[ $player != $pub_ip ]]; then
            echo -e "\n$col${bold}Player $n$end\n"
            info $player
            echo -e "\t$col${underline}Host Distance$end:     ${host_dist[$player]} miles"
            echo -e "\t$col${underline}User Distance$end:     ${user_dist[$player]} miles"
            ((n++))
        else
            echo -e "\n$col${bold}User$end\n"
            echo -e "\t$col${underline}Ping Deviation$end:    $avg_jitter ms"
            echo -e "\t$col${underline}Host Distance$end:     ${host_dist[$player]} miles"
            echo -e "\t$col${underline}Total Distance$end:    ${total_dist[$player]} miles"
            echo -e "\t$col${underline}Average Speed$end:     $avg_mpm miles/ms"
        fi
    done
}
average ()
{
    local sum i
    sum=0
    for i; do
        sum=$(echo "$i+$sum"|bc -l)
    done
    echo "scale=3; $sum/$#"|bc
}
total (){
    local sum i
    sum=0
    for i; do
        ((sum+=$i))
    done
    echo $sum
}
traceOut ()
{
    # Output traceroute latency to furthest hop

    local trace i
    trace=()
    while read -ra line; do
        # Don't match dropped hops or unreachable messages
        if [[ ${line[@]} != *"*"* && ${line[@]} != *"!"* ]]; then
            trace=()
            for i in ${line[@]}; do
                # match time in milliseconds
                if [[ $i =~ $d+\.$d+ && ! $i =~ $d+\.$d+\. ]]; then
                    trace+=($i)
                fi
            done
        fi
    done < <($tracert $player -q 3 -n -f 5 -m 25)
    echo "${trace[@]}"
}
dumpRead ()
{
    # Parse tcpdump for player IP addresses

    local i d3 ip
    d3="$d{1,3}"
    ip="$d3\.$d3\.$d3\.$d3"
    while read -ra line; do
        for i in ${line[@]}; do
            if [[ $i =~ $ip ]]; then
                if [[ $BASH_REMATCH != $xbox ]]; then
                    echo $BASH_REMATCH
                    # Match first IP only if host capture
                    [[ $1 == $host_cap ]] && return
                fi
            fi
        done
    done < <($cap -n -r $1 2>$null)
}
regions ()
{
    local player
    for player; do
        # Parse geoiplookup for location data
        local n re
        n=0
        re="[-0-9\.]{8,11}"
        while IFS=, read -ra reg; do
            ((n++))
            # Only need lat/long points for user
            if [[ $player != $pub_ip ]]; then
                if [ $n -eq 1 ]; then
                    country[$player]="${reg[-1]#[[:space:]]}"
                elif [ $n -eq 2 ]; then
                    city[$player]="${reg[-6]#[[:space:]]}"
                    state[$player]="${reg[-7]#[[:space:]]}"
                fi
            fi
            if [[ ${reg[@]} =~ ($re)\ ($re) ]]; then
                lat[$player]=${BASH_REMATCH[1]}
                long[$player]=${BASH_REMATCH[2]}
                break
            fi
        done < <($geo $player)
    done
}
ispFind ()
{
    # ISP lookup fields vary by region
    while read ref org; do
        if [[ ${country[$1]} == "United States" ||
                ${country[$1]} == "Canada" ]]; then
            if [[ $ref == "CustName:" || $ref == "OrgName:" ]]; then
                isp[$1]="$org"
                break
            fi
        elif [[ $ref == "descr:" || $ref == "owner:" ]]; then
            isp[$1]="$org"
            break
        fi
    done < <(whois $1)
    [[ ! ${isp[$1]} ]] && isp[$1]="N/A"
}
latency ()
{
    local t
    read t < $shm/$1
    trace_ms[$1]="$t"
    avg_rtt[$1]="$(printf "%1.3f" $(average ${trace_ms[$1]}))"
    diff[$1]="$(for i in ${trace_ms[$1]}; do
                    echo "($i - ${avg_rtt[$1]})^2"|bc
                done)"
    diff_avg[$1]="$(average ${diff[$1]})"
    jitter[$1]="$(printf "%1.3f" $(echo "sqrt(${diff_avg[$1]})"|bc))"
    mpm[$1]=$(printf "%1.0f" $(echo "(${user_dist[$1]}*2)/${avg_rtt[$1]}"|bc)) 
}
distances ()
{
    # Perform distance calculations for each unique pair

    local i j refs distances increment player target
    declare -A distances
    refs=(${!client[@]})
    user_ref=${refs[-1]}

    # Iterate over all player references except last
    for i in ${refs[@]:0:$user_ref}; do
        player=${client[$i]}
        increment=$((i+1))

        # Calculate only from next reference to the end
        for j in ${refs[@]:$increment}; do
            target=${client[$j]}
            haversine $player $target
            distances[$i,$j]=$dist
            if [ $i -eq 0 ]; then
                host_dist[$target]=$dist
            fi
            if [ $j -eq $user_ref ]; then
                user_dist[$player]=$dist
            fi
        done
    done
    
    # Add up total distance for each player
    for i in ${refs[@]:1}; do
        player=${client[$i]}
        total_dist[$player]=0
        for j in ${!distances[@]}; do
            if [[ $j == *"$i"* ]]; then
                ((total_dist[$player]+=${distances[$j]}))
            fi
        done
    done
    total_dist[$host]=$(total ${host_dist[@]})
}
if [ $players -gt 0 ]; then
    trap controlC SIGINT

    # Find LAN subnet and interface
    IFS=. read -r f1 f2 f3 _ <<< "$xbox"
    lan_sub="$f1.$f2.$f3"
    while read -ra line; do
        [[ ${line[3]} == "$lan_sub"* ]] && lan_if=${line[1]}
    done < <(ip -o addr show)

    # Ascii color codes
    col="\x1b["
    end="\x1b[0m"
    green="1;32"
    underline="4m"
    bold="1m"

    [ ! -d "$shm" ] && mkdir $shm

    echo "Waiting for Host to be detected"
    arr=('|' '/' '-' '\ ')
    until [ -f "$shm/fin1" ]; do
        wheel "${arr[@]}"
    done &
    pids=($!)

    # Reset packet counters
    $conn -D -p udp -s $xbox --sport $xport &>$null
    $conn -D -p udp -d $wan_ip --dport $nat_port &>$null
    sleep 15

    # Wait for enough packets to transfer
    track pack
    while [ $max_pack -lt 725 ]; do
        sleep 3
        track pack
    done &
    pids+=($!)

    # Capture packets unique to host
    $cap -c 4 -vvv -i $lan_if udp port $xport and \
        length = 306 or length = 146 and not host 65.55 and \
        not host 65.59 -w $host_cap &> $null &
    pids+=($!)

    wait ${pids[1]}

    # Check for user host
    track count
    p_num=0
    for i in ${c_pack[@]}; do
        if [ $i -gt 625 ]; then
            ((p_num++))
        fi
    done
    if [ $p_num -gt 0 ]; then
        h_bool=$(echo "${#c_pack[@]}/$p_num <= 1.5"|bc)
        if [ $h_bool -eq 1 ]; then
            echo -e "You Have Host"
            procKill
            exit 0
        fi
    fi
    wait ${pids[2]}

    # Capture heartbeat packets unique to players
    $cap -c 38 -vvv -i $lan_if udp port $xport and length = 66 \
        or length = 68 -w $client_cap &> $null

    pub_ip=$(curl -4 icanhazip.com 2>$null)

    # Create list of players
    host=$(dumpRead $host_cap)
    client=($host $(dumpRead $client_cap|sort -u) $pub_ip)

    finishedBG fin1 ${pids[0]}

    echo "Testing latency"
    arr=('|>    |' '|=>   |' '|==>  |' '|===> |' '|====>|'
         '|    <|' '|   <=|' '|  <==|' '| <===|' '|<====|')
    until [ -f "$shm/fin2" ]; do
        wheel "${arr[@]}"
    done &
    pids+=($!)

    # Run parallel traceroutes
    sans_user=(${client[@]%${client[-1]}})
        
    for player in ${sans_user[@]}; do
        traceOut > $shm/$player &
        trace_pids+=($!)
    done
    wait ${trace_pids[@]}

    declare -A trace_ms avg_rtt diff diff_avg jitter \
               country city state isp mpm user_dist \
               total_dist host_dist lat long
    regions ${client[@]}
    distances
    for player in ${sans_user[@]}; do
        ispFind $player
        latency $player
    done
    avg_jitter=$(printf "%1.3f" $(average ${jitter[@]}))
    avg_mpm=$(printf "%1.0f" $(average ${mpm[@]}))

    finishedBG fin2 ${pids[3]}

    # Print and save temporary report
    date_time="$(date +%m-%d-%Y-%H.%M)"
    file="/tmp/hostcheck.$date_time"
    infoCall ${client[@]}|tee "$file"
    echo -e "\nA copy of this report is saved at '$file'"

    disconnect
    rm -rf $shm
else
    echo "Please wait to be matched in a game"
    exit 1
fi
exit 0
