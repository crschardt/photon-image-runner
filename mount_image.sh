#!/bin/bash
set -euo pipefail

image="$1"
additional_mb=$2
minimum_free=$3
root_location=$4

####
# Prepare and mount the image
####

case ${root_location,,} in
    partition* )
        rootpartition=${root_location#*=}
        loopdev=$(losetup --find --show --partscan ${image})
        rootdev="${loopdev}p${rootpartition}"
    ;;
    offset* )
        rootpartition=1
        rootoffset=${root_location#*=}
        loopdev=$(losetup --find --show --offset=${rootoffset} ${image})
        rootdev="${loopdev}"
    ;;
    * ) 
        echo "Don't understand value for root_location: ${root_location}"
        exit 1
    ;;
esac

echo "loopdev=${loopdev}" >> "$GITHUB_ENV"
echo "rootpartition=${rootpartition}" >> "$GITHUB_ENV"
echo "rootdev=${rootdev}" >> "$GITHUB_ENV"
echo "Root device is: ${rootdev}"

echo "Partitions in the mounted image:"
lsblk "${loopdev}"

part_type=$(blkid -o value -s PTTYPE "${loopdev}")
echo "part_type=${part_type}" >> "$GITHUB_ENV"
echo "Image is using ${part_type:=NO} partition table"

rootdir="./rootfs"
rootdir="$(realpath ${rootdir})"
mkdir --parents ${rootdir}

if [[ ${minimum_free} -gt 0 ]]; then
    mount "${rootdev}" "${rootdir}"
    echo "Space in root directory:"
    df --block-size=M "${rootdir}"
    free=$( df --block-size=$((1024*1024)) --output=avail "${rootdir}" |  tail -n1)
    umount "${rootdir}"
    need=$(( ${minimum_free} - ${free} ))
    if [[ ${additional_mb} -lt ${need} ]]; then
        additional_mb=${need}
    fi
fi

if [[ ${additional_mb} -gt 0 ]]; then
    echo "Resizing the disk image by ${additional_mb}MB"
    dd if=/dev/zero bs=1M count=${additional_mb} >> ${image}
    losetup --set-capacity ${loopdev}
    if [[ "${part_type}" == "gpt" ]]; then
        sgdisk --move-second-header "${loopdev}"
    fi
    if [[ ${rootpartition} -gt 0 ]]; then
        parted --script "${loopdev}" resizepart ${rootpartition} 100%
    fi
    e2fsck -p -f "${rootdev}"
    resize2fs "${rootdev}"
    echo "Finished resizing disk image."
fi

sync

echo "Partitions in the mounted image:"
lsblk "${loopdev}"

mount "${rootdev}" "${rootdir}"
echo "rootdir=${rootdir}" >> "$GITHUB_ENV"
echo "Root directory is: ${rootdir}"

echo "Space in root directory:"
df --block-size=M "${rootdir}"

# Set up the environment
mount -t proc /proc "${rootdir}/proc"
mount -t sysfs /sys "${rootdir}/sys"
mount -t tmpfs /tmpfs "${rootdir}/run"
mount --rbind /dev "${rootdir}/dev"

# Temporarily replace resolv.conf for networking
mv -v "${rootdir}/etc/resolv.conf" "${rootdir}/etc/resolv.conf.bak"
cp -v /etc/resolv.conf "${rootdir}/etc/resolv.conf"
