# Cutiepie - A very small linux live image

Cutiepie is a linux live image that is do darn cute and small. It only contains the kernel and a statically linked version of busybox. Not even a libc implementation is included.

To build it simply run the build script

```bash
> ./build.sh
```

This will fetch all the required resources and compile them for you. You can also pass additional arguments to skip building some parts:
- `-s` - Will skip the download and extract step
- `-k` - Will skip building the kernel
- `-b` - Will skip building busybox

After a successful build you could run the following command to skip buiilding everything again:

```bash
> ./build.sh -skb
```

After everything is compiled you should end up with a `cutiepie.iso` file, this is currently only bootable in legacy/bios mode. A convenience script to boot with qemu is provided:

```bash
> ./qemu.sh
```

### System manager

You might notice there is a folder called system, that is a rather broken and not working attempt at building a simple init system to replace the busybox provided one. It currently doesn't really do anything beside being configured for completely libc free operation.

# Building requirements

// TODO
