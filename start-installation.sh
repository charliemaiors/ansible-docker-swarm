#! /usr/bin/env bash

#set -x 

isnumber='^[0-9]+$'

valid_ip(){
    local  ip=$1
    local  stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

valid_fqdn(){
    local fqdn=$1
    local stat=1
    
    host $1 2>&1 > /dev/null 
    stat=$?
    
    return $stat
}

check_in_system_host_file(){
   local exist_host=$(cat /etc/hosts | grep $1)
   
   if [[ -z ${exist_host} ]]; then
      return 1
   else
      return 0
   fi
}

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
           if [ ! -z $has_ssh ]; then
              export SSH_PRESENT="y"
              return 1
           else
              has_pass=$(echo $host_configured | grep -o ansible_ssh_pass.*)
              if [ ! -z $has_pass ];then
                 export SSH_PRESENT="n"
                 export HOST_PASSWORD=$(echo $host_configured | grep -o ansible_ssh_pass.* | awk -F "=" '{print $2}')
                 return 1
              fi
           fi
       fi
    fi
    return 0
}

compile_ansible_master(){
    $_ex 'echo "[docker]" > hosts'

    read -p "The connection with your master uses ssh key?[y/n] " ssh_present
    export SSH_PRESENT=${ssh_present}
    if check_answer $SSH_PRESENT; then
        read -p "What is the name of remote docker-master key (with file extension)? " host_key
        export host_key=${host_key}

        read -p "is in the ${HOME}/.ssh folder?[y/n] " loc_answer
        if ! check_answer $loc_answer; then
            read -p "Where is located docker-master ssh key?[only path] "host_key_loc
            $_ex "mv $host_key_loc/$host_key $HOME/.ssh"
            $_ex "chmod 600 $HOME/.ssh/$host_key"
        fi
        read -p "Your remote user could use sudo without password?[y/n] " sudo_password_mandatory
        export sudo_password_mandatory=$sudo_password_mandatory

        if ! check_answer $sudo_password_mandatory; then
            set +x
            stty -echo
            read -p "Please type remote root password, it will not be echoed or recorded (except in ansible host file): " remote_host_password
            export HOST_PASSWORD=$remote_host_password
            $_ex "echo \"${host_name} ansible_become_password=${remote_host_password}  ansible_connection=ssh ansible_user=${ansible_user} ansible_ssh_private_key_file=${host_key_path}/${host_key}\" >> /etc/ansible/hosts"
            stty echo
            set -x
        else 
            $_ex "echo \"${host_name} ansible_connection=ssh ansible_user=${ansible_user} ansible_ssh_private_key_file=${host_key_path}/${host_key}\" >> /etc/ansible/hosts"
        fi
        env master_home=$HOME keypair_name=$host_key image_user=$ansible_user docker_public=$host_name remote_ip=$host_name j2 templates/worker_vars.yml.j2 > group_vars/workers/vars.yml
    else
        set +x
        stty -echo
        read -p "Please type ssh password (it will not be shown): " host_password
        export HOST_PASSWORD=${host_password}
        stty echo
        set -x

        read -p "Your remote user requires a password in order to execute sudo command?[y/n] " sudo_password_mandatory
        export sudo_password_mandatory=$sudo_password_mandatory

        if check_answer $sudo_password_mandatory; then
            read -p "Are you using a different password in order to become a super user?" different_password
            export different_password=$different_password
            if check_answer $different_password; then    
                set +x
                stty -echo
                read -p "Please type your become password, il will not be logged or sent and also will not be echoed: " remote_host_password
                export remote_host_password=$remote_host_password
                $_ex "echo \"${host_name} ansible_become_password=${remote_host_password} ansible_connection=ssh ansible_user=${ansible_user} ansible_ssh_pass=${host_password}\" >> /etc/ansible/hosts"
                stty echo
                set -x
            else
                set +x
                $_ex "echo \"${host_name} ansible_become_password=${host_password} ansible_connection=ssh ansible_user=${ansible_user} ansible_ssh_pass=${host_password}\" >> /etc/ansible/hosts"
                set -x
            fi
        else
            set +x
            stty -echo
            $_ex "echo \"${host_name} ansible_connection=ssh ansible_user=${ansible_user} ansible_ssh_pass=${host_password}\" >> /etc/ansible/hosts"
            stty echo
            set -x
        fi

        if ! check_binary ssh_pass; then
            $_ex "$PKG_MGR install -y sshpass"
        fi

        env ssh_password=$host_password image_user=$ansible_user docker_public=$host_name remote_ip=$host_name j2 templates/worker_vars_sshpass.yml.j2 > group_vars/workers/vars.yml
    fi
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
       #Kerberos entries will be echoed here to hosts file when support will be available
    else
        echo "Updating host file"
        set +x
        echo "$1 ansible_connection=winrm ansible_user=$2 ansible_password=${winrm_password} ansible_port=${winrm_port} ansible_winrm_server_cert_validation=ignore ansible_winrm_scheme=${winrm_https} ansible_winrm_transport=${winrm_transport}" >> hosts
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
            echo "Nothing to copy, key is already in place" # If user can't modify current folder this script is already terminated
        else
            read -p "The private key is somewhere else on your machine?[y/n] " workers_loc_answer
            if check_answer ${workers_loc_answer}; then
                read -p "Please write the absolute REMOTE path (without the key name): " remote_path
                $_ex "cp $remote_path/$ssh_worker_key $HOME/.ssh/"
            else
                echo "Please copy your ssh key on your machine, or modify the ansible.cfg in order to enable the ForwardAgent and configure the script in order to use ssh args"
                exit 3
            fi
            
            read -p "Your remote user could use sudo without password?[y/n] " sudo_password_mandatory
            export sudo_password_mandatory=$sudo_password_mandatory

            if ! check_answer $sudo_password_mandatory; then
                set +x
                stty -echo
                read -p "Please type remote root password, it will not be echoed or recorded (except in ansible host file): " remote_host_password
                export remote_host_password=$remote_host_password

                echo "${1} ansible_become_password=${remote_host_password}  ansible_connection=ssh ansible_user=${2} ansible_ssh_private_key_file=${HOME}/.ssh/${ssh_worker_key}" >> hosts
                stty echo
                set -x
            else 
                echo "${1} ansible_connection=ssh ansible_user=${2} ansible_ssh_private_key_file=${HOME}/.ssh/${ssh_worker_key}" >> hosts
            fi
        fi

        read -p "Your remote user could use sudo without password?[y/n] " sudo_password_mandatory
        export sudo_password_mandatory=$sudo_password_mandatory

        if ! check_answer $sudo_password_mandatory; then
            set +x
            stty -echo
            read -p "Please type remote root password, it will not be echoed or recorded (except in ansible host file): " remote_host_password
            export remote_host_password=$remote_host_password

            echo "${1} ansible_become_password=${remote_host_password}  ansible_connection=ssh ansible_user=${2} ansible_ssh_private_key_file=.ssh/${ssh_worker_key}" >> hosts
            stty echo
            set -x
        else 
            echo "${1} ansible_connection=ssh ansible_user=${2} ansible_ssh_private_key_file=.ssh/${ssh_worker_key}" >> hosts
        fi
    else
        set +x 
        stty -echo #Avoid to display password
        read -p "Which is your host password? " host_worker_password
        export host_worker_password=$host_worker_password
        stty echo #Enable again echo
        set -x
        
        read -p "Your remote user requires a password in order to execute sudo command?[y/n] " sudo_password_mandatory
        export sudo_password_mandatory=$sudo_password_mandatory

        if check_answer $sudo_password_mandatory; then
            read -p "Are you using a different password in order to become a super user?" different_password
            export different_password=$different_password
            if check_answer $different_password; then    
                set +x
                stty -echo
                read -p "Please type your become password, il will not be logged or sent and also will not be echoed: " remote_host_password
                export remote_host_password=$remote_host_password
                $_ex "echo \"${1} ansible_become_password=${remote_host_password} ansible_connection=ssh ansible_user=${2} ansible_ssh_pass=${host_worker_password}\" >> /etc/ansible/hosts"
                stty echo
                set -x
            else
                set +x
                $_ex "echo \"${1} ansible_become_password=${host_worker_password} ansible_connection=ssh ansible_user=${2} ansible_ssh_pass=${host_password}\" >> /etc/ansible/hosts"
                set -x
            fi
        else
            set +x
            stty -echo
            $_ex "echo \"${1} ansible_connection=ssh ansible_user=${2} ansible_ssh_pass=${host_worker_password}\" >> /etc/ansible/hosts"
            stty echo
            set -x
        fi        
        
    fi
}

