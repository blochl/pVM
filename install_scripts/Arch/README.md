# Arch Linux pVM installation scripts

1. Prepare an empty *qcow2* image.

    ```sh
    qemu-img create -f qcow2 /path/to/DRIVEDIR/Arch_fresh.qcow2 15G
    ```
1. Verify the variables in **pVM.cfg**.
1. Run: `./pVM.sh -d Arch_fresh --install`
1. Connect through *spice* (the connection command will be shown):

    ```sh
    spicy -h localhost -p 6000
    ```
1. Hit *enter* to boot the installation.
1. Once at the root prompt on the VM, type:

    ```sh
    mkdir install
    mount -t 9p install install
    ```
1. Run the installation script:

    ```sh
    ./install/Arch/initial_setup
    ```
  * You will be asked to set the root and user passwords during the installation.
1. The machine will shut down.
1. Start the VM: `./pVM.sh -d Arch_fresh`
1. Now you can connect as *pvm-user* via SSH (the connection command will be shown) and run the post-installation script:

    ```sh
    vm_post_setup
    ```
  * At this stage the installation is complete. You can make snapshots of this image, and use them, while keeping the clean installation pristine.

## Points to note

* The default non-privileged username is **pvm-user**.
* This user can install packages, reboot, and shutdown the machine with sudo.
* SSH X-forwarding is enabled, so you can SSH with `-X` (or `-Y`) option.
