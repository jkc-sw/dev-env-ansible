#!/bin/bash

# get location of this folder
SCRIPT_DIR="$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )"

# make sure we are in the correct folder
pushd &>/dev/null

# run ansible playbook
ansible-playbook playbook.yml -K
# ansible-playbook playbook.yml
