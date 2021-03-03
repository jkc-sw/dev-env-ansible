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
ANSIBLE_HOME=/home/developer

ANSIBLE_DEV_ENV_ANSIBLE_PATH=$ANSIBLE_HOME/repos/dev-env-ansible
# dotfile path
DOTFILE_PATH="$SCRIPT_DIR/../dotfiles"
ANSIBLE_DOTFILE_PATH=$ANSIBLE_DEV_ENV_ANSIBLE_PATH/../dotfiles

# docker files dir
DOCKER_FILE_DIR=./dockerfiles

# docker file name
DOCKER_FILE_UBUNTU_20="$DOCKER_FILE_DIR/ubuntu2004"
DOCKER_FILE_UBUNTU_18="$DOCKER_FILE_DIR/ubuntu1804"
DOCKER_FILE_UBUNTU_16="$DOCKER_FILE_DIR/ubuntu1604"

# docker repo name to be managed by rr.sh
DEV_ENV_REPOSITORY_NAME=devenvansible
RUN_PREFIX_FOR_NAME=run
USE_PREFIX_FOR_NAME=use

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
    if ! grep -q 'not installed properly' $TEST_LOG; then
        echo "checking exe that some are not done right" >&2
        exit 3
    fi
}

# use command to check if cmd is present
checkCmd() {
    cmd=$1
    if ! command -v $cmd &>/dev/null; then
        echo "$cmd not installed properly"
        return 1
    fi
}

# When spawning a docker container, use a easily recognized name
compose_container_name() {
    prefix=$1
    tag=$2
    suffix=$RANDOM
    echo -n "${prefix}_${tag}_${suffix}"
}

displayHelp() {
    # print help here
    echo "${BASH_SOURCE[0]} [...]"
    echo " One-stop shop for to do everything related to this repository"
    echo ""
    echo "Display Help"
    echo "  -h|--help|h|hel|help  : Print this help command"
    echo ""
    echo "Running the ansible commands or related check"
    echo "  install-i [-v] [-b]    : Install on the host system (when do it on your production machine) prompting for password"
    echo "  install [-v] [-b] [-u] : Install on the host system (mostly container) w/o asking for password"
    echo "  check                  : Do simple check on the host system for all executable"
    echo "  preupgrade             : Do the necessary stuff to get the system upgraded"
    echo ""
    echo "Start a tmux session to develop this repo"
    echo "  tmux            : Start the tmux development session"
    echo ""
    echo "This is used to manage the lifetime of the containers"
    echo "  run [ver]        : Start a new docker container only"
    echo "  run-build [ver]  : Start a new docker container and run ansible-playbook"
    echo "  commit ID TAG    : Commit a running docker container ID with the TAG specified"
    echo "  use TAG [-w dir] : Start a committed image only"
    echo "  list             : List all the images"
    echo "  use-build TAG    : Start a committed image and run ansible-playbook"
    echo ""
    echo "This is used by CI to do testing"
    echo "  run-test [ver]  : Start a new docker container and run simple CI test"
    echo ""
    echo "Options:"
    echo "  -v > Provide the -vvv option to the ansigle command to have debug output"
    echo "  -b > Use the HEAD for all the git repo"
    echo "  -u > Will update the dotfile repo"
    echo ""
    echo "Arguments:"
    echo "  ver > Specify the version to use. Default 18. Currently supported '16, 18', '20'"
    echo "  ID  > This is the container name or ID to use to make a commit, full name required"
    echo "  TAG > This is by your preference on how the commited container to be tagged"
}

# see what version to use
select_docker_ver() {
    # get the arg
    ver=$1
    # select the version
    case "$ver" in
    20)
        echo -n "$DOCKER_FILE_UBUNTU_20"
        ;;

    18)
        echo -n "$DOCKER_FILE_UBUNTU_18"
        ;;

    16)
        echo -n "$DOCKER_FILE_UBUNTU_16"
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
'-h'|'--help'|'h'|'hel'|'help')
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
    . $HOME/.bashrc_append
    # do it here, as I don't want it in bashrc to slow it down
    nvm use node
    # get a list of commands to check
    cmds=( \
        'ansible' \
        'ansible-playbook' \
        # 'bash-language-server' \
        'bat' \
        'caddy' \
        'cargo' \
        'clang' \
        'clangd' \
        'conda' \
        'ctags' \
        'docker' \
        # 'dockerfile-language-server-nodejs' \
        'doxygen' \
        'dust' \
        'exa' \
        'fd' \
        'git' \
        # 'gtop' \
        'lua' \
        'luarocks' \
        'luarocks' \
        'node' \
        'npm' \
        'nvim' \
        'nvm' \
        'procs' \
        'pwsh' \
        'python3' \
        'rg' \
        'rustc' \
        'rustup' \
        'sd' \
        'starship' \
        'tmux' \
        'tokei' \
        # 'tree-sitter-cli' \
        # 'typescript' \
        # 'typescript-language-server' \
        # 'vscode-json-languageserver' \
        'yaml-language-server' \
        'yarn' \
    )
        # 'svls' \
    ret=0
    for c in "${cmds[@]}"; do
        checkCmd $c
        if [[ $? -ne 0 ]]; then
            ret=1
        fi
    done
    exit $ret
    ;;

