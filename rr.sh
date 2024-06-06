#!/bin/bash

: <<AEOF
SOURCE_THESE_VIMS_START
nnoremap <leader>ueo <cmd>silent exec "!tmux send-keys -t :.+ 'ANSIBLE_DEBUG=false ANSIBLE_VERBOSITY=1 ./rr.sh edit ./inventory/local.yaml' Enter"<cr>
nnoremap <leader>ued <cmd>silent exec "!tmux send-keys -t :.+ 'ANSIBLE_DEBUG=false ANSIBLE_VERBOSITY=1 ./rr.sh edit ./inventory/docker-enc.yaml' Enter"<cr>
nnoremap <leader>us <cmd>silent exec "!tmux send-keys -t :.+ 'ANSIBLE_DEBUG=false ANSIBLE_VERBOSITY=1 ./rr.sh role -r scratch -g asus' Enter"<cr>
nnoremap <leader>udh <cmd>silent exec "!tmux send-keys -t :+ 'ANSIBLE_DEBUG=false ANSIBLE_VERBOSITY=1 ./rr.sh role-i -r home-manager -t fast' Enter"<cr>
nnoremap <leader>udi <cmd>silent exec "!tmux send-keys -t :+ 'ANSIBLE_DEBUG=false ANSIBLE_VERBOSITY=1 ./rr.sh install-i -t fast' Enter"<cr>

let @h="yoecho \"\<c-r>\" = \$\<c-r>\"\"\<esc>j"
echom 'Sourced'
SOURCE_THESE_VIMS_END
AEOF


# get location of this folder
SCRIPT_DIR="$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )"
PROJECT_DIR="$SCRIPT_DIR"

# make sure we are in the correct folder
pushd "$SCRIPT_DIR" &>/dev/null

# container tag
CONTAINER_TAG=devenvansible:1.0

# lxc name
LXC_NAME=tom

# ansible workspace path
ANSIBLE_HOME="/home/$USER"
ANSIBLE_DEV_ENV_ANSIBLE_PATH=$ANSIBLE_HOME/repos/dev-env-ansible

# docker volumn mount
DOCKER_VOLUME_MOUNT=()
LXC_VOLUME_MOUNT=()

# docker files dir
DOCKER_FILE_DIR=./dockerfiles

# docker file name
DOCKER_FILE_UBUNTU_24="$DOCKER_FILE_DIR/ubuntu2404/Dockerfile"
DOCKER_FILE_UBUNTU_22="$DOCKER_FILE_DIR/ubuntu2204/Dockerfile"
DOCKER_FILE_UBUNTU_20="$DOCKER_FILE_DIR/ubuntu2004/Dockerfile"
DOCKER_FILE_UBUNTU_18="$DOCKER_FILE_DIR/ubuntu1804/Dockerfile"
DOCKER_FILE_UBUNTU_16="$DOCKER_FILE_DIR/ubuntu1604/Dockerfile"

# docker repo name to be managed by rr.sh
DEV_ENV_REPOSITORY_NAME=devenvansible
RUN_PREFIX_FOR_NAME=run
USE_PREFIX_FOR_NAME=use

# Docker only password file path
DOCKER_INVENTORY_FILE_ENCRYPETED="$PROJECT_DIR/inventory/docker-enc.yaml"
DOCKER_INVENTORY_FILE="$PROJECT_DIR/inventory/docker.yaml"

# Temp playbook
WHOLE_PLAYBOOK_PATH="$SCRIPT_DIR/playbooks/everything.yml"
WORKFLOW_PATH="$SCRIPT_DIR/.github/workflows/main.yml"

# Write playbook
# @brief Return the name for the playbook
# @param role - The name of the role to put in the playbook
playbookName() {
    # role is
    role="$1"

    # Find all the roles
    if ! ls "$SCRIPT_DIR/playbooks/roles" | grep -q "$role"; then
        echo "role $role cannot be found in the ./playbooks/roles folder" >&2
        exit 1
    fi

    echo -n "$SCRIPT_DIR/playbooks/testbook_$role.yml"
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
- hosts: "{{ playbook_target }}"
  gather_facts: true
  roles:
    - $role
EOF

    # return the name
    echo -n "$playpath"
}

# define a function to perform check on role
roleCheck() {
    log="$1"
    # perform test
    if ! grep -q 'failed=0' "$log"; then
        echo "failed should be 0 at the secound run" >&2
        exit 2
    fi
}

