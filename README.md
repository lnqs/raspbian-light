raspbian-light
==============

The official [Raspbian](http://www.raspbian.org/)-images are to heavy-weight? Including way to much random stuff, you don't need for your current project?

With _create-image.sh_ you've got a script to generate an image-file containing only a basic system. You can _apt-get install_ whatever you need additionally anyway.

Since I don't saw any good reason to do the root-fs-resizing-stuff on the Pi itself, as other distributions do it, I also included _write-image.sh_. This scripts writes the image to the SD-card and expands the root-fs.

Usage
-----

### create-image.sh
./create-image.sh IMAGEFILE

Where IMAGEFILE is the name of the file to write.

The following options may be set additionally:

Option          | Description
----------------|-----------------------------------------------------------------------------------------------------------
-d DISTRIBUTION | set the raspbian distribution to DISTRIBUTION (default is 'wheezy').
-m MIRROR       | use MIRROR (default is http://archive.raspbian.org/raspbian).
-s IMAGE_SIZE   | create an image of size IMAGE_SIZE (default is 512M).
-b BOOT_SIZE    | set the size of the boot-partition to BOOT_SIZE (default is 32M).
-f FIRMWARE_URL | download firmware from FIRMWARE_URL. (default is https://github.com/raspberrypi/firmware/tarball/master).
-n HOSTNAME     | set the system's hostname to HOSTNAME (default is raspberry)
-p PASSWORD     | set root-password to PASSWORD (default is raspberry)
-a A,B,C        | also install packages A,B,C (default is locales,console-common,openssh-server)
-h              | display this help and exit

Make sure qemu for emulating armhf is available ('apt-get install qemu-user qemu-user-static binfmt-support' on debian-based systems).

### write-image.sh
./write-image.sh IMAGEFILE DEVICE

Where IMAGEFILE is the image to write and DEVICE the devicefile of the SD-card to write to.