'preupgrade')
    # if not being called from the rr.sh script itself
    if [[ -z $FROM_RR_CHECK ]]; then
        # recursively call itself
        FROM_RR_CHECK=1 bash -i -c "$SCRIPT_DIR/${BASH_SOURCE[0]#./*} preupgrade"
        # edit when done
        exit $?
    fi
    # below are for the best effort
    . $HOME/.bashrc_append
    # do it here, as I don't want it in bashrc to slow it down
    nvm use node
    # Do the node upgrade
    nvm install --latest-npm
    ;;

'install')
    # var
    verbose=false
    stable=true
    updateDotfile='{"update_dotfile": false}'

    # parse the argumetns
    shift
    while getopts ':vbu' opt; do
        case "$opt" in
        v)
            verbose=true
            ;;
        b)
            stable=false
            ;;
        u)
            updateDotfile='{"update_dotfile": true}'
            ;;
        *)
            echo "Unrecognized option $opt" >&2
            displayHelp
            ;;
        esac
    done

    # check if the ansible is installed, if not, install it
    if ! command -v ansible &>/dev/null; then
        sudo apt update
        sudo apt install -y python3 python3-pip
        sudo -H python3 -m pip install ansible
    fi

    # install with ansible playbook
    if [[ "$verbose" == 'true' && "$stable" == 'true' ]]; then
        ansible-playbook -vvv playbook.yml --extra-vars '@./vars/stable.yml' --extra-vars "$updateDotfile"
    elif [[ "$verbose" == 'true' && "$stable" == 'false' ]]; then
        ansible-playbook -vvv playbook.yml --extra-vars "$updateDotfile"
    elif [[ "$verbose" == 'false' && "$stable" == 'true' ]]; then
        ansible-playbook playbook.yml --extra-vars '@./vars/stable.yml' --extra-vars "$updateDotfile"
    else
        ansible-playbook playbook.yml --extra-vars "$updateDotfile"
    fi
    ;;

'install-i')
    # var
    verbose=false
    stable=true
    updateDotfile='{"update_dotfile": true}'

    # parse the argumetns
    shift
    while getopts ':vb' opt; do
        case "$opt" in
        v)
            verbose=true
            ;;
        b)
            stable=false
            ;;
        *)
            echo "Unrecognized option $opt" >&2
            displayHelp
            ;;
        esac
    done

    # check if the ansible is installed, if not, install it
    if ! command -v ansible &>/dev/null; then
        sudo apt update
        sudo apt install -y python3 python3-pip
        sudo -H python3 -m pip install ansible
    fi

    # install with ansible playbook
    if [[ "$verbose" == 'true' && "$stable" == 'true' ]]; then
        PY_COLORS=1 \
        ANSIBLE_FORCE_COLOR=1 \
        ansible-playbook -K -vvv playbook.yml --extra-vars "@./vars/stable.yml" --extra-vars "$updateDotfile" | tee $TEST_LOG

    elif [[ "$verbose" == 'true' && "$stable" == 'false' ]]; then
        PY_COLORS=1 \
        ANSIBLE_FORCE_COLOR=1 \
        ansible-playbook -K -vvv playbook.yml --extra-vars "$updateDotfile" | tee $TEST_LOG

    elif [[ "$verbose" == 'false' && "$stable" == 'true' ]]; then
        PY_COLORS=1 \
        ANSIBLE_FORCE_COLOR=1 \
        ansible-playbook -K playbook.yml --extra-vars "@./vars/stable.yml" --extra-vars "$updateDotfile" | tee $TEST_LOG

    else
        PY_COLORS=1 \
        ANSIBLE_FORCE_COLOR=1 \
        ansible-playbook -K playbook.yml --extra-vars "$updateDotfile" | tee $TEST_LOG
    fi
    ;;

