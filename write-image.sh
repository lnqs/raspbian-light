#!/bin/bash -e

program="$0"
image=""
device=""

function parse_arguments {
    if [[ $# != 2 ]]; then
        echo "Usage: $program IMAGEFILE DEVICE"
        exit 2
    fi

    image="$1"
    device="$2"
}

function check_root {
    if [[ $(whoami) != "root" ]]; then
        echo "$program: root privileges required" >&2
        exit 1
    fi
}

function write_image {
    dd if="$1" of="$2" bs=1K 2>&1 | grep -v records 1>&2
}

function resize_partition {
    (
        fdisk "$1" << EOF
d
2
n
p
2


w
EOF
    ) 2>&1 1>/dev/null | grep -v 'Changes will\|After that' 1>&2
}

function resize_filesystem {
    resize2fs "$1$2"
}

parse_arguments $*
check_root
write_image "$image" "$device"
resize_partition "$device"
resize_filesystem "$device" "2"
