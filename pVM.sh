#!/bin/bash

#------------------------------------------------------------------------------
# Copyright (c) 2016, Leonid Bloch
# All rights reserved.
# This code is licensed under standard 3-clause BSD license.
# See file LICENSE supplied with this package for the full license text.
#------------------------------------------------------------------------------

SCRDIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd)
. "${SCRDIR}"/pVM.cfg

while [ $# -gt 0 ]
do
    key="$1"
    case $key in
        -d)
            DRIVES=(${2//,/ })
            shift
            ;;
        -i)
            INDRIVES=(${2//,/ })
            shift
            ;;
        -o)
            OUTDIRS=(${2//,/ })
            shift
            ;;
        -m)
            MEM=(${2//,/ })
            shift
            ;;
        -c)
            CORES=(${2//,/ })
            shift
            ;;
        -a)
            ADDITIONAL=(${2//,/ })
            shift
            ;;
        --install)
            INSTALLING=true
            ;;
        -h|--help)
            cat <<EOF
Usage: $0 [-d DRIVE] [-i SQSH|DIR] [-o DIR] [-m MEM] [-c CORES] [-a OPTS] \
[--install]
EOF
            exit 0
            ;;
    esac
    shift
done

case $NET_TYPE in
    tap)
        case $USER in
        root)
            echo "Running with tap network."
            ;;
        *)
            echo "Error: tap network can be run with root privileges only!"
            exit 1
        esac
        ;;
    user)
        echo "Running with user network."
        ;;
    *)
        echo "Error: NET_TYPE should be defined as \"tap\" or \"user\" only!"
        exit 1
esac

CURR_USER=${SUDO_USER:-${USER}}
SSH_LOCAL=$(awk '{ print $3 ":" $4 }' <<< ${SSH_CONNECTION})

numbers_dont_match() {
    echo "Check config arrays!"
    exit 1
}

getmac() {
    local MAC_I="56:3c:4c:"
    local MAC_F=":cc"
    local MAC_M=$(printf "%04d" $1 | sed 's/.\{2\}/&:/' | cut -c 1-5)
    printf "%s%s%s" ${MAC_I} ${MAC_M} ${MAC_F}
}

zerolead() {
    printf "%02d" $1
}

calcvec() {
    printf "$(( $1 * 2 + 2 ))"
}

name_from_drive() {
    local DRIVE=$(basename $1)
    printf "%s_%s" ${DRIVE%.*} $2
}

start_dnsmasq() {
    dnsmasq -i ${VM_BRIDGE} -z -F "${LEASE_RANGE}" -x "${SCRDIR}"/dnsmasq.pid
    chown ${CURR_USER}:$(id -g -n ${CURR_USER}) "${SCRDIR}"/dnsmasq.pid
}

stop_dnsmasq() {
    kill -9 $(cat "${SCRDIR}"/dnsmasq.pid)
    rm -r "${SCRDIR}"/dnsmasq.pid
}

create_bridge() {
    ovs-vsctl add-br ${VM_BRIDGE}
    ip link set ${VM_BRIDGE} up
    ip addr add ${BR_ADDR} dev ${VM_BRIDGE}
}

remove_bridge() {
    ip link set ${VM_BRIDGE} down
    ovs-vsctl del-br ${VM_BRIDGE}
}

create_bridge_scripts() {
cat > "${SCRDIR}"/upscript.sh <<EOF
#!/bin/sh
ip link set \$1 up
ovs-vsctl add-port ${VM_BRIDGE} \$1
EOF
chmod 755 "${SCRDIR}"/upscript.sh
chown ${CURR_USER}:$(id -g -n ${CURR_USER}) "${SCRDIR}"/upscript.sh
}

remove_bridge_scripts() {
    rm -f "${SCRDIR}"/upscript.sh
}

kill_machines() {
    for j in $@
    do
        kill -9 $j
    done
}

squashdrive_cmd() {
    if [ -f "$2" ]
    then
        printf -- "-drive file=%s,if=none,id=rdrive%s,readonly,format=raw
                   -device scsi-hd,drive=rdrive%s" "$2" "$1" "$1"
    fi
}

drivedir_cmd() {
    # Arguments: name number ro|rw /path/on/host
    if [ -d "$4" ]
    then
        local ID="$1dir$(zerolead $2)"
        local TAG="$1"
        case $3 in
        ro)
            local LOCRO=",readonly"
        esac
        printf -- "-virtfs local,id=%s,path=%s,security_model=none,mount_tag=%s%s" \
                  $ID $4 $TAG $LOCRO
    fi
}