# define a function to perform check
ansibleCheck() {
    log="$1"
    # perform test
    if ! grep -q 'changed=0' "$log"; then
        echo "changed should be 0 at the secound run" >&2
        exit 1
    fi

    roleCheck "$log"

    if grep -q 'not installed properly' "$log"; then
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
    echo " install -g HOSTS [-v] [-t 'tag1[,tag2 ...]']"
    echo "   Install on the host system (when do it on your production machine) prompting for password"  # desc
    echo ""
    echo " install-i [-g HOSTS] [-v] [-t 'tag1[,tag2 ...]']"
    echo "   Install on the host system (mostly container) w/o asking for password"  # desc
    echo ""
    echo " tags"
    echo "   List all the tags"  # desc
    echo ""
    echo " roles"
    echo "   List all the roles"  # desc
    echo ""
    echo " role -g HOSTS [-v] [-t 'tag1[,tag2 ...]'] -r <role>"
    echo "   Run a role on the host system (mostly container) prompting for password"  # desc
    echo ""
    echo " role-i [-g HOSTS] [-v] [-t 'tag1[,tag2 ...]'] -r <role>"
    echo "   Run a role on the host system (mostly container) w/o asking for password"  # desc
    echo ""
    echo " check"
    echo "   Do simple check on the host system for all executable"  # desc
    echo ""
    echo " preupgrade"
    echo "   Do the necessary stuff to get the system upgraded"  # desc
    echo ""
    echo "  where"
    echo "   -g > An inventory host name or a group of hosts in the inventory file"
    echo "   -v > Provide the -vvv option to the ansigle command to have debug output"
    echo "   -u > Will update the dotfile repo"
    echo "   -a > Install all, like xmonad, etc"
    echo "   -t > Tags to use, comma separated, no space"
    echo ""
    echo "--------------------------------------------------------------------------------"
    echo "Manage and handle the ansible vault for inventory file"
    echo " edit: Edit the inventory file"
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
    echo " run [-n UBUNTU_VER] [-w dir]"
    echo "   Start a new docker container only"  # desc
    echo ""
    echo " run-build [ver]"
    echo "   Start a new docker container and run ansible-playbook"  # desc
    echo ""
    echo " commit ID TAG"
    echo "   Commit a running docker container ID with the TAG specified"  # desc
    echo ""
    echo " use -d TAG [-w dir]"
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
    echo " use-role <ver> <role>"
    echo "   Start a committed image and run a role"  # desc
    echo ""
    echo " where"
    echo "  -n UBUNTU_VER > Ubuntu version to spawn a docker container. One of 18, 20, 22, 24"
    echo "  -d TAG > One of the docker tag from image devenvansible"
    echo "  -w dir > Bind mount this folder to the container"
    echo " arguments:"
    echo "  ver > Specify the version to use. Default 18. One of 18, 20, 22, 24"
    echo "  ID  > This is the container name or ID to use to make a commit, full name required"
    echo "  TAG > This is by your preference on how the commited container to be tagged"
}

# see what version to use
select_docker_ver() {
    # get the arg
    ver=$1
    # select the version
    case "$ver" in
    24)
        echo -n "$DOCKER_FILE_UBUNTU_24"
        ;;

    22)
        echo -n "$DOCKER_FILE_UBUNTU_22"
        ;;

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

# Build container
build_image() {
    # Get args
    tag="$1"
    dfile="$2"
    # Infer arg
    args=(build --tag "$tag" -f "$dfile")
    args+=(--build-arg SHELL_USER="$USER")
    args+=(--build-arg SHELL_UID="$(id -u "$USER")")
    args+=(--build-arg SHELL_GID="$(id -g "$USER")")
    args+=(.)
    docker "${args[@]}"
}

# Setup nix
setup_nix() {
    export LOCALE_ARCHIVE=/usr/lib/locale/locale-archive
    # Source nix if using nix-installer
    if [[ -r "/nix/var/nix/profiles/default/etc/profile.d/nix.sh" ]]; then
        . "/nix/var/nix/profiles/default/etc/profile.d/nix.sh"
    fi
    # Source nix if using nix official installer
    if [[ -r "$HOME/.nix-profile/etc/profile.d/nix.sh" ]]; then
        . "$HOME/.nix-profile/etc/profile.d/nix.sh"
    fi
}

