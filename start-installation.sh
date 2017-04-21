#! /bin/bash
	
set -x 

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

check_local_ansible(){ #Uses negative logic
    
    host_configured=$(cat /etc/ansible/hosts | grep $host_name)
    if [ ! -z ${host_configured+x} ];then
       user_configured=$(echo $host_configured | grep -o ansible_user.* | cut -f2 -d= | awk '{print $1}')
       if [[ $user_configured != "" ]] && [[ $user_configured == $ansible_user ]]; then
           has_ssh=$(echo $host_configured | grep -o ansible_ssh_private_key_file.*)
           if [ -z $has_ssh ]; then
              return 1
           else
              has_pass=$(echo $host_configured | grep -o ansible_ssh_pass.*)
              if [ -z $has_pass ];then
                 return 1
              fi
           fi
       fi
    fi
    return 0
}

compile_ansible_host(){
    read -p "Write the ip address or hostname of worker number $1: " host_ip
    export host_ip=${host_ip}

    read -p "What is the default user of worker $1 ? " worker_user
    export worker_user=${worker_user}

    read -p "The connection with your worker uses ssh key?[y/n] " ssh_worker_present
    export ssh_worker_present=${ssh_worker_present}

    if check_answer ${ssh_worker_present}; then
        read -p "What is the name of workers ssh private key (included extension)? " ssh_worker_key
        export ssh_worker_key=${ssh_worker_key}

        read -p "Private key is in the ${HOME}/.ssh local folder?[y/n] " workers_loc_answer
        if check_answer ${workers_loc_answer}; then
            $_ex 'cp $HOME/.ssh/${ssh_worker_key} keys/' # If user can't modify current folder this script is already terminated
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
        echo "${host_ip} ansible_connection=ssh ansible_user=${worker_user} ansible_ssh_private_key_file=~/.ssh/${ssh_worker_key}" >> hosts
    else
        stty -echo #Aavoid to display password
        read -p "Which is your host password? " host_worker_password
        echo "${host_ip} ansible_connection=ssh ansible_user=${worker_user} ansible_ssh_pass=${host_worker_password}" >> hosts
        stty echo #Enable again echo
    fi
}

install_ansible(){
    if [[ ${PKG_MGR} == 'apt-get' ]]; then
        $_ex "$REPO_MGR -y ppa:ansible/ansible;"
    fi
        $_ex "$PKG_MGR update -y; $PKG_MGR install -y ansible"
}

