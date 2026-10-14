# cicd-vmlab: disposable KVM VMs (QEMU) running INSIDE this container, so nothing is installed on the host.
# Run (no published ports, default bridge, own network namespace; NOT --privileged):
#   docker run -d --rm --name cicd-vmlab --device /dev/kvm --device /dev/net/tun --cap-add NET_ADMIN \
#     --sysctl net.ipv4.ip_forward=1 -v "$LAB_DIR":/lab cicd-vmlab:1
# The two lab segments, NAT, the LAN resolver and the fake "LAN services" all live in this container's netns.
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update -q && apt-get install -y -q --no-install-recommends \
      qemu-system-x86 qemu-utils cloud-image-utils genisoimage openssh-client iproute2 nftables dnsmasq-base \
      ca-certificates curl socat procps iputils-ping python3-minimal rsync \
 && rm -rf /var/lib/apt/lists/*
COPY vmlab.sh /usr/local/bin/vmlab
ENTRYPOINT ["/usr/local/bin/vmlab"]
CMD ["serve"]
