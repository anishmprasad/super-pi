# super-pi

A Pi based super-powered cluster computer ( Distributed system )

# Prerequisite

- 3 x RPI 4 Model B 8GB with Heat Sink
- 3 x Samsung Evo plus
- 3 x Type C Cable
- 1 x Network Switch
- 1 x 6 Node Cluster case
- 4 x RJ 45 Category 6
- 1 x mini HDMI to VGA / HDMI

# Algorithm

- The Bully Algorithm
- The Ring Algorithm

# Algorithm Reference

- https://github.com/ZacharyMcGee/mpi-bully-algorithm

- https://www.meccanismocomplesso.org/en/clusters-and-parallel-programming-with-mpi-and-raspberry-pi/

# Reference

- https://magpi.raspberrypi.org/articles/build-a-raspberry-pi-cluster-computer

- https://www.mpich.org/downloads/

- https://makezine.com/projects/build-a-compact-4-node-raspberry-pi-cluster/

- https://magpi.raspberrypi.org/articles/build-a-raspberry-pi-cluster-computer

- https://www.techworm.net/2018/03/learn-build-supercomputer-raspberry-pi-3-cluster.html

- https://community.particle.io/t/raspberry-pi-electron-master-slave-communication/33052

- https://www.geeksforgeeks.org/election-algorithm-and-distributed-processing/

- https://www.ukessays.com/essays/information-technology/comparisons-with-the-bully-algorithm-information-technology-essay.php

- https://www.ques10.com/p/19537/compare-bully-election-algorithm-with-ring-algor-1/

- https://linuxhint.com/setup_hostname_ubuntu_2004/

- https://superuser.com/questions/185678/connect-to-linux-by-name-rather-than-ip

- https://www.open-mpi.org/doc/v4.0/man1/mpic++.1.php

- https://medium.com/@glmdev/building-a-raspberry-pi-cluster-784f0df9afbd

- https://www.nagafm.com/2020/07/02/how-to-create-ssh-alias-in-linux/

# Sleep ubuntu

- https://askubuntu.com/questions/47311/how-do-i-disable-my-system-from-going-to-sleep

- `sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target`

# Steps

- `ssh-keygen -R 192.168.0.16`
- `ssh ubuntu@192.168.0.16`
- `vim /Users/{username / ghost}/.ssh/known_hosts`

# Utils

- `arp -a` // to get all ip address in the network
- `htop` // An interactive system-monitor process-viewer and process-manage
- `nmap -sn 192.168.1.1/12` // for scan all ports 1 - 12 range

# Steps

## Machine 1 ( 01 )

- sudo apt-get install gfortran
- cd tools && tar -xzf openmpi-4.0.5.tar.gz && cd openmpi-4.0.5 && ./configure
- sudo apt install ntpdate -y

## Machine 2 ( 02 )

- sudo apt-get install gfortran
- cd tools && tar -xzf openmpi-4.0.5.tar.gz && cd openmpi-4.0.5 && ./configure

## Machine 3 ( 03 )

- sudo apt-get install gfortran
- cd tools && tar -xzf openmpi-4.0.5.tar.gz && cd openmpi-4.0.5 && ./configure

# Licence

Apache - 2.0
