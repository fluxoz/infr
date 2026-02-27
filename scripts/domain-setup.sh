#! /usr/bin/env bash

set -euo pipefail

usage() {
    echo "Usage: $0 -l linode-label -d 'domain.name' -t 'domain-type' -e 'soa_email@domain'" 
    echo
    echo "  -d   FQ domain name for project, e.g. project1.mydomain.com"
    echo "  -l   label for linode we want to associate"
    echo "  -e   soa email for domain"
    echo "  -t   type of domain"
    echo
    exit 1
}

# Defaults
LINODE_API="https://api.linode.com/v4"
DOMAIN=""
EMAIL=""
TYPE=""

while getopts "d:l:e:t:h" opt; do
    case ${opt} in
	d) DOMAIN="$OPTARG" ;;
	l) LABEL="$OPTARG" ;;
	e) EMAIL="$OPTARG" ;;
	t) TYPE="$OPTARG" ;;
        h) usage ;;
        \?|:) usage ;;
    esac
done

shift $((OPTIND -1))

if [[ -z "$DOMAIN" || -z "$EMAIL" || -z "$TYPE" || -z "$LABEL" ]]; then
	echo "[ERROR]: Missing required argument"
	usage
	exit 1
fi

DOMAIN_ID=""
function check_if_domain_exists {
	DOMAIN_SHORT=$(echo "$DOMAIN" | sed -r 's/^[^.]*\.//g')
	DOMAIN_RESPONSE=$(curl -s -X GET \
		-H "Authorization: Bearer $LINODE_TOKEN" \
		"$LINODE_API/domains" | jq ".data[] | select(.domain | contains(\"$DOMAIN_SHORT\")) | .id")
	mapfile -t DOMAINS <<< "$DOMAIN_RESPONSE"
	if [[ -z "${DOMAINS[@]}" ]]; then
		# need to create domain?
		echo "[INFO]: Creating domain entry in linode, ensure registrar is using linode nameservers"
		CREATION_RESPONSE=$(curl -s -X POST \
			-H "Authorization: Bearer $LINODE_TOKEN" \
			-H "Content-Type: application/json" \
			-d "{ \"domain\": \"$DOMAIN\", \"soa_email\": \"$EMAIL\", \"type\": \"$TYPE\" }")
	else
		echo "[INFO]: Requested domain exists, adding linode records"
	fi
	DOMAIN_ID=$(echo "${DOMAINS[0]}")
	if [[ -z "$DOMAIN_ID" ]]; then
		echo "[ERROR]: No domain id found for $DOMAIN_SHORT"
	fi
}

IPV4=""
IPV6=""
function get_linode_ips {
	LINODE_RESPONSE=$(curl -s -X GET \
		-H "Authorization: Bearer $LINODE_TOKEN" \
		"$LINODE_API/linode/instances" | jq ".data[] | select(.label | contains(\"$LABEL\"))")
	IPV4_RESPONSE=$(echo "$LINODE_RESPONSE" | jq -r '.ipv4[]')
	IPV6=$(echo "$LINODE_RESPONSE" | jq -r '.ipv6' | sed 's/\/.*$//g')
	mapfile -t IPV4 <<< "$IPV4_RESPONSE"
	IPV4="${IPV4[0]}"
	if [[ -z "$IPV4" || -z "$IPV6" ]]; then
		echo "[ERROR]: missing ipv4 or ipv6 address"
	fi
	echo "[INFO]: Retrieved ipv4 address: $IPV4"
	echo "[INFO]: Retrieved ipv6 address: $IPV6"
}

function create_a_record {
	if curl -o /dev/null --fail -s -X POST \
		-H "Authorization: Bearer $LINODE_TOKEN" \
		-H "Content-Type: application/json" \
		-d "{ \"type\": \"A\", \"name\": \"$DOMAIN\", \"target\": \"$IPV4\" }" \
		"$LINODE_API/domains/$DOMAIN_ID/records"; then
		echo "[SUCCESS]: A record created under $DOMAIN with target $IPV4"
	else
		echo "[ERROR]: Unable to create A record"
		exit 1
	fi
}

function create_aaaa_record {
	if curl -o /dev/null --fail -s -X POST \
		-H "Authorization: Bearer $LINODE_TOKEN" \
		-H "Content-Type: application/json" \
		-d "{ \"type\": \"AAAA\", \"name\": \"$DOMAIN\", \"target\": \"$IPV6\" }" \
		"$LINODE_API/domains/$DOMAIN_ID/records"; then
		echo "[SUCCESS]: AAAA record created under $DOMAIN with target $IPV6"
	else
		echo "[ERROR]: Unable to create AAAA record"
		exit 1
	fi
}

check_if_domain_exists
# domain exists
get_linode_ips
create_a_record
create_aaaa_record
