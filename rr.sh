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
# docker files dir
DOCKER_FILE_DIR=./dockerfiles
# docker file name
DOCKER_FILE_UBUNTU_20="$DOCKER_FILE_DIR/ubuntu2004"
DOCKER_FILE_UBUNTU_18="$DOCKER_FILE_DIR/ubuntu1804"
DOCKER_FILE_UBUNTU_16="$DOCKER_FILE_DIR/ubuntu1604"

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

displayHelp() {
    # print help here
    echo "${BASH_SOURCE[0]} [args...]"
    echo "  Shortcuts for many things"
    echo "args:"
    echo " no arg          : Interactive install on host system asking for password"
    echo " -h|--help|help  : Print this help command"
    echo " install-i       : Install on the host system (mostly container) prompting for password"
    echo " install         : Install on the host system (mostly container) w/o asking for password"
    echo " check           : Do simple check on the host system for all executable"
    echo " run [ver]       : Start the docker container only"
    echo " run-build [ver] : Start the docker container and run ansible-playbook"
    echo " run-test [ver]  : Start the docker container and run simple CI test"
    echo "Where:"
    echo " ver > Specify the version to use. Default 18. Currently supported '16, 18', '20'"
}

# see what version to use
select_docker_ver() {
    # get the arg
    ver=$1
    # select the version
    case "$ver" in
    *20*)
        echo "$DOCKER_FILE_UBUNTU_20"
        ;;

    *18*)
        echo "$DOCKER_FILE_UBUNTU_18"
        ;;

    *16*)
        echo "$DOCKER_FILE_UBUNTU_16"
        ;;

    *)
        echo "Invalid version tag $ver" >&2
        displayHelp
        exit 1
        ;;
    esac
}

# if there are arg for test, run test
case "$1" in
'-h'|'--help'|'help')
    displayHelp
    ;;

'check')
    # if not being called from the rr.sh script itself
    if [[ -z $FROM_RR_CHECK ]]; then
        # recursively call itself
        FROM_RR_CHECK=1 bash -i -c "$SCRIPT_DIR/${BASH_SOURCE[0]#./*} check"
        # edit when done
        exit $?
    fi
    # below are for the best effort
    . $HOME/.bashrc
    # do it here, as I don't want it in bashrc to slow it down
    nvm use node
    # get a list of commands to check
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
        'node' \
        'nvm' \
        'yarn'
    )
    for c in "${cmds[@]}"; do
        checkCmd $c
    done
    ;;

'install')
    # install with ansible playbook
    ansible-playbook playbook.yml
    ;;

'install-i')
    # run ansible playbook
    PY_COLORS=1 \
    ANSIBLE_FORCE_COLOR=1 \
    ansible-playbook playbook.yml -K | tee $TEST_LOG
    ansibleCheck
    ;;

'run')
    # select docker
    ver="$DOCKER_FILE_UBUNTU_18"
    if [[ $# -gt 1 ]]; then
        ver="$(select_docker_ver $2)"
    fi
    # start bash inside container
    docker build --tag "$CONTAINER_TAG" "$ver" && \
    docker run --rm -it \
        --network="host" \
        -v $SCRIPT_DIR:$ANSIBLE_WORKSPACE_PATH \
        "$CONTAINER_TAG" \
        bash -i -c "cd ./dev-env-ansible ; bash -i"
    ;;

'run-build')
    # build up the command here
    cmd="cd ./dev-env-ansible && ./rr.sh install"
    cmd="$cmd && . ~/.bashrc"
    # select docker
    ver="$DOCKER_FILE_UBUNTU_18"
    if [[ $# -gt 1 ]]; then
        ver="$(select_docker_ver $2)"
    fi
    # start bash inside container
    docker build --tag "$CONTAINER_TAG" "$ver" && \
    docker run --rm -it \
        --network="host" \
        -v $SCRIPT_DIR:$ANSIBLE_WORKSPACE_PATH \
        "$CONTAINER_TAG" \
        bash -i -c "$cmd ; bash -i"
    ;;

'run-test')
    # build up the command here
    cmd="cd ./dev-env-ansible && ./rr.sh install"
    cmd="$cmd && . ~/.bashrc && ./rr.sh install && ./rr.sh check"
    # select docker
    ver="$DOCKER_FILE_UBUNTU_18"
    if [[ $# -gt 1 ]]; then
        ver="$(select_docker_ver $2)"
    fi
    # start bash inside container
    docker build --tag "$CONTAINER_TAG" "$ver" && \
    docker run --rm \
        --network="host" \
        -v $SCRIPT_DIR:$ANSIBLE_WORKSPACE_PATH \
        "$CONTAINER_TAG" \
        bash -c "$cmd" | tee $TEST_LOG
    # perform check
    ansibleCheck
    ;;

*)
    # error out
    echo "subcommand $1 invalid" >&2
    # print help
    displayHelp
    exit 1
    ;;

esac