#set_qcow2_l2_cache() {
#    local L2_DEFAULT_CLUSTERS=8
#    local L2_DEFAULT_SIZE=1048576
#    # Format, virtual size, cluster size:
#    set $(${QEMU_IMG_BIN} info $1 |
#          egrep 'file format|virtual size|cluster_size' |
#          sed 's/(//;s/ bytes)//' |
#          awk '{print $NF}')
#    if [ "$1" = qcow2 ]
#    then
#        # size*cache_clusters/cluster_size, but divisible by cluster_size:
#        local L2SIZE=$(( $2 * $L2_DEFAULT_CLUSTERS / $3**2 * $3 ))
#        # Apply only if not smaller than the default
#        [ $L2SIZE -gt $L2_DEFAULT_SIZE ] && printf ",l2-cache-size=%s" $L2SIZE
#    fi
#}
set_qcow2_l2_cache() {
    local L2_DEFAULT_CLUSTERS=8
    local L2_DEFAULT_SIZE=1048576
    # Info: http://git.qemu.org/?p=qemu.git;a=blob;f=docs/specs/qcow2.txt
    set $(od -N 32 --endian=big -An -x $1 2> /dev/null | tr -d " ")
    local MAG_VER=$(cut -c 1-16 <<< $1)
    case $MAG_VER in
    514649fb0000000[2-3])
        # File is qcow2
        local CLUSTERBITS=$(cut -c 9-16 <<< $2)
        local CLUSTERSIZE=$(( 1 << 0x$CLUSTERBITS ))
        local DRIVESIZE=$(cut -c 17-32 <<< $2)
        # size*cache_clusters/cluster_size, but divisible by cluster_size:
        # Info: http://git.qemu.org/?p=qemu.git;a=blob;f=docs/qcow2-cache.txt
        local L2SIZE=$(( 0x$DRIVESIZE * $L2_DEFAULT_CLUSTERS /
                         $CLUSTERSIZE**2 * $CLUSTERSIZE ))
        # Apply only if not smaller than the default
        [ $L2SIZE -gt $L2_DEFAULT_SIZE ] && printf ",l2-cache-size=%s" $L2SIZE
    esac
}

is_sqsh() {
    local SQSH_MAGIC=73717368
    local FHEAD=$(od -N 4 --endian=little -An -t x4 $1 2> /dev/null | tr -d " ")
    [ $FHEAD -eq $SQSH_MAGIC ] && printf "sqsh"
}

find_drive() {
    # Args: prefix, suffix, name
    if [ -f ${3} ]
    then
        printf "%s" ${3}
    elif [ -f ${3}.${2} ]
    then
        printf "%s" ${3}.${2}
    elif [ -f ${1}/${3} ]
    then
        printf "%s" ${1}/${3}
    elif [ -f ${1}/${3}.${2} ]
    then
        printf "%s" ${1}/${3}.${2}
    fi
}

usr_ssh_fwd() {
    case $NET_TYPE in
    user)
        printf ",hostfwd=tcp::%s-:22" $(( $INIT_SSH_PORT + $1 ))
    esac
}

find_tapnet_ip() {
    printf "%s" $(ip neigh | awk -v mac="$(getmac $1)" '$5 == mac { print $1 }')
}

ssh_print() {
    case $NET_TYPE in
    user)
        printf -- "-p %s pvm-user@localhost\n" $(( $INIT_SSH_PORT + $1 ))
        ;;
    tap)
        local TAPNET_IP=$(find_tapnet_ip $1)
        printf -- "pvm-user@%s\n" ${TAPNET_IP:-"<GUEST> (not online yet...)"}
    esac
}

use_net_scripts() {
    case $NET_TYPE in
    tap)
        printf ",script=%s/upscript.sh,downscript=no" "${SCRDIR}"
    esac
}

set_runas() {
    case $USER in
    root)
        [ "${CURR_USER}" = root ] || printf -- "-runas %s" ${CURR_USER}
    esac
}

complete_arr() {
    # If array is not long enough, complete with the last member.
    # Example: complete_arr $NUMBER ARRAY[@]
    local -a LOCARR=("${!2}")
    while [ ${#LOCARR[@]} -gt 0 ] && [ ${#LOCARR[@]} -lt $1 ]
    do  LOCARR+=("${LOCARR[${#LOCARR[@]}-1]}")
    done
    eval "${2%[*}=(${LOCARR[@]})"
}

prepare_net() {
    case $NET_TYPE in
    tap)
        create_bridge
        start_dnsmasq
        create_bridge_scripts
    esac
}

end_net() {
    case $NET_TYPE in
    tap)
        stop_dnsmasq
        remove_bridge
        remove_bridge_scripts
    esac
}