compile_section_loop(){
    if [[ $1 == "ubuntu" ]]; then         
        worker_type="Ubuntu/Debian/Raspbian"     
    else         
        worker_type="$(tr '[:lower:]' '[:upper:]' <<< ${1:0:1})${1:1}"     
    fi

    echo "Compiling $worker_type section"
    echo "[${1}-workers]" >> hosts    

    read -p "How many $worker_type workers you have? " workers_number        
    if check_is_number $workers_number; then          
        for i in $(seq 1 $workers_number); do             
            compile_ansible_host $i $2          
        done        
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

    if valid_ip $host_name; then
        export docker_cert="ip"
    elif valid_fqdn $host_name; then
        export docker_cert="dns"
    elif check_in_system_host_file $host_name; then
        export host_name=$(cat /etc/hosts | grep docker | awk '{print $1}') #check if someone put the hosts file alias as docker manager dns
        export docker_cert="ip"
    else
        echo "$host_name is not valid, aborting..."
        exit 2
    fi

    read -p "What is the default user of docker-master? " ansible_user
    export ansible_user=${ansible_user}

    install_pip_prerequisite j2cli[yaml]
    if check_binary ansible; then
      echo "Configuring..."
      compile_ansible_master
    else
      install_ansible
      compile_ansible_master
    fi

    if [ ! -f "hosts" ]; then
        echo "Preparing workers host file"
        echo "#This is a generate hosts file for ansible" > hosts
    fi

    read -p "Do you have Ubuntu/Debian/Raspbian workers?[y/n] " ubuntu_workers
    export ubuntu_workers $ubuntu_workers
    if check_answer $ubuntu_workers; then
    compile_section_loop "ubuntu" true
    fi

    read -p "Do you have CentOS workers?[y/n] " centos_workers
    export centos_workers=$centos_workers
    if check_answer $centos_workers; then
    compile_section_loop "centos" true
    fi

    read -p "Do you have Windows Server workers?[y/n]" windows_workers
    export windows_workers=${windows_workers}
    if check_answer ${windows_workers}; then
        compile_section_loop "windows" false
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

    $_ex 'ansible-playbook master.yml --extra-vars "windows_workers=${windows_workers} winrm_transport=${winrm_transport:=basic} cert_type=${docker_cert}"'

    if [ $? -ne 0 ]; then   
        read -p "Ansible playbook failed, do you want to clean or just leave it as it is and try to relaunch the script?[y/n] " clean
        if check_answer $clean; then
            ctrl_c
        fi
        exit 3
    fi
}

