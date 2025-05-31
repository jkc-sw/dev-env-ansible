#!/usr/bin/env bash

: <<AEOF
SOURCE_THESE_VIMS_START
nnoremap <leader>ueo <cmd>silent exec "!tmux send-keys -t :.+ 'ANSIBLE_DEBUG=false ANSIBLE_VERBOSITY=1 ./rr.sh edit ./inventory/localhost.yaml' Enter"<cr>
nnoremap <leader>us <cmd>silent exec "!tmux send-keys -t :.+ 'ANSIBLE_DEBUG=false ANSIBLE_VERBOSITY=1 ./rr.sh role -r scratch -g asus' Enter"<cr>
nnoremap <leader>udh <cmd>silent exec "!tmux send-keys -t :+ 'ANSIBLE_DEBUG=false ANSIBLE_VERBOSITY=1 ./rr.sh role-i -r home-manager' Enter"<cr>
nnoremap <leader>udi <cmd>silent exec "!tmux send-keys -t :+ 'ANSIBLE_DEBUG=false ANSIBLE_VERBOSITY=1 ./rr.sh install-i' Enter"<cr>

let @h="yoecho \"\<c-r>\" = \$\<c-r>\"\"\<esc>j"
echom 'Sourced'
SOURCE_THESE_VIMS_END
AEOF


# get location of this folder
SCRIPT_DIR="$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )"
PROJECT_DIR="$SCRIPT_DIR"

# make sure we are in the correct folder
pushd "$SCRIPT_DIR" &>/dev/null

# ansible workspace path
ANSIBLE_DEV_ENV_ANSIBLE_PATH="$SCRIPT_DIR"

# container volumn mount
lxc_volume_mount=()

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
    # if ! ls "$SCRIPT_DIR/playbooks/roles" | grep -q "$role"; then
    if [[ ! -d "$SCRIPT_DIR/playbooks/roles/$role" ]]; then
        echo "role '$role' cannot be found in the ./playbooks/roles folder" >&2
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
    ret="$?"
    if [[ "$ret" -ne 0 ]]; then
        exit "$ret"
    fi

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
    if ! command -v "$cmd" &>/dev/null; then
        echo "$cmd not installed properly"
        return 1
    fi
}

displayHelpLxc() {
    # print help here
    echo "${BASH_SOURCE[0]} lxc [...]"
    echo " Commands to handle the lxc containers setup"
    echo ""
    echo "--------------------------------------------------------------------------------"
    echo "Display Help"
    echo " -h|--help|h|hel|help  : Print this help command"
    echo ""
    echo "--------------------------------------------------------------------------------"
    echo "Manage a bespoked lxc container for testing this repository"
    echo " start: [-r] [-w DIR]... [-v] [-d] [-m]"
    echo "   Start a LXC container"
    echo ""
    echo " stop: [-v]"
    echo "   Stop a LXC container"
    echo ""
    echo " mount: [-w DIR]... [-v]"
    echo "   Mount this additional paths plus all the default paths"
    echo ""
    echo " shell: [-v]"
    echo "   Spawn a bash shell to the LXC container"
    echo ""
    echo " where"
    echo "  -v     > Enable verbose trace in the script"
    echo "  -d     > Enable desktop environment install via VNC"
    echo "  -r     > Stop and remove the running container"
    echo "  -m     > Create a VM instead of a container"
    echo "  -w dir > Bind mount this folder to the container"
}

displayHelpMain() {
    # print help here
    echo "${BASH_SOURCE[0]} [...]"
    echo " One-stop shop to do everything related to this repository"
    echo ""
    echo "--------------------------------------------------------------------------------"
    echo "Pre-requisite"
    echo " Please run './shell.sh' to start a nix shell before running any command below"
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
    echo " tags"
    echo "   List all the tags"  # desc
    echo ""
    echo " roles"
    echo "   List all the roles"  # desc
    echo ""
    echo " role [-v] [-t 'tag1[,tag2 ...]'] -r <role>"
    echo "   Run a role on the host system (mostly container) prompting for password"  # desc
    echo ""
    echo "  where"
    echo "   -r > The role to run"
    echo "   -v > Provide the -vvv option to the ansigle command to have debug output"
    echo "   -t > Tags to use, comma separated, no space"
    echo ""
    echo "--------------------------------------------------------------------------------"
    echo "Manage and handle the ansible vault for inventory file"
    echo " edit FILE: Edit the inventory file"
    echo ""
    echo "  where:"
    echo "   FILE : Inventory file"
    echo ""
    echo "--------------------------------------------------------------------------------"
    echo "Create a new row template"
    echo " new-role NAME : Create a new role with some default"
    echo ""
    echo "  where:"
    echo "   NAME : The name of the role appears in the folder"
    echo ""
    echo "--------------------------------------------------------------------------------"
    echo "Manage a bespoked lxc container for testing this repository"
    echo " lxc [...]: Use '${BASH_SOURCE[0]} lxc -h' subcommand to learn more"
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
    if [[ "${lxc_volume_mount[*]}" == *"$path"* ]]; then
        return 0
    fi
    lxc_volume_mount+=(-w "$path")
    # echo "DEBUG (append_lxc_mount_global): Added '$path'" >&2
}

