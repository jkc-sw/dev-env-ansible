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

# docker volumn mount
DOCKER_VOLUME_MOUNT=" -v $SCRIPT_DIR/../dotfiles:$ANSIBLE_HOME/repos/dotfiles "
DOCKER_VOLUME_MOUNT="$DOCKER_VOLUME_MOUNT -v $SCRIPT_DIR:$ANSIBLE_DEV_ENV_ANSIBLE_PATH "
DOCKER_VOLUME_MOUNT="$DOCKER_VOLUME_MOUNT -v $SCRIPT_DIR/../focus-side.vim:$ANSIBLE_HOME/repos/focus-side.vim "

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
    if grep -q 'not installed properly' $TEST_LOG; then
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
    echo "--------------------------------------------------------------------------------"
    echo "Display Help"
    echo " -h|--help|h|hel|help  : Print this help command"
    echo ""
    echo "--------------------------------------------------------------------------------"
    echo "Running the ansible commands or related check"
    echo " install-i [-v] [-b] [-a]    : Install on the host system (when do it on your production machine) prompting for password"
    echo " install [-v] [-b] [-u] [-a] : Install on the host system (mostly container) w/o asking for password"
    echo " check                       : Do simple check on the host system for all executable"
    echo " preupgrade                  : Do the necessary stuff to get the system upgraded"
    echo ""
    echo "  where"
    echo "   -v > Provide the -vvv option to the ansigle command to have debug output"
    echo "   -b > Use the HEAD for all the git repo"
    echo "   -u > Will update the dotfile repo"
    echo "   -a > Install all, like xmonad, etc"
    echo ""
    echo "--------------------------------------------------------------------------------"
    echo "Create a new row template"
    echo " new-role NAME : Create a new role with some default"
    echo ""
    echo "  where:"
    echo "   NAME : The name of the role appears in the folder"
    echo ""
    echo "--------------------------------------------------------------------------------"
    echo "Start a tmux session to develop this repo"
    echo " tmux : Start the tmux development session"
    echo ""
    echo "--------------------------------------------------------------------------------"
    echo "This is used to manage the lifetime of the containers"
    echo " run [ver]        : Start a new docker container only"
    echo " run-build [ver]  : Start a new docker container and run ansible-playbook"
    echo " commit ID TAG    : Commit a running docker container ID with the TAG specified"
    echo " use TAG [-w dir] : Start a committed image only"
    echo " list             : List all the images"
    echo " use-build TAG    : Start a committed image and run ansible-playbook"
    echo " run-test [ver]   : Start a new docker container and run simple CI test"
    echo ""
    echo " arguments:"
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

# function to install ansible
install_ansible() {
    # check if the ansible is installed, if not, install it
    if ! command -v ansible &>/dev/null; then
        sudo apt update
        sudo apt install -y python3 python3-pip
        sudo -H python3 -m pip install ansible
    fi
}

# if there are arg for test, run test
case "$1" in
'-h'|'--help'|'h'|'hel'|'help')
    displayHelp
    ;;

