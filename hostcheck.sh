#!/bin/bash

. "$(dirname "$(readlink -f "$0")")"/host_env
if [ $EUID -ne 0 ]; then
    string="This script needs to capture raw packets, "
    string+="and requires sudoer privileges."
    echo $string
fi

# Find Xbox Live connection track
while read -r line; do
    if [[ $line == *"src=65.55."* ]]; then
        for re in [a-zA-Z] \[\] \= \_; do
            line=${line//$re/}
        done
        live=($line)

        # Remove unnecessary fields
        for i in 0 1 6 7 12 13 14 15; do
            unset live[$i]
        done
        live=(${live[@]})
        break
    fi
done < <(sudo -k $conn -L -p udp 2>$null)

# Enable conntrack packet counter if disabled
acct=/proc/sys/net/netfilter/nf_conntrack_acct
if [ $(< $acct) -ne 1 ]; then
    sudo echo 1 > $acct
    echo "Enabling netfilter's packet counter"
    sudo conntrack -D -p udp
    sleep 3
fi

d="[0-9]"
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
if [ ${#player_packets} -gt 0 ]; then
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

    [[ ! -d $tmp ]] && mkdir $tmp

    echo "Waiting for Host to be detected"
    arr=('|' '/' '-' '\ ')
    until [ -f "$tmp/fin1" ]; do
        wheel "${arr[@]}"
    done &
    pids=($!)

    # Reset packet counters
    sudo $conn -D -p udp -s $xbox --sport $xport &>$null
    sudo $conn -D -p udp -d $wan_ip --dport $nat_port &>$null
    sleep 15

    # Wait for enough packets to transfer
    track pack
    while [ $max_packets -lt 725 ]; do
        sleep 3
        track pack
    done &
    pids+=($!)

    # In the background, capture packets unique to host
    sudo $cap -c 4 -vvv -i $lan_if udp port $xport and \
        length = 306 or length = 146 and not host 65.55 and \
        not host 65.59 -w $host_cap 2>$null &
    pids+=($!)

    wait ${pids[1]}

    # Check for user host
    track count
    packet_num=0
    for i in ${packets[@]}; do
        if [ $i -gt 625 ]; then
            ((packet_num++))
        fi
    done
    if [ $packet_num -gt 0 ]; then
        host_bool=$(echo "${#packets[@]}/$packet_num <= 1.5"|bc)
        if [ $host_bool -eq 1 ]; then
            echo -e "You Have Host"
            procKill
            exit 0
        fi
    fi
    wait ${pids[2]}

    # Capture heartbeat packets unique to players
    $cap -c 38 -vvv -i $lan_if udp port $xport and length = 66 \
        or length = 68 -w $client_cap 2>$null

    pub_ip=$(curl -4 icanhazip.com 2>$null)

    # Create list of players
    host=$(dumpRead $host_cap)
    players=($host $(dumpRead $client_cap|sort -u) $pub_ip)

    # Send finished signal to wheel process
    finishedBG fin1 ${pids[0]}

    # Start latency wheel
    echo "Testing latency"
    arr=('|>    |' '|=>   |' '|==>  |' '|===> |' '|====>|'
         '|    <|' '|   <=|' '|  <==|' '| <===|' '|<====|')
    until [ -f "$tmp/fin2" ]; do
        wheel "${arr[@]}"
    done &
    pids+=($!)

    # Run parallel traceroutes
    sans_user=(${players[@]%${players[-1]}})
        
    for player in ${sans_user[@]}; do
        traceOut > $tmp/$player &
        trace_pids+=($!)
    done
    wait ${trace_pids[@]}

    declare -A trace_ms avg_rtt diff diff_avg jitter \
               country city state isp mpm user_dist \
               total_dist host_dist lat long
    regions ${players[@]}
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
    infoCall ${players[@]}|tee "$file"
    echo -e "\nA copy of this report is saved at '$file'"

    disconnect
    rm -rf $tmp
else
    echo "Please wait to be matched in a game"
    exit 1
fi
exit 0
