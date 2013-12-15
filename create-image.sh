#!/bin/bash -e

program="$0"
image=""
distribution="wheezy"
mirror="http://archive.raspbian.org/raspbian"
image_size="512M"
boot_size="32M"
firmware_url="https://github.com/raspberrypi/firmware/tarball/master"
hostname="raspberry"
password="raspberry"
additional_packages="locales,console-common,openssh-server"

help="Usage: $0 IMAGEFILE
Create the minimal raspberry-image IMAGEFILE.

Options:
  -d DISTRIBUTION            set the raspbian distribution to DISTRIBUTION
                             (default is '$distribution').
  -m MIRROR                  use MIRROR (default is $mirror).
  -s IMAGE_SIZE              create an image of size IMAGE_SIZE
                             (default is $image_size).
  -b BOOT_SIZE               set the size of the boot-partition to BOOT_SIZE
                             (default is $boot_size).
  -f FIRMWARE_URL            download firmware from FIRMWARE_URL.
                             (default is $firmware_url).
  -n HOSTNAME                set the system's hostname to HOSTNAME
                             (default is $hostname)
  -p PASSWORD                set root-password to PASSWORD
                             (default is $password)
  -a A,B,C                   also install packages A,B,C
                             (default is $additional_packages)
  -h                         display this help and exit

