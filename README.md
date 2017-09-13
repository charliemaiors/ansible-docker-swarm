# Swarm Deploy #

This simple bash+ansible script deploy [Docker Swarm](https://docs.docker.com/swarm/), it supports as control machine:

* Linux
* macOS
* Windows (with WSL enabled)

This script install docker on all nodes, provide swarm external access setting up a **CA** on manager node and downloading client certificates. On control machine it install docker (on WSL docker will be installed but daemon will not work but client part is usable, daemon fails silently...).
Docker manager (the exposed machine) must be a Linux machine (working on Windows Server controller), nodes could be whatever included Windows Server and Raspberry Pi.
This script deploy also (on demand at the end of the process) [portainer](https://portainer.io/) and [OpenFaaS](https://github.com/alexellis/faas).

## Instructions ##

Clone this repository:

```
git clone https://bitbucket.org/charliemaiors/ansible-docker-trystack.git swarm-deploy/
```

Move into cloned directory

```
cd swarm-deploy/
```

run start installation script and follow instructions

```
./start-installation.sh
```

If everything went fine, enjoy your swarm.