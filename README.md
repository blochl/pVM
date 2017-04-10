# pVM - quick and easy VM starter for data processing and testing

This set of scripts makes it easy to start, run and manage Linux virtual
machines, mainly with data processing in mind.

## Main characteristics:

### Specific:

* Start several VMs with one command.
* Quick and easy configuration *via* a configuration file and/or command line parameters.
* Automatic installation of OS images (currently Arch Linux only).
* Optimized for best performance, but with compatibility in mind - migration-safe.
* Simple layout: one read-only location for input data, one read-write location for output.
* Support for SquashFS filesystems as the input source - safe (read-only) and efficient (compressed) archiving.
* Easy to setup central repositories for OS images and data archives - no mess!

### Why to use VMs for data processing?

* Nearly native performance with KVM, with just a small memory overhead.
* Ensures repeatability, independent of hardware or the local kernel.
* The VMs can be migrated between physical servers while working, or stopped with state preservation, to be re-started later from exactly the same point, possibly on a different physical server. For example, in the middle of processing the VM can be migrated to a more powerful server, to finish the job quicker!
* The VM images can be separate snapshots of some main image - common base for everyone, while saving on storage space, and ensuring per-user consistency. A user may save a ~100 MB image, and come back after a year to the exact same computing environment that she left, with personal modifications, packages, scripts, etc...
* Possibility to use the latest and possibly experimental software, which is not stable enough for the physical servers.

## Demo videos

