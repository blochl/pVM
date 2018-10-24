# Welcome to LinuxDays Virtualization hands-on!

## The purpose of this hands-on

After completing this walk-through you will have an Arch Linux virtual machine
installed on your computer that you can experiment with without any fear for
ruining something.

## The real purpose

You will have all the tools used here for preparing and launching the VMs. Feel
free to use them, analyze them, modify and extend them as you wish!

## The walkthrough

### Before we begin

#### Install the prerequisites

Few packages need to be installed before we begin:

1. QEMU
1. SPICE-server, SPICE-client, and SPICE-protocol
1. libcap and libattr
1. Git
1. aria2

A single command to install these on Ubuntu/Debian is:

````sh
sudo apt-get install qemu-kvm libspice-server-dev spice-client-gtk \
libspice-protocol-dev libcap-dev libattr1-dev git aria2
````

(On other distributions the command will be different)

#### Download

Clone this repository:

```sh
git clone https://github.com/blochl/pVM.git
cd pVM
git checkout demo
```
Download the latest (October 2018) Arch Linux installation media:

```sh
aria2c -d images --seed-time=0 "magnet:?xt=urn:btih:b674f2afa42d2b72b5d5dbb6965d23edaebb2364&dn=archlinux-2018.10.01-x86_64.iso&tr=udp://tracker.archlinux.org:6969&tr=http://tracker.archlinux.org:6969/announce"
```
* Ignore the initial message `[NOTICE] Download complete` - it just says that the metadata is finished downloading.

### Let's go!!!

Let's stay in the same directory we `cd`ed to at the **Download** step.

1. Change the images' location in the configuration file (**pVM.cfg**):
    ```sh
    sed -i "s|\(DRIVEREPO=\)\([^ ]*\)|\1'$(pwd)/images'|" pVM.cfg
    ```
    * **Tip:** you can do `git diff` to see what the above command did.
1. Prepare an empty *qcow2* image. This is the virtual hard drive of your new VM. The VM will see it as a 15GB hard drive, but the file itself will be really small, and will grow only as you write actual data there.
    ```sh
    qemu-img create -f qcow2 images/Arch_fresh.qcow2 15G
    ```
1. Start the VM in installation mode:
    ```sh
    ./pVM.sh -d Arch_fresh --install
    ```
1. Connect through *spice* - the "screen" of your virtual computer (the connection command will be shown):
    ```sh
    spicy -h localhost -p 6000
    ```
1. Hit *enter* to boot the installation.
1. Once at the root prompt on the VM, type:
    ```sh
    mkdir install
    mount -t 9p install install
    ```
    * This mounts an external directory with our installation scripts.
1. Run the installation script:
    ```sh
    ./install/Arch/initial_setup
    ```
    * **Tip:** you can use tab completion to avoid typing the whole command.
    * You will be asked to set the root and user passwords during the installation.
1. The machine will shut down.
1. Start the VM, not in installation mode this time:
    ```sh
    ./pVM.sh -d Arch_fresh
    ```
1. Now you can connect as *pvm-user* via SSH (the connection command will be shown)
1. Now you have a very minimal system. So you can run the post-installation script, which will install some extra packages (for example some Python packages for data processing) and make your vi editor very beautiful:
    ```sh
    vm_post_setup
    ```
1. At this stage the installation is complete. You can make snapshots of this image, and use them, while keeping the clean installation pristine. To make a snapshot you must turn off the VM (`sudo shutdown -h now` **in the VM terminal**) and do the following:
    ```sh
    qemu-img create -f qcow2 -b images/Arch_fresh.qcow2 images/Arch_snap.qcow2
    ```
    * Once you have the snapshot, **never** boot the pristine image again, otherwise the snapshot will not work. You can obviously use the pristine image to make more snapshots though.
    * To start a VM with the new snapshot as a drive, do: `./pVM.sh -d Arch_snap`

### Points to note

* The default non-privileged username is **pvm-user**.
* This user can install packages, reboot, and shutdown the machine *via* `sudo`.
* SSH X-forwarding is enabled, so you can SSH with `-X` (or `-Y`) option.

## What's next?

Now you have your first VM. You can explore the [**README.md**](https://github.com/blochl/pVM/tree/master) file for more
options, for example how to mount directories from your computer as drives on
the VM, etc.

And most importantly: go over the scripts here, understand what they do, come
up with your own ideas - the possibilities are endless, and think how to
implement them in your own way!
