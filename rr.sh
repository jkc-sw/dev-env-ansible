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

# Temp playbook
WHOLE_PLAYBOOK_PATH="$SCRIPT_DIR/playbook.yml"
WORKFLOW_PATH="$SCRIPT_DIR/.github/workflows/main.yml"

# Write playbook
# @brief Return the name for the playbook
# @param role - The name of the role to put in the playbook
playbookName() {
    # role is
    role="$1"

    # Find all the roles
    if ! ls "$SCRIPT_DIR/roles" | grep -q "$role"; then
        echo "role $role cannot be found in the ./roles folder" >&2
        exit 1
    fi

    echo -n "$SCRIPT_DIR/testbook_$role.yml"
}

# Write playbook
# @brief Create temp playbook for a role
# @param role - The name of the role to put in the playbook
writePlaybook() {
    # role is
    role="$1"

    # playname
    playpath="$(playbookName "$role")"

    cat <<EOF > "$playpath"
---
- hosts: local
  gather_facts: true
  roles:
    - $role
EOF

    # return the name
    echo -n "$playpath"
}

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
    echo " One-stop shop to do everything related to this repository"
    echo ""
    echo "--------------------------------------------------------------------------------"
    echo "Display Help"
    echo " -h|--help|h|hel|help  : Print this help command"
    echo ""
    echo "--------------------------------------------------------------------------------"
    echo "Running the ansible commands or related check"
    echo " install [-v] [-t 'tag1[,tag2 ...]']"
    echo "   Install on the host system (when do it on your production machine) prompting for password"  # desc
    echo ""
    echo " install-i [-v] [-t 'tag1[,tag2 ...]']"
    echo "   Install on the host system (mostly container) w/o asking for password"  # desc
    echo ""
    echo " tags"
    echo "   List all the tags"  # desc
    echo ""
    echo " roles"
    echo "   List all the roles"  # desc
    echo ""
    echo " role [-v] [-t 'tag1[,tag2 ...]'] [-r <role>]"
    echo "   Run a role on the host system (mostly container) prompting for password"  # desc
    echo ""
    echo " role-i [-v] [-t 'tag1[,tag2 ...]'] [-r <role>]"
    echo "   Run a role on the host system (mostly container) w/o asking for password"  # desc
    echo ""
    echo " check"
    echo "   Do simple check on the host system for all executable"  # desc
    echo ""
    echo " preupgrade"
    echo "   Do the necessary stuff to get the system upgraded"  # desc
    echo ""
    echo "  where"
    echo "   -v > Provide the -vvv option to the ansigle command to have debug output"
    echo "   -u > Will update the dotfile repo"
    echo "   -a > Install all, like xmonad, etc"
    echo "   -t > Tags to use, comma separated, no space"
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
    echo " run [ver]"
    echo "   Start a new docker container only"  # desc
    echo ""
    echo " run-build [ver]"
    echo "   Start a new docker container and run ansible-playbook"  # desc
    echo ""
    echo " commit ID TAG"
    echo "   Commit a running docker container ID with the TAG specified"  # desc
    echo ""
    echo " use TAG [-w dir]"
    echo "   Start a committed image only"  # desc
    echo ""
    echo " list"
    echo "   List all the images"  # desc
    echo ""
    echo " use-build TAG"
    echo "   Start a committed image and run ansible-playbook"  # desc
    echo ""
    echo " run-test [ver]"
    echo "   Start a new docker container and run simple CI test"  # desc
    echo ""
    echo " run-role <ver> <role>"
    echo "   Start a new docker container and run a role"  # desc
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

# if args, print help
if test "$#" -eq 0; then
    displayHelp
    exit 0
fi

# if there are arg for test, run test
subcmd="$1"
shift
case "$subcmd" in
'-h'|'--help'|'h'|'hel'|'help')
    displayHelp
    exit 1
    ;;

'new-role')
    # need 1 argrs
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
    awk "1;/roles:/{print \"    - $name\"}" "$WHOLE_PLAYBOOK_PATH" > "$WHOLE_PLAYBOOK_PATH.tmp"
    if test "$?" -eq 0; then
        test -r "$WHOLE_PLAYBOOK_PATH.tmp" && mv "$WHOLE_PLAYBOOK_PATH.tmp" "$WHOLE_PLAYBOOK_PATH"
    fi

    # add to workflow in case I forgot
    awk "1;/role:/{print \"          '$name',\"}" "$WORKFLOW_PATH" > "$WORKFLOW_PATH.tmp"
    if test "$?" -eq 0; then
        test -r "$WORKFLOW_PATH.tmp" && mv "$WORKFLOW_PATH.tmp" "$WORKFLOW_PATH"
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
    nv

    # # do it here, as I don't want it in bashrc to slow it down
    # nvm use --lts

    # get a list of commands to check
    cmds=( \
        # 'fzf' \
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
        'ghdl' \
        'git' \
        'gtop' \
        'hdl_checker' \
        'iverilog' \
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
        'p4v' \
        'procs' \
        'pwsh' \
        'python3' \
        'rg' \
        'rofi' \
        'rustc' \
        'rustup' \
        'sd' \
        'starship' \
        'svls' \
        'tmux' \
        'toclip' \
        'tokei' \
        'tracecompass' \
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

'roles')
    # List all the roles
    ls "$SCRIPT_DIR/roles" \
    | sort \
    | xargs printf 'role: %s\n'
    ;;

