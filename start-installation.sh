#! /bin/bash

read -p "write the ip address of the first slave: " host_ip
sed -i "s|changeme1 ansible_connection=ssh ansible_user=centos ansible_ssh_private_key_file=trystack-maior.pem|$host_ip ansible_connection=ssh ansible_user=centos ansible_ssh_private_key_file=trystack-maior.pem|g" hosts

read -p "write the ip address of the second slave: " host_ip
sed -i "s|changeme2 ansible_connection=ssh ansible_user=centos ansible_ssh_private_key_file=trystack-maior.pem|$host_ip ansible_connection=ssh ansible_user=centos ansible_ssh_private_key_file=trystack-maior.pem|g" hosts

eval `ssh-agent -s`
ssh-add /home/carlo/.ssh/trystack-maior.pem

ansible-playbook master.yml
ssh trystack bash -c 'export ANSIBLE_SSH_ARGS=UserKnownHostsFile=/dev/null; export ANSIBLE_HOST_KEY_CHECKING=False; eval `ssh-agent -s`; ssh-add ~/.ssh/trystack-maior.pem; ansible-playbook worker.yml'