# instal nix
install_nix() {
    setup_nix
    if ! command -v nix &>/dev/null; then
        # Install nix
        export NIX_INSTALLER_NO_MODIFY_PROFILE=1 ; /bin/bash <(curl -L https://nixos.org/nix/install)
        setup_nix
    fi
}

# Setup env
setup_brew() {
    if [[ -x /home/linuxbrew/.linuxbrew/bin/brew && -z "$HOMEBREW_PREFIX" ]]; then
        eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    fi
}

# instal brew
install_brew() {
    setup_brew
    if ! command -v brew &>/dev/null; then
        /bin/bash -c "export NONINTERACTIVE=1 ; $(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        brew install ansible
        setup_brew
    fi
}

# NOTE: This should only be used for the ephemeral docker image
decrypt_inventory_for_docker() {
    if [[ -n "$PASSWORD_STORE_DIR" ]]; then
        # Check dependencies
        toexit=false
        for c in pass; do
            if ! command -v "$c" &>/dev/null; then
                echo "ERR: $c is not found in your PATH" >&2
                toexit=true
            fi
        done
        if [[ "$toexit" == true ]]; then
            echo "ERR (decrypt_inventory_for_docker): Please make sure you install all the necessary tool first" >&2
            exit 1
        fi
    fi
    "$PROJECT_DIR/scripts/decrypt_file.sh" "$DOCKER_INVENTORY_FILE_ENCRYPETED" "$DOCKER_INVENTORY_FILE"
}

# function to install ansible
install_ansible() {
    # check if the ansible is installed, if not, install it
    if ! command -v curl &>/dev/null; then
        # sudo apt install -y python3 python3-pip
        # sudo -H python3 -m pip install ansible

        sudo apt update
        sudo apt install -y curl git ca-certificates xz-utils
    fi
    install_nix
    # install_brew
}

# fnuction that check and set a docker mount when not fonud
append_docker_mount_global() {
    # Get arguments
    local args=("$@")
    # Need 1 argument
    if [[ "${#args[@]}" -ne 1 ]]; then
        echo "ERR (append_docker_mount_global): need 1 argument only, but found ${#args[@]}" >&2
        return 1
    fi
    local path="${args[0]}"
    if [[ "${DOCKER_VOLUME_MOUNT[*]}" == *"$path"* ]]; then
        return 0
    fi
    DOCKER_VOLUME_MOUNT+=(-v "$path")
    echo "DEBUG (append_docker_mount_global): Add '$path'" >&2
}

# function to populate the docker mount in a function
set_docker_mounts_global() {
    # docker volumn mount
    for each in \
        "$SCRIPT_DIR/../dotfiles:$ANSIBLE_HOME/repos/dotfiles" \
        "$SCRIPT_DIR:$ANSIBLE_DEV_ENV_ANSIBLE_PATH" \
        "$SCRIPT_DIR/../focus-side.vim:$ANSIBLE_HOME/repos/focus-side.vim" \
        "$SCRIPT_DIR/../jerry-nixos:$ANSIBLE_HOME/repos/jerry-nixos" \
        "$HOME/.ssh/id_ed25519:$HOME/.ssh/id_ed25519" \
    ; do
        append_docker_mount_global "$each"
    done
}

# function ta append the lxc mount
add_lxc_mount_global() {
    # Get arguments
    local args=("$@")
    # Need 1 argument
    if [[ "${#args[@]}" -ne 3 ]]; then
        echo "ERR (add_lxc_mount_global): need 3 arguments (bin, name, path) only, but found ${#args[@]}" >&2
        return 1
    fi
    local cmd="${args[0]}"
    local name="${args[1]}"
    local path="${args[2]}"
    "$cmd" config device add "$LXC_NAME" "$name" disk source="${path#*:}" path="${path%:*}"
    echo "DEBUG (add_lxc_mount_global): Added '$path'" >&2
}

append_lxc_mount_global() {
    # Get arguments
    local args=("$@")
    # Need 1 argument
    if [[ "${#args[@]}" -ne 1 ]]; then
        echo "ERR (append_lxc_mount_global): need 1 argument only, but found ${#args[@]}" >&2
        return 1
    fi
    local path="${args[0]}"
    if [[ "${LXC_VOLUME_MOUNT[*]}" == *"$path"* ]]; then
        return 0
    fi
    LXC_VOLUME_MOUNT+=("$path")
    echo "DEBUG (append_lxc_mount_global): Added '$path'" >&2
}

# function to populate the docker mount in a function
apply_lxc_mounts_global() {
    # Get arguments
    local args=("$@")
    # Need 1 argument
    if [[ "${#args[@]}" -ne 1 ]]; then
        echo "ERR (apply_lxc_mounts_global): need 1 arguments (bin) only, but found ${#args[@]}" >&2
        return 1
    fi
    local cmd="${args[0]}"
    # Add default monut
    for each in \
        "$SCRIPT_DIR/../dotfiles:$ANSIBLE_HOME/repos/dotfiles" \
        "$SCRIPT_DIR:$ANSIBLE_DEV_ENV_ANSIBLE_PATH" \
        "$SCRIPT_DIR/../focus-side.vim:$ANSIBLE_HOME/repos/focus-side.vim" \
        "$SCRIPT_DIR/../jerry-nixos:$ANSIBLE_HOME/repos/jerry-nixos" \
        "$HOME/.ssh/id_ed25519:$HOME/.ssh/id_ed25519" \
    ; do
        append_lxc_mount_global "$each"
    done
    # Apply the monts to the lxc
    for ii in $(seq 0 $(( "${#LXC_VOLUME_MOUNT[@]}" - 1)) ); do
        local each="${LXC_VOLUME_MOUNT[ii]}"
        add_lxc_mount_global "$cmd" "d$ii" "$each"
    done
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
    mkdir -p "$SCRIPT_DIR/playbooks/roles/$name/meta"
    mkdir -p "$SCRIPT_DIR/playbooks/roles/$name/tasks"
    mkdir -p "$SCRIPT_DIR/playbooks/roles/$name/defaults"

    # write meta
    echo '---'                      >> "$SCRIPT_DIR/playbooks/roles/$name/meta/main.yml"
    echo 'dependencies:'            >> "$SCRIPT_DIR/playbooks/roles/$name/meta/main.yml"
    echo '  - common_settings'      >> "$SCRIPT_DIR/playbooks/roles/$name/meta/main.yml"
    echo ''                         >> "$SCRIPT_DIR/playbooks/roles/$name/meta/main.yml"
    echo '# vim:et ts=2 sts=2 sw=2' >> "$SCRIPT_DIR/playbooks/roles/$name/meta/main.yml"

    # write tasks
    echo '---'                                      >> "$SCRIPT_DIR/playbooks/roles/$name/tasks/main.yml"
    echo '- name: PLACEHOLDER'                      >> "$SCRIPT_DIR/playbooks/roles/$name/tasks/main.yml"
    echo '  fail:'                                  >> "$SCRIPT_DIR/playbooks/roles/$name/tasks/main.yml"
    echo "    msg: 'need to implement $name tasks'" >> "$SCRIPT_DIR/playbooks/roles/$name/tasks/main.yml"
    echo ''                                         >> "$SCRIPT_DIR/playbooks/roles/$name/tasks/main.yml"
    echo '# vim:et ts=2 sts=2 sw=2'                 >> "$SCRIPT_DIR/playbooks/roles/$name/tasks/main.yml"

    # write defaults
    echo '---'                                 >> "$SCRIPT_DIR/playbooks/roles/$name/defaults/main.yml"
    echo 'home_dir: "{{ ansible_env.HOME }}" ' >> "$SCRIPT_DIR/playbooks/roles/$name/defaults/main.yml"
    echo ''                                    >> "$SCRIPT_DIR/playbooks/roles/$name/defaults/main.yml"
    echo '# vim:et ts=2 sts=2 sw=2'            >> "$SCRIPT_DIR/playbooks/roles/$name/defaults/main.yml"

    # add to playbook in case I forgot
    awk "1; /roles:/ { if (found == 0) { print \"    - $name\" }; found++ }" "$WHOLE_PLAYBOOK_PATH" > "$WHOLE_PLAYBOOK_PATH.tmp"
    if test "$?" -eq 0; then
        test -r "$WHOLE_PLAYBOOK_PATH.tmp" && mv "$WHOLE_PLAYBOOK_PATH.tmp" "$WHOLE_PLAYBOOK_PATH"
    fi

    # add to workflow in case I forgot
    awk "1; /role:/ { if (found == 0) { print \"          '$name',\" }; found++ }" "$WORKFLOW_PATH" > "$WORKFLOW_PATH.tmp"
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
        # 'ghdl' \
        # 'iverilog' \
        'ansible' \
        'ansible-playbook' \
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
        'eza' \
        'fd' \
        'git' \
        'gtop' \
        'hdl_checker' \
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
    ls "$SCRIPT_DIR/playbooks/roles" \
    | sort \
    | xargs printf 'role: %s\n'
    ;;

'tags')
    # List all the tags
    echo "Listing all the tags"
    decrypt_inventory_for_docker
    ansible-playbook -i ./inventory/docker.yaml -e "playbook_target=docker" --vault-id "prod@$PROJECT_DIR/scripts/vault-client.sh" "$WHOLE_PLAYBOOK_PATH" --list-tags
    ;;

'role-i')
    # var
    verbose=false
    tags='untagged'
    role=''
    hosts='docker'

    # parse the argumetns
    while getopts ':vg:t:r:' opt; do
        case "$opt" in
        g)
            hosts="$OPTARG"
            ;;
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
        echo "ERR: No role specified, use -r <role> to run a role" >&2
        exit 1
    fi

    if [[ -z "$hosts" ]]; then
        echo 'ERR: no hosts specified. Add -g HOSTS to the command and try again' >&2
        exit 1
    fi

    install_ansible

    # Write the role
    playpath="$(writePlaybook "$role")"

    # trap remove
    trap "rm -f $playpath" EXIT SIGINT SIGTERM KILL

    # install with ansible playbook
    if [[ "$verbose" == 'true' ]]; then
        nix-shell -p ansible --command "time ansible-playbook -i ./inventory/docker.yaml -e 'playbook_target=$hosts' -vvv '$playpath' --tags '$tags'"
    elif [[ "$verbose" == 'false' ]]; then
        nix-shell -p ansible --command "time ansible-playbook -i ./inventory/docker.yaml -e 'playbook_target=$hosts' '$playpath' --tags '$tags'"
    fi
    ;;

