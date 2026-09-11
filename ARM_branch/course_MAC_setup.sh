#!/bin/bash

echo 'This is not really a script, read through it, it is a set of instructions for installing qemu and preparing your build host'
exit 0

# specific to MAC aarch64
# covers:
# 1) installing qemu
# 2) creating base disks
# 3) copying UEFI baseline image (part of secure boot/modern laptops, technically this is optional)
# 4) downloading a ready-made Linux distribution as our build environment
# 5) installing distribution as our build disk image
# 6) booting the installed distribution

# 1. install qemu
# install homebrew if you haven't already:
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
# install qemu via brew
brew install qemu

# 2. create pair of qemu disks (60GB for build, 20GB for target are good starting points, depending on what you want, e.g. X windows or not, embedded, etc)
#    use the qemu copy-on-write format (qcow2) for snapshot/recovery options
qemu-img create -f qcow2 build-host.qcow2 60G
qemu-img create -f qcow2 lfs-target.qcow2 20G

# 3. copy UEFI baseline for aarch64 systems, note this is one major distinction from Intel systems (and RISC-V)
cp /opt/homebrew/share/qemu/edk2-aarch64-code.fd build-host-vars.fd

# 4. download appropriate ubuntu 26.04 image - specific to arm64
Navigate to: https://ubuntu.com/download/desktop/thank-you?version=26.04.1&architecture=arm64&lts=true
OR (direct download)
wget https://cdimage.ubuntu.com/releases/26.04.1/release/ubuntu-26.04.1-live-server-arm64.iso
# very optional and not recommended due to slowness - you CAN run a intel-based arch on an ARM CPU but it will be slow
# For Win: https://ubuntu.com/download/desktop/thank-you?version=26.04.1&architecture=amd64&lts=true

# 5. install this distribution on the build-host disk
# note, many of the incantations are specific to architecture (aarch64 vs x86_64), referring to drivers built for those platforms
# set up some temporary variables for the parts we'll swap out
QDISPLAY="-device virtio-gpu-pci -display default,show-cursor=on -full-screen"
QNODISP="-nographic"

# specify the two disks we'll be targeting: 1 for the build host, 2 for the target linux-from-scratch we are building
QDRIVE1="-drive file=build-host.qcow2,if=virtio,format=qcow2"
QDRIVE2="-drive file=lfs-target.qcow2,if=virtio,format=qcow2"

# mount distribution's iso directly (will boot from this)
QDRIVEINSTALL="-drive file=ubuntu-26.04.1-live-server-arm64.iso,if=virtio,format=raw,readonly=on"

# EFI needs a pristine disk for install and a readwrite disk to emulate what happens on a laptop with full UEFI support
QEFI_RO="-drive if=pflash,format=raw,readonly=on,file=/opt/homebrew/share/qemu/edk2-aarch64-code.fd"
# the read-write small disk holds boot selection and boot-persistent data, this will get written to as you boot and therefore its binary data will mutate over time
QEFI_RW="-drive if=pflash,format=raw,file=build-host-vars.fd"

# boot the system with the install disk and the build host disk - enable graphics and follow the instructions to install on that disk
qemu-system-aarch64 \
  -M virt -accel hvf -cpu host -smp 4 -m 8192 \
  $QEFI_RO \
  $QEFI_RW \
  $QDRIVE1 \
  $QDRIVEINSTALL \
  -device qemu-xhci -device usb-kbd -device usb-tablet \
  -netdev user,id=n0,hostfwd=tcp::2222-:22 \
  $QDISPLAY \
  -device virtio-net-pci,netdev=n0

# pick a username and password - this will be used every time you log in and for superuser permissions
# everything else can be default, including the warning about erasing your disk - this is limited to the disk you mounted in qemu
# pay attention to the install options however, these delineate the few required inputs for as-close-to-automated installation as is possible today

# 6. once install is done and you've shut down the qemu emulator, start it again with the build host and the LFS disk target (can use nographics if you like)
qemu-system-aarch64 \
  -M virt -accel hvf -cpu host -smp 4 -m 8192 \
  $QEFI_RO \
  $QEFI_RW \
  $QDRIVE1 \
  $QDRIVE2 \
  -device qemu-xhci -device usb-kbd -device usb-tablet \
  -netdev user,id=n0,hostfwd=tcp::2222-:22 \
  $QNODISP \
  -device virtio-net-pci,netdev=n0

# once booted, you can also log in via ssh localhost -p 2222
ssh -l $INSTALLUSER localhost -p 2222
# if you are in a trusted environment, create an ssh key on your computer (not in qemu) and copy its pubkey 
# to the .ssh/authorized_keys file inside your logged-in qemu build host
# ensure permissions are correct inside the emulated build host:
chmod go-rw .ssh/authorized_keys

# 7. Done on the host side, the remaining work all happens inside qemu, I suggest writing aliases/shell functions to help you start up qemu and work with it 
# flexibly from outside the emulated running build or lfs system, here's a few example aliases:
alias lt="ls -ltr | tail"
alias ll="ls -l"
alias sslfs="ssh -p 2222 nano@localhost"

