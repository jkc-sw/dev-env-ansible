#!/bin/bash

# get location of this folder
SCRIPT_DIR="$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )"

# make sure we are in the correct folder
pushd &>/dev/null

# container tag
CONTAINER_TAG=devenvansible:1.0
# test log file name
TEST_LOG=./test.log
# ansible workspace path
ANSIBLE_WORKSPACE_PATH=/home/developer/dev-env-ansible

# define a function to perform check
check() {
    # perform test
    if ! grep -q 'changed=0' $TEST_LOG; then
        echo "changed should be 0 at the secound run" >&2
        exit 1
    fi
    if ! grep -q 'failed=0' $TEST_LOG; then
        echo "failed should be 0 at the secound run" >&2
        exit 2
    fi
}

if [[ $# -lt 1 ]]; then
    # run ansible playbook
    ansible-playbook playbook.yml -K | tee $TEST_LOG
    # ansible-playbook playbook.yml | tee $TEST_LOG
    check
else
    # if there are arg for test, run test
    case "$1" in
    'run')
        # start bash inside container
        docker build --tag "$CONTAINER_TAG" . && \
        docker run --rm -it \
            -v $SCRIPT_DIR:$ANSIBLE_WORKSPACE_PATH \
            "$CONTAINER_TAG" \
            bash
        ;;
    'test')
        # build up the command here
        cmd='cd ./dev-env-ansible && ansible-playbook playbook.yml'
        cmd="$cmd && . ~/.bashrc && ansible-playbook playbook.yml"
        cmd="$cmd | tee $TEST_LOG"
        # this awesome blog post is worth the read
        # https://www.jeffgeerling.com/blog/2018/testing-your-ansible-roles-molecule
        # build and run the container
        docker build --tag "$CONTAINER_TAG" . && \
        docker run --rm \
            -v $SCRIPT_DIR:$ANSIBLE_WORKSPACE_PATH \
            "$CONTAINER_TAG" \
            bash -c "$cmd"
        ret=$?
        if [[ $ret -ne 0 ]]; then
            echo "Failed to provision the docker machine" >&2
            exit $ret
        fi
        # perform check
        check
        ;;
    *)
        # error out
        echo "subcommand $1 invalid" >&2
        exit 1
        ;;
    esac
fi
