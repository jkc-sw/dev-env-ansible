#!/bin/bash

# get location of this folder
SCRIPT_DIR="$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )"

# make sure we are in the correct folder
pushd &>/dev/null

if [[ $# -lt 1 ]]; then
    # run ansible playbook
    ansible-playbook playbook.yml -K
    # ansible-playbook playbook.yml
else
    # if there are arg for test, run test
    case "$1" in
    'test')
        # build up the command here
        cmd='cd ./dev-env-ansible && ansible-playbook playbook.yml'
        cmd="$cmd && ansible-playbook playbook.yml"
        # this awesome blog post is worth the read
        # https://www.jeffgeerling.com/blog/2018/testing-your-ansible-roles-molecule
        # build and run the container
        docker build --tag devenvansible:1.0 . && \
        docker run --rm \
            -v $SCRIPT_DIR:/home/developer/dev-env-ansible \
            devenvansible:1.0 \
            bash -c "$cmd"
        ;;
    *)
        # error out
        echo "subcommand $1 invalid" >&2
        exit 1
        ;;
    esac
fi
