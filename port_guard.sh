#!/opt/bin/bash

echoerr() { echo "$@" 1>&2; }

LF=$'\n'
CR=$'\r'
is_debug=0
sudocmd=""
bin_path="/opt/bin/bash"
script_path="$(dirname $0)"
echoerr "Home: $script_path"

if [[ -f "$bin_path" ]];then
	bin_path="$(dirname $bin_path)"
else
	bin_path=""
fi

source "$script_path/2fa.sh"
source "$script_path/opt.sh"
secret_key=$(cat "$script_path/secret_key.txt")
secret_key=${secret_key^^}

# -----------------------------------
function finish() { 
	printf -- '-%.0s' {1..20}  1>&2
	echo ""  1>&2
}
trap finish EXIT

# -----------------------------------
echoheader() { 
	headers="${headers}$@${CR}${LF}" 
	echo "$@" 1>&2;
}

echobody() { 
	txtBody="${txtBody}$@${LF}" 
	[ "$is_debug" -gt 0 ] && echo "$@" 1>&2;
}

endheader() {

	RESPONSE_CODE="$1"
	echo "$RESPONSE_CODE" 1>&2;
	
	CONTENT_TYPE="$2"
	if [ -z "$CONTENT_TYPE" ];then
		CONTENT_TYPE="text/html; charset=utf-8"
	fi

	printf "HTTP/1.0 %s\r\n" "$RESPONSE_CODE"
	printf "Cache-Control: no-store,no-cache\r\n"
	printf "Content-Type: %s\r\n" "$CONTENT_TYPE"
	txtBody="${txtBody//%/%%}"
	byteCNT=$(printf "$txtBody" | wc -c)
	LineCNT=$(printf "$txtBody" | wc -l)
#	totalCNT=`expr $byteCNT + $LineCNT`
	printf "Content-Length: %d\r\n" "$byteCNT"
	printf "%s\r\n" "$headers" # End of headers

	# Printing the response body
	printf "%s" "$txtBody"
	
	#---------------------
	d=`date '+%m-%d %T'`
	echoerr "[ ] $RESPONSE_CODE $LineCNT lines $byteCNT bytes | $HTTP_DEBUG"
	echoerr ""
	echoerr ""
	"$bin_path/"sleep 0.2
	exit 0;
}

# -----------------------------------
elapsed() {
	if [ "$1" -eq 0 ];then
		start_time=$(date +%s.%3N)
		echoerr "$2"
	else
		end_time=$(date +%s.%3N)
		echoerr "$2" $(echo "scale=3; x=$end_time - $start_time;if(x<1) print 0; x" | bc)
		start_time=$(date +%s.%3N)
	fi
}

# -----------------------------------
# Function to URL-decode a string
urldecode() {
	local url_encoded=$1
	local url_decoded=""
	local hex_part
	local char_part

	while [[ -n $url_encoded ]]; do
		if [[ $url_encoded =~ ^([^%]*)%([0-9a-fA-F]{2})(.*) ]]; then
			char_part="${BASH_REMATCH[1]}"
			hex_part="${BASH_REMATCH[2]}"
			url_encoded="${BASH_REMATCH[3]}"
			url_decoded+="${char_part}"
			url_decoded+=$(printf "\x$hex_part")
		else
			url_decoded+="$url_encoded"
			break
		fi
	done

	echo "$url_decoded"
}

# Function to get value by key
getValueByKey() {
	local input=$1
	local key=$2
	local value=""
	local mode="header"

	while IFS= read -r line || [[ -n "$line" ]]; do
		if [[ "$line" == "" ]]; then
			mode="body"
			continue
		fi

		if [[ "$mode" == "header" && "$line" == "$key:"* ]]; then
			value="${line#*: }"
			break
		elif [[ "$mode" == "body" && "$line" == *"$key="* ]]; then
			local temp="${line#*$key=}"
			value="${temp%%&*}"
			value=$(urldecode "$value")
			break
		fi
	done <<< "$input"

	echo "$value"
}

# -----------------------------------

	init_rules ipv4
	init_rules ipv6

# -----------------------------------
	LINES=`timeout 0.3s cat`
	LINE_CLEAN=$(echo -n "$LINES" | tr -d "\r" )
	echoerr "--LINE_CLEAN--"
	echoerr "$LINE_CLEAN"

# ---------------------------------------------------
	# Regular expression to match the HTTP method and path
	regex_path="^GET (.*) HTTP/1.[01]"
	if [[ "$LINE_CLEAN" =~ $regex_path ]];then
			path="${BASH_REMATCH[1]}"
			echoerr ""
			echoerr "path $path"
	fi

	# ---------------------------------------------------
	regex_key="key=([0-9]{6})" #string="key=123456"

	if [[ "$LINE_CLEAN" =~ $regex_key ]]; then
		ClientIPv4="$(getValueByKey "$LINE_CLEAN" 'ipv4')"
		ClientIPv6="$(getValueByKey "$LINE_CLEAN" 'ipv6')"
		ClientIP_CF=$(getValueByKey "$LINE_CLEAN" 'cf-connecting-ip')

		echoerr ""
		echoerr "Extracted number: ${BASH_REMATCH[1]}"
		echoerr "ClientIP is $ClientIPv4 $ClientIPv6"
		echoerr "ClientIP CF is $ClientIP_CF"
		echoerr "SOCAT_PEERADDR is $SOCAT_PEERADDR"
		echoerr ""

		if [[ -z "$ClientIP" ]];then
			ClientIP="$ClientIP_CF"
		fi

		rt=$(totp $secret_key)
		if [[ "$rt" -eq "${BASH_REMATCH[1]}" ]]; then
			if [[ -z "$ClientIPv4" && -z "$ClientIPv6" ]];then
				if [[ "$ClientIP" == *.* ]]; then
					add_ipv4 $ClientIP
				elif [[ "$ClientIP" == *:* ]]; then
					add_ipv6 $ClientIP
				else
					echoerr "Text does not contain ':' or '.'"
					echobody "ClientIP is Missing"
					endheader "202 Accepted" "text/plain; charset=UTF-8"
				fi
			else
				if [[ "$ClientIPv4" == *.* ]]; then
					add_ipv4 $ClientIPv4
				fi
				if [[ "$ClientIPv6" == *:* ]]; then
					add_ipv6 $ClientIPv6
				fi
			fi

			echoerr "PASS"
			echobody "OK"
			endheader "200 OK"

		else
			echoerr "BAD $rt"
			endheader "403 Forbidden"
		fi
	elif [[ "$path" == "/" ]];then
			echobody "$(cat "$script_path/index.html")"
			endheader "200 OK"
	else
		endheader "404 Not Found"
	fi
