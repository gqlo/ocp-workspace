# OpenShift Networking Tracing

## Overview

This directory provides a comprehensive set of tools for network analysis, packet capture, and troubleshooting in OpenShift environments. It includes a container image with essential networking tools and example YAML manifests for deploying networking test scenarios.

## Contents

### Dockerfile

The `Dockerfile` builds a container image based on Fedora that includes a set of networking and troubleshooting tools:

**Network Analysis Tools:**
- `tcpdump` - Packet capture and analysis
- `wireshark-cli` - Command-line network protocol analyzer
- `conntrack-tools` - Connection tracking utilities

**Network Utilities:**
- `iproute`, `iputils` - IP and routing management
- `bind-utils` - DNS troubleshooting (dig, nslookup)
- `net-tools` - Traditional networking utilities (ifconfig, netstat)
- `bridge-utils`, `ethtool` - Bridge and Ethernet interface management

**Network Testing:**
- `curl`, `wget` - HTTP/HTTPS testing
- `nmap-ncat`, `nc` - Network connectivity testing
- `iperf3` - Network performance testing
- `nmap` - Network scanning
- `traceroute` - Route tracing
- `telnet` - Interactive network testing
- `socat` - Multipurpose relay tool

**Monitoring Tools:**
- `iftop` - Network interface bandwidth monitoring
- `iotop` - I/O monitoring
- `htop` - Process monitoring
- `mtr` - Network diagnostic tool

**System Tools:**
- `procps-ng` - Process utilities
- `lsof` - List open files/connections
- `strace` - System call tracing

**Utilities:**
- `bash-completion`, `vim`, `less` - Enhanced shell experience

### YAML Manifests

#### http-svc.yaml

A complete OpenShift application manifest that includes:
- **ConfigMap** (`static-content`) - Sample static content
- **ConfigMap** (`nginx-config`) - Nginx server configuration
- **Deployment** (`static-server`) - Nginx-based static content server
- **Service** (`static-server`) - ClusterIP service exposing the deployment
- **Routes** - HTTP and HTTPS routes for external access

This manifest can be used to:
- Test network connectivity between pods and services
- Verify route functionality
- Create a test endpoint for network tracing exercises

#### dual-container.yaml

A Pod manifest that creates a single pod with two containers sharing the same network namespace for container-to-container communication tracing:
- **Pod** (`nettools-dual-pod`) - Contains two `nettools-fedora` containers
- **Container 1** (`nettools-container-1`) - Runs a Python HTTP server on port 8080 serving content from `/tmp`
- **Container 2** (`nettools-container-2`) - Runs `sleep infinity` for interactive access
- Both containers run with privileged security context and share the same pod network namespace

Used for network tracing exercises to capture and analyze HTTP traffic between containers within the same pod.

## Configuration

### Building the Networking Tools Container

```bash
# Build the container image
podman build -t nettools-fedora:latest .

```

### Push image to quay
```bash
# tag the image
podman tag localhost/nettools-fedora:latest quay.io/<your-username>/nettools-fedora:latest

# push the image to the remote repo
podman push quay.io/<your-username>/nettools-fedora:latest
```

### Deploying the Test Application

```bash
# Deploy the HTTP service for testing
oc apply -f http-svc.yaml
```

```bash
# Deploy a pod with two containers
oc apply -f dual-container.yaml
```
## Tracing
### container to container communication
```bash
# Once we deployed the dual-container pod, we should have the following pod running
oc get pod -n network-trace | grep dual
nettools-dual-pod                2/2     Running   0          5d22h
```