'tmux')
    # check if we have a section already
    if ! (tmux ls | grep -q blah); then
        if command -v tmuxinator &>/dev/null; then
            tmuxinator start blah -n blah
        else
            echo "Tmuxinator is not installed yet, please install first" >&2
            exit 1
        fi
    else
        # attach to the session
        tmux attach-session -t blah
    fi
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
        -v $SCRIPT_DIR:$ANSIBLE_DEV_ENV_ANSIBLE_PATH \
        -v $DOTFILE_PATH:$ANSIBLE_DOTFILE_PATH \
        --name "$(compose_container_name "$RUN_PREFIX_FOR_NAME" "$2")" \
        "$CONTAINER_TAG" \
        bash -i -c "cd ./repos/dev-env-ansible ; bash -i"
    ;;

'run-build')
    # build up the command here
    cmd="cd ./repos/dev-env-ansible && ./rr.sh install"
    cmd="$cmd && . ~/.bashrc_append"
    # select docker
    ver="$DOCKER_FILE_UBUNTU_18"
    if [[ $# -gt 1 ]]; then
        ver="$(select_docker_ver $2)"
    fi
    # start bash inside container
    docker build --tag "$CONTAINER_TAG" "$ver" && \
    docker run --rm -it \
        --network="host" \
        -v $SCRIPT_DIR:$ANSIBLE_DEV_ENV_ANSIBLE_PATH \
        -v $DOTFILE_PATH:$ANSIBLE_DOTFILE_PATH \
        --name "$(compose_container_name "$RUN_PREFIX_FOR_NAME" "$2")" \
        "$CONTAINER_TAG" \
        bash -i -c "$cmd ; exec zsh"
    ;;

'commit')
    # get args
    ident=$2
    tag=$3
    # make a commit
    docker commit "$ident" "$DEV_ENV_REPOSITORY_NAME:$tag"
    ;;

'list')
    # list all the images
    echo "All the committed images"
    docker images
    echo ""
    echo "All the running containers"
    docker ps
    ;;

'use')
    # get tag
    shift
    tag=$1
    shift
    # parse the rest
    while getopts ':w:' args; do
        case "$args" in
        w)
            wdir="$OPTARG"
            if [[ ! -d "$wdir" ]]; then
                echo "$wdir is not found" >&2
                exit 1
            fi
            ;;
        esac
    done

    # start bash inside container
    if [[ -z $wdir ]]; then
        docker run --rm -it \
            --network="host" \
            -v $SCRIPT_DIR:$ANSIBLE_DEV_ENV_ANSIBLE_PATH \
            -v $DOTFILE_PATH:$ANSIBLE_DOTFILE_PATH \
            --name "$(compose_container_name "$RUN_PREFIX_FOR_NAME" "$tag")" \
            "$DEV_ENV_REPOSITORY_NAME:$tag" \
            bash -i -c "cd ./repos/dev-env-ansible; exec zsh"

    else
        docker run --rm -it \
            --network="host" \
            -v $SCRIPT_DIR:$ANSIBLE_DEV_ENV_ANSIBLE_PATH \
            -v $DOTFILE_PATH:$ANSIBLE_DOTFILE_PATH \
            -v $wdir:"$ANSIBLE_HOME/$(basename "$wdir")" \
            --name "$(compose_container_name "$RUN_PREFIX_FOR_NAME" "$tag")" \
            "$DEV_ENV_REPOSITORY_NAME:$tag" \
            bash -i -c "cd ./$(basename "$wdir"); exec zsh"
    fi
    ;;

'use-build')
    # get arg
    tag=$2
    # build up the command here
    cmd="cd ./repos/dev-env-ansible && ./rr.sh install"
    cmd="$cmd && . ~/.bashrc_append"

    # start bash inside container
    docker run --rm -it \
        --network="host" \
        -v $SCRIPT_DIR:$ANSIBLE_DEV_ENV_ANSIBLE_PATH \
        -v $DOTFILE_PATH:$ANSIBLE_DOTFILE_PATH \
        --name "$(compose_container_name "$RUN_PREFIX_FOR_NAME" "$tag")" \
        "$DEV_ENV_REPOSITORY_NAME:$tag" \
        bash -i -c "$cmd; exec zsh"
    ;;

'run-test')
    # build up the command here
    cmd="cd ./repos/dev-env-ansible && ./rr.sh install"
    cmd="$cmd && . ~/.bashrc_append && ./rr.sh install -u && ./rr.sh check"
    cmd="$cmd && ./rr.sh preupgrade && ./rr.sh install -u && ./rr.sh check"
    # select docker
    ver="$DOCKER_FILE_UBUNTU_18"
    if [[ $# -gt 1 ]]; then
        ver="$(select_docker_ver $2)"
    fi

    # start bash inside container
    docker build --tag "$CONTAINER_TAG" "$ver" && \
    docker run --rm \
        --network="host" \
        -v $SCRIPT_DIR:$ANSIBLE_DEV_ENV_ANSIBLE_PATH \
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
