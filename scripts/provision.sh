#! /usr/bin/env bash

set -euo pipefail

echo "[INFO]: running provision.sh"

usage() {
    echo "Usage: $0 -r 'us-east' -l 'new-project' -i IMAGE_FILE"
    echo
    echo "  -r   linode region (optional, default: us-lax"
    echo "  -l   linode label (optional, default: nixos-<random>"
    echo "  -i   path to image file"
    echo
    exit 1
}

# Defaults
IMAGE_FILE=(./result/nixos*.img.gz)
REGION="us-lax"
TYPE="g6-dedicated-2"
ROOT_PASS=$(openssl rand -base64 32)  # or use a fixed one
IMAGE_ID=""
LINODE_API="https://api.linode.com/v4"
LATEST_IMAGE=""
LABEL="nixos-$RANDOM"

while getopts ":i:r:t:l:h" opt; do
    case ${opt} in
        r) REGION="$OPTARG" ;;
	t) TYPE="$OPTARG" ;;
	l) LABEL="$OPTARG" ;;
	i) IMAGE_FILE="$OPTARG" ;;
        h) usage ;;
        \?|:) usage ;;
    esac
done

shift $((OPTIND -1))

HASH=$(shasum "$IMAGE_FILE" | cut -d ' ' -f 1)

function get_latest_image {
	LATEST_IMAGE=$(curl -s -X GET \
		-H "Authorization: Bearer $LINODE_TOKEN" \
		-H "Content-Type: application/json" \
		"$LINODE_API/images" | jq -r ".data.[] | select(.label | contains(\"$HASH\")) | .id")
	if [[ -z "$LATEST_IMAGE" ]]; then
		echo "[INFO]: no available image matching our current build hash, running upload script"
		'nix run .#upload'
		get_latest_image
	fi
}

NEW_LINODE_ID=""
function create_linode {
	NEW_LINODE_ID=$(curl -s -X POST $LINODE_API/linode/instances \
		-H "Authorization: Bearer $LINODE_TOKEN" \
		-H "Content-Type: application/json" \
		-d "{
			\"type\": \"$TYPE\",
			\"region\": \"$REGION\",
			\"image\": \"$LATEST_IMAGE\",
			\"root_pass\": \"$ROOT_PASS\",
			\"label\": \"$LABEL\"
		}" | jq '.id')
} 

CONFIG_ID=""
function get_config {
	CONFIG_ID=$(curl -s -X GET \
		-H "Content-Type: application/json" \
		-H "Authorization: Bearer $LINODE_TOKEN" \
		"$LINODE_API/linode/instances/$NEW_LINODE_ID/configs" | jq -r '.data[].id')
}


function update_grub2 {
	RESPONSE=$(curl -s -X PUT \
		-H "Content-Type: application/json" \
		-H "Authorization: Bearer $LINODE_TOKEN" \
		-d '{
			"kernel": "linode/grub2"
		}' \
		"$LINODE_API/linode/instances/$NEW_LINODE_ID/configs/$CONFIG_ID")
}

get_latest_image
create_linode
get_config
update_grub2
