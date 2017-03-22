#! /bin/bash

isnumber='^[0-9]+$'

check_binary () {
  echo -n " * Checking for '$1' ... "
  if command -v $1 >/dev/null 2>&1; then
     echo "OK"
     return 0
  else
     echo >&2 "FAILED"
     return 1
  fi
}

#Execute command?
_ex='sh -c'
if [ "${USER}" != "root" ]; then
    if check_binary sudo; then
        _ex='sudo -E sh -c'
    elif check_binary su; then
        _ex='su -c'
    fi
fi

#Retrieving package manager
_pkgmgr=''
if check_binary apt-get; then #Ubuntu
    _pkgmgr='apt-get'
elif check_binary yum; then #CentOS/RedHat
    _pkgmgr='yum'
elif check_binary aptitue; then #Debian old version?
    _pkgmgr='aptitude'
fi

#Installing ansible if is not present

if !check_binary ansible; then
  $_ex $_pkgmgr 'update -y' #if is update -y on ubuntu does not matter
  $_ex $_pkgmgr 'install -y ansible'
fi

read -p "What is "

read -p "how many workers you have? " host_number

if ! [[ $host_number = $isnumber ]] ; then
   echo "error: Not an integer number" >&2; exit 1
fi

read -p "write the ip address of the first slave: " host_ip
sed -i "s|changeme1 ansible_connection=ssh ansible_user=centos ansible_ssh_private_key_file=trystack-maior.pem|$host_ip ansible_connection=ssh ansible_user=centos ansible_ssh_private_key_file=trystack-maior.pem|g" hosts

read -p "write the ip address of the second slave: " host_ip
sed -i "s|changeme2 ansible_connection=ssh ansible_user=centos ansible_ssh_private_key_file=trystack-maior.pem|$host_ip ansible_connection=ssh ansible_user=centos ansible_ssh_private_key_file=trystack-maior.pem|g" hosts

eval `ssh-agent -s`
ssh-add /home/carlo/.ssh/trystack-maior.pem

ansible-playbook master.yml
ssh trystack bash -c 'export ANSIBLE_SSH_ARGS=UserKnownHostsFile=/dev/null; export ANSIBLE_HOST_KEY_CHECKING=False; eval `ssh-agent -s`; ssh-add ~/.ssh/trystack-maior.pem; ansible-playbook worker.yml'