'tags')
    # List all the tags
    echo "Listing all the tags"
    ansible-playbook "$WHOLE_PLAYBOOK_PATH" --list-tags
    ;;

'role-i')
    # var
    verbose=false
    tags='untagged'
    role=''

    # parse the argumetns
    while getopts ':vt:r:' opt; do
        case "$opt" in
        v)
            verbose=true
            ;;
        r)
            role="$OPTARG"
            ;;
        t)
            tags="$tags,$OPTARG"
            ;;
        *)
            echo "Unrecognized option $opt" >&2
            displayHelp
            ;;
        esac
    done

    # need a role
    if test -z "$role"; then
        echo "No role specified, use -r <role> to run a role" >&2
        exit 1
    fi

    install_ansible

    # Write the role
    playpath="$(writePlaybook "$role")"

    # trap remove
    trap "rm -f $playpath" EXIT SIGINT SIGTERM KILL

    # install with ansible playbook
    if [[ "$verbose" == 'true' ]]; then
        ansible-playbook -vvv "$playpath" --tags "$tags"
    elif [[ "$verbose" == 'false' ]]; then
        ansible-playbook "$playpath" --tags "$tags"
    fi
    ;;

'role')
    # var
    verbose=false
    tags='untagged'
    role=''

    # parse the argumetns
    while getopts ':vt:r:' opt; do
        case "$opt" in
        v)
            verbose=true
            ;;
        t)
            tags="$tags,$OPTARG"
            ;;
        r)
            role="$OPTARG"
            ;;
        *)
            echo "Unrecognized option $opt" >&2
            displayHelp
            ;;
        esac
    done

    # need a role
    if test -z "$role"; then
        echo "No role specified, use -r <role> to run a role" >&2
        exit 1
    fi

    install_ansible

    # Write the role
    playpath="$(writePlaybook "$role")"

    # trap remove
    trap "rm -f $playpath" EXIT SIGINT SIGTERM KILL

    # install with ansible playbook
    if [[ "$verbose" == 'true' ]]; then
        PY_COLORS=1 \
        ANSIBLE_FORCE_COLOR=1 \
        ansible-playbook -K -vvv "$playpath" --tags "$tags" | tee $TEST_LOG

    elif [[ "$verbose" == 'false' ]]; then
        PY_COLORS=1 \
        ANSIBLE_FORCE_COLOR=1 \
        ansible-playbook -K "$playpath" --tags "$tags" | tee $TEST_LOG
    fi
    ;;

'install-i')
    # var
    verbose=false
    tags='untagged'

    # parse the argumetns
    while getopts ':vt:r:' opt; do
        case "$opt" in
        v)
            verbose=true
            ;;
        t)
            tags="$tags,$OPTARG"
            ;;
        *)
            echo "Unrecognized option $opt" >&2
            displayHelp
            ;;
        esac
    done

    install_ansible

    # install with ansible playbook
    if [[ "$verbose" == 'true' ]]; then
        ansible-playbook -vvv "$WHOLE_PLAYBOOK_PATH" --tags "$tags"
    elif [[ "$verbose" == 'false' ]]; then
        ansible-playbook "$WHOLE_PLAYBOOK_PATH" --tags "$tags"
    fi
    ;;

