From: http://www.vivekjuneja.in/tips/2016/12/02/docker-1.12.3-view-host-fs/

Run a docker container where the Docker VM filesystem is mounted at /vm-root

$ docker run --rm -it --privileged --pid=host -v /:/vm-root debian:stretch bash