Make sure qemu for emulating armhf is available ('apt-get install qemu-user
qemu-user-static binfmt-support' on debian-based systems)."

cmdline="dwc_otg.lpm_enable=0 console=ttyAMA0,115200 kgdboc=ttyAMA0,115200 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait"

fstab="# <filesystem> <mount point> <type> <options> <dump> <pass>
proc           /proc         proc   defaults  0      0
/dev/mmcblk0p1 /boot         vfat   defaults  0      0"

interfaces="auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp"

modules="vchiq
snd_bcm2835"

trap_code=""
function at_exit {
    trap_code="$1; $trap_code"
    trap -- "$trap_code" EXIT
}

function print_status {
    echo -e "\033[1m$@\033[0m" >&2
}

function check_size {
    if ( ! echo "$1" | grep -E '[0-9]+[KMG]' 1>/dev/null ); then
        echo "$program: $1 is not a valid size"
        exit 2
    fi
}

function check_program {
    if ( ! which "$1" &>/dev/null ); then
        echo "$program: Cannot find $1. Please make sure it is installed and in PATH."
        exit 2
    fi
}

function parse_arguments {
    while getopts d:m:s:b:f:n:p:a:h flag; do
        case $flag in
            d)
                distribution="$OPTARG"
                ;;
            m)
                mirror="$OPTARG"
                ;;
            s)
                check_size "$OPTARG"
                image_size="$OPTARG"
                ;;
            b)
                check_size "$OPTARG"
                boot_size="$OPTARG"
                ;;
            f)
                firmware_url="$OPTARG"
                ;;
            n)
                hostname="$OPTARG"
                ;;
            p)
                password="$OPTARG"
                ;;
            a)
                additional_packages="$OPTARG"
                ;;
            h)
                echo "$help"
                exit 0
                ;;
            ?)
                echo "Try '$program -h' for more information." >&2
                exit 1
                ;;
        esac
    done

    shift $[OPTIND - 1];

    if [[ $# != 1 ]]; then
        echo "$0: No IMAGEFILE given" >&2
        echo "Try '$0 -h' for more information." >&2
        exit 1
    fi

    image="$1"
}

function check_root {
    if [[ $(whoami) != "root" ]]; then
        echo "$program: root privileges required" >&2
        exit 1
    fi
}

function create_blank {
    dd if=/dev/zero of="$1" bs="$2" count=1 2>&1 | grep -v records 1>&2
}

function partition {
    (
        fdisk "$1" << EOF
o
n
p
1

+$2
t
c
n
p
2


w
EOF
    ) 2>&1 1>/dev/null | grep -v 'Changes will\|After that' 1>&2
}

function setup_loopdevice {
    offset=$[$(fdisk -l "$1" | grep "$1"$2 | sed -re "s/$1$2[\t ]+([0-9]+).*/\1/") * 512]
    size=$[$(fdisk -l "$1" | grep "$1"$2 | sed -re "s/$1$2[\t ]+[0-9]+[\t ]+([0-9]+).*/\1/") * 512 - $offset]
    loop=$(losetup -f)

    losetup --offset "$offset" --sizelimit="$size" "$loop" "$1"
    at_exit "losetup -d \"$loop\""

    retval="$loop"
}

function create_filesystems {
    mkfs.vfat "$1"
    mkfs.ext4 "$2"
}

function mount_filesystems {
    mountpoint="$(mktemp -d rasbian-image-mount.XXXXXXXXXX)"
    at_exit "rmdir \"$mountpoint\""

    mount "$2" "$mountpoint"
    at_exit "umount \"$mountpoint\""

    # these get mounted by debootstrap
    at_exit "umount \"$mountpoint/proc\" 1>/dev/null 2>&1 || true"
    at_exit "umount \"$mountpoint/sys\" 1>/dev/null 2>&1 || true"

    mkdir -p "$mountpoint/boot"
    mount "$1" "$mountpoint/boot"
    at_exit "umount \"$mountpoint/boot\""

    retval="$mountpoint"
}

function run_debootstrap {
    debootstrap --foreign --arch=armhf --include="$4" "$1" "$2" "$3"
    cp $(which qemu-arm-static) "$2/usr/bin/"
    at_exit "rm -f \"$2/usr/bin/qemu-arm-static\""
    LANG=C chroot "$2" /debootstrap/debootstrap --second-stage
}

function add_firmware {
    tarball="$(mktemp rasbian-firmware.XXXXXXXXXX.tar.gz)"
    wget "$1" -O "$tarball"
    at_exit "rm -f \"$tarball\""

    tar --wildcards --strip-components=2 -C "$2/boot" -zxf "$tarball" "raspberrypi-firmware*/boot"
    mkdir -p "$2/lib/modules"
    tar --wildcards --strip-components=2 -C "$2/lib/modules" -zxf "$tarball" "raspberrypi-firmware*/modules"
    mkdir -p "$2/opt"
    tar --wildcards --strip-components=3 -C "$2/opt" -zxf "$tarball" "raspberrypi-firmware*/hardfp/opt"
}

function configure_system {
    echo "$cmdline" > "$1/boot/cmdline.txt"
    echo "$fstab" > "$1/etc/fstab"
    echo "$2" > "$1/etc/hostname"
    echo "$interfaces" > "$1/etc/network/interfaces"
    echo "$modules" > "$1/etc/modules"
    echo "deb $3 $4 main contrib non-free" > "$1/etc/apt/sources.list"
    chroot "$1" /bin/sh -c "echo 'root:$5' | chpasswd"
    chroot "$1" /bin/sh -c "apt-get clean"
}

parse_arguments $*

check_root

check_program fdisk
check_program debootstrap
check_program losetup
check_program mkfs.vfat
check_program mkfs.ext4
check_program qemu-arm-static
check_program wget

print_status "Creating blank image"
create_blank "$image" "$image_size"

print_status "Partitioning image"
partition "$image" "$boot_size"

print_status "Setting up loopdevices"
setup_loopdevice "$image" 1
loop_boot="$retval"
setup_loopdevice "$image" 2
loop_root="$retval"

print_status "Creating filesystems"
create_filesystems "$loop_boot" "$loop_root"

print_status "Mounting image"
mount_filesystems "$loop_boot" "$loop_root"
mountpoint="$retval"

print_status "Running debootstrap"
run_debootstrap "$distribution" "$mountpoint" "$mirror" "$additional_packages"

print_status "Adding firmware"
add_firmware "$firmware_url" "$mountpoint"

print_status "Configuring system"
configure_system "$mountpoint" "$hostname" "$mirror" "$distribution" "$password"

print_status "Done"

