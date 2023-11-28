#!/opt/bin/bash

sudocmd=""

# -----------------------------------
# Function to initialize rules
function init_rules() {
	local ip_version=$1
	local LINE_NUM=1
	local chain="RDP"
	local ipt_cmd

	# Define your ipset rule
	read -r -d '' IPSET_RULE4 <<- EOF
	-m set --match-set myRDPset4 src -p tcp --dport 3389 -j ACCEPT
	-m set --match-set myRDPset4 src -p udp --dport 3389 -j ACCEPT
	-i eth+ -p tcp --dport 3389  -j DROP
	-i eth+ -p udp --dport 3389  -j DROP
	-i ppp+ -p tcp --dport 3389  -j DROP
	-i ppp+ -p udp --dport 3389  -j DROP
EOF

	# Define your ipset rule
	read -r -d '' IPSET_RULE6 <<- EOF
	-m set --match-set myRDPset6 src -p tcp --dport 3389  -j ACCEPT
	-m set --match-set myRDPset6 src -p udp --dport 3389  -j ACCEPT
	-i eth+ -p tcp --dport 3389  -j DROP
	-i eth+ -p udp --dport 3389  -j DROP
	-i ppp+ -p tcp --dport 3389  -j DROP
	-i ppp+ -p udp --dport 3389  -j DROP
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
		if [[ $LINE_NUM -eq 1 ]]; then
			# Check if the rule exists
			if $ipt_cmd -C $chain $rule 1>&2; then
				break
			fi
			$ipt_cmd -N $chain            1>&2
			$ipt_cmd -I FORWARD -j $chain 1>&2
		fi
		# Insert the rule at the specified line number
		$ipt_cmd -I $chain $((LINE_NUM)) $rule 1>&2
		((LINE_NUM++))
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