```bash
# since containers within the same pod shares network namespace, their nic, mac address are identical
oc rsh -c nettools-container-1 -n network-trace nettools-dual-pod
sh-5.1# ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host 
       valid_lft forever preferred_lft forever
2: eth0@if4615: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1400 qdisc noqueue state UP group default 
    link/ether 0a:58:0a:80:02:2b brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet 10.128.2.43/23 brd 10.128.3.255 scope global eth0
       valid_lft forever preferred_lft forever
    inet6 fe80::858:aff:fe80:22b/64 scope link 
       valid_lft forever preferred_lft forever

oc rsh -c nettools-container-2 -n network-trace nettools-dual-pod
sh-5.1# ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host 
       valid_lft forever preferred_lft forever
2: eth0@if4615: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1400 qdisc noqueue state UP group default 
    link/ether 0a:58:0a:80:02:2b brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet 10.128.2.43/23 brd 10.128.3.255 scope global eth0
       valid_lft forever preferred_lft forever
    inet6 fe80::858:aff:fe80:22b/64 scope link 
       valid_lft forever preferred_lft forever

# process isolation
oc rsh -c nettools-container-2 -n network-trace nettools-dual-pod
sh-5.1# ps aux
USER         PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root           1  0.0  0.0   2624  1024 ?        Ss   Nov17   0:00 sleep infinity
root          13  0.0  0.0   4424  3584 pts/0    Ss   02:08   0:00 /bin/sh
root          14  0.0  0.0   7008  2560 pts/0    R+   02:08   0:00 ps aux

oc rsh -c nettools-container-1 -n network-trace nettools-dual-pod
sh-5.1# ps aux
USER         PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root           1  0.0  0.0  96720 16384 ?        Ss   Nov17   0:12 python3 -m http.server 8080
root           8  0.0  0.0   4424  3584 pts/0    Ss   02:08   0:00 /bin/sh
root           9  0.0  0.0   7008  2560 pts/0    R+   02:09   0:00 ps aux
sh-5.1# 

# filesystem isolation
## keep the this session on, create a file under /tmp
oc rsh -c nettools-container-1 -n network-trace nettools-dual-pod
sh-5.1# echo "container 1" >> /tmp/container-1.txt
sh-5.1# cat /tmp/container-1.txt 
container 1

# examine container-2, check if txt file exists? 
oc rsh -c nettools-container-2 -n network-trace nettools-dual-pod
sh-5.1# ls /tmp/
sh-5.1# 

# contrack to track real-time connection event log
oc rsh -c nettools-container-1 -n network-trace nettools-dual-pod
sh-5.1# conntrack -E
    [NEW] tcp      6 120 SYN_SENT src=127.0.0.1 dst=127.0.0.1 sport=51000 dport=8080 [UNREPLIED] src=127.0.0.1 dst=127.0.0.1 sport=8080 dport=51000
 [UPDATE] tcp      6 60 SYN_RECV src=127.0.0.1 dst=127.0.0.1 sport=51000 dport=8080 src=127.0.0.1 dst=127.0.0.1 sport=8080 dport=51000
 [UPDATE] tcp      6 432000 ESTABLISHED src=127.0.0.1 dst=127.0.0.1 sport=51000 dport=8080 src=127.0.0.1 dst=127.0.0.1 sport=8080 dport=51000 [ASSURED]
 [UPDATE] tcp      6 120 FIN_WAIT src=127.0.0.1 dst=127.0.0.1 sport=51000 dport=8080 src=127.0.0.1 dst=127.0.0.1 sport=8080 dport=51000 [ASSURED]
 [UPDATE] tcp      6 30 LAST_ACK src=127.0.0.1 dst=127.0.0.1 sport=51000 dport=8080 src=127.0.0.1 dst=127.0.0.1 sport=8080 dport=51000 [ASSURED]
 [UPDATE] tcp      6 120 TIME_WAIT src=127.0.0.1 dst=127.0.0.1 sport=51000 dport=8080 src=127.0.0.1 dst=127.0.0.1 sport=8080 dport=51000 [ASSURED]
[DESTROY] tcp      6 TIME_WAIT src=127.0.0.1 dst=127.0.0.1 sport=49368 dport=8080 src=127.0.0.1 dst=127.0.0.1 sport=8080 dport=49368 [ASSURED]
[DESTROY] tcp      6 TIME_WAIT src=127.0.0.1 dst=127.0.0.1 sport=33924 dport=8080 src=127.0.0.1 dst=127.0.0.1 sport=8080 dport=33924 [ASSURED]

# curl the localhost on the second container
oc rsh -c nettools-container-2 -n network-trace nettools-dual-pod
sh-5.1# curl http://127.0.0.1:8080/hello.txt
Hello World

# using tcp dump to get packet level details, start the tcpdump listening on port 8080 and loopback device, curl the hello.txt on the second container 
oc rsh -c nettools-container-1 -n network-trace nettools-dual-pod
sh-5.1#  tcpdump -i lo -nn -A 'port 8080 and (host 127.0.0.1)'
dropped privs to tcpdump
tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on lo, link-type EN10MB (Ethernet), snapshot length 262144 bytes

02:32:28.679560 IP 127.0.0.1.39630 > 127.0.0.1.8080: Flags [S], seq 388646906, win 65495, options [mss 65495,sackOK,TS val 2431590157 ecr 0,nop,wscale 7], length 0
E..<..@.@................*G..........0.........
............
02:32:28.679581 IP 127.0.0.1.8080 > 127.0.0.1.39630: Flags [S.], seq 3084335693, ack 388646907, win 65483, options [mss 65495,sackOK,TS val 2431590157 ecr 2431590157,nop,wscale 7], length 0
E..<..@.@.<...............:M.*G......0.........
............
02:32:28.679593 IP 127.0.0.1.39630 > 127.0.0.1.8080: Flags [.], ack 1, win 512, options [nop,nop,TS val 2431590157 ecr 2431590157], length 0
E..4..@.@................*G...:N.....(.....
.......                      
02:32:28.679638 IP 127.0.0.1.39630 > 127.0.0.1.8080: Flags [P.], seq 1:88, ack 1, win 512, options [nop,nop,TS val 2431590157 ecr 2431590157], length 87: HTTP: GET /hello.txt HTTP/1.1
E.....@.@................*G...:N...........                                                                                                                                                                              
........GET /hello.txt HTTP/1.1
Host: 127.0.0.1:8080
User-Agent: curl/7.82.0
Accept: */*


02:32:28.679642 IP 127.0.0.1.8080 > 127.0.0.1.39630: Flags [.], ack 88, win 511, options [nop,nop,TS val 2431590157 ecr 2431590157], length 0
E..4T.@.@.................:N.*HR.....(.....
.......
02:32:28.681580 IP 127.0.0.1.8080 > 127.0.0.1.39630: Flags [P.], seq 1:187, ack 88, win 512, options [nop,nop,TS val 2431590159 ecr 2431590157], length 186: HTTP: HTTP/1.0 200 OK
E...T.@.@..5..............:N.*HR...........
........HTTP/1.0 200 OK
Server: SimpleHTTP/0.6 Python/3.10.4
Date: Tue, 18 Nov 2025 02:32:28 GMT
Content-type: text/plain
Content-Length: 12
Last-Modified: Mon, 17 Nov 2025 08:08:08 GMT
02:32:28.681608 IP 127.0.0.1.39630 > 127.0.0.1.8080: Flags [.], ack 187, win 511, options [nop,nop,TS val 2431590159 ecr 2431590159], length 0
E..4..@.@................*HR..;......(.....
........
02:32:28.681675 IP 127.0.0.1.8080 > 127.0.0.1.39630: Flags [P.], seq 187:199, ack 88, win 512, options [nop,nop,TS val 2431590159 ecr 2431590159], length 12: HTTP
E..@T.@.@.................;..*HR.....4.....
........Hello World

02:32:28.681684 IP 127.0.0.1.39630 > 127.0.0.1.8080: Flags [.], ack 199, win 511, options [nop,nop,TS val 2431590159 ecr 2431590159], length 0
E..4..@.@................*HR..;......(.....
........
02:32:28.681774 IP 127.0.0.1.8080 > 127.0.0.1.39630: Flags [F.], seq 199, ack 88, win 512, options [nop,nop,TS val 2431590159 ecr 2431590159], length 0
E..4T.@.@.................;..*HR.....(.....
........
02:32:28.681894 IP 127.0.0.1.39630 > 127.0.0.1.8080: Flags [F.], seq 88, ack 200, win 512, options [nop,nop,TS val 2431590159 ecr 2431590159], length 0
E..4..@.@................*HR..;......(.....
........
02:32:28.681934 IP 127.0.0.1.8080 > 127.0.0.1.39630: Flags [.], ack 89, win 512, options [nop,nop,TS val 2431590159 ecr 2431590159], length 0
E..4T.@.@.................;..*HS.....(.....
........
^C
12 packets captured
24 packets received by filter
0 packets dropped by kernel

# curl the localhost on the second container
oc rsh -c nettools-container-2 -n network-trace nettools-dual-pod
sh-5.1# curl http://127.0.0.1:8080/hello.txt
Hello World

```
### OVS Topology on a Physical Node
```bash
# Here is the complete OVS topology, as we can see there are two bridges being created: br-ex enslaves the physical NIC - ens2f0np0, which include 3 ports and the second bridge has N number of ports which connects all the containers via veth pairs.

sh-5.1# ovs-vsctl show
cbab9023-5b75-43cc-93fd-61db4e0d387f
    Bridge br-ex
        Port ens2f0np0
            Interface ens2f0np0
                type: system
        Port br-ex
            Interface br-ex
                type: internal
        Port patch-br-ex_m42-h32-000-r650-to-br-int
            Interface patch-br-ex_m42-h32-000-r650-to-br-int
                type: patch
                options: {peer=patch-br-int-to-br-ex_m42-h32-000-r650}
    Bridge br-int
        fail_mode: secure
        datapath_type: system
        Port "7be093806debefd"
            Interface "7be093806debefd"
        Port "4952fbdba0f3a02"
            Interface "4952fbdba0f3a02"
        ...
        [~150 more container veth interfaces]
        ...
        Port patch-br-int-to-br-ex_m42-h32-000-r650
            Interface patch-br-int-to-br-ex_m42-h32-000-r650
                type: patch
                options: {peer=patch-br-ex_m42-h32-000-r650-to-br-int}
        Port ovn-k8s-mp0
            Interface ovn-k8s-mp0
                type: internal
        Port ovn-91667b-0
            Interface ovn-91667b-0
                type: geneve
                options: {csum="true", key=flow, local_ip="198.18.0.9", remote_ip="198.18.0.7"}
        Port ovn-ae72c2-0
            Interface ovn-ae72c2-0
                type: geneve
                options: {csum="true", key=flow, local_ip="198.18.0.9", remote_ip="198.18.0.8"}
        ...
        [3 more Geneve tunnels to nodes .5, .6, .10]
        ...
        Port br-int
            Interface br-int
                type: internal
    ovs_version: "3.4.3-66.el9fdp"


# here is a high level flow diagrams of those two bridges: br-ex, br-int and those ports that are connected to containers.
External Network/Internet
        │
        │ (Ethernet cable plugged into Port 1)
        ↓
┌───────────────────────────────────────┐
│       Switch: br-ex                   │
│       (3-port switch)                 │
│                                       │
│  [Port 1]  [Port 2]  [Port 3]       │
│     │         │         │             │
│     │         │         └────────┐    │
│  ens2f0np0  br-ex            patch   │
│  (physical) (virtual)      (virtual) │
└─────────────────────────────────┬─────┘
                                  │
                    Virtual Patch Cable
                    (like an Ethernet cable)
                                  │
┌─────────────────────────────────┴─────┐
│       Switch: br-int                  │
│       (157-port switch)               │
│                                       │
│  [Port 1] [Port 2] [Port 3] ... [157]│
│     │        │        │                │
│   patch    veth1    veth2    ... more │
│  (from     (to      (to              │
│   br-ex)   pod-1)   pod-2)           │
└───────────┬─────────┬─────────────────┘
            │         │
        Container1  Container2  ... (~150 containers)

```

