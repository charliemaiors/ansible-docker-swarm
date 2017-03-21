#! /bin/bash

eval ssh-agent -s
ssh-add

ansible-playbook master.yml
ssh trystack ansible-playbook worker.yml 
