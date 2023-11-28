#!/bin/sh


# HOTP(RFC-4226) and TOTP(RFC-6238) implementation
# Compare with Google Authenticator, FreeOTP, Microsoft Authenticator
# Source: https://github.com/SomajitDey/2FA-HOTP-TOTP-Bash

hmac(){
  # Usage: hmac <key in hex> <data to be hashed in hex>
  # The data can also be provided through stdin if not passed as parameter
  local key="${1}"
  local data="${2}"
  [[ -n "${data}" ]] || read -rd '' data
  echo -n "${data}" | xxd -r -p | openssl dgst -sha1 -mac hmac -macopt hexkey:"${key}" | cut -d ' ' -f 2
}; #export -f hmac

keygen(){
  # Generate random 160-bit keys in base32
  local rand; read rand </dev/urandom
  key=$(RANDOM="$(date +%s)"; printf "%x" "${RANDOM}") # Seeding with current time
  hmac "${key}" "${rand}_${SECONDS}" | xxd -r -p | base32
}; #export -f keygen

hotp(){
  # Ref: RFC-4226
  # Usage: hotp <key or secret in base32> <counter>
  local key_hex=$(echo -n "${1}" | base32 -d | xxd -p)
  local counter_hex="$(printf %016x "${2}")" # Get 64 bit hex representation of the int counter
  # Now, simply follow Sec. 5.3 of RFC-4226
  local string=$(hmac "${key_hex}" "${counter_hex}")
  local offset=$(( 2 *  0x${string:39:1}))
  local truncated=${string:$offset:8}
  local masked=$((0x${truncated} & 0x7fffffff))
  printf "%06d\n" $((masked % 1000000))
  >&2 echo $key_hex $counter_hex $string $offset $truncated $masked
}; #export -f hotp

totp(){
  # Ref: RFC-6238
  # Usage: totp <key or secret in base32> [<unix time>]
  # If no unix timestamp is passed as parameter, it defaults to current time
  timestamp=${2:-"$(date +%s)"}
  hotp "${1}" "$((timestamp/30))"
}; #export -f totp
