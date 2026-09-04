# DavidsonLFSFall2026

Repository for Linux From Scratch Fall 2026 Course

This course's build and target environments are maintained in qemu VMs, one is the build, the other is the target.
The build VM is a stock off-the-shelf Ubuntu 26.04 installation. The target is a bare disk or set of disks.
Note, the build should match the user's compute, (e.g. I'm on a macbook air, so mine will need to be aarch64, others with older Macs having Intel PCs or others with Windows PCs will almost certainly be using x86_64) however if you wish to build aarch64 on an Intel PC, that will likely be too slow (and vice versus).
If your qemu is running too slowly, the first thing to check is whether you are using hardware acceleration.
If on the other hand, you do want to cross-compile for a different architecture (e.g. a Raspberry Pi from a Windows PC), you'll be limited to software acceleration - it'll work but it will be much slower because the just-in-time trans-compiler will get constantly called to translate architectures.