'edit')
    # Get arguments
    args=("$@")

    # Need 1 argument
    if [[ "${#args[@]}" -ne 1 ]]; then
        echo "ERR: edit command need an encrypted inventory file, but you have ${#args[@]}."
        exit 0
    fi

    "$PROJECT_DIR/scripts/edit_inventory.sh" "${args[0]}"
    ;;

'role')
    # var
    verbose=false
    tags='untagged'
    role=''
    hosts=''

    # parse the argumetns
    while getopts ':vg:t:r:' opt; do
        case "$opt" in
        g)
            hosts="$OPTARG"
            ;;
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
        echo "ERR: No role specified, use -r <role> to run a role" >&2
        exit 1
    fi
    if [[ -z "$hosts" ]]; then
        echo 'ERR: no hosts specified. Add -g HOSTS to the command and try again' >&2
        exit 1
    fi

    install_ansible

    # Write the role
    playpath="$(writePlaybook "$role")"

    # trap remove
    trap "rm -f $playpath" EXIT SIGINT SIGTERM KILL

    # buil args
    aargs=()
    aargs+=(--vault-id "prod@$PROJECT_DIR/scripts/vault-client.sh")

    # install with ansible playbook
    if [[ "$verbose" == 'true' ]]; then
        aargs+=("-vvv")
    fi
    aargs+=(-e "playbook_target=$hosts")
    aargs+=(-i "./inventory/local.yaml")
    aargs+=("$playpath")
    aargs+=("--tags")
    aargs+=("$tags")

    time PY_COLORS=1 \
    ANSIBLE_FORCE_COLOR=1 \
    ansible-playbook "${aargs[@]}"
    ;;

