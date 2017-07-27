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

    if [ $2 = true ]; then
        compile_linux_ansible_host $host_ip $worker_user
    else
        compile_windows_ansible_host $host_ip $worker_user
    fi
}

compile_windows_ansible_host(){
    read -p "Which schema uses winrm connection?[http/https]" winrm_https
    export winrm_https=${winrm_https}

    if [ ${winrm_https} != "http" ] && [ ${winrm_https} != "https" ]; then
        echo "Invalid winrm scheme, aborting..."
        exit 3
    fi

    read -p "Which port is settled up for winrm? " winrm_port
    export winrm_port=${winrm_port}
    check_is_number $winrm_port
    
    set +x
    stty -echo #Password will not be echoed
    read -p "Which is the account password ?" winrm_password
    export winrm_password=${winrm_password}
    stty echo
    set -x

    read -p "Which authentication scheme are you using?[Kerberos, NTLM, Basic, CredSSP]" winrm_transport
    export winrm_transport=${winrm_transport}

    if [ ${winrm_transport} == "Kerberos" ] || [ ${winrm_transport} == "kerberos" ]; then
       get_kerberos_variables
       #Kerberos entries will be echoed here to hosts file
    else
        echo "Updating host file"
        set +x
        $_ex "$1 ansible_connection=winrm ansible_user=$2 ansible_password=${winrm_password} ansible_port=${winrm_port} ansible_winrm_server_cert_validation=ignore ansible_winrm_scheme=${winrm_https} ansible_winrm_transport=${winrm_transport}"
       set -x
    fi 
}

get_kerberos_variables(){
    echo "Kerberos support is still in development for now use a different one"
    exit 2
}

compile_linux_ansible_host(){

    read -p "The connection with your worker uses ssh key?[y/n] " ssh_worker_present
    export ssh_worker_present=${ssh_worker_present}

    if check_answer ${ssh_worker_present}; then
        read -p "What is the name of workers ssh private key (included extension)? " ssh_worker_key
        export ssh_worker_key=${ssh_worker_key}

        read -p "Private key is in the ${HOME}/.ssh local folder?[y/n] " workers_loc_answer
        if check_answer ${workers_loc_answer}; then
            $_ex 'cp $HOME/.ssh/${ssh_worker_key} keys/' # If user can't modify current folder this script is already terminated
        else
            read -p "The private key is already in place in remote $2/.ssh folder?[y/n] " workers_loc_answer
            if check_answer ${workers_loc_answer}; then
                echo "Nothing to copy, key is already in place"
            else
                read -p "The key is somewhere else on remote host?[y/n] " workers_loc_answer
                if check_answer ${workers_loc_answer}; then #Are you kidding me????
                    read -p "Please write the absolute REMOTE path (without the key name): " remote_path
                    $_ex "echo \"$1 ansible_connection=ssh ansible_user=$2 ansible_ssh_private_key_file=${remote_path}/${ssh_worker_key}\" >> hosts"
                    continue
                else
                    read -p "Please enter the absolute LOCAL path (without key name): " local_path
                     $_ex 'cp ${local_path}/${ssh_worker_key} keys/'
                fi
            fi
        fi
        echo "$1 ansible_connection=ssh ansible_user=$2 ansible_ssh_private_key_file=~/.ssh/${ssh_worker_key}" >> hosts
    else
        stty -echo #Aavoid to display password
        read -p "Which is your host password? " host_worker_password
        echo "$1 ansible_connection=ssh ansible_user=$2 ansible_ssh_pass=${host_worker_password}" >> hosts
        stty echo #Enable again echo
    fi
}

