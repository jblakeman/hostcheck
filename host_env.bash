#!/bin/bash

IPT=$(which iptables)
TRACERT=$(which traceroute)
CONN=$(which conntrack)
IP=$(which ip)
CAP=$(which tcpdump)
GEO=$(which geoiplookup)
WHO=$(which whois)

tmp=/tmp/host
null=/dev/null
host_cap=$tmp/host.pcap
client_cap=$tmp/client.pcap

# Ascii color codes
col="\x1b["
end="\x1b[0m"
green="1;32"
underline="4m"
bold="1m"

servers=(65.55. 65.59.)
d="[0-9]"
y_or_n="Please answer yes or no"

is_sudoer (){
     awk -F: -v u="$USER" '
        /^sudo/ {
            for(i=4;i<=NF;i++) {
                if($i==u) {
                    f=1
                    break
                }
            }
        } END {
            if(!f)
            exit 1
    }' /etc/group
}

list_udp_conn (){
    $CONN -L -p udp 2>$null
}
track ()
{
    # Count number of potential players and max packet count
    local i
    player_track=($(
        awk -v x="sport=$xport" -v s1="src=${servers[0]}" \
            -v s2="src${servers[1]}" '
            $0 ~ x && $0 !~ s1 && $0 !~ s2 {
                sub("packets=","",$8)
                print $8
            }' < <(list_udp_conn)
    ))
    if [[ $1 == max ]]; then
        max_packets=${player_track[0]}
        for i in ${player_track[@]/$max_packets/}; do
            [ $i -gt $max_packets ] && max_packets=$i
        done
    fi
}
proc_kill ()
{
    local pid
    for pid; do
        if [ -e /proc/$pid ]; then
            disown $pid
            kill -9 $pid
        fi
    done
}
graceful_exit ()
{
    echo -e "\rScript exiting..."
    rm -rf $tmp
    proc_kill ${pids[@]}
    exit 1
}
finished_bg ()
{
    # Create temporary file to signal end of process

    local shared
    shared=$tmp/$1
    echo 1 > $shared
    wait $2
    rm $shared
}
wheel ()
{
    local spoke
    for spoke; do
        printf " $col${green}m%s$end\r" "$spoke"
        sleep ".15"
    done
}
haversine ()
{
    # Find distance between two points on the globe

    local pi radians radius l lats longs d_lat d_long a b
    pi=$(echo "4*a(1)"|bc -l)
    radians=$(echo "scale=20; $pi/180"|bc)
    for l in $1 $2; do
        lats+=($(echo "${lat[$l]}*$radians"|bc))
        longs+=($(echo "${long[$l]}*$radians"|bc))
    done
    radius=$(echo "6371.0072*0.6214"|bc)
    d_lat=$(echo "${lats[0]} - ${lats[1]}"|bc)
    d_long=$(echo "${longs[0]} - ${longs[1]}"|bc)
    a=$(echo "sqrt(s($d_lat/2)^2+c(${lats[0]})*c(${lats[1]})*s($d_long/2)^2)"|bc -l)
    b=$(awk -v a=$a 'BEGIN{print 2*atan2(a,sqrt(1-a*a));}')
    dist=$(printf "%1.0f" $(echo "$radius*$b"|bc))
    unset lats longs
}
info ()
{
    echo -e "\t$col${underline}Country$end:         ${country[$1]}"
    echo -e "\t$col${underline}Region$end:          ${city[$1]}, ${state[$1]}"
    echo -e "\t$col${underline}Provider$end:        ${isp[$1]}"
    echo -e "\t$col${underline}Average Ping$end:    ${avg_rtt[$1]} ms"
    echo -e "\t$col${underline}Ping Deviation$end:  ${jitter[$1]}$end ms"
    echo -e "\t$col${underline}Total Distance$end:  ${total_dist[$1]}$end miles"
}
info_call ()
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
            indirect=$((${host_dist[$player]}+${user_dist[$player]}))
            echo -e "\t$col${underline}Route Distance$end:  $indirect miles"
            ((n++))
        else
            echo -e "\n$col${bold}User$end\n"
            echo -e "\t$col${underline}Ping Deviation$end:  $avg_jitter ms"
            echo -e "\t$col${underline}Host Distance$end:   ${host_dist[$player]} miles"
            echo -e "\t$col${underline}Total Distance$end:  ${total_dist[$player]} miles"
            echo -e "\t$col${underline}Average Speed$end:   $avg_mpm miles/ms"
        fi
    done
}
total (){
    local sum i
    sum=0
    for i; do
        ((sum+=$i))
    done
    echo $sum
}
average ()
{
    local sum f
    sum=0
    for f; do
        sum=$(echo "$f+$sum"|bc)
    done
    echo "scale=3; $sum/$#"|bc
}