'install-i')
    # var
    verbose=false
    tags='untagged'
    hosts='docker'

    # parse the argumetns
    while getopts ':vg:t:r:' opt; do
        case "$opt" in
        g)
            hosts="$OPTARG"
            ;;
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

    if [[ -z "$hosts" ]]; then
        echo 'ERR: no hosts specified. Add -g HOSTS to the command and try again' >&2
        exit 1
    fi

    install_ansible

    # install with ansible playbook
    if [[ "$verbose" == 'true' ]]; then
        nix-shell -p ansible --command "time ansible-playbook -i ./inventory/docker.yaml -e 'playbook_target=$hosts' -vvv '$WHOLE_PLAYBOOK_PATH' --tags '$tags'"
    elif [[ "$verbose" == 'false' ]]; then
        nix-shell -p ansible --command "time ansible-playbook -i ./inventory/docker.yaml -e 'playbook_target=$hosts' '$WHOLE_PLAYBOOK_PATH' --tags '$tags'"
    fi
    ;;

'install')
    # var
    verbose=false
    tags='untagged'
    hosts=''

    # parse the argumetns
    while getopts ':vg:t:r:' opt; do
        case "$opt" in
        g)
            hosts="$OPTARG"
            ;;
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

    if [[ -z "$hosts" ]]; then
        echo 'ERR: no hosts specified. Add -g HOSTS to the command and try again' >&2
        exit 1
    fi

    install_ansible

    # buil args
    aargs=()
    aargs+=(--vault-id "prod@$PROJECT_DIR/scripts/vault-client.sh")

    # install with ansible playbook
    if [[ "$verbose" == 'true' ]]; then
        aargs+=("-vvv")
    fi
    aargs+=(-i "./inventory/local.yaml")
    aargs+=(-e "playbook_target=$hosts")
    aargs+=("$WHOLE_PLAYBOOK_PATH")
    aargs+=("--tags")
    aargs+=("$tags")

    time PY_COLORS=1 \
    ANSIBLE_FORCE_COLOR=1 \
    ansible-playbook "${aargs[@]}"
    ;;