install_pip_prerequisite(){
    exist=$(pip freeze | grep $1)
    if [ -z $exist ]; then
       $_ex "pip install $1"
    else
       echo "$1 already installed"
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
            compile_ansible_host $i true
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
            compile_ansible_host $i true
         done
       fi
    fi

    read -p "Do you have Windows Server workers?[y/n]" windows_workers
    export windows_workers=${windows_workers}
    if check_answer ${windows_workers}; then
        echo "Compiling Windows Section"
        echo "[windows-workers]" >> hosts
        read -p "How many Windows Server workers you have? " workers_number
        if check_is_number ${workers_number}; then
            for i in $(seq 1 $workers_number); do
             compile_ansible_host $i false
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
    
    if check_answer ${windows_workers}; then
         echo "windows-workers" >> hosts
    fi

    $_ex 'ansible-playbook master.yml'

    if [ "${ssh_present}" = "n" -o "${ssh_present}" = "N" -o "${ssh_present}" = "No" ]; then
       if check_binary sshpass; then
          sshpass -p "${host_password}" ssh -o "StrictHostKeyChecking=no" ${ansible_user}@${host_name} 'ansible-playbook worker.yml'
       else
          $_ex "$PKG_MGR install  -y sshpass"
          sshpass -p "${host_password}" ssh -o "StrictHostKeyChecking=no" ${ansible_user}@${host_name} 'ansible-playbook worker.yml'
       fi
    else
       pass=$(echo $present | grep ansible_ssh_pass)
       if [[ ! -z ${pass} ]]; then
          pass=$(echo $present | grep -o ansible_ssh_pass.* | cut -f2 -d=)
          if check_binary sshpass; then
             continue
          else
             $_ex "$PKG_MGR install -y sshpass"
          fi
          sshpass -p "${host_password}" ssh -o "StrictHostKeyChecking=no" ${ansible_user}@${host_name} 'ansible-playbook worker.yml'
       else
          if [[ -z $host_key_path ]]; then
              host_key_path=$(cat /etc/ansible/hosts | grep ${host_name} |grep -o ansible_ssh_private_key_file.* | cut -f2 -d=)
          fi
          ssh -tt -i ${host_key_path} -o "StrictHostKeyChecking=no" ${ansible_user}@${host_name} 'ansible-playbook worker.yml'
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

read -p "Do you require also machine creation?[y/n] " required_openstack
export required_openstack=${required_openstack}

if ! check_answer ${required_openstack}; then
    already_instantiated_cluster
else
    
    if ! check_binary ansible; then
        install_ansible
    fi
    read -p "Do you want to deploy all instances with a floating ip?[y/n] " all_floating
    export all_floating=${all_floating}

    echo "Installing playbook prerequisite"
    install_pip_prerequisite shade
    $_ex "ansible-playbook deploy_machines_openstack.yml -e \"all_floating=${all_floating}\""
    source ./env
    #if check_answer ${UBUNTU_MANAGER}; then
    #    $_ex 'ansible-playbook ubuntu.yml'
    #fi
    #$_ex 'ansible-playbook master.yml'
    if ! check_answer ${all_floating}; then
        $_ex "chown -R $current_user:$current_user /home/$current_user/.ssh"
        ssh -tt -i ${HOME}/.ssh/swarm_key -o "StrictHostKeyChecking=no" ${ansible_user}@${host_name} 'ansible-playbook worker.yml'
    fi
fi

echo "Configuring local docker client"

if ! check_binary docker; then
   read -p "Docker is currently not installed do you want to install it?" docker_req
   export docker_req=$docker_req
   if check_answer $docker_req; then
      if ! check_binary curl; then
        $_ex "$PKG_MGR install -y curl"
      fi
      curl -sSL https://get.docker.com/ | sh
   fi
fi

if [ ! -d "$HOME/.docker" ]; then
    mkdir -p $HOME/.docker/${host_name}
else
    mkdir -p $HOME/.docker/${host_name}
fi

cp certs/* $HOME/.docker/${host_name}
$_ex "chown -R $current_user:$current_user /home/$current_user/.docker/"

echo "Generating source file"
echo "export DOCKER_CERT_PATH=$HOME/.docker/$host_name" > $HOME/docker_remote
echo "export DOCKER_HOST=tcp://$host_name:2376" >> $HOME/docker_remote
echo "export DOCKER_TLS_VERIFY=1" >> $HOME/docker_remote

read -p "Do you want to deploy portainer (http://portainer.io/) on your swarm?[y/n] " portainer
export portainer=$portainer
if check_answer $portainer; then
    $_ex "ansible-playbook portainer.yml --extra-vars=\"openstack=$required_openstack\""
fi

echo "Cleaning up"


if check_answer $required_openstack; then
   $_ex 'rm env'
   if ! check_answer ${all_floating}; then
     $_ex 'rm -rf keys/ certs/'
     $_ex 'rm hosts'
   fi
else
  $_ex 'rm -rf keys/ certs/'
  $_ex 'rm hosts'
fi

echo "Everything should be properly configured, please run 'source(.)  docker_remote' in your home directory ($HOME) in order to interact with remote swarm"