[▶ New VM installation](https://www.youtube.com/watch?v=LsPO3XtgbNQ) | [▶ Benchmarking against the host](https://www.youtube.com/watch?v=NRMyI5FfJRw)
--- | ---
[![New VM installation demo](https://img.youtube.com/vi/LsPO3XtgbNQ/mqdefault.jpg)](https://www.youtube.com/watch?v=LsPO3XtgbNQ "New VM installation demo") | [![Benchmarking against the host demo](https://img.youtube.com/vi/NRMyI5FfJRw/mqdefault.jpg)](https://www.youtube.com/watch?v=NRMyI5FfJRw "Benchmarking against the host demo")

## Usage

* Please note: in order to use this setup, the user needs to be a member of the "kvm" group!

### Quick start

1. Make sure that the variables in **pVM.cfg** are correct.
2. Run `./pVM.sh` (or `./pVM.sh [parameters]` - as described below).
3. Wait for the connection details to appear.

### Details

#### Command line parameters

* In general, the command line parameters just substitute select settings in the **pVM.cfg** file.
* Therefore, if the setup is static, it is possible not to use any parameters, and just save the settings in the config file.
* Each flag can receive several comma separated values - one for each VM.

##### Example of parameters' usage

* Run VMs from `image1.qcow2` and `image2.qcow2`, with data sources `data1.sqsh` and `/path/to/data/`, and a single output directory for both: `/path/to/output`:

    ```sh
    ./pVM.sh -d image1,image2 -i data1,"/path/to/data" -o "/path/to/output"
    ```
  * As you can see, ".qcow2" and ".sqsh" extensions can be omitted for QCOW2 and SquashFS files, respectively.
  * No path needs to be specified if the VM or the data images are in the locations which are configured in the .cfg file.

##### Complete list of parameters:

* All the parameters are optional. The values from the config file will be used by default.
* `-d`: Specify the VM images to use.
* `-i`: Specify the input locations (SquashFS images, or directories).
* `-o`: Specify the output locations (directories).
* `-m`: Specify the memory per VM. *E.g.*: 4G,8G
* `-c`: Specify the vCPU cores per VM. *E.g.*: 4,8
* `-a`: Specify any additional options per VM. *E.g.*: " -snapshot"
* `--install`: Use when installing a new OS. It will boot the installation media and expose the **install_scripts** directory to the guest (mountable via 9p protocol, with the tag "install").
* `-h|--help`: Print a short help and exit.

#### Options in **pVM.cfg** explained

##### General options:

* `DRIVEREPO`: The location where the VM images reside.
* `SQUASHREPO`: The location where the SquashFS images reside.
* `QEMU_BIN`: The path to QEMU binary. The latest is recommended! It can be easily compiled locally!
* `NET_TYPE`: Accepts "user" or "tap". *User* network has worse performance than *tap* network, yet usually you would use *user* network only, since *tap* network requires running the script as root (or via sudo). This is only useful for testing, where high network performance is required, and the user has root access on the host.

##### Per-VM configurations:

* `DRIVES`: Array of the VM images. Its size determines the amount of VMs that will be launched. If the image is in the `DRIVEREPO` location, no path is needed. Also, no ".qcow2" extension is needed for QCOW2 images.
  * The following examples are equivalent:
  1. `( "${DRIVEREPO}/image1.qcow2" "${DRIVEREPO}/image2.qcow2" )`
  2. `( image1 image2 )`
* `INDRIVES`: Array of input data locations. Can be SquashFS images, or directories which contain the data. In case of SquashFS images, if they are in the `SQUASHREPO` location, no path is needed. Also, no ".sqsh" extension is needed. Notice: if there are less data locations than there are VM images, the last one will be used with all the VMs after the VM which will exhaust the list.
  * The following examples are equivalent:
  1. `( "${SQUASHREPO}/data1.sqsh" "${SQUASHREPO}/data2.sqsh" )`
  2. `( data1 data2 )`
* `OUTDIRS`: Array of output data locations. Should be directories. Notice: if there are less output locations than there are VM images, the last one will be used with all the VMs after the VM which will exhaust the list.
* `MEM`: Array of memory leased to the VMs. If there are more VMs than members of this array, all the VMs after the exhaustion of this array will use the last memory value. For example, if you want all the VMs to run with a single value, just fill in one member.
  * Example: `( 4G 8G 16G )`
* `CORES`: Array with the numbers of vCPUs. If there are more VMs than members of this array, all the VMs after the exhaustion of this array will use the last number of vCPUs.
  * Example: `( 4 2 1 )`
* `ADDITIONAL`: Additional arguments. Not usually needed, but at least one empty value (`""`) must be filled. Again, if there are more members than VMs, the last one will be repeated.

##### User net settings:

* `INIT_SSH_PORT`: The port through which it will be possible to SSH to the first VM in user mode. They increment by one for each following VM.

##### Tap net settings:

* `VM_BRIDGE`: Name of the bridge to which the VMs should connect.
* `BR_ADDR`: The address and netmask that will be given to the bridge above.
  * Example: "10.0.0.1/24"
* `LEASE_RANGE`: Range of IPs that the DHCP will lease to the VMS on the bridge above.
  * Example: "10.0.0.2,10.0.0.30"

##### New installation settings:
* `INSTALLING`: "true" or "false". Whether we are performing a new OS installation now. When *true*, the installation media will be inserted, and the **install_scripts** directory will be exposed to the guest (mountable via 9p protocol, with the tag "install").
* `INSTALL_MEDIA`: The path to the installation media, *e.g.* ISO image.

## Check list for the first usage

1. **(Optional)** Download and compile QEMU. You can use the system installed version, but using the latest is recommended. Note: some distributions, like Arch Linux, already provide the latest QEMU in their repositories, so no compilation is needed.

    ```sh
    # Install the dependencies. (e.g. "sudo apt-get build-dep qemu" on Debian/Ubuntu)
    mkdir -p ~/Builds ~/local
    cd ~/Builds
    git clone git://git.qemu-project.org/qemu.git
    cd qemu
    ./configure --target-list=x86_64-softmmu --disable-docs --prefix=${HOME}/local
    # Make sure that the fields after "spice support" and "ATTR/XATTR support" say "yes".
    make -j$(nproc)
    make install
    # The binary will be at: ~/local/bin/qemu-system-x86_64
    ```
1. Define the QEMU binary location in **pVM.cfg**. Define the installation media location there as well.
1. Create directories for VM images and data SquashFS images, and define them in **pVM.cfg**.
    * Note: if your VM image repository resides on a BTRFS filesystem, COW must be disabled on that directory, and the compression, preferably, forced:

        ```sh
        chattr +C +c /path/to/DRIVEREPO
        ```
1. Create a QCOW2 image for the VM boot drive:

    ```sh
    qemu-img create -f qcow2 /path/to/DRIVEDIR/image_fresh.qcow2 15G
    ```
    * In this example, `DRIVEDIR` is the location for VM images that was created previously.
    * The image will be about 200 KB in size. It will grow as needed, up to the limit of 15 GB (in this example).
    * You probably want to create just a single image at this stage. If you want to use more, you can make snapshots (details later).
1. If needed for future use, define the image in the `DRIVES` array in **pVM.cfg**.
1. Run `./pVM.sh -d image_fresh --install`.
1. Perform the installation, as described in the distribution-specific README under **install_scripts**.
1. **(Optional)** Make one or several snapshot images - it will allow to perform different configurations with the same base:

    ```sh
    cd /path/to/DRIVEDIR
    qemu-img create -f qcow2 -b image_fresh.qcow2 image1.qcow2
    qemu-img create -f qcow2 -b image_fresh.qcow2 image2.qcow2
    ```
    * Notice: once the snapshots are created, do NOT change the backing image (nor boot it)!!!
1. THAT'S IT! Now you can squash your data and get to business!
    * Although the data location can also be a directory, squashing is recommended because it will archive the data in a compressed and read-only form, saving a lot of space, protecting from accidental corruption, and increasing the performance if the data is highly compressible.
    * To squash (to the `SQUASHREPO` location created earlier) do:

        ```sh
        mksquashfs /path/to/data/dir /path/to/SQUASHREPO/data1.sqsh
        ```
      * Try following the above with `-lz4` for ultra-fast compression. Check other compression options as well, by typing `mksquashfs --help`.

## Usage with tap network

TAP networking requires root privileges to run. Therefore it is not intended for
"regular" usage, unless a high performance, low-overhead, networking is required,
and if the user has root access on the host server. To use the tap networking,
several preparations on the host are required:

1. **openvswitch** and **dnsmasq** packages installed.

If external network is to be accessed from the VMs, also do the following:

1. The physical network adapter should be connected to an OpenVswith bridge (a different one than the bridge for the VMS). A simple Linux bridge will work as well, but OpenVswitch is recommended for the possible scalability/flexibility of the setup.
1. Packet forwarding should be enabled.
1. Proper firewall rules should be set to allow masquerading and forwarding, so that the internal bridge created during runtime for the VMs (*ovs-br1* by default) will be able to connect to the outside world through the bridge that the physical adapter is connected to.
* Of course, on a system that spans over several servers, more advanced options can be used, such as GRE tunnels, etc...

## Licensing

This code is released under the standard 3-clause BSD license. Please see the
**LICENSE** file supplied with this package for the full license text.