'tmux')
    if ! (tmux ls | grep -q blah); then
        tmux new-session -d -s blah -n dev-env-ansible -c "$SCRIPT_DIR"
        tmux new-window -d -t blah: -n dockers -c "$SCRIPT_DIR"
        [[ -d "$SCRIPT_DIR/../dotfiles" ]] && tmux new-window -d -t blah: -n dotfiles -c "$SCRIPT_DIR/../dotfiles"
        [[ -d "$SCRIPT_DIR/../kinesisadv360pro" ]] && tmux new-window -d -t blah: -n adv360pro -c "$SCRIPT_DIR/../kinesisadv360pro"
        # tmux new-window -d -t blah: -n focusside -c "$SCRIPT_DIR/../focus-side.vim"
    fi
    tmux attach-session -t blah
    ;;

'run')
    # var
    ver="$DOCKER_FILE_UBUNTU_22"

    # parse the argumetns
    while getopts ':d:w:' opt; do
        case "$opt" in
        d)
            ver="$(select_docker_ver "$OPTARG")"
            ;;
        w)
            append_docker_mount_global "$OPTARG:$OPTARG"
            ;;
        *)
            echo "Unrecognized option $opt" >&2
            displayHelp
            ;;
        esac
    done

    decrypt_inventory_for_docker
    set_docker_mounts_global

    # start bash inside container
    build_image "$CONTAINER_TAG" "$ver" && \
    docker run --cpu-shares=1024 --rm -it \
        --user "$USER:$USER" \
        --network="host" \
        "${DOCKER_VOLUME_MOUNT[@]}" \
        --name "$(compose_container_name "$RUN_PREFIX_FOR_NAME" "$1")" \
        "$CONTAINER_TAG" \
        bash -i -c "cd ./repos/dev-env-ansible ; bash -i"
    ;;

