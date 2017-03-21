#! /bin/bash

read -p "write the ip address of first slave: " host_ip
sed -i "s/changeme-1*/$host_ip*/g" hosts


eval `ssh-agent -s`
ssh-add /home/carlo/.ssh/trystack-maior.pem

ansible-playbook master.yml
ssh trystack 'export ANSIBLE_HOST_KEY_CHECKING=False; eval `ssh-agent -s`; ssh-add ~/.ssh/trystack-maior.pem; ansible-playbook worker.yml'
