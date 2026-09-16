#!/bin/bash

echo 'This is not really a script, read through it, it is a set of instructions for installing qemu and preparing your build host'
exit 0

# specific to Intel x86_64 (aka amd64)
# covers:
# 1) installing qemu
# 2) creating base disks
# 3) copying UEFI baseline image (part of secure boot/modern laptops, technically this is optional)
# 4) downloading a ready-made Linux distribution as our build environment
# 5) installing distribution as our build disk image
# 6) booting the installed distribution

# 1. enable hypervisor features and install WSL if you haven't already
optionalfeatures.exe (enable Windows Hypervisor Platform)
# Optional alternative is MSYS2, e.g. see msys2.org (msys2 is windows-native, unlike WSL which itself is virtualized)
wsl --install

# 2. install qemu (now assuming you're in an ubuntu WSL) and add user permissions
sudo apt-get install qemu-system-86
sudo adduser $(id -un) libvirt
sudo adduser $(id -un) kvm
sudo chown root:kvm /dev/kvm
sudo chmod 660 /dev/kvm
# you may need to restart the ubuntu-container at this point

# 2. create pair of qemu disks (60GB for build, 20GB for target are good starting points, depending on what you want, e.g. X windows or not, embedded, etc)
#    use the qemu copy-on-write format (qcow2) for snapshot/recovery options
qemu-img create -f qcow2 build-host.qcow2 30G
qemu-img create -f qcow2 lfs-target.qcow2 20G

# 3. copy UEFI baseline for Intel systems, note this is one major distinction from aarch64/ARM systems (and RISC-V)
# note the secboot version is for true secure boot, we are not here discussing secboot although if interest arises, we could
# see https://wiki.debian.org/SecureBoot/VirtualMachine for more details if interested
cp /usr/share/OVMF/OVMF_VARS_4M.fd OVMF_VARS-build-host.fd
cp /usr/share/OVMF/OVMF_VARS_4M.fd OVMF_VARS-lfs-target.fd

# 4. download appropriate ubuntu 26.04 image - specific to amd64
Navigate to: https://ubuntu.com/download/desktop/thank-you?version=26.04.1&architecture=amd64&lts=true
OR (direct download)
wget https://cdimage.ubuntu.com/releases/26.04.1/release/ubuntu-26.04.1-live-server-amd64.iso

# 5. run qemu and install this distribution on the build-host disk
# note, many of the incantations are specific to architecture (aarch64 vs x86_64), referring to drivers built for those platforms
# set up some temporary variables for the parts we'll swap out
QDISPLAY="-device virtio-gpu-pci -display default,show-cursor=on -full-screen"
QNODISP="-nographic"

# specify the two disks we'll be targeting: 1 for the build host, 2 for the target linux-from-scratch we are building
QDRIVE1="-drive file=build-host.qcow2,if=virtio,format=qcow2"
QDRIVE2="-drive file=lfs-target.qcow2,if=virtio,format=qcow2"
# alternatively
QDRIVE1="-hda build-host.qcow2"

# mount distribution's iso directly (will boot from this)
QDRIVEINSTALL="-drive file=ubuntu-26.04.1-live-server-amd64.iso,if=virtio,format=raw,readonly=on"
# alternatively
QDRIVEINSTALL="-cdrom ubuntu-26.04.1-live-server-amd64.iso"

# EFI needs a firmware disk and a readwrite disk to emulate what happens on a laptop with full UEFI support
QEFI_RO="-drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd"
# the read-write small disk holds boot selection and boot-persistent data, this will get 
# written to as you boot and therefore its binary data will mutate over time
QEFI_RW="-drive if=pflash,format=raw,file=OVMF_VARS-build-host.fd"

# Differences bw Mac aarch64:
# whpx instead of hvf
# virtio-net-pci instead of virtio-net-device on aarch64
# -M q35 and -accel kvm (note, if working in a qemu on MSYS2 or bare windows, use -accel whpx)
# OVMF_<>_4M.fd instead of edk-aarch64

# boot the system with the install disk and the build host disk - enable graphics and follow the instructions to install on that disk
qemu-system-x86_64 -M q35 -accel kvm -cpu host -smp 4 -m 8192 \
  $QEFI_RO \
  $QEFI_RW \
  $QDRIVE1 \
  $QDRIVEINSTALL \
  -device virtio-net-pci,netdev=n0 \
  -netdev user,id=n0,hostfwd=tcp::2222-:22 \
  -boot menu=on

# pick a username and password - this will be used every time you log in and for superuser permissions
# enable openssh server, this will let you log in via additional terminals (qemu tag with hostfwd for forwarding a port locally to the ssh port on the ubuntu install)
# everything else can be default, including the warning about erasing your disk - this is limited to the disk you mounted in qemu
# pay attention to the install options however, these delineate the few required inputs for as-close-to-automated installation as is possible today
# watch the "full log" when its installing - these are similar to what you'll be doing for LFS
# note, you are sharing your network to this virtual machine with the qemu tag "-device virtio-net-pci,netdev=n0"
# eventually (half an hour or more) you will get an option to reboot within the virtual machine, go ahead, your system is installed
# you can then shutdown with "sudo shutdown -h now", or you can explore the system and disks available to you
# WORK: what disk drives are available to you? What (generally speaking) is on them?

# 6. once install is done and you've shut down the qemu emulator, start it again with the build host and the LFS disk target (can use nographics if you like)
qemu-system-x86_64 -M q35 -accel kvm -cpu host -smp 4 -m 8192 \
  $QEFI_RO \
  $QEFI_RW \
  $QDRIVE1 \
  $QDRIVE2 \
  -device qemu-xhci -device usb-kbd -device usb-tablet \
  -netdev user,id=n0,hostfwd=tcp::2222-:22 \
  $QNODISP \
  -device virtio-net-pci,netdev=n0

# once booted, you can also log in via ssh localhost -p 2222
ssh -l <user you picked> localhost -p 2222
# if you are in a trusted environment, create an ssh key on your computer (not in qemu) and copy its pubkey 
ssh-keygen -t ed25519 -f ./id_ed25519_lfs
# to the .ssh/authorized_keys file inside your logged-in qemu build host
# ensure permissions are correct inside the emulated build host:
chmod go-rw .ssh/authorized_keys
# then, test ssh (anyone with the non .pub file can get access via ssh)
ssh -i ./id_ed25519_lfs -l $INSTALLUSER localhost -p 2222

# 7. Done on the host side, the remaining work all happens inside qemu, I suggest writing aliases/shell functions to help you start up qemu and work with it 
# flexibly from outside the emulated running build or lfs system, here's a few example aliases:
alias lt="ls -ltr | tail"
alias ll="ls -l"
alias sslfs="ssh -p 2222 nano@localhost"

# 8. shutdown the VM and take an overlay - work in snapshots whenever there is any chance of system changes
qemu-img create -f qcow2 -b build-host.qcow2 -F qcow2 build-host-phase0.qcow2

# 9. boot with this overlay (alternatively, could work in a "snapshot", which is contained in the same qcow2 image)
QDRIVE1="-drive file=build-host-phase0.qcow2,if=virtio,format=qcow2"