'run-build')
    # build up the command here
    cmd="cd ./repos/dev-env-ansible && ./rr.sh install-i"
    cmd="$cmd && . ~/.bashrc && . ~/.bashrc_append"
    # select docker
    ver="$DOCKER_FILE_UBUNTU_22"
    if [[ $# -gt 0 ]]; then
        ver="$(select_docker_ver $1)"
    fi

    decrypt_inventory_for_docker
    set_docker_mounts_global

    # start bash inside container
    build_image "$CONTAINER_TAG" "$ver" && \
    docker run --cpu-shares=1024 --rm -it \
        --user "$USER:$USER" \
        --network="host" \
        "${DOCKER_VOLUME_MOUNT[@]}" \
        --name "$(compose_container_name "$RUN_PREFIX_FOR_NAME" "$1")" \
        "$CONTAINER_TAG" \
        bash -i -c "$cmd ; command -v zsh && exec zsh || exec bash"
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

'start')
    # var
    imgName='ubuntu:lts'
    cmd=lxc

    # parse the argumetns
    while getopts ':i:w:' opt; do
        case "$opt" in
        i)
            imgName="$OPTARG"
            ;;
        w)
            append_lxc_mount_global "$OPTARG"
            ;;
        *)
            echo "Unrecognized option $opt" >&2
            displayHelp
            ;;
        esac
    done

    decrypt_inventory_for_docker

    if [[ "$(lxc list -f json | jq --raw-output ".[] | select(.name | test(\"^$LXC_NAME\$\")) | .name" | wc -l)" -ne 1 ]]; then

        # Start an instance
        "$cmd" launch --ephemeral "$imgName" "$LXC_NAME"

        # Remove default ubuntu user and add my user
        "$cmd" exec "$LXC_NAME" -- bash -c "deluser \"\$(id -un $(id -u))\""
        "$cmd" exec "$LXC_NAME" -- adduser --uid "$(id -u)" "$USER"
        "$cmd" exec "$LXC_NAME" -- bash -c "echo '$USER ALL=(ALL:ALL) NOPASSWD: ALL' >> /etc/sudoers"

        # map the user id in the container
        "$cmd" config set "$LXC_NAME" raw.idmap "both $(id -u) $(id -u)"
        "$cmd" restart "$LXC_NAME"

        # Mount folders
        apply_lxc_mounts_global "$cmd"

        # Fix the locale on debian
        "$cmd" exec "$LXC_NAME" -- bash -c 'export DEBIAN_FRONTEND=noninteractive && dpkg-reconfigure -f noninteractive locales \
            && locale-gen en_US.UTF-8 \
            && update-locale LC ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
            && locale-gen en_US.UTF-8'

        # Install the desktop environment
        "$cmd" exec "$LXC_NAME" -- bash -c 'apt update \
            && apt install -y --no-install-recommends xorg ubuntu-desktop-minimal \
            && systemctl enable gdm.service \
            && systemctl start gdm.service'

    fi

        # # Install the desktop environment
        # "$cmd" exec "$LXC_NAME" -- cat /etc/os-release

        # # Install vnc
        # "$cmd" exec "$LXC_NAME" -- bash -c "cd /tmp \
        #     && wget https://github.com/kasmtech/KasmVNC/releases/download/v1.3.1/kasmvncserver_jammy_1.3.1_amd64.deb \
        #     && apt install -y --no-install-recommends ./kasmvncserver_jammy_1.3.1_amd64.deb \
        #     && usermod -aG ssl-cert '$USER'"
        # "$cmd" restart "$LXC_NAME"

        # "$cmd" exec "$LXC_NAME" -- su - "$USER" bash -c "echo $("$cmd" list -f json | jq --raw-output ".[] | select(.name | test(\"^$LXC_NAME\$\")) | .state.network.eth0.addresses[] | select (.family | test(\"^inet\$\")) | .address")"
        # "$cmd" exec "$LXC_NAME" -- su - "$USER" bash -c 'kasmvncserver'
        # "$cmd" exec "$LXC_NAME" -- su - "$USER" bash -c 'kasmvncserver -list'

    # # Install vnc
    # "$cmd" exec "$LXC_NAME" -- bash -c 'wget -q -O- https://packagecloud.io/dcommander/turbovnc/gpgkey | \
    #     gpg --dearmor >/etc/apt/trusted.gpg.d/TurboVNC.gpg \
    #     && wget -q -O/etc/apt/sources.list.d/turbovnc.list https://raw.githubusercontent.com/TurboVNC/repo/main/TurboVNC.list \
    #     && apt update \
    #     && apt install -y --no-install-recommends turbovnc'

    # # Install vnc
    # "$cmd" exec "$LXC_NAME" -- bash -c 'apt install -y --no-install-recommends x11vnc'

    # # Configure and start x11vnc
    # "$cmd" exec "$LXC_NAME" -- su - "$USER" bash -c 'unset SSH_TTY ; nohup x11vnc -display ":0" -auth /var/lib/gdm3/greeter-dconf-defaults -forever -loop -noxdamage -repeat -rfbauth "$HOME/.vnc/passwd" -autoport 5900 -shared | tee "/tmp/x11vnc.$disp.$$"'
    #
    # # List the active vnc ports
    # "$cmd" exec "$LXC_NAME" -- su - "$USER" bash -c 'x11vnc -finddpy'

    # # Configure and start vnc
    # "$cmd" exec "$LXC_NAME" -- su - "$USER" bash -c 'unset SSH_TTY ; /opt/TurboVNC/bin/vncserver -depth 24 -geometry "1920x1080"'
    #
    # # List the active vnc ports
    # "$cmd" exec "$LXC_NAME" -- su - "$USER" bash -c '/opt/TurboVNC/bin/vncserver -list'

    # # print ip
    # printf "Connect to VNC using '_vncconnect %s :1'\n" "$("$cmd" list -f json | jq --raw-output ".[] | select(.name | test(\"^$LXC_NAME\$\")) | .state.network.eth0.addresses[] | select (.family | test(\"^inet\$\")) | .address")"

    # # start a bash shell as root
    # "$cmd" exec "$LXC_NAME" -- bash -l

    # # start a bash shell
    # "$cmd" exec "$LXC_NAME" --cwd "/home/$USER" -- su - "$USER"

    # # stop the shell
    # "$cmd" stop "$LXC_NAME"

    ;;

'use')
    # var
    tag=''

    # parse the argumetns
    while getopts ':d:w:' opt; do
        case "$opt" in
        d)
            tag="$OPTARG"
            ;;
        w)
            append_docker_mount_global "$OPTARG:$OPTARG"
            ;;
        *)
            echo "Unrecognized option $opt" >&2
            displayHelp
            ;;
        esac
    done

    # need a tag
    if test -z "$tag"; then
        echo "ERR ($0 use): Need to pass in a tag using -d" >&2
        exit 1
    fi

    decrypt_inventory_for_docker
    set_docker_mounts_global

    # start bash inside container
    docker run --cpu-shares=1024 --rm -it \
        --user "$USER:$USER" \
        --network="host" \
        "${DOCKER_VOLUME_MOUNT[@]}" \
        --name "$(compose_container_name "$USE_PREFIX_FOR_NAME" "$tag")" \
        "$DEV_ENV_REPOSITORY_NAME:$tag" \
        bash -i -c "cd ./repos/dev-env-ansible; command -v zsh &>/dev/null && exec zsh || exec bash"
    ;;

