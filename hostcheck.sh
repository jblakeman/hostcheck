#!/usr/bin/env bash

script_dir="$(dirname "$(readlink -f "$0")")"
. $script_dir/host_env
if [ $EUID -ne 0 ]; then
    echo "'${0##*/}' needs sudoer permission to capture raw packets."
    error=$(sudo -K 2>&1 1>$null)
    if [ $? -ne 0 ]; then
        echo "$error"
        exit 1
    fi
fi

# Find Xbox Live connection track
live=($(awk -v s="src=${servers[0]}" '
        $0 ~ s {
        gsub(/[^[:digit:].[:space:]]/,"")
        print $3,$4,$5,$6,$9,$10,$11,$12 
        exit
    }' < <(list_udp_conn)
))

# Enable conntrack packet counter if disabled (default)
acct=/proc/sys/net/netfilter/nf_conntrack_acct
if [ $(< $acct) -ne 1 ]; then
    sudo echo 1 > $acct
    echo "Enabling netfilter's packet counter"
    sudo $CONN -D -p udp &>$null
    sleep 3
fi

if [[ ! ${live[0]} ]]; then
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
    track
fi
if [ ${#player_track} -gt 0 ]; then
    trap control_c SIGINT

    # Find LAN subnet and interface
    IFS=. read -r f1 f2 f3 _ <<< "$xbox"
    lan_sub="$f1.$f2.$f3"
    while read -ra line; do
        [[ ${line[3]} == "$lan_sub"* ]] && lan_if=${line[1]}
    done < <(ip -o addr show)

    [[ ! -d $tmp ]] && mkdir $tmp

    echo "Waiting for Host to be detected"
    arr=('|' '/' '-' '\ ')
    until [ -f "$tmp/fin1" ]; do
        wheel "${arr[@]}"
    done &
    pids=($!)

    # Reset packet counters
    sudo $CONN -D -p udp -s $xbox --sport $xport &>$null
    sudo $CONN -D -p udp -d $wan_ip --dport $nat_port &>$null

    # Wait for enough packets to transfer
    sleep 15
    while track max && [ $max_packets -lt 725 ]; do
        sleep 3
    done &
    pids+=($!)

    # In the background, capture packets unique to host
    sudo $CAP -c 4 -vvv -i $lan_if udp port $xport and \
        length = 306 or length = 146 and not host 65.55 and \
        not host 65.59 -w $host_cap 2>$null &
    pids+=($!)

    wait ${pids[1]}

    # Check for user host
    track
    packet_num=0
    for i in ${packets[@]}; do
        [ $i -gt 625 ] && ((packet_num++))
    done
    if [ $packet_num -gt 0 ]; then
        host_bool=$(echo "${#packets[@]}/$packet_num <= 1.5"|bc)
        if [ $host_bool -eq 1 ]; then
            echo -e "You Have Host"
            proc_kill
            exit 0
        fi
    fi
    wait ${pids[2]}

    # Capture heartbeat packets unique to players
    sudo $CAP -c 38 -vvv -i $lan_if udp port $xport and length = 66 \
        or length = 68 -w $client_cap 2>$null

    pub_ip=$(curl -4 icanhazip.com 2>$null)
    if [[ ! $pub_ip ]]; then
        pub_ip=$(curl -4 checkip.dyndns.org 2>/dev/null)
        pub_ip=${pub_ip#*:}
        pub_ip=${pub_ip%%<*}
    fi

    # Create list of players
    host=$(dump_read $host_cap)
    players=($host $(dump_read $client_cap|sort -u) $pub_ip)

    # Send finished signal to wheel process
    finished_bg fin1 ${pids[0]}

    # Start latency wheel
    echo "Testing latency"
    arr=('|>    |' '|=>   |' '|==>  |' '|===> |' '|====>|'
         '|    <|' '|   <=|' '|  <==|' '| <===|' '|<====|')
    until [ -f "$tmp/fin2" ]; do
        wheel "${arr[@]}"
    done &
    pids+=($!)

    # Run parallel traceroutes to each player
    sans_user=(${players[@]/$pub_ip/})
        
    for player in ${sans_user[@]}; do
        trace_out > $tmp/$player &
        trace_pids+=($!)
    done
    wait ${trace_pids[@]}

    declare -A trace_ms avg_rtt diff diff_avg jitter \
               country city state isp mpm user_dist \
               total_dist host_dist lat long

    regions ${players[@]}
    distances
    for player in ${sans_user[@]}; do
        isp_find $player
        latency $player
    done
    avg_jitter=$(printf "%1.3f" $(average ${jitter[@]}))
    avg_mpm=$(printf "%1.0f" $(average ${mpm[@]}))

    finished_bg fin2 ${pids[3]}

    # Print and save temporary report
    date_time="$(date +%m-%d-%Y-%H.%M)"
    file="/tmp/hostcheck.$date_time"
    info_call ${players[@]}|tee "$file"
    echo -e "\nA copy of this report is saved at '$file'"

    disconnect
    rm -rf $tmp
else
    echo "Please wait to be matched in a game"
    exit 1
fi

exit 0
