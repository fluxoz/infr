#! /usr/bin/env bash

set -euo pipefail

usage() {
    echo "Usage: $0 -l 'new-project'" 
    echo
    echo "  -l   linode label (optional, default: nixos-<random>"
    echo "  -d   top level domain name, no subdomains."
    echo
    exit 1
}

# Defaults
IMAGE_FILE="./result/nixos.img.gz"
REGION="us-lax"
TYPE="g6-dedicated-2"
ROOT_PASS=$(openssl rand -base64 32)  # or use a fixed one
IMAGE_ID=""
LINODE_API="https://api.linode.com/v4"
LATEST_IMAGE=""
LABEL="nixos-$RANDOM"
DOMAIN_SHORT=""

while getopts ":l:d:h" opt; do
    case ${opt} in
	l) LABEL="$OPTARG" ;;
	d) DOMAIN_SHORT="$OPTARG" ;;
        h) usage ;;
        \?|:) usage ;;
    esac
done

shift $((OPTIND -1))

DOMAIN_ID=""
function get_domain_id {
	DOMAIN_RESPONSE=$(curl -s -X GET \
		-H "Authorization: Bearer $LINODE_TOKEN" \
		"$LINODE_API/domains" | jq ".data[] | select(.domain | contains(\"$DOMAIN_SHORT\")) | .id")
	mapfile -t DOMAINS <<< "$DOMAIN_RESPONSE"
	if [[ -z "${DOMAINS[@]}" ]]; then
		echo "[INFO]: Specified domain does not exist"
	fi
	DOMAIN_ID=$(echo "${DOMAINS[0]}")
	if [[ -z "$DOMAIN_ID" ]]; then
		echo "[ERROR]: No domain id found for $DOMAIN_SHORT"
	fi
}

LINODES_TO_DELETE=()
function get_linodes {
	LINODES=$(curl -s -X GET \
			-H "Authorization: Bearer $LINODE_TOKEN" \
			"$LINODE_API/linode/instances/" | jq -r ".data[] | select(.label | contains(\"$LABEL\")) | .id")
	mapfile -t LINODES_TO_DELETE <<< "$LINODES"
}

function delete_linode {
	DELETE=$(curl -s -X DELETE \
		-H "Authorization: Bearer $LINODE_TOKEN" \
		"$LINODE_API/linode/instances/$1")
}

function get_and_delete_records {
	RECORDS=$(curl -s -X GET \
		-H "Authorization: Bearer $LINODE_TOKEN" \
		"$LINODE_API/domains/$DOMAIN_ID/records" | jq -r ".data[] | select(.name | contains(\"$LABEL\")) | .id" ) 
	mapfile -t RECORDS <<< "$RECORDS"
	for RECORD_ID in "${RECORDS[@]}"; do
		if curl -s --fail -X DELETE \
			-H "Authorization: Bearer $LINODE_TOKEN" \
			"$LINODE_API/domains/$DOMAIN_ID/records/$RECORD_ID"; then
			echo "[SUCCESS]: Deleted record id $RECORD_ID under $DOMAIN_SHORT for linode labeled $LABEL"
		else
			echo "[ERROR]: Failed to delete record id $RECORD_ID under $DOMAIN_SHORT for linode labeled $LABEL"
		fi
	done
}

# linode ops
get_linodes
for linode in ${LINODES_TO_DELETE[@]}; do
	delete_linode "$linode"
done

# domain ops
get_domain_id
get_and_delete_records
