#!/opt/bin/bash

sudocmd=""

# -----------------------------------
# Function to initialize rules
function init_rules() {
	local ip_version=$1
	local LINE_NUM=0
	local CHAIN="RDP"
	local ipt_cmd

	# Define your ipset rule
	#12345 tcp4 -> PREROUTING(OUT=?) -> DNAT(192.168.5.85:3389) -> FORWARD(OUT=br0) -> 192.168.5.85:3389
	read -r -d '' IPSET_RULE4 <<- EOF
	-C FORWARD -j RDP
	-N RDP
	-I FORWARD -j RDP
	-A RDP -m set --match-set myRDPset4 src -p tcp --dport 3389 -j ACCEPT
	-A RDP -m set --match-set myRDPset4 src -p udp --dport 3389 -j ACCEPT
	-A RDP -p tcp --dport 3389 -j LOG --log-prefix 'RDP tcp4 FW '
	-A RDP -p udp --dport 3389 -j LOG --log-prefix 'RDP udp4 FW '
	-A RDP -i eth+ -p tcp --dport 3389  -j DROP
	-A RDP -i eth+ -p udp --dport 3389  -j DROP
	-A RDP -i ppp+ -p tcp --dport 3389  -j DROP
	-A RDP -i ppp+ -p udp --dport 3389  -j DROP
EOF

	# Define your ipset rule
	# 12345 tcp6 -> nat6 PREROUTING(OUT=?) -> INPUT6(12345) -> socat TCP6TO4(DNAT) -> nat4 POSTROUTING -> 192.168.5.85:3389
	read -r -d '' IPSET_RULE6 <<- EOF
	-C INPUT -j RDP
	-N RDP
	-I INPUT -j RDP
	-A RDP -m set --match-set myRDPset6 src -j ACCEPT
	-A RDP -p tcp -m multiport --dport 11111,11112,11113,53389 -j LOG --log-prefix 'RDP tcp6 IN '
	-A RDP -p udp -m multiport --dport 11111,11112,11113,53389 -j LOG --log-prefix 'RDP udp6 IN '
EOF

	# Choose command based on IP version
	if [ "$ip_version" = "ipv4" ]; then
		ipt_cmd="$sudocmd iptables"
		IPSET_RULE="$IPSET_RULE4"
		$sudocmd ipset -! create myRDPset4 hash:ip  timeout 86400 1>&2
	elif [ "$ip_version" = "ipv6" ]; then
		ipt_cmd="$sudocmd ip6tables"
		IPSET_RULE="$IPSET_RULE6"
		$sudocmd ipset -! create myRDPset6 hash:ip family inet6 timeout 86400 1>&2
	else
		echo "Invalid IP version specified"
		return 1
	fi

	while IFS= read -r rule || [[ -n "$rule" ]]; do
		((LINE_NUM++))
		if [[ $LINE_NUM -eq 1 ]]; then
			# Check if the rule exists
			if $ipt_cmd $rule 1>&2; then
				break
			fi
			echo "$ip_version Init" | tr -d '\n' | logger -t "opt.sh" -p "user.notice";
			continue
		fi
		# Insert the rule at the specified line number
		eval $ipt_cmd $rule 1>&2 || echo $rule
	done <<< "$IPSET_RULE"
}

# -----------------------------------
# Function to initialize rules
function add_ipv4() {
    local ClientIP=$1
    init_rules ipv4
    $sudocmd ipset add myRDPset4 $ClientIP 1>&2
}

function add_ipv6() {
    local ClientIP=$1
    init_rules ipv6
    $sudocmd ipset add myRDPset6 $ClientIP 1>&2
}

function flush() {
    local ClientIP=$1
    $sudocmd iptables  -D FORWARD -j RDP || echo FORWARD4
    $sudocmd iptables  -F RDP            || echo RDP4
    $sudocmd ip6tables -D INPUT   -j RDP || echo INPUT6
    $sudocmd ip6tables -F RDP            || echo RDP6
    $sudocmd ipset flush  myRDPset6      || echo myRDPset6
    $sudocmd ipset flush  myRDPset4      || echo myRDPset4
}