ctrl_c(){
   echo "Cleaning..."
   $_ex "rm -rf certs/ keys/"
   if [ -f hosts ]; then
      $_ex "rm hosts"
   fi
   echo "cleaned! exiting"
   exit 1
}

 # trap ctrl-c and call ctrl_c() 
trap ctrl_c INT

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

    echo "Installing playbook prerequisite"
    install_pip_prerequisite shade
    $_ex "ansible-playbook deploy_machines_openstack.yml"
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

read -p "Do you want to deploy openfaas (http://portainer.io/) on your swarm?[y/n] " openfaas
export openfaas=$openfaas                                                                    
if check_answer $openfaas; then                                                               
    $_ex "ansible-playbook openfaas.yml --extra-vars=\"openstack=$required_openstack\""       
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

read -p "Do you want to generate a zip archive in order to export current configuration on another client node?[y/n] " archive_it
export archive_it=${archive_it}
if check_answer $archive_it; then
    mkdir -p swarm-tar
    echo "\$Env:DOCKER_CERT_PATH=\"\$env:USERPROFILE\\.docker\\$host_name\"" > swarm-tar/docker_remote.ps1
    echo "\$Env:DOCKER_HOST = \"tcp://$host_name:2376\"" >> swarm-tar/docker_remote.ps1
    echo "\$Env:DOCKER_TLS_VERIFY=\"1\"" >> swarm-tar/docker_remote.ps1
    echo "\$Env:COMPOSE_CONVERT_WINDOWS_PATHS = \"true\"" >> swarm-tar/docker_remote.ps1
    echo "#This is a generated bat file please use .\\docker_remote.ps1 | Invoke-Expression in order to have your docker client configured" >> swarm-tar/docker_remote.ps1
    
    cp $HOME/docker_remote swarm-tar/
    cp -R $HOME/.docker/$host_name swarm-tar/
    cp Install-Cert.ps1 swarm-tar/
    cp install-cert.sh swarm-tar/
    cp Installation.txt swarm-tar/
    tar cvf $HOME/swarm-tar.tar swarm-tar/
    rm -rf swarm-tar/
    echo "You have a file called swarm-tar.tar in your home directory ($HOME), please copy it to remote node and uncompress it"
fi

echo "Everything should be properly configured, please run 'source(.)  docker_remote' in your home directory ($HOME) in order to interact with remote swarm"
