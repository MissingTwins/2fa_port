# Guide to Adding 2FA to Incoming Ports on AX86U
## Background
I'm currently using RDP and providing a few public services for my family. Since RDP doesn't support public-private key authentication, my open ports have been subjected to extensive scanning. It seems like there's always someone on the internet trying to exploit my ports.

To combat this, I've decided to take action.

I've made a script based on 2FA. This script creates a simple WebUI for authentication and then adds the authenticated IP to IPSet, and insert RDP chain at top of iptabes/ip6tabes FORWARD chain, allowing only registered IPs access.

The script is built on Bash (which can be converted to Shell later), socat, OpenSSL, iptables, ip6tables, IPSet, xxd, base32 (this can be replaced with a script), and sleep(less than 1s). The 'date' command is also used, but it's optional.

The WebUI automatically detects your public IPv4 and IPv6 addresses and sends them to the backend to be added to IPSet.

## Installation
This project comprises five files:
 - 1. port_guard.sh: The main script.
 - 2. 2fa.sh: A modified version of a 2FA library, credit to [2FA-HOTP-TOTP-Bash](https://github.com/SomajitDey/2FA-HOTP-TOTP-Bash).
 - 3. opt.sh: Options for post-authentication processes.
 - 4. index.html: The WebUI for you to input 2fa code.
 - 5. secret_key.txt: Your private key.(Empty YOU MUST GENERATE YOURS) This can be used with 1Password, Google Authenticator, or Microsoft Authenticator.

Setup environment and dependencies  
`opkg update && opkg install bash`  
`nano /jffs/configs/profile.add`  
`	[ -f /opt/bin/bash ] && exec /opt/bin/bash`  
`opkg install xxd coreutils-base32 coreutils-sleep coreutils-date`

You can generate the private key using the command:  
`source ./2fa.sh; keygen | tee secret_key.txt`  
`RD76DLH7WBOGF56JHZALFHEMXQ2JRV5Y`  

The script can be launched as(replace 192.168.77.1 with your own router LAN IP)  
`chmod +x .port_guard.sh`  
`socat -d TCP4-LISTEN:65432,reuseaddr,fork,bind=192.168.77.1 SYSTEM:/opt/etc/rdp/port_guard.sh,pipes`  
Then access the WebUI by  
`http://192.168.77.1:65432`  

## Setup https
- 1. Download your personal domain name cert and key put them inside a folder such as domain.com
- 2. Install stunnel  
`opkg install stunnel`  
- 3. Configure stunnel
```
nano /opt/etc/rdp/stunnel.cfg
	[https]
	accept = 7443
	connect = 192.168.77.1:7777
	cert = /opt/etc/rdp/domain.com/certificate.cer 
	key = /opt/etc/rdp/domain.com/private.key
```
- 4. Start stunnel
`stunnel /opt/etc/rdp/stunnel.cfg`
- 5. Turn on port
`iptables -I INPUT -p tcp --dport 7443 -j ACCEPT`  
`ip6tables -I INPUT -p tcp --dport 7443 -j ACCEPT`  
- 6. set your ota.domain.com to router's public address
- 7. open https://ota.domain.com:7443/

Optional: It is better to put the WebUI behind nginx proxy so you can utilize https or cloudflare protection.
```
 server {
	server_name "~^(mfa)\.domain\.com$";
	listen 127.0.0.1:1443 ssl proxy_protocol;
	include	/etc/nginx/domain.comm.conf; #<-- your ssl settings
	access_log /var/log/nginx/access_mfa.log main2;
	proxy_set_header	Host	$http_host;
	location = / {
		#proxy_pass	http://192.168.77.1:65432/;
		proxy_pass	https://ota.domain.com:7443/;
	}
}
```

## Planning
iOS Shortcuts + A-Shell Automation

## Example
Front End  
![image](https://github.com/MissingTwins/2fa_port/assets/146804746/7dba7a9d-3b50-4bbb-aa87-dc867e64a434)

Server End
```
--------------------
Home: .
--LINE_CLEAN--
POST / HTTP/1.1
Host: mfa.domain.com
X-Real-IP: 141.xx.xx.xx
X-Forwarded-For: 141.xx.xx.xx
Connection: close
Content-Length: 35
cf-connecting-ip: 150.xx.xx.xxx
x-forwarded-proto: https
cf-visitor: {"scheme":"https"}
user-agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:120.0) Gecko/20100101 Firefox/120.0
accept: */*
accept-language: en-US,en;q=0.5
referer: https://mfa.domain.com/
content-type: application/x-www-form-urlencoded;charset=UTF-8
origin: https://mfa.domain.com
sec-fetch-dest: empty
sec-fetch-mode: cors
sec-fetch-site: same-origin
cdn-loop: cloudflare

key=317521&ipv4=150.xx.xx.xxx&ipv6=

Extracted number: 317521
ClientIP is 150.xx.xx.xxx
ClientIP CF is 150.xx.xx.xxx
SOCAT_PEERADDR is 10.9.8.14

845317521
PASS
200 OK
[ ] 200 OK 1 lines 3 bytes |
```
iptables, REJECT is for test purpose.
```
# iptables -nvL RDP
Chain RDP (1 references)
 pkts bytes target     prot opt in     out     source               destination
   15   835 ACCEPT     tcp  --  *      *       0.0.0.0/0            0.0.0.0/0            match-set myRDPset4 src tcp dpt:3389
    0     0 ACCEPT     udp  --  *      *       0.0.0.0/0            0.0.0.0/0            match-set myRDPset4 src udp dpt:3389
  626 32480 REJECT     tcp  --  ppp+   *       0.0.0.0/0            0.0.0.0/0            tcp dpt:3389 reject-with icmp-port-unreachable
    0     0 DROP       tcp  --  eth+   *       0.0.0.0/0            0.0.0.0/0            tcp dpt:3389
    0     0 DROP       udp  --  eth+   *       0.0.0.0/0            0.0.0.0/0            udp dpt:3389
  156  8072 DROP       tcp  --  ppp+   *       0.0.0.0/0            0.0.0.0/0            tcp dpt:3389
    0     0 DROP       udp  --  ppp+   *       0.0.0.0/0            0.0.0.0/0            udp dpt:3389
# ip6tables -nvL RDP
Chain RDP (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 ACCEPT     tcp      *      *       ::/0                 ::/0                 match-set myRDPset6 src tcp dpt:3389
    0     0 ACCEPT     udp      *      *       ::/0                 ::/0                 match-set myRDPset6 src udp dpt:3389
    0     0 DROP       tcp      eth+   *       ::/0                 ::/0                 tcp dpt:3389
    0     0 DROP       udp      eth+   *       ::/0                 ::/0                 udp dpt:3389
    0     0 DROP       tcp      ppp+   *       ::/0                 ::/0                 tcp dpt:3389
    0     0 DROP       udp      ppp+   *       ::/0                 ::/0                 udp dpt:3389
```
