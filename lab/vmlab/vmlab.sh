#!/usr/bin/env bash
# vmlab — runs inside the cicd-vmlab container (see Dockerfile).
#   vmlab serve                                   build the lab network, then idle (container main process)
#   vmlab up <name> <seg> <ip-suffix> <mem-MiB> <cpus> <disk-GB>   create (first time) + boot a VM
#   vmlab down <name>                             ACPI power off (then kill)
#   vmlab ssh <name> [cmd...]  /  vmlab ip <name>  /  vmlab scp-to <name> <src> <dst>
# Lab network (private ranges ON PURPOSE, so the egress policy is tested against real RFC1918 targets):
#   seg lan    10.77.0.0/24  "home LAN": forge VM .10, deploy target VM .30; gateway/resolver .1
#   seg runner 10.78.0.0/24  "runner VLAN": runner VM .20;                    gateway/resolver .1
#   probes: 10.77.0.1:8080 ("NAS" on the LAN), 100.64.0.1:8080 (CGNAT/Tailscale-like), 10.77.0.99 (outsider
#   source address for the Caddy allow-list test). Lab DNS (dnsmasq) answers *.lab.test, forwards the rest.
set -euo pipefail
L=/lab; IMG=$L/img/${VM_IMAGE:-ubuntu-24.04-server-cloudimg-amd64.img}
mkdir -p $L/vms
key() { [ -f $L/id_lab ] || ssh-keygen -q -t ed25519 -N '' -f $L/id_lab -C vmlab; }
SSHO="-i $L/id_lab -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5"
ipof() { cat $L/vms/$1/ip; }
case "${1:-}" in
serve)
  key
  for b in "labbr0 10.77.0.1/24" "labbr1 10.78.0.1/24"; do
    set -- $b; ip link add $1 type bridge 2>/dev/null || true; ip addr add $2 dev $1 2>/dev/null || true; ip link set $1 up
  done
  ip addr add 10.77.0.99/24 dev labbr0 2>/dev/null || true          # "outsider" source for allow-list tests
  ip link add probe0 type dummy 2>/dev/null || true; ip addr add 100.64.0.1/32 dev probe0 2>/dev/null || true
  ip link set probe0 up
  nft -f - <<'NFT'
table ip vmlab_nat {
  chain post {
    type nat hook postrouting priority srcnat; policy accept;
    ip saddr { 10.77.0.0/24, 10.78.0.0/24 } oifname "eth0" masquerade
  }
}
NFT
  cat > $L/dnsmasq.hosts <<'H'
10.77.0.10 git.lab.test mirror.lab.test
10.77.0.30 app.lab.test target.lab.test
H
  dnsmasq --no-resolv --server=1.1.1.1 --server=9.9.9.9 --no-hosts --addn-hosts=$L/dnsmasq.hosts \
    --listen-address=10.77.0.1,10.78.0.1 --bind-interfaces --log-queries --log-facility=$L/dnsmasq.log --pid-file=/run/dnsmasq.pid
  # fake LAN services that the runner egress policy must refuse
  for a in 10.77.0.1 100.64.0.1; do
    socat TCP-LISTEN:8080,bind=$a,fork,reuseaddr SYSTEM:'echo HTTP/1.0 200 OK; echo; echo lan-service-reached' &
  done
  echo "vmlab ready: lan 10.77.0.1/24, runner 10.78.0.1/24, dns on .1"; exec sleep infinity;;
up)
  n=$2; seg=$3; s=$4; mem=$5; cpu=$6; disk=$7; d=$L/vms/$n; mkdir -p $d; key
  case $seg in lan) br=labbr0; net=10.77.0; tag=a;; runner) br=labbr1; net=10.78.0; tag=b;; *) echo bad seg; exit 2;; esac
  mac=$(printf '52:54:00:%s0:00:%02x' "$tag" "$s")
  if [ ! -f $d/disk.qcow2 ]; then
    qemu-img create -q -f qcow2 -F qcow2 -b $IMG $d/disk.qcow2 ${disk}G
    cat > $d/user-data <<UD
#cloud-config
hostname: $n
users:
  - name: ubuntu
    sudo: "ALL=(ALL) NOPASSWD:ALL"
    shell: /bin/bash
    ssh_authorized_keys: ["$(cat $L/id_lab.pub)"]
package_update: false
UD
    cat > $d/network-config <<NC
version: 2
ethernets:
  lan:
    match: {macaddress: "$mac"}
    set-name: eth0
    addresses: [$net.$s/24]
    routes: [{to: default, via: $net.1}]
    nameservers: {addresses: [$net.1], search: [lab.test]}
NC
    printf 'instance-id: %s\nlocal-hostname: %s\n' "$n" "$n" > $d/meta-data
    cloud-localds -N $d/network-config $d/seed.iso $d/user-data $d/meta-data
    echo $net.$s > $d/ip
  fi
  ip tuntap add dev tap-$n mode tap 2>/dev/null || true
  ip link set tap-$n master $br up
  qemu-system-x86_64 -name $n -enable-kvm -cpu host -smp $cpu -m $mem -display none -daemonize \
    -pidfile $d/pid -serial file:$d/serial.log -monitor unix:$d/mon.sock,server,nowait \
    -drive file=$d/disk.qcow2,if=virtio,cache=unsafe -drive file=$d/seed.iso,if=virtio,format=raw,readonly=on \
    -netdev tap,id=n0,ifname=tap-$n,script=no,downscript=no -device virtio-net-pci,netdev=n0,mac=$mac \
    -object rng-random,id=rng0,filename=/dev/urandom -device virtio-rng-pci,rng=rng0
  for i in $(seq 1 90); do ssh $SSHO ubuntu@$(ipof $n) true 2>/dev/null && break; sleep 2; done
  ssh $SSHO ubuntu@$(ipof $n) 'cloud-init status --wait >/dev/null 2>&1; echo "$(hostname) up: $(. /etc/os-release; echo $PRETTY_NAME) kernel $(uname -r)"';;
down)
  d=$L/vms/$2; echo system_powerdown | socat - UNIX-CONNECT:$d/mon.sock >/dev/null 2>&1 || true
  for i in $(seq 1 60); do kill -0 "$(cat $d/pid 2>/dev/null)" 2>/dev/null || break; sleep 1; done
  kill "$(cat $d/pid 2>/dev/null)" 2>/dev/null || true; ip link del tap-$2 2>/dev/null || true; echo "$2 down";;
ssh) n=$2; shift 2; exec ssh $SSHO ubuntu@$(ipof $n) "$@";;
scp-to) exec scp -r $SSHO "$3" ubuntu@$(ipof $2):"$4";;
scp-from) exec scp -r $SSHO ubuntu@$(ipof $2):"$3" "$4";;
ip) ipof $2;;
*) sed -n '2,12p' "$0"; exit 2;;
esac