'new-role')
    # need 1 argrs
    shift
    if test "$#" -ne 1; then
        echo "Need 1 argument <NAME> for the role to be created" >&2
        exit 1
    fi
    name="$1"

    # create the folders
    mkdir -p "$SCRIPT_DIR/roles/$name/meta"
    mkdir -p "$SCRIPT_DIR/roles/$name/tasks"
    mkdir -p "$SCRIPT_DIR/roles/$name/defaults"

    # write meta
    echo '---'                      >> "$SCRIPT_DIR/roles/$name/meta/main.yml"
    echo 'dependencies:'            >> "$SCRIPT_DIR/roles/$name/meta/main.yml"
    echo '  - common_settings'      >> "$SCRIPT_DIR/roles/$name/meta/main.yml"
    echo ''                         >> "$SCRIPT_DIR/roles/$name/meta/main.yml"
    echo '# vim:et ts=2 sts=2 sw=2' >> "$SCRIPT_DIR/roles/$name/meta/main.yml"

    # write tasks
    echo '---'                                      >> "$SCRIPT_DIR/roles/$name/tasks/main.yml"
    echo '- name: PLACEHOLDER'                      >> "$SCRIPT_DIR/roles/$name/tasks/main.yml"
    echo '  fail:'                                  >> "$SCRIPT_DIR/roles/$name/tasks/main.yml"
    echo "    msg: 'need to implement $name tasks'" >> "$SCRIPT_DIR/roles/$name/tasks/main.yml"
    echo ''                                         >> "$SCRIPT_DIR/roles/$name/tasks/main.yml"
    echo '# vim:et ts=2 sts=2 sw=2'                 >> "$SCRIPT_DIR/roles/$name/tasks/main.yml"

    # write defaults
    echo '---'                      >> "$SCRIPT_DIR/roles/$name/defaults/main.yml"
    echo ''                         >> "$SCRIPT_DIR/roles/$name/defaults/main.yml"
    echo '# vim:et ts=2 sts=2 sw=2' >> "$SCRIPT_DIR/roles/$name/defaults/main.yml"

    # add to playbook in case I forgot
    awk "1;/roles:/{print \"    - $name\"}" "$SCRIPT_DIR/playbook.yml" > "$SCRIPT_DIR/playbook.yml.tmp"
    if test "$?" -eq 0; then
        test -r "$SCRIPT_DIR/playbook.yml.tmp" && mv "$SCRIPT_DIR/playbook.yml.tmp" "$SCRIPT_DIR/playbook.yml"
    else
        test -r "$SCRIPT_DIR/playbook.yml.tmp" && rm "$SCRIPT_DIR/playbook.yml.tmp"
    fi
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
    . $HOME/.bashrc_append
    sdev

    # # do it here, as I don't want it in bashrc to slow it down
    # nvm use --lts

    # get a list of commands to check
    cmds=( \
        # 'svls' \
        'ansible' \
        'ansible-playbook' \
        'asdf' \
        'bash-language-server' \
        'bat' \
        'caddy' \
        'cargo' \
        'clang' \
        'clangd' \
        'cmake' \
        'conda' \
        'ctags' \
        'dmenu' \
        'doas' \
        'docker' \
        'docker-langserver' \
        'doxygen' \
        'dust' \
        'exa' \
        'fd' \
        'git' \
        'gtop' \
        'java' \
        'javac' \
        'kitty' \
        'lua' \
        'luarocks' \
        'nethogs' \
        'node' \
        'npm' \
        'nvim' \
        'nvm' \
        'openconnect' \
        'p4' \
        'p4p' \
        'procs' \
        'pwsh' \
        'python3' \
        'rg' \
        'rustc' \
        'rustup' \
        'sd' \
        'starship' \
        'tmux' \
        'toclip' \
        'tokei' \
        'tree-sitter' \
        'tshark' \
        'typescript-language-server' \
        'vncserver' \
        'vscode-json-language-server' \
        'wireshark' \
        'xclip' \
        'xmobar' \
        'xmonad' \
        'yaml-language-server' \
        'yarn' \
    )
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
    . $HOME/.bashrc
    . $HOME/.bashrc_append
    sdev
    # do it here, as I don't want it in bashrc to slow it down
    nvm use --lts
    # Do the node upgrade
    nvm install-latest-npm
    ;;

'install')
    # var
    verbose=false
    stable=true
    updateDotfile='{"update_dotfile": false}'
    installAll='{"install_all": false}'

    # parse the argumetns
    shift
    while getopts ':avbu' opt; do
        case "$opt" in
        v)
            verbose=true
            ;;
        b)
            stable=false
            ;;
        a)
            installAll='{"install_all": true}'
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

    install_ansible

    # install with ansible playbook
    if [[ "$verbose" == 'true' && "$stable" == 'true' ]]; then
        ansible-playbook -vvv playbook.yml --extra-vars '@./vars/stable.yml' --extra-vars "$updateDotfile" --extra-vars "$installAll"
    elif [[ "$verbose" == 'true' && "$stable" == 'false' ]]; then
        ansible-playbook -vvv playbook.yml --extra-vars "$updateDotfile" --extra-vars "$installAll"
    elif [[ "$verbose" == 'false' && "$stable" == 'true' ]]; then
        ansible-playbook playbook.yml --extra-vars '@./vars/stable.yml' --extra-vars "$updateDotfile" --extra-vars "$installAll"
    else
        ansible-playbook playbook.yml --extra-vars "$updateDotfile" --extra-vars "$installAll"
    fi
    ;;

