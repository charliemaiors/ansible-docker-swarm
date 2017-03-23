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

check_answer () {
 if [ "${1}" != "" ]; then
    if [ "${1}" = "n" -o "${1}" = "N" -o "${1}" = "No" ]; then
      return 1
    else
      return 0
    fi
 else
   return 0 #A null answer is equal to an affermative answer   
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


read -p "What is the name of remote docker-master key (with file extension)? " host_key
export host_key=${host_key}

read -p "is in the ${HOME}/.ssh folder?[y/n] " loc_answer
if [[ $(check_answer $loc_answer) -eq 1 ]]; then
   read -p "Where is located docker-master ssh key?[only path] "host_key_loc
   export host_key_path=${host_key_loc}
else
  export host_key_path=$HOME/.ssh
fi

read -p "What is the ip/dns name of remote docker-master? " host_name
export  host_name=${host_name}

read -p "What is the default user of docker-master? " ansible_user
export ansible_user=${ansible_user}

if  check_binary ansible; then
  read -p "is ansible host already configured with docker section which point to your docker-master node?[y/n] " already_configured
  if [[ $(check_answer $already_configured) -eq 1 ]]; then
    $_ex 'echo "[docker]" >> /etc/ansible/hosts'
    $_ex 'echo "${host_name} ansible_connection=ssh ansible_user=${ansible_user} ansible_ssh_private_key_file=${host_key}" >> /etc/ansible/hosts'
  fi
else
  $_ex '${_pkgmgr} update -y' #if is update -y on ubuntu does not matter
  $_ex '${_pkgmgr} install -y ansible'
  $_ex 'echo "[docker]" >> /etc/ansible/hosts'
  $_ex 'echo "${host_name} ansible_connection=ssh ansible_user=${ansible_user} ansible_ssh_private_key_file=${host_key}" >> /etc/ansible/hosts'
fi

read -p "The ssh key to connect to your workers different from the docker master key?[y/n] " answer
export  answer=${answer}
if check_answer $answer; then
  read -p "What is the name of workers ssh private key (included extension)? " ssh_workers
  export SSH_WORKERS=${ssh_workers}
  read -p "Where is located, please enter full path [leave blank if is in the same folder of this script]: " ssh_location_workers
  if [ "${ssh_location_workers}" != "" ]; then
    $_ex 'copy ${ssh_location_workers} .'
    $_ex 'chmod 666 ${SSH_WORKERS}'
  fi
else
  export SSH_WORKERS=${host_key} 
  $_ex 'cp ${host_key_path}/${host_key} .'
  $_ex 'chmod 666 ${SSH_WORKERS}'
fi

read -p "how many workers you have? " workers_number

if ! [[ $workers_number =~ $isnumber ]] ; then
   echo "error: Not an integer number" >&2; exit 1
fi

for i in $(seq 1 $workers_number); do
   read -p "write the ip address of slave number ${i}: " host_ip
   export host_ip=${host_ip}
   $_ex 'echo "${host_ip} ansible_connection=ssh ansible_user=centos ansible_ssh_private_key_file=${SSH_WORKERS}" >> hosts'
done

eval `ssh-agent -s`
ssh-add ${host_key_path}/${host_key}

#echo "Generating script"
#echo "export ANSIBLE_SSH_ARGS=UserKnownHostsFile=/dev/null\nexport ANSIBLE_HOST_KEY_CHECKING=False\neval ssh-agent -s\nssh-add /.ssh/${SSH_WORKERS}\nansible-playbook worker.yml" > remote_exec

ansible-playbook master.yml
ssh ${ansible_user}@${host_name} bash -c 'export ANSIBLE_SSH_ARGS=UserKnownHostsFile=/dev/null; export ANSIBLE_HOST_KEY_CHECKING=False; eval ssh-agent -s; ssh-add /.ssh/${SSH_WORKERS}; ansible-playbook worker.yml'

echo "Cleaning up"
rm remote_exec
rm $SSH_WORKERS