trace_out ()
{
    # Output traceroute latency to furthest hop
    awk '!/[*\!]/ {
            for(i=1; i<=NF; i++) {
                if($i!~/^[0-9]{1,3}\.[0-9]{1,3}$/) 
                    $i=""
            }
            a=$0
        }END{
            print a
        }' < <($TRACERT $player -q 3 -n -f 5 -m 25)
}
dump_read ()
{
    # Parse tcpdump for player IP addresses
    local l d3 ip
    d3="$d{1,3}"
    ip="$d3\.$d3\.$d3\.$d3"
    while read -ra line; do
        for l in ${line[@]}; do
            if [[ $l =~ $ip ]]; then
                if [[ $BASH_REMATCH != $xbox ]]; then
                    echo $BASH_REMATCH
                    # Match first IP only if host capture
                    [[ $1 == $host_cap ]] && return
                fi
            fi
        done
    done < <($CAP -n -r $1 2>$null)
}
regions ()
{
    local player n re
    points="[-0-9\.]{8,11}" 
    for player; do
        # Parse geoiplookup for location data
        n=0
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
            if [[ ${reg[@]} =~ ($points)\ ($points) ]]; then
                lat[$player]=${BASH_REMATCH[1]}
                long[$player]=${BASH_REMATCH[2]}
                break
            fi
        done < <($GEO $player)
    done
}
isp_find ()
{
    # Find ISP information
    while read ref org; do
        # ISP lookup fields vary by region
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
    done < <($WHO $1)
    [[ ! ${isp[$1]} ]] && isp[$1]=N/A
}
latency ()
{
    read trace_ms[$1] < $tmp/$1
    avg_rtt[$1]=$(printf "%1.3f" $(average ${trace_ms[$1]}))
    diff[$1]="$(
        for i in ${trace_ms[$1]}; do
            echo "($i - ${avg_rtt[$1]})^2"|bc
        done
    )"
    diff_avg[$1]=$(average ${diff[$1]})
    jitter[$1]=$(printf "%1.3f" $(echo "sqrt(${diff_avg[$1]})"|bc))
    mpm[$1]=$(printf "%1.0f" $(echo "(${user_dist[$1]}*2)/${avg_rtt[$1]}"|bc)) 
}
distances ()
{
    # Perform distance calculations for each unique pair

    local i j refs distances increment player target
    declare -A distances
    refs=(${!players[@]})
    user_ref=${refs[-1]}

    # Iterate over all player references except last (User)
    for i in ${refs[@]:0:$user_ref}; do
        player=${players[$i]}
        increment=$((i+1))

        # Calculate only from next reference to the end
        for j in ${refs[@]:$increment}; do
            target=${players[$j]}
            haversine $player $target
            distances[$i,$j]=$dist
            [ $i -eq 0 ] && host_dist[$target]=$dist
            [ $j -eq $user_ref ] && user_dist[$player]=$dist
        done
    done

    # Total uniquely for Host and User
    total_dist[$host]=$(total ${host_dist[@]})
    total_dist[$pub_ip]=$(total ${user_dist[@]})

    # Add up total distance for each other player
    for i in ${refs[@]:1:$user_ref}; do
        player=${players[$i]}
        total_dist[$player]=0
        for j in "${!distances[@]}"; do
            if [[ $j == *"$i"* ]]; then
                ((total_dist[$player]+=${distances[$j]}))
            fi
        done
    done
}
