# OVS-Docker-CentOS Vagrantfile

This Vagrantfile sets up Open vSwitch and Docker on a CentOS host for
Virtualbox. Use this for testing purposes only.

## Dependency Information
* Virtualbox 6.1.18
* Vagrant 2.2.14
* CentOS 8

## Usage

For more information about Vagrant usage, see 
[Vagrant's documentation](https://www.vagrantup.com/docs/)

* Download Vagrantfile to a directory, navigate to inside
the directory

* Download the bootstrap shell script, the Vagrantfile
needs it to provision Open vSwitch and other components.

* Run the box.
  ```shell
  $ vagrant up
  Bringing machine 'default' up with 'virtualbox' provider...
  ...
  ==> default: Complete!
  ==> default: === INSTALLING OVS ===
  ==> default: === CHECKING OVS VERSION ===
  ==> default: === TURNING ON OVS ===
  ==> default: Created symlink from /etc/systemd/system/multi-user.target.wants/openvswitch.service to /usr/lib/systemd/system/openvswitch.  service.
  ==> default: === INSTALLING DOCKER ===
  ...
  ==> default: === TURNING ON DOCKER ===
  ==> default: === CHECKING DOCKER DAEMON ===
  ==> default: Created symlink from /etc/systemd/system/multi-user.target.wants/docker.service to /usr/lib/systemd/system/docker.service.
  ==> default: === BOOTSTRAP COMPLETED SUCCESSFULLY! ===
  ```

* To SSH into the box, use `vagrant ssh`.
* To destroy the box, use `vagrant destroy`.

