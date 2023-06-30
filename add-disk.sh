#Scan for new disks
echo "- - -" >  /sys/class/scsi_host/host0/scan

#Get disk info
DISK=$(lsblk -d | grep 'disk' | tail -n 1 | cut -d ' ' -f 1)

#VG and LV settings
VG=rootvg
LV=inmxlv

#Fail if disk is already allocated in LVM
if pvs | grep -q $DISK; then
    if [ pvdisplay -v /dev/${DISK}1 | grep "Allocated PE" | egrep -o "[0-9]+" -gt 0 ]; then
        echo "Disk $DISK already allocated in LVM"
        exit 1
    fi
fi

#Create partition table if needed or fail if wrong
if ( parted /dev/$DISK print | grep -q "Partition Table: unknown" ||  parted /dev/$DISK print | grep -q "unrecognised disk label" ); then
    echo "Making label for /dev/${DISK}"
    parted /dev/${DISK} mklabel gpt
elif parted /dev/$DISK print | grep -q "Partition Table: gpt"; then
    echo "GPT partition table already created on ${DISK}"
else
    echo "Existing partition table on ${DISK} is not gpt. Is this the right disk?"
    exit 1
fi

#Create partition if needed
if parted /dev/$disk print -m | grep -q "1:.*xfs"; then
    echo "xfs partition already exists on /dev/${DISK}"
else
    echo "Making xfs partition for /dev/${DISK}"
    parted -a opt /dev/${DISK} mkpart primary xfs 0% 100%
fi

#Add to disk to vg if needed, fail if wrong vg
if pvs | grep -q ${DISK}1; then
    if pvdisplay /dev/${DISK}1 | egrep -q "VG Name.*$VG"; then
        echo "Disk ${DISK}1 already in VG: $VG"
    else
         echo "Disk ${DISK}1 is in the wrong VG. Is this the right disk?"
         exit 1
    fi
else
    echo "Extending VG: $VG with Disk: /dev/${DISK}1 "
    vgextend $VG /dev/${DISK}1
fi

#Create new LV Filesystem for Infomix DB
echo "Create LV: ${LV} with PV: /dev/${DISK}1"
lvcreate -L 10GB -n ${LV} ${VG}
mkfs.ext4 /dev/${VG}/${LV}
echo "Logical Volume ${LV} Created"
mkdir -p /ifmx 
echo /dev/${VG}/${LV}     /ifmx     ext4    defaults        0 0  | cat >> /etc/fstab
mount -a
#echo "Extending LV: /dev/$VG/$LV with PV: /dev/${DISK}1"
#lvextend --resizefs /dev/$VG/$LV /dev/${DISK}1