### Container, bridge-port veth pair and physical nic
```bash
# find out which node the pod is running
oc get pod -o wide -n network-trace 
NAME                             READY   STATUS    RESTARTS   AGE   IP             NODE               NOMINATED NODE   READINESS GATES
nettools-dual-pod                2/2     Running   0          15d   10.128.2.43    m42-h32-000-r650   <none>           <none>


# we should be able to curl the static file within that node using the pod IP
[root@m42-h27-000-r650 ~]# oc debug node/m42-h32-000-r650
Temporary namespace openshift-debug-wjxnq is created for debugging node...
Starting pod/m42-h32-000-r650-debug-vtjjz ...
To use host binaries, run chroot /host
Pod IP: 198.18.0.9
If you dont see a command prompt, try pressing enter.
sh-5.1# chroot /host
sh-5.1# curl http://10.128.2.43:8080/hello.txt
Hello World
sh-5.1# 

# use crictl tool to check those two containers running on this host
sh-5.1# crictl ps | grep dual
da7e98b24503f       quay.io/rh_ee_lguoqing/nettools-fedora@sha256:94790b86e5e1db5e80d9b5987ea7c8fa1567a6b6a735ee3f00fb082941ba6a01                                                     2 weeks ago         Running             nettools-container-2                    0                   7be093806debe       nettools-dual-pod
b5ec119e63fa6       quay.io/rh_ee_lguoqing/nettools-fedora@sha256:94790b86e5e1db5e80d9b5987ea7c8fa1567a6b6a735ee3f00fb082941ba6a01                                                     2 weeks ago         Running             nettools-container-1                    0                   7be093806debe       nettools-dual-pod
sh-5.1# 

# examine namespaces of this pod
crictl inspectp 7be093806debe | jq -r '.info.runtimeSpec.linux.namespaces[] | select(.type=="network").path'
/var/run/netns/67f12702-ca28-499f-b79f-e317ce158fe2

# enter that network namespace and examine the network interfaces, we will see a veth pair etho0@if4615, it tells you that this eth0 interface is connected to interface index 4615 on the other side - in this case an interface on the host side.

sh-5.1# nsenter --net=/var/run/netns/67f12702-ca28-499f-b79f-e317ce158fe2 
[systemd]
Failed Units: 1
  NetworkManager-wait-online.service
[root@m42-h32-000-r650 /]# ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host 
       valid_lft forever preferred_lft forever
2: eth0@if4615: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1400 qdisc noqueue state UP group default 
    link/ether 0a:58:0a:80:02:2b brd ff:ff:ff:ff:ff:ff link-netns b4c80c54-362d-405e-8c54-a170a7de8386
    inet 10.128.2.43/23 brd 10.128.3.255 scope global eth0
       valid_lft forever preferred_lft forever
    inet6 fe80::858:aff:fe80:22b/64 scope link 
       valid_lft forever preferred_lft forever

# if we grep the interface index on the host side, we will see that this interface is connect to the other end - the container side on the second index - "2: eth0@if4615"  <--> 4615: 7be093806debefd@if2, you might have noticed, the interface name here used is the same as the pod ID. Check ref[1] more information on Linux interfaces. 

sh-5.1# ip link show | grep 4615
4615: 7be093806debefd@if2: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1400 qdisc noqueue master ovs-system state UP mode DEFAULT group default 

# from the output above, we can also see that veth 4615 is enslaved by a master called ovs-system, the details of this interface shows that it is an openvswitch[2] interface which is not a standard linux network interface. This OVN-kubernetes[3] architure diagram also shows how OVS fits into the picture. 

sh-5.1# ip -d link show ovs-system
11: ovs-system: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN mode DEFAULT group default qlen 1000
    link/ether e2:43:fd:d1:2e:58 brd ff:ff:ff:ff:ff:ff promiscuity 1  allmulti 0 minmtu 68 maxmtu 65535 
    openvswitch addrgenmode eui64 numtxqueues 1 numrxqueues 1 gso_max_size 65536 gso_max_segs 65535 tso_max_size 65536 tso_max_segs 65535 gro_max_size 65536 gso_ipv4_max_size 65536 gro_ipv4_max_size 65536

# There are 3 devices assoicated with ovs-system, ens2f0np0 -  the physical nic that's enslaved by ovs-system, 
genev_sys_6081 - for geneve tunneling. 
sh-5.1# ip link show | grep "ovs-system" | grep -v "@if"
8: ens2f0np0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq master ovs-system state UP mode DEFAULT group default qlen 1000
11: ovs-system: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN mode DEFAULT group default qlen 1000
14: genev_sys_6081: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 65000 qdisc noqueue master ovs-system state UNKNOWN mode DEFAULT group default qlen 1000


# capture packets go through the veth port on the host side
[root@m42-h27-000-r650 ~]# oc debug node/m42-h32-000-r650
Temporary namespace openshift-debug-r97rt is created for debugging node...
Starting pod/m42-h32-000-r650-debug-sgwtr ...
To use host binaries, run chroot /host
Pod IP: 198.18.0.9
If you dont see a command prompt, try pressing enter.
sh-5.1# tcpdump -i 7be093806debefd -n
dropped privs to tcpdump
tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on 7be093806debefd, link-type EN10MB (Ethernet), snapshot length 262144 bytes
04:50:13.113152 IP 10.128.2.43 > 8.8.8.8: ICMP echo request, id 15, seq 1, length 64
04:50:13.127747 IP 8.8.8.8 > 10.128.2.43: ICMP echo reply, id 15, seq 1, length 64
04:50:18.590973 ARP, Request who-has 10.128.2.1 tell 10.128.2.43, length 28
04:50:18.591379 ARP, Reply 10.128.2.1 is-at 0a:58:a9:fe:01:01, length 28


# capture packets go through container eth0 nic
[root@m42-h27-000-r650 ~]#  oc rsh nettools-dual-pod
Defaulted container "nettools-container-1" out of: nettools-container-1, nettools-container-2
sh-5.1# tcpdump -i eth0 -n
dropped privs to tcpdump
tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on eth0, link-type EN10MB (Ethernet), snapshot length 262144 bytes
04:50:13.113137 IP 10.128.2.43 > 8.8.8.8: ICMP echo request, id 15, seq 1, length 64
04:50:13.127754 IP 8.8.8.8 > 10.128.2.43: ICMP echo reply, id 15, seq 1, length 64
04:50:18.590915 ARP, Request who-has 10.128.2.1 tell 10.128.2.43, length 28
04:50:18.591382 ARP, Reply 10.128.2.1 is-at 0a:58:a9:fe:01:01, length 28

# capture packets go through the physical nic
[root@m42-h27-000-r650 ~]# oc debug node/m42-h32-000-r650
Temporary namespace openshift-debug-r97rt is created for debugging node...
Starting pod/m42-h32-000-r650-debug-sgwtr ...
To use host binaries, run chroot /host
Pod IP: 198.18.0.9
If you dont see a command prompt, try pressing enter.
sh-5.1# tcpdump icmp -i ens2f0np0 -n
dropped privs to tcpdump
tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on ens2f0np0, link-type EN10MB (Ethernet), snapshot length 262144 bytes
04:50:13.115888 IP 198.18.0.9 > 8.8.8.8: ICMP echo request, id 15, seq 1, length 64
04:50:13.124988 IP 8.8.8.8 > 198.18.0.9: ICMP echo reply, id 15, seq 1, length 64


# send a ICMP packet to 8.8.8.8
[root@m42-h27-000-r650 ~]# oc debug node/m42-h32-000-r650
Temporary namespace openshift-debug-mhpwp is created for debugging node...
Starting pod/m42-h32-000-r650-debug-nc7fk ...
To use host binaries, run chroot /host
Pod IP: 198.18.0.9
If you dont see a command prompt, try pressing enter.
sh-5.1# chroot /host
sh-5.1# nsenter --net=/var/run/netns/67f12702-ca28-499f-b79f-e317ce158fe2
[systemd]
Failed Units: 1
  NetworkManager-wait-online.service
[root@m42-h32-000-r650 /]# ping 8.8.8.8 -c 1
PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data.
64 bytes from 8.8.8.8: icmp_seq=1 ttl=107 time=14.5 ms

--- 8.8.8.8 ping statistics ---
1 packets transmitted, 1 received, 0% packet loss, time 0ms
rtt min/avg/max/mdev = 14.507/14.507/14.507/0.000 ms
[root@m42-h32-000-r650 /]# 


# The tcp dump between veth port on the host side and the nic eth0 within the container looks almost identical, which is what we expect for a veth pair, can you tell the difference between those two? 

# Looking at the physical nic tcp dump, the source IP address changed from 10.128.2.43 to 198.18.0.9 which indicates some sort of NATing was going on the OVN layer.
```

## Requirements

- OpenShift cluster
- Container runtime (Podman, Docker, or CRI-O)

## Notes

- The networking tools container requires privileged access for some operations (e.g., packet capture on host interfaces)

## References
1. [Linux interfaces](https://developers.redhat.com/blog/2018/10/22/introduction-to-linux-interfaces-for-virtual-networking)
2. [Openvswitch](https://docs.openvswitch.org/en/latest/intro/what-is-ovs/)
3. [OVN-kubernetes](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/ovn-kubernetes_network_plugin/ovn-kubernetes-architecture-assembly#ovn-kubernetes-architecture-con)