'install-i')
    # var
    verbose=false
    stable=true
    updateDotfile='{"update_dotfile": false}'
    installAll='{"install_all": false}'

    # parse the argumetns
    shift
    while getopts ':avbu' opt; do
        case "$opt" in
        v)
            verbose=true
            ;;
        a)
            installAll='{"install_all": true}'
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

    install_ansible

    # install with ansible playbook
    if [[ "$verbose" == 'true' && "$stable" == 'true' ]]; then
        PY_COLORS=1 \
        ANSIBLE_FORCE_COLOR=1 \
        ansible-playbook -K -vvv playbook.yml --extra-vars "@./vars/stable.yml" --extra-vars "$updateDotfile" --extra-vars "$installAll" | tee $TEST_LOG

    elif [[ "$verbose" == 'true' && "$stable" == 'false' ]]; then
        PY_COLORS=1 \
        ANSIBLE_FORCE_COLOR=1 \
        ansible-playbook -K -vvv playbook.yml --extra-vars "$updateDotfile" --extra-vars "$installAll" | tee $TEST_LOG

    elif [[ "$verbose" == 'false' && "$stable" == 'true' ]]; then
        PY_COLORS=1 \
        ANSIBLE_FORCE_COLOR=1 \
        ansible-playbook -K playbook.yml --extra-vars "@./vars/stable.yml" --extra-vars "$updateDotfile" --extra-vars "$installAll" | tee $TEST_LOG

    else
        PY_COLORS=1 \
        ANSIBLE_FORCE_COLOR=1 \
        ansible-playbook -K playbook.yml --extra-vars "$updateDotfile" --extra-vars "$installAll" | tee $TEST_LOG
    fi
    ;;

'tmux')
    if ! (tmux ls | grep -q blah); then
        tmux new-session -d -s blah -n dev-env-ansible -c "$SCRIPT_DIR"
        tmux new-window -d -t blah: -n dockers -c "$SCRIPT_DIR"
        tmux new-window -d -t blah: -n dotfiles -c "$SCRIPT_DIR/../dotfiles"
        tmux new-window -d -t blah: -n focusside -c "$SCRIPT_DIR/../focus-side.vim"
    fi
    tmux attach-session -t blah
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
        $DOCKER_VOLUME_MOUNT \
        --name "$(compose_container_name "$RUN_PREFIX_FOR_NAME" "$2")" \
        "$CONTAINER_TAG" \
        bash -i -c "cd ./repos/dev-env-ansible ; bash -i"
    ;;

'run-build')
    # build up the command here
    cmd="cd ./repos/dev-env-ansible && ./rr.sh install"
    cmd="$cmd && . ~/.bashrc && . ~/.bashrc_append"
    # select docker
    ver="$DOCKER_FILE_UBUNTU_18"
    if [[ $# -gt 1 ]]; then
        ver="$(select_docker_ver $2)"
    fi
    # start bash inside container
    docker build --tag "$CONTAINER_TAG" "$ver" && \
    docker run --rm -it \
        --network="host" \
        $DOCKER_VOLUME_MOUNT \
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
            DOCKER_VOLUME_MOUNT="$DOCKER_VOLUME_MOUNT -v $wdir:$ANSIBLE_HOME/$(basename $wdir) "
            ;;
        esac
    done

    # start bash inside container
    if [[ -z $wdir ]]; then
        docker run --rm -it \
            --network="host" \
            $DOCKER_VOLUME_MOUNT \
            --name "$(compose_container_name "$RUN_PREFIX_FOR_NAME" "$tag")" \
            "$DEV_ENV_REPOSITORY_NAME:$tag" \
            bash -i -c "cd ./repos/dev-env-ansible; exec zsh"

    else
        docker run --rm -it \
            --network="host" \
            $DOCKER_VOLUME_MOUNT \
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
    cmd="$cmd && . ~/.bashrc && . ~/.bashrc_append"

    # start bash inside container
    docker run --rm -it \
        --network="host" \
        $DOCKER_VOLUME_MOUNT \
        --name "$(compose_container_name "$RUN_PREFIX_FOR_NAME" "$tag")" \
        "$DEV_ENV_REPOSITORY_NAME:$tag" \
        bash -i -c "$cmd; exec zsh"
    ;;

'run-test')
    # build up the command here
    cmd="cd ./repos/dev-env-ansible && ./rr.sh install -a -u"
    cmd="$cmd && . ~/.bashrc && . ~/.bashrc_append && ./rr.sh install -a -u && ./rr.sh check"
    cmd="$cmd && ./rr.sh preupgrade && ./rr.sh install -a -u && ./rr.sh check"
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
