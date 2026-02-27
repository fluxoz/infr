#! /usr/bin/env bash

set -euo pipefail

usage() {
    echo "Usage: $0 -l 'new-project'" 
    echo
    echo "  -l   linode label (optional, default: nixos-<random>"
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

while getopts ":l:h" opt; do
    case ${opt} in
	l) LABEL="$OPTARG" ;;
        h) usage ;;
        \?|:) usage ;;
    esac
done

shift $((OPTIND -1))

LINODES_TO_DELETE=()
function get_linodes {
	LINODES=$(curl -s -X GET \
			-H "Authorization: Bearer $LINODE_TOKEN" \
			"$LINODE_API/linode/instances/" | jq -r ".data[] | select(.label | contains(\"$LABEL\")) | .id")
	mapfile -t LINODES_TO_DELETE <<< "$LINODES"
}

function delete_linode {
	delete=$(curl -s -X DELETE \
		-H "Authorization: Bearer $LINODE_TOKEN" \
		"$LINODE_API/linode/instances/$1")
}

get_linodes

for linode in ${LINODES_TO_DELETE[@]}; do
	delete_linode "$linode"
done

