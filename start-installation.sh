#! /bin/bash

eval `ssh-agent -s`
ssh-add /home/carlo/.ssh/trystack-maior.pem

ansible-playbook master.yml
ssh trystack 'export ANSIBLE_HOST_KEY_CHECKING=False; eval `ssh-agent -s`; ssh-add ~/.ssh/trystack-maior.pem; ansible-playbook worker.yml'
