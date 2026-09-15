
# create serious faults on the base build-host, but do it in an overlay
# 1: damage a key library or the dynamic loader
qemu-img create -f qcow2 -b build-host.qcow2 -F qcow2 build-host-bug1.qcow2
QDRIVE1="-drive file=build-host-bug1.qcow2,if=virtio,format=qcow2"
# boot with this snapshot in place in case you have to kill qemu (could corrupt the filesystem, a snapshot will contain the damage)
qemu-system-aarch64   -M virt -accel hvf -cpu host -smp 4 -m 8192   $QEFI_RO   $QEFI_RW  -drive file=build-host-bug1.qcow2,if=virtio,format=qcow2   -device qemu-xhci -device usb-kbd -device usb-tablet -netdev user,id=n0,hostfwd=tcp::2222-:22   $QNODISP   -device virtio-net-pci,netdev=n0

# recommended, have a second shell open, AS ROOT user, before doing the following in one window:
cd /lib/aarch64-linux-gnu
sudo mv ld-linux-aarch64.so.1 ld-linux-aarch64.so.1.2
# alternatively, move the c library or another key library
# now try to do _anything_
# there are commands that will still work, but not many...

# there are multiple ways to recover, some easier than others
# WORK: identify 3 different ways to recover from this fault
# WORK: why does what fails, fail?

# 2. boot with the wrong UEFI partition
cp /opt/homebrew/share/qemu/edk2-aarch64-code.fd build-host-vars-fresh.fd
QEFI_RW_WRONG="-drive if=pflash,format=raw,file=build-host-vars-fresh.fd"
qemu-system-aarch64   -M virt -accel hvf -cpu host -smp 4 -m 8192   $QEFI_RO   $QEFI_RW  -drive file=build-host-bug1.qcow2,if=virtio,format=qcow2   -device qemu-xhci -device usb-kbd -device usb-tablet -netdev user,id=n0,hostfwd=tcp::2222-:22   $QNODISP   -device virtio-net-pci,netdev=n0
# this _might_ boot, or it might refuse to do so, why? what is UEFI providing?
# doing more work on the system with different mount points will make this less likely to work