# function to populate the mount in a function
set_mounts_global() {
    # volumn mount
    for each in \
        "$HOME/repos/dotfiles:$HOME/repos/dotfiles" \
        "$SCRIPT_DIR:$ANSIBLE_DEV_ENV_ANSIBLE_PATH" \
        "$HOME/repos/focus-side.vim:$HOME/repos/focus-side.vim" \
        "$HOME/repos/jerry-nixos:$HOME/repos/jerry-nixos" \
        "$HOME/.ssh/id_ed25519:$HOME/.ssh/id_ed25519" \
    ; do
        append_lxc_mount_global "$each"
    done
}

# Set the mounts to a list
set_mounts_global

# A submain just for the lxc command
sub_main_lxc() {
    # if args, print help
    if test "$#" -eq 0; then
        displayHelpLxc
        exit 0
    fi
    # if there are arg for test, run test
    subcmd="$1"
    shift
    # Get a list of args here before they get consumed
    local args=("$@")
    # Iterate each subcommand
    case "$subcmd" in
    '-h'|'--help'|'h'|'hel'|'help')
        displayHelpLxc
        exit 1
        ;;

    'stop')
        startarg=(-r)
        # parse the argumetns
        while getopts 'v' opt; do
            case "$opt" in
            v)
                startarg+=(-v)
                ;;
            *)
                echo "Unrecognized option $opt" >&2
                displayHelpLxc
                exit 1
                ;;
            esac
        done

        "$PROJECT_DIR/scripts/start_lxc_container.sh" "${startarg[@]}"
        ;;

    'shell')
        startarg=(-s)
        # parse the argumetns
        while getopts 'v' opt; do
            case "$opt" in
            v)
                startarg+=(-v)
                ;;
            *)
                echo "Unrecognized option $opt" >&2
                displayHelpLxc
                exit 1
                ;;
            esac
        done

        "$PROJECT_DIR/scripts/start_lxc_container.sh" "${startarg[@]}"
        ;;

    'mount')
        startarg=()
        # parse the argumetns
        while getopts ':vw:' opt; do
            case "$opt" in
            v)
                startarg+=(-v)
                ;;
            w)
                each="$OPTARG"
                each="$(realpath "$each")"
                append_lxc_mount_global "$each:$each"
                ;;
            *)
                echo "Unrecognized option $opt" >&2
                displayHelpLxc
                exit 1
                ;;
            esac
        done

        startarg+=("${lxc_volume_mount[@]}")
        "$PROJECT_DIR/scripts/start_lxc_container.sh" "${startarg[@]}"
        ;;

    'start')
        startarg=()
        # parse the argumetns
        while getopts ':rdvmw:' opt; do
            case "$opt" in
            d)
                startarg+=(-d)
                ;;
            v)
                startarg+=(-v)
                ;;
            m)
                startarg+=(-m)
                ;;
            w)
                each="$OPTARG"
                each="$(realpath "$each")"
                append_lxc_mount_global "$each:$each"
                ;;
            r)
                startarg+=(-r)
                ;;
            *)
                echo "Unrecognized option $opt" >&2
                displayHelpLxc
                exit 1
                ;;
            esac
        done

        startarg+=("${lxc_volume_mount[@]}")
        "$PROJECT_DIR/scripts/start_lxc_container.sh" "${startarg[@]}"
        ;;
    esac
}