NUMDRIVES=${#DRIVES[@]}
if [ $NUMDRIVES -eq 0 ] || [ ${#MEM[@]} -eq 0 ] || [ ${#CORES[@]} -eq 0 ]
then
    echo "Please make sure that bootdrives/memory/CPUs are specified!"
    exit 1
fi

for i in ${!DRIVES[@]}
do
    TMP_DRV=${DRIVES[$i]}
    DRIVES[$i]="$(find_drive "${DRIVEREPO}" "qcow2" ${DRIVES[$i]})"
    if [ -z "${DRIVES[$i]}" ]
    then
        printf "File %s not found.\n" "${TMP_DRV}"
        exit 1
    fi
done

for i in ${!INDRIVES[@]}
do
    TMP_IDRV="${INDRIVES[$i]}"
    INDRIVES[$i]="$(find_drive "${SQUASHREPO}" "sqsh" ${INDRIVES[$i]})"
    if [ -d "${TMP_IDRV}" ]
    then
        INDRIVES[$i]=${TMP_IDRV}
    elif [ -n "${INDRIVES[$i]}" ] && [ "$(is_sqsh "${INDRIVES[$i]}")" != sqsh ]
    then
        printf "\e[31mWarning: %s is not SquashFS/directory. Not using.\e[0m\n" \
               "${INDRIVES[$i]}"
    elif [ -z "${INDRIVES[$i]}" ]
    then
        printf "\e[31mWarning: %s not found. Not using.\e[0m\n" "${TMP_IDRV}"
    fi
done

for i in ${OUTDIRS[@]}
do
    if [ ! -d "${i}" ]
    then
        printf "\e[31mWarning: OUT directory %s not found. Not using.\e[0m\n" \
               "${i}"
    fi
done

complete_arr $NUMDRIVES INDRIVES[@]
complete_arr $NUMDRIVES OUTDIRS[@]
complete_arr $NUMDRIVES MEM[@]
complete_arr $NUMDRIVES CORES[@]
complete_arr $NUMDRIVES ADDITIONAL[@]

PIDS=()
trap "kill_machines ${PIDS[@]}; end_net; exit 0" INT

prepare_net

[ "$INSTALLING" = true ] && printf "=== INSTALLATION MODE ===\n"
[ "$SSH_LOCAL" = ":" ] || printf "Connected remotely (%s)\n" "$SSH_LOCAL"
for i in ${!DRIVES[@]}
do
    SPICE_PORT=$(( 6000 + $i ))
    MON_PORT=$(( 10000 + $i ))
    if [ $INSTALLING = true ]
    then
        ADDITIONAL[$i]+=" -cdrom ${INSTALL_MEDIA}"
        INST_DRIVE=$(drivedir_cmd install $i ro "${SCRDIR}"/install_scripts)
    fi
    "${QEMU_BIN}" \
        $(set_runas) \
        -device virtio-scsi-pci,id=scsi \
        -drive file="${DRIVES[$i]}",if=none,id=bootdrive$(set_qcow2_l2_cache ${DRIVES[$i]}) \
        -device scsi-hd,drive=bootdrive \
        $(squashdrive_cmd $(zerolead $i) "${INDRIVES[$i]}") \
        $(drivedir_cmd dat $i ro "${INDRIVES[$i]}") \
        $(drivedir_cmd out $i rw "${OUTDIRS[$i]}") \
        ${INST_DRIVE} \
        -netdev ${NET_TYPE},id=hostnet$(zerolead $i),vhost=on$(use_net_scripts),ifname=netif$(zerolead $i)$(usr_ssh_fwd $i),queues=${CORES[$i]} \
        -device virtio-net-pci,netdev=hostnet$(zerolead $i),mac=$(getmac $i),mq=on,vectors=$(calcvec ${CORES[$i]}),id=netif$(zerolead $i) \
        -m ${MEM[$i]} \
        -smp ${CORES[$i]},cores=${CORES[$i]} \
        -enable-kvm \
        -cpu qemu64,+ssse3,+sse4.1,+sse4.2,+x2apic,+fsgsbase,model=26 \
        -usb \
        -device usb-tablet \
        -boot order=cd \
        -global kvm-pit.lost_tick_policy=discard \
        -rtc base=utc,clock=host,driftfix=slew \
        -device virtio-balloon \
        -name "$(name_from_drive ${DRIVES[$i]} $i)" \
        -spice port=$SPICE_PORT,disable-ticketing \
        -vga qxl \
        -global qxl-vga.revision=4 \
        -monitor telnet::$MON_PORT,server,nowait ${ADDITIONAL[$i]} &

    PIDS+=($!)

    sleep 3
    if ps -p ${PIDS[${#PIDS[@]}-1]} > /dev/null
    then
        sleep 7
        printf "=== VM %02d ===\nGraphics: %s\nMonitor: %s\n" \
               $(( $i + 1 )) \
               "spicy -h localhost -p $SPICE_PORT" "telnet localhost $MON_PORT"
        [ "$INSTALLING" = true ] || printf "SSH: %s\n" "ssh $(ssh_print $i)"
    else
        printf "VM %02d: FAILED!\n" $(( $i + 1 ))
    fi
done

printf "=== END ===\n"

wait

end_net
