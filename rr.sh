#!/bin/bash

# get location of this folder
SCRIPT_DIR="$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )"

# make sure we are in the correct folder
pushd "$SCRIPT_DIR" &>/dev/null

# container tag
CONTAINER_TAG=devenvansible:1.0
# test log file name
TEST_LOG=./test.log
# ansible workspace path
ANSIBLE_WORKSPACE_PATH=/home/developer/dev-env-ansible

# define a function to perform check
ansibleCheck() {
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

checkCmd() {
    cmd=$1
    if ! command -v $cmd &>/dev/null; then
        echo "$cmd not installed properly" >&2
        exit 3
    fi
}

if [[ $# -lt 1 ]]; then
    # run ansible playbook
    PY_COLORS=1 \
    ANSIBLE_FORCE_COLOR=1 \
    ansible-playbook playbook.yml -K | tee $TEST_LOG
    ansibleCheck
else
    # if there are arg for test, run test
    case "$1" in
    '-h'|'--help'|'help')
        # print help here
        echo "${BASH_SOURCE[0]} [args...]"
        echo "  Shortcuts for many things"
        echo "args:"
        echo " no arg         : Interactive install on host system asking for password"
        echo " -h|--help|help : Print this help command"
        echo " install        : Install on the host system (mostly container) w/o asking for password"
        echo " check           : Do simple check on the host system for all executable"
        echo " run            : Start the docker container only"
        echo " run-build      : Start the docker container and run ansible-playbook"
        echo " run-test           : Start the docker container and run simple CI test"
        ;;
    'run')
        # start bash inside container
        docker build --tag "$CONTAINER_TAG" . && \
        docker run --rm -it \
            -v $SCRIPT_DIR:$ANSIBLE_WORKSPACE_PATH \
            "$CONTAINER_TAG" \
            bash
        ;;
    'check')
        # below are for the best effort
        . $HOME/.bashrc
        cmds=('git' \
            'docker' \
            'conda' \
            'nvim' \
            'ansible' \
            'ansible-playbook' \
            'cargo' \
            'fd' \
            'rg' \
            'exa' \
            'bat' \
            'ctags' \
            'lua' \
            'luarocks' \
            'pwsh' \
        )
        for c in "${cmds[@]}"; do
            checkCmd $c
        done
       ;;
    'install')
        # install with ansible playbook
        ansible-playbook playbook.yml
        ;;
    'run-build')
        # build up the command here
        cmd="cd ./dev-env-ansible && ./rr.sh install"
        cmd="$cmd && . ~/.bashrc"
        # start bash inside container
        docker build --tag "$CONTAINER_TAG" . && \
        docker run --rm -it \
            -v $SCRIPT_DIR:$ANSIBLE_WORKSPACE_PATH \
            "$CONTAINER_TAG" \
            bash -i -c "$cmd ; bash -i"
        ;;
    'run-test')
        # build up the command here
        cmd="cd ./dev-env-ansible && ./rr.sh install"
        cmd="$cmd && . ~/.bashrc && ./rr.sh install"
        # this awesome blog post is worth the read
        # https://www.jeffgeerling.com/blog/2018/testing-your-ansible-roles-molecule
        # build and run the container
        docker build --tag "$CONTAINER_TAG" . && \
        docker run --rm \
            -v $SCRIPT_DIR:$ANSIBLE_WORKSPACE_PATH \
            "$CONTAINER_TAG" \
            bash -c "$cmd" | tee $TEST_LOG
        # perform check
        ansibleCheck
        ;;
    *)
        # error out
        echo "subcommand $1 invalid" >&2
        exit 1
        ;;
    esac
fi