# Main for the entire program
main() {
    # if args, print help
    if test "$#" -eq 0; then
        displayHelpMain
        exit 0
    fi
    # if there are arg for test, run test
    subcmd="$1"
    shift
    # Get a list of args here before they get consumed
    local args=("$@")

    # Handle to subcommands hele
    case "$subcmd" in
    'lxc')
        # delegate to the lxc submain
        sub_main_lxc "${args[@]}"
        exit "$?"
        ;;
    esac

    # Main command required nix shell
    if [[ -z "$IN_NIX_RR_SHELL" ]]; then
        echo "ERR: Please run ./shell.sh to start a nix shell, then run ./rr.sh ..." >&2
        exit 1
    fi

    # Iterate each subcommand
    case "$subcmd" in
    '-h'|'--help'|'h'|'hel'|'help')
        displayHelpMain
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

    'roles')
        # List all the roles
        while read -d $'\0' -r each; do
            eachrole="${each##*/roles}"
            if [[ -z "${eachrole:1}" ]]; then
                continue
            fi
            echo "role: ${eachrole:1}"
        done < <(find "$SCRIPT_DIR/playbooks/roles" -maxdepth 1 -type d -print0)
        ;;

    'tags')
        # List all the tags
        echo "Listing all the tags"
        ansible-playbook -i ./inventory/localhost.yaml -e "ansible_python_interpreter=$EXPLICIT_PYTHON_PATH_FOR_ANSIBLE" -e 'playbook_target=localhost' "$WHOLE_PLAYBOOK_PATH" --list-tags
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
                displayHelpMain
                exit 1
                ;;
            esac
        done

        # need a role
        if test -z "$role"; then
            echo "ERR: No role specified, use -r <role> to run a role" >&2
            exit 1
        fi

        # Write the role
        playpath="$(writePlaybook "$role")"
        ret="$?"
        if [[ "$ret" -ne 0 ]]; then
            exit "$ret"
        fi

        # trap remove
        trap "rm -f '$playpath'" EXIT SIGINT SIGTERM

        # install with ansible playbook
        if [[ "$verbose" == 'true' ]]; then
            time ansible-playbook -i ./inventory/localhost.yaml -e 'playbook_target=localhost' -e "ansible_python_interpreter=$EXPLICIT_PYTHON_PATH_FOR_ANSIBLE" -vvv "$playpath" --tags "$tags"
        elif [[ "$verbose" == 'false' ]]; then
            time ansible-playbook -i ./inventory/localhost.yaml -e 'playbook_target=localhost' -e "ansible_python_interpreter=$EXPLICIT_PYTHON_PATH_FOR_ANSIBLE" "$playpath" --tags "$tags"
        fi
        ;;

    # 'edit')
    #     # Get arguments
    #     args=("$@")
    #
    #     # Need 1 argument
    #     if [[ "${#args[@]}" -ne 1 ]]; then
    #         echo "ERR: edit command need an encrypted inventory file, but you have ${#args[@]}."
    #         exit 0
    #     fi
    #
    #     "$PROJECT_DIR/scripts/edit_inventory.sh" "${args[0]}"
    #     ;;

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
                displayHelpMain
                exit 1
                ;;
            esac
        done

        # need a role
        if test -z "$role"; then
            echo "ERR: No role specified, use -r <role> to run a role" >&2
            exit 1
        fi

        # Write the role
        playpath="$(writePlaybook "$role")"
        ret="$?"
        if [[ "$ret" -ne 0 ]]; then
            exit "$ret"
        fi

        # trap remove
        trap "rm -f '$playpath'" EXIT SIGINT SIGTERM

        # buil args
        aargs=()

        # install with ansible playbook
        if [[ "$verbose" == 'true' ]]; then
            aargs+=("-vvv")
        fi
        aargs+=(-K)
        aargs+=(-e "playbook_target=localhost")
        aargs+=(-e "ansible_python_interpreter=$EXPLICIT_PYTHON_PATH_FOR_ANSIBLE")
        aargs+=(-i "./inventory/localhost.yaml")
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
                displayHelpMain
                exit 1
                ;;
            esac
        done

        # buil args
        aargs=()

        # install with ansible playbook
        if [[ "$verbose" == 'true' ]]; then
            aargs+=("-vvv")
        fi
        aargs+=(-e "playbook_target=localhost")
        aargs+=(-e "ansible_python_interpreter=$EXPLICIT_PYTHON_PATH_FOR_ANSIBLE")
        aargs+=(-i "./inventory/localhost.yaml")
        aargs+=("$WHOLE_PLAYBOOK_PATH")
        aargs+=("--tags")
        aargs+=("$tags")

        time ansible-playbook "${aargs[@]}"
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
                displayHelpMain
                exit 1
                ;;
            esac
        done

        # buil args
        aargs=()

        # install with ansible playbook
        if [[ "$verbose" == 'true' ]]; then
            aargs+=("-vvv")
        fi
        aargs+=(-K)
        aargs+=(-i "./inventory/localhost.yaml")
        aargs+=(-e "playbook_target=localhost")
        aargs+=(-e "ansible_python_interpreter=$EXPLICIT_PYTHON_PATH_FOR_ANSIBLE")
        aargs+=("$WHOLE_PLAYBOOK_PATH")
        aargs+=("--tags")
        aargs+=("$tags")

        time PY_COLORS=1 \
        ANSIBLE_FORCE_COLOR=1 \
        ansible-playbook "${aargs[@]}"
        ;;

    *)
        # error out
        echo "subcommand $subcmd invalid" >&2
        # print help
        displayHelpMain
        exit 1
        ;;
    esac
}

main "$@"
