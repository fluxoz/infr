#!/usr/bin/env bash

set -euo pipefail

usage() {
    echo "Usage: $0 -i IMAGE_FILE -f"
    echo
    echo "  -i   image file (optional, default: ../result/nixos.img.gz"
    echo "  -r   linode region (optional, default: us-lax"
    echo "  -f   overwrites existing image if found."
    echo
    exit 1
}

# Defaults
REGION="us-lax"
IMAGE_FILE=(./result/nixos*.img.gz)
LINODE_API="https://api.linode.com/v4"
IMAGE_ALREADY_UPLOADED=0

while getopts ":e:p:i:r:fh" opt; do
    case ${opt} in
        i) IMAGE_FILE="$OPTARG" ;;
        r) REGION="$OPTARG" ;;
        h) usage ;;
        \?|:) usage ;;
    esac
done

shift $((OPTIND -1))

: "${LINODE_TOKEN:?LINODE_TOKEN must be set}"

HASH=$(shasum "$IMAGE_FILE" | cut -d ' ' -f 1)

function test_auth {
	if curl -sS -o /dev/null -H "Authorization: Bearer $LINODE_TOKEN" "$LINODE_API/account"; then
		echo "[INFO]: Auth to linode successful"
	else 
		echo "[ERROR]: Unable to auth to linode API"
		exit 1
	fi
}

function delete_old_image {
	curl -X DELETE \
		-H 'accept: application/json' \
		-H "authorization: Bearer $LINODE_TOKEN" \
		"$LINODE_API/images/$1" 
}

function check_for_old_images {
	ALL_IMAGES=$(curl -s -X GET \
		--header 'accept: application/json' \
		--header "authorization: Bearer $LINODE_TOKEN" \
		"$LINODE_API/images")
	OLD_IMAGES=$(echo "$ALL_IMAGES" | jq -r '.data.[] | select(.label | contains("nix-base")) | .id')
	CURRENT_IMAGE=$(echo "$ALL_IMAGES" | jq -r ".data.[] | select(.label | contains(\"$HASH\")) | .id")
	mapfile -t IMAGES <<< "$OLD_IMAGES"
	mapfile -t CURRENT_IMAGE <<< "$CURRENT_IMAGE"
	if [[ -z "${CURRENT_IMAGE[@]}" ]]; then
		if [[ -z "${IMAGES[@]}" ]]; then
			echo "[INFO]: No old images"
		else 
			for IMAGE in "${IMAGES[@]}"; do 
				echo "$IMAGE"
				delete_old_image "$IMAGE"
			done
		fi
	else
		echo "[INFO]: Current image is already in linode."
		IMAGE_ALREADY_UPLOADED=1
		IMAGE_ID=$(echo "$ALL_IMAGES" | jq -r ".data.[] | select(.label | contains(\"$HASH\")) | .id")
		IMAGES_TO_DELETE=$(echo "$ALL_IMAGES" | jq -r ".data.[] | select(.label | contains(\"nix-base\")) | select(.label | contains(\"$HASH\") | not) | .id")
		mapfile -t OTHER_IMAGES <<< "$IMAGES_TO_DELETE"
		if [[ ! -z "${OTHER_IMAGES[@]}" ]]; then
			for IMAGE in "${OTHER_IMAGES[@]}"; do
				delete_old_image "$IMAGE"
			done
		fi
	fi
}

function dummy_upload {
	curl -s -X POST \
	     --url "$LINODE_API/images/upload" \
	     -H 'accept: application/json' \
	     -H "authorization: Bearer $LINODE_TOKEN" \
	     -H 'content-type: application/json' \
	     -d "{ \"label\": \"nix-base_$RANDOM\", \"description\": \"NixOS base image\", \"region\": \"$REGION\" }" | jq -r '.upload_to'
}

function upload {
	echo "[INFO]: Initiating image upload"
	if (( ! $IMAGE_ALREADY_UPLOADED )); then
		UPLOAD_TO=$(curl -s -X POST \
		     --url "$LINODE_API/images/upload" \
		     -H 'accept: application/json' \
		     -H "authorization: Bearer $LINODE_TOKEN" \
		     -H 'content-type: application/json' \
		     -d "{ \"label\": \"nix-base_$HASH\", \"description\": \"NixOS base image\", \"region\": \"$REGION\" }" | jq -r '.upload_to')
		echo "[INFO]: image container created"
		echo "[INFO]: initiating image upload"
		curl -s -X PUT -H "Content-Type: application/octet-stream" --upload-file "$IMAGE_FILE" "$UPLOAD_TO"
		echo "[SUCCESS]: Image upload complete"
	fi
}

function wait_for_available {
	IS_AVAILABLE=0
	while (( ! $IS_AVAILABLE )); do 
		echo "[INFO]: Waiting for image to become available"
		latest_image=$(curl -s -X GET \
			-H "Authorization: Bearer $LINODE_TOKEN" \
			-H "Content-Type: application/json" \
			"$LINODE_API/images" | jq -r ".data.[] | select(.label | contains(\"$HASH\")) | select(.status == \"available\") | .id")
		if [[ ! -z "$latest_image" ]]; then
			echo "[SUCCESS]: new image with hash $HASH is available"
			exit
		fi
		sleep 5
	done
}

test_auth
check_for_old_images
upload "$IMAGE_FILE"
wait_for_available