'use-build')
    # get arg
    tag=$1
    # build up the command here
    cmd="cd ./repos/dev-env-ansible && ./rr.sh install-i -t 'tagged'"
    cmd="$cmd && . ~/.bashrc && . ~/.bashrc_append"

    decrypt_inventory_for_docker
    set_docker_mounts_global

    # start bash inside container
    docker run --cpu-shares=1024 --rm -it \
        --user "$USER:$USER" \
        --network="host" \
        "${DOCKER_VOLUME_MOUNT[@]}" \
        --name "$(compose_container_name "$USE_PREFIX_FOR_NAME" "$tag")" \
        "$DEV_ENV_REPOSITORY_NAME:$tag" \
        bash -i -c "$cmd; command -v zsh &>/dev/null && exec zsh || exec bash"
    ;;

'run-role')
    # get args
    ver="$1"
    role="$2"

    log="./role-$role-on-$ver.log"

    # build up the command here
    cmd='cd ./repos/dev-env-ansible && export ANSIBLE_CONFIG="$(pwd)/ansible.cfg" && ./rr.sh role-i -v -t "tagged,fast" -r'
    cmd="$cmd '$role'"

    # select docker
    ver="$DOCKER_FILE_UBUNTU_22"
    if [[ $# -gt 0 ]]; then
        ver="$(select_docker_ver $1)"
    fi

    decrypt_inventory_for_docker

    # trap remove
    trap "rm -f $log" EXIT SIGINT SIGTERM KILL

    # start bash inside container
    build_image "$CONTAINER_TAG" "$ver" && \
    docker run --cpu-shares=1024 --rm \
        --user "$USER:$USER" \
        --network="host" \
        -v $SCRIPT_DIR:$ANSIBLE_DEV_ENV_ANSIBLE_PATH \
        "$CONTAINER_TAG" \
        bash -c "$cmd" | tee "$log"
    # perform check
    roleCheck "$log"
    ;;

'use-role')
    # get args
    ver="$1"
    role="$2"

    # build up the command here
    cmd='cd ./repos/dev-env-ansible && export ANSIBLE_CONFIG="$(pwd)/ansible.cfg" && ./rr.sh role-i -r'
    cmd="$cmd '$role'"

    decrypt_inventory_for_docker

    # select docker
    ver="$DOCKER_FILE_UBUNTU_22"
    if [[ $# -gt 0 ]]; then
        ver="$(select_docker_ver $1)"
    fi

    # start bash inside container
    build_image "$CONTAINER_TAG" "$ver" && \
    docker run --cpu-shares=1024 --rm \
        --user "$USER:$USER" \
        --network="host" \
        -v $SCRIPT_DIR:$ANSIBLE_DEV_ENV_ANSIBLE_PATH \
        "$CONTAINER_TAG" \
        bash -i -c "$cmd; command -v zsh &>/dev/null && exec zsh || exec bash"
    ;;

'run-test')
    # build up the command here
    cmd='cd ./repos/dev-env-ansible && export ANSIBLE_CONFIG="$(pwd)/ansible.cfg" && ./rr.sh install-i -v -t "tagged,fast"'
    cmd="$cmd && . ~/.bashrc && . ~/.bashrc_append && ./rr.sh install-i -v -t 'tagged,fast' && ./rr.sh check"
    cmd="$cmd && ./rr.sh preupgrade && ./rr.sh install-i -v -t 'tagged,fast' && ./rr.sh check"

    log="./test-$1.log"

    # select docker
    ver="$DOCKER_FILE_UBUNTU_22"
    if [[ $# -gt 0 ]]; then
        ver="$(select_docker_ver $1)"
    fi

    decrypt_inventory_for_docker

    # trap remove
    trap "rm -f $log" EXIT SIGINT SIGTERM KILL

    [[ -r "$log" ]] && echo "File $log still here" || echo "Oh no, file $log is missing"

    # start bash inside container
    build_image "$CONTAINER_TAG" "$ver" && \
    docker run --cpu-shares=1024 --rm \
        --user "$USER:$USER" \
        --network="host" \
        -v $SCRIPT_DIR:$ANSIBLE_DEV_ENV_ANSIBLE_PATH \
        "$CONTAINER_TAG" \
        bash -c "$cmd" | tee "$log"

    [[ -r "$log" ]] && echo "File $log still here" || echo "Oh no, file $log is missing"
    # perform check
    ansibleCheck "$log"
    ;;

*)
    # error out
    echo "subcommand $subcmd invalid" >&2
    # print help
    displayHelp
    exit 1
    ;;
esac
