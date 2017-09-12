#! /usr/bin/env bash

set -a

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


if check_binary docker; then
        if [ ! -d "$HOME/.docker" ]; then
        	mkdir -p $HOME/.docker
        fi

	cert_folder=$(ls | egrep '[[:digit:]]{1,3}\.[[:digit:]]{1,3}\.[[:digit:]]{1,3}\.[[:digit:]]{1,3}')
	if [ -z $cert_folder ]; then
		cert_folder=$(ls | egrep -x '[[:alnum:]]{1,254}\.[[:alnum:]]{2,63}\.[[:alnum:]]{2,}')
        fi
        mv $cert_folder $HOME/.docker
	echo "Certificates installed, now please source docker_remote file and run docker commands on remote swarm"
else
	read -p "docker is not installed do you want to install it?[y/n] " install_docker
        if check_answer $install_docker; then
		curl -sSL get.docker.com | sh
		if [ $? -eq 0 ]; then
			echo "Successfully installed docker, now please re-run this script"
		fi
	else
		echo "Please install docker on your own"
		exit 2
	fi
fi