'install')
    # var
    verbose=false
    tags='untagged'

    # parse the argumetns
    while getopts ':vt:r:' opt; do
        case "$opt" in
        v)
            verbose=true
            ;;
        t)
            tags="$tags,$OPTARG"
            ;;
        *)
            echo "Unrecognized option $opt" >&2
            displayHelp
            ;;
        esac
    done

    install_ansible

    # install with ansible playbook
    if [[ "$verbose" == 'true' ]]; then
        PY_COLORS=1 \
        ANSIBLE_FORCE_COLOR=1 \
        ansible-playbook -K -vvv "$WHOLE_PLAYBOOK_PATH" --tags "$tags" | tee $TEST_LOG

    elif [[ "$verbose" == 'false' ]]; then
        PY_COLORS=1 \
        ANSIBLE_FORCE_COLOR=1 \
        ansible-playbook -K "$WHOLE_PLAYBOOK_PATH" --tags "$tags" | tee $TEST_LOG
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
    ver="$DOCKER_FILE_UBUNTU_20"
    if [[ $# -gt 0 ]]; then
        ver="$(select_docker_ver $1)"
    fi

    # start bash inside container
    docker build --tag "$CONTAINER_TAG" "$ver" && \
    docker run --rm -it \
        --network="host" \
        $DOCKER_VOLUME_MOUNT \
        --name "$(compose_container_name "$RUN_PREFIX_FOR_NAME" "$1")" \
        "$CONTAINER_TAG" \
        bash -i -c "cd ./repos/dev-env-ansible ; bash -i"
    ;;

'run-build')
    # build up the command here
    cmd="cd ./repos/dev-env-ansible && ./rr.sh install-i"
    cmd="$cmd && . ~/.bashrc && . ~/.bashrc_append"
    # select docker
    ver="$DOCKER_FILE_UBUNTU_20"
    if [[ $# -gt 0 ]]; then
        ver="$(select_docker_ver $1)"
    fi
    # start bash inside container
    docker build --tag "$CONTAINER_TAG" "$ver" && \
    docker run --rm -it \
        --network="host" \
        $DOCKER_VOLUME_MOUNT \
        --name "$(compose_container_name "$RUN_PREFIX_FOR_NAME" "$1")" \
        "$CONTAINER_TAG" \
        bash -i -c "$cmd ; exec zsh"
    ;;

'commit')
    # get args
    ident=$1
    tag=$2
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
    tag=$1
    # build up the command here
    cmd="cd ./repos/dev-env-ansible && ./rr.sh install-i -t 'gui,dotfiles'"
    cmd="$cmd && . ~/.bashrc && . ~/.bashrc_append"

    # start bash inside container
    docker run --rm -it \
        --network="host" \
        $DOCKER_VOLUME_MOUNT \
        --name "$(compose_container_name "$RUN_PREFIX_FOR_NAME" "$tag")" \
        "$DEV_ENV_REPOSITORY_NAME:$tag" \
        bash -i -c "$cmd; exec zsh"
    ;;

'run-role')
    # get args
    ver="$1"
    role="$2"

    # build up the command here
    cmd='cd ./repos/dev-env-ansible && export ANSIBLE_CONFIG="$(pwd)/ansible.cfg" && ./rr.sh role-i -r'
    cmd="$cmd '$role'"
    cmd="$cmd && . ~/.bashrc && . ~/.bashrc_append && ./rr.sh role-i -r '$role'"
    cmd="$cmd && ./rr.sh preupgrade && ./rr.sh install-i -r '$role'"

    # select docker
    ver="$DOCKER_FILE_UBUNTU_20"
    if [[ $# -gt 0 ]]; then
        ver="$(select_docker_ver $1)"
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

'run-test')
    # build up the command here
    cmd='cd ./repos/dev-env-ansible && export ANSIBLE_CONFIG="$(pwd)/ansible.cfg" && ./rr.sh install-i -t "gui,dotfiles"'
    cmd="$cmd && . ~/.bashrc && . ~/.bashrc_append && ./rr.sh install-i -t 'gui,dotfiles' && ./rr.sh check"
    cmd="$cmd && ./rr.sh preupgrade && ./rr.sh install-i -t 'gui,dotfiles' && ./rr.sh check"
    # select docker
    ver="$DOCKER_FILE_UBUNTU_20"
    if [[ $# -gt 0 ]]; then
        ver="$(select_docker_ver $1)"
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
    echo "subcommand $subcmd invalid" >&2
    # print help
    displayHelp
    exit 1
    ;;
esac

# # Some great links: https://web.archive.org/web/20170203212120/http://www.ibm.com/developerworks/opensource/library/l-bash-parameters/index.html
# showopts () {
#   while getopts ":pq:" optname
#     do
#       case "$optname" in
#         "p")
#           echo "Option $optname is specified"
#           ;;
#         "q")
#           echo "Option $optname has value $OPTARG"
#           ;;
#         "?")
#           echo "Unknown option $OPTARG"
#           ;;
#         ":")
#           echo "No argument value for option $OPTARG"
#           ;;
#         *)
#         # Should not occur
#           echo "Unknown error while processing options"
#           ;;
#       esac
#     done
#   return $OPTIND
# }
#  
# showargs () {
#   for p in "$@"
#     do
#       echo "[$p]"
#     done
# }
#  
# optinfo=$(showopts "$@")
# argstart=$?
# arginfo=$(showargs "${@:$argstart}")
# echo "Arguments are:"
# echo "$arginfo"
# echo "Options are:"
# echo "$optinfo"