already_instantiated_cluster(){
    read -p "What is the ip/dns name of remote docker-master? " host_name
    export  host_name=${host_name}

    read -p "What is the default user of docker-master? " ansible_user
    export ansible_user=${ansible_user}

    if check_binary ansible; then
      read -p "is ansible host already configured with docker section which point to your docker-master node?[y/n] " already_configured
      export already_configured=$already_configured
      if check_answer $already_configured; then

        echo "Double checking is better..."

        if check_local_ansible; then
          echo "Account is not configured or hostname contains typos, please check your local installation of ansible! Exiting..." >&2
          exit 1
        fi

        echo "Everything configured"
      else
        echo "Configuring..."
        $_ex 'echo "[docker]" >> /etc/ansible/hosts'

        read -p "The connection with your master uses ssh key?[y/n] " ssh_present
        export ssh_present=${ssh_present}
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
            export host_password=${host_password}
            $_ex 'echo "${host_name} ansible_connection=ssh ansible_user=${ansible_user} ansible_ssh_pass=${host_password}" >> /etc/ansible/hosts'
            stty echo
        fi
      fi
    else
      install_ansible
      $_ex 'echo "[docker]" >> /etc/ansible/hosts'
      read -p "The connection with your master uses ssh key?[y/n] " ssh_present
      export ssh_present=${ssh_present}
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
          set +x
          stty -echo
          read -p "Please type ssh password (it will not be shown): " host_password
          export host_password=${host_password}
          $_ex 'echo "${host_name} ansible_connection=ssh ansible_user=${ansible_user} ansible_ssh_pass=${host_password}" >> /etc/ansible/hosts'
          stty echo
          set -x
      fi
    fi
    echo "Preparing workers host file"
    echo "#This is a generate hosts file for ansible" > hosts

    read -p "Do you have Ubuntu workers?[y/n] " ubuntu_workers
    export ubuntu_workers $ubuntu_workers
    if check_answer $ubuntu_workers; then
       echo "Compiling Ubuntu section"
       echo "[ubuntu-workers]" >> hosts
       read -p "How many Ubuntu workers you have? " workers_number
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
       echo "[centos-workers]" >> hosts
       read -p "How many CentOS workers you have? " workers_number
       if check_is_number $workers_number; then
         for i in $(seq 1 $workers_number); do
            compile_ansible_host $i
         done
       fi
    fi

    echo "Adding last section"
    echo "[workers:children]" >> hosts

    if check_answer $ubuntu_workers; then
       echo "ubuntu-workers" >> hosts
    fi

    if check_answer $centos_workers; then
       echo "centos-workers" >> hosts
    fi

    read -p "Is docker master ubuntu?[y/n] " answer
    if check_answer $answer; then #modify
      export UBUNTU_MANAGER=y
    fi

    $_ex 'ansible-playbook master.yml'

    if [ "${ssh_present}" = "n" -o "${ssh_present}" = "N" -o "${ssh_present}" = "No" ]; then
       if check_binary sshpass; then
          sshpass -p "${host_password}" ssh ${ansible_user}@${host_name} 'ansible-playbook worker.yml'
       else
          $_ex "$PKG_MGR install  -y sshpass"
          sshpass -p "${host_password}" ssh ${ansible_user}@${host_name} 'ansible-playbook worker.yml'
       fi
    else
       pass=$(echo $present | grep ansible_ssh_pass)
       if [[ ! -z ${pass} ]]; then
          pass=$(echo $present | grep -o ansible_ssh_pass.* | cut -f2 -d=)
          if check_binary sshpass; then
             continue
          else
             $_ex '$PKG_MGR install -y sshpass'
          fi
          sshpass -p "${host_password}" ssh ${ansible_user}@${host_name} 'ansible-playbook worker.yml'
       else
          if [[ -z $host_key_path ]]; then
              host_key_path=$(cat /etc/ansible/hosts | grep ${host_name} |grep -o ansible_ssh_private_key_file.* | cut -f2 -d=)
          fi
          ssh -tt -i ${host_key_path} ${ansible_user}@${host_name} 'ansible-playbook worker.yml'
       fi
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

#Retrieving package manage
PKG_MGR=''
if check_binary apt-get; then #Ubuntu
    PKG_MGR='apt-get'
    REPO_MGR='apt-add-repository'
elif check_binary yum; then #CentOS/RedHat
    PKG_MGR='yum'
elif check_binary aptitue; then #Debian old version?
    PKG_MGR='aptitude'
else
    echo "Your package manager is not currently supported, exit.."
    exit 2
fi

echo "Creating keys directory for copy"
mkdir keys

echo "Creating docker cert directory for docker master "
mkdir certs

echo "This script requires administrative privileges"
$_ex 'echo "$USER" >> /dev/null'
export current_user=$USER

read -p "Did you already instantiated machine for swarm?[y/n] " required_openstack
export required_openstack=${required_openstack}

if check_answer ${required_openstack}; then
    already_instantiated_cluster
else
    
    if ! check_binary ansible; then
        install_ansible
    fi
    $_ex 'ansible-playbook deploy_machines_openstack.yml'
    source ./env
    #if check_answer ${UBUNTU_MANAGER}; then
    #    $_ex 'ansible-playbook ubuntu.yml'
    #fi
    #$_ex 'ansible-playbook master.yml'
    $_ex "chown -R $current_user:$current_user /home/$current_user/.ssh"
    ssh -tt -i ${HOME}/.ssh/swarm_key ${ansible_user}@${host_name} 'ansible-playbook worker.yml'
fi

echo "Configuring local docker client"

if [ ! -d "$HOME/.docker" ]; then
    mkdir -p $HOME/.docker
fi

cp certs/* $HOME/.docker/
$_ex "chown -R $current_user:$current_user /home/$current_user/.docker/"

export DOCKER_CERT_PATH=$HOME/.docker/
export DOCKER_HOST=tcp://$host_name:2376
export DOCKER_TLS_VERIFY=1 

echo "Cleaning up"
$_ex 'rm -rf keys/'
$_ex 'rm hosts'
$_ex 'rm env'
