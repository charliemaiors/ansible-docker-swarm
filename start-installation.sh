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

check_is_number() {
  if ! [[ $1 =~ $isnumber ]] ; then
   echo "error: Not an integer number" >&2; exit 1
  fi
}

compile_ansible_host(){
    read -p "Write the ip address or hostname of worker number $1: " host_ip
    export host_ip=${host_ip}

    read -p "What is the default user of worker $1 ? " worker_user
    export worker_user=${worker_user}

    read -p "The connection with your worker uses ssh key?[y/n] " ssh_present
    export ssh_present=${ssh_present}

    if check_answer ${ssh_present}; then
        read -p "What is the name of workers ssh private key (included extension)? " ssh_worker_key
        export ssh_worker_key=${ssh_worker_key}

        read -p "Private key is in the ${HOME}/.ssh local folder?[y/n] " workers_loc_answer
        if check_answer ${workers_loc_answer}; then
            $_ex 'cp $HOME/.ssh/${ssh_worker_key} keys/'
        else
            read -p "The private key is already in place in remote ${worker_user}/.ssh folder?[y/n] " workers_loc_answer
            if check_answer ${workers_loc_answer}; then
                echo "Nothing to copy, key is already in place"
            else
                read -p "The key is somewhere else on remote host?[y/n] " workers_loc_answer
                if check_answer ${workers_loc_answer}; then #Are you kidding me????
                    read -p "Please write the absolute REMOTE path (without the key name): " remote_path
                    $_ex 'echo "${host_ip} ansible_connection=ssh ansible_user=${worker_user} ansible_ssh_private_key_file=${remote_path}/${ssh_worker_key}" >> hosts'
                    continue
                else
                    read -p "Please enter the absolute LOCAL path (without key name): " local_path
                     $_ex 'cp ${local_path}/${ssh_worker_key} keys/'
                fi
            fi
        fi
        $_ex 'echo "${host_ip} ansible_connection=ssh ansible_user=${worker_user} ansible_ssh_private_key_file=~/.ssh/${ssh_worker_key}" >> hosts'
    else
        stty -echo #Aavoid to display password
        read -p "Which is your host password? " host_password
        $_ex 'echo "${host_ip} ansible_connection=ssh ansible_user=${worker_user} ansible_ssh_pass=${host_password}" >> hosts'
        stty echo #Enable again echo
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

echo "creating docker cert directory"
mkdir certs

read -p "What is the ip/dns name of remote docker-master? " host_name
export  host_name=${host_name}

read -p "What is the default user of docker-master? " ansible_user
export ansible_user=${ansible_user}

if check_binary ansible; then
  read -p "is ansible host already configured with docker section which point to your docker-master node?[y/n] " already_configured
  export already_configured=$already_configured
  if check_answer $already_configured; then
  
    echo "Double checking is better..."
    present=`cat /etc/ansible/hosts | grep $host_name`
    
    if [ -z $present ]; then
      echo "Account is not configured or hostname contains typos, please check your local installation of ansible!\nExiting..." >&2
      exit 1
    fi

    echo "Everything configured"
  else
    echo "Configuring..."
    $_ex 'echo "[docker]" >> /etc/ansible/hosts'

    read -p "The connection with your master uses ssh key?[y/n] " ssh_present

    if check_answer $ssh_present; then
        read -p "What is the name of remote docker-master key (with file extension)? " host_key
        export host_key=${host_key}

        read -p "is in the ${HOME}/.ssh folder?[y/n] " loc_answer
        if check_answer $loc_answer; then
           export host_key_path=$HOME/.ssh
        else
           read -p "Where is located docker-master ssh key?[only path] "host_key_loc
           export host_key_path=${host_key_loc}
        fi

        $_ex 'echo "${host_name} ansible_connection=ssh ansible_user=${ansible_user} ansible_ssh_private_key_file=${host_key_path}/${host_key}" >> /etc/ansible/hosts'
    else
        stty -echo
        read -p "Please type ssh password (it will not be shown): " host_password
        $_ex 'echo "${host_name} ansible_connection=ssh ansible_user=${ansible_user} ansible_ssh_pass=${host_password}" >> /etc/ansible/hosts'
        stty echo
    fi
  fi
else
  $_ex '${_pkgmgr} update -y' #if is update -y on ubuntu does not matter
  $_ex '${_pkgmgr} install -y ansible'
  $_ex 'echo "[docker]" >> /etc/ansible/hosts'
  $_ex 'echo "${host_name} ansible_connection=ssh ansible_user=${ansible_user} ansible_ssh_private_key_file=${host_key_path}/${host_key}" >> /etc/ansible/hosts'
fi

echo "Preparing workers host file and folders"
touch hosts
mkdir keys

read -p "Do you have Ubuntu workers?[y/n] " ubuntu_workers
export ubuntu_workers $ubuntu_workers
if check_answer $ubuntu_workers; then
   echo "Compiling Ubuntu section"
   echo "[ubuntu-workers]" >> hosts
   read -p "How many ubuntu workers you have? " workers_number
   if check_is_number $workers_number; then
     for i in $(seq 1 $workers_number); do
        compile_ansible_host $i
     done
   fi 
fi

read -p "Do you have CentOS workers?[y/n] " centos_workers
export centos_workers=$centos_workers
if check_answer $centos_workers; then
   echo "Compiling CentOS section"
   $_ex echo "[centos-workers]" >> hosts
   read -p "How many ubuntu workers you have? " workers_number
   if check_is_number $workers_number; then
     for i in $(seq 1 $workers_number); do
        compile_ansible_host $i
     done
   fi
fi

echo "Adding last section"
$_ex echo "[workers:childer]" >> hosts

if [ ${ubuntu_workers} -eq 0 ]; then
   $_ex echo "ubuntu-workers" >> hosts
fi

if [ ${centos_workers} -eq 0 ]; then
   $_ex echo "centos-workers" >> hosts
fi

echo "Generating script"
touch remote_exec
echo "#! /bin/bash\nexport ANSIBLE_SSH_ARGS=UserKnownHostsFile=/dev/null\nexport ANSIBLE_HOST_KEY_CHECKING=False\n" > remote_exec

if [ ${ubuntu_workers} -eq 0 ]; then
    echo "ansible_playbook worker-ubuntu.yml\n" >> remote_exec
fi

echo "ansible_playbook worker.yml" >> remote_exec

read -p "Is docker master ubuntu?[y/n] " answer
if check_answer $answer; then
  ansible-playbook ubuntu.yml
fi

ansible-playbook master.yml
ssh ${ansible_user}@${host_name} bash -c 'remote_exec'

echo "Cleaning up"
$_ex 'rm -rf keys/'
$_ex 'rm hosts'
