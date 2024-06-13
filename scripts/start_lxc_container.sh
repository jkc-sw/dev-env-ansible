#!/usr/bin/env bash

: <<'20240423EOF'
SOURCE_THESE_VIMS_START
nnoremap <leader>ne <cmd> silent call execute(escape("!tmux send-keys -t :+1 './rr.sh start -v' Enter", '#'))<cr>
nnoremap <leader>na <cmd> silent call execute(escape("!tmux send-keys -t :+1 './rr.sh shell -v' Enter", '#'))<cr>
nnoremap <leader>nE <cmd> silent call execute(escape("!tmux send-keys -t :+1 './rr.sh stop -v' Enter", '#'))<cr>
nnoremap <leader>no <cmd> silent call execute(escape("!tmux send-keys -t :+1 './rr.sh stop -v' Enter", '#'))<cr>
let @h="\"lyoecho \"DEBUG: \<c-r>l = \$\<c-r>l\"\<esc>j"
echom 'Sourced'
SOURCE_THESE_VIMS_END
20240423EOF


args=("$@")

displayHelp() {
    # print help here
    echo "${BASH_SOURCE[0]} [flags] Create lxc container for testing"
    echo ""
    echo "Flags:"
    echo " -c                        : Creat a new container instance"
    echo " -r                        : Remove this container instance"
    echo " -s                        : Drop me into a bash shell"
    echo ""
    echo " -b BRIDGE                 : Name of the default bridge. Default is lxdbr0"
    echo " -f VNC_PORT_ON_HOST       : The VNC port to map onto the host address. Default is 15901"
    echo " -i IMAGE_NAME             : Ubuntu image to use. Default is 22.04"
    echo " -n CONTAINER_NAME         : Name of the lxc container. Default is 'tom'"
    echo " -p VNC_PORT               : The VNC port inside the container. Default is 5901"
    echo " -w HOST_DIR:CONATINER_DIR : Map this folder to the container. Can call multiple times"
    echo " -x CMD                    : Command to use. Default is lxc"
    echo ""
    echo " -h                        : Print this help command"
    echo " -v                        : Verbose trace information"
}

# const
SCRIPT_DIR="$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )"

# function to locate the hostAddr
get_host_addr() {
    # Get arguments
    local args=("$@")
    # Need 1 argument
    if [[ "${#args[@]}" -ne 2 ]]; then
        echo "ERR (get_host_addr): need 2 arguments (cmd, bridge) only, but found ${#args[@]}" >&2
        return 1
    fi
    local cmd="${args[0]}"
    local brid="${args[1]}"
    local forward="$("$cmd" network forward list "$brid" -f json)"
    local listenAddress="$(echo -n "$forward" | jq --raw-output '.[].listen_address')"
    local currentIpOutput="$(ip -j a|jq '.[].addr_info[]|select(.family | test("^inet$")).local' --raw-output)"
    # Find an existing one and return it
    while read -r each; do
        if [[ "$currentIpOutput" == *"$each"* ]]; then
            echo -n "$each"
            return 0
        fi
    done <<<"$listenAddress"
    # otherwise, use fzf to search it
    local selectedHostIp="$(echo -n "$currentIpOutput" | fzf)"
    if [[ "$?" -ne 0 || -z "$selectedHostIp" ]]; then
        echo "ERR (get_host_addr): Cannot get the host address using fzf" >&2
        return 1
    fi
    echo -n "$selectedHostIp"
    return 0
}

# function to calculating the checksum of the argument
get_all_mounted_paths_from_containers() {
    # Get arguments
    local args=("$@")
    # Need 1 argument
    if [[ "${#args[@]}" -ne 2 ]]; then
        echo "ERR (get_all_mounted_paths_from_containers): need 2 arguments (bin, container name) only, but found ${#args[@]}" >&2
        return 1
    fi
    local cmd="${args[0]}"
    local lxc_name="${args[1]}"
    local paths="$("$cmd" list -f json | jq --raw-output ".[] | select(.name | test(\"^$lxc_name\$\")) | .devices[] | \"\(.path):\(.source)\"")"
    echo -n "$paths"
}

# function to get all the mounted disks
add_lxc_mount_global() {
    # Get arguments
    local args=("$@")
    # Need 1 argument
    if [[ "${#args[@]}" -ne 4 ]]; then
        echo "ERR (add_lxc_mount_global): need 4 arguments (bin, container name, disk name, path) only, but found ${#args[@]}" >&2
        return 1
    fi
    local cmd="${args[0]}"
    local lxc_name="${args[1]}"
    local name="${args[2]}"
    local path="${args[3]}"
    local src="${path%:*}"
    if [[ ! -e "$src" ]]; then
        echo "ERR (add_lxc_mount_global): src path '$src' is not found." >&2
        return 1
    fi
    local dest="${path#*:}"
    local out="$(sha1sum <<<"$path")"
    local pathHash="${out%% *}"
    # Add this disk because it is not found
    "$cmd" config device add "$lxc_name" "$pathHash" disk source="$src" path="$dest"
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
    if [[ "${lxc_volume_mount[*]}" == *"$path"* ]]; then
        return 0
    fi
    lxc_volume_mount+=("$path")
    echo "DEBUG (append_lxc_mount_global): Added '$path'" >&2
}

chown_lxc_mount_global() {
    # Get arguments
    local args=("$@")
    # Need 1 argument
    if [[ "${#args[@]}" -ne 3 ]]; then
        echo "ERR (chown_lxc_mount_global): need 3 argument (bin, container name, path), but found ${#args[@]}" >&2
        return 1
    fi
    local cmd="${args[0]}"
    local lxc_name="${args[1]}"
    local path="${args[2]}"
    local dest="${path#*:}"
    "$cmd" exec "$lxc_name" -- chown -R "$USER:$USER" "$dest"
}

# function to setup generic stuff in the container
apply_generic_configurations() {
    # Get arguments
    local args=("$@")
    # Need 1 argument
    if [[ "${#args[@]}" -ne 2 ]]; then
        echo "ERR (apply_lxc_mounts_global): need 2 arguments (bin, container name) only, but found ${#args[@]}" >&2
        return 1
    fi
    local cmd="${args[0]}"
    local lxc_name="${args[1]}"
    local uid="$(id -u)"
    local gid="$(id -g)"
    # Remove default ubuntu user and add my user
    "$cmd" exec "$lxc_name" -t -- bash -c "id -un $uid 2>/dev/null && userdel -f \"\$(id -un $uid)\""
    "$cmd" exec "$lxc_name" -t -- bash -c "export uid=$uid gid=$gid \
        && mkdir -p /home/${USER} \
        && echo \"${USER}:x:\${uid}:\${gid}:${USER},,,:${HOME}:/bin/bash\" >> /etc/passwd \
        && echo \"${USER}:x:\${uid}:\" >> /etc/group \
        && echo \"${USER} ALL=(ALL:ALL) NOPASSWD: ALL\" > /etc/sudoers.d/${USER} \
        && chmod 0440 /etc/sudoers.d/${USER} \
        && chown \${uid}:\${gid} -R ${HOME} \
        && echo ${USER}:aoeu | chpasswd"
    # map the user id in the container
    "$cmd" config set "$lxc_name" raw.idmap "both $uid $uid"
    "$cmd" restart "$lxc_name"
}

# function to populate the docker mount in a function
apply_lxc_mounts_global() {
    # Get arguments
    local args=("$@")
    # Need 1 argument
    if [[ "${#args[@]}" -ne 2 ]]; then
        echo "ERR (apply_lxc_mounts_global): need 2 arguments (bin, container name) only, but found ${#args[@]}" >&2
        return 1
    fi
    local cmd="${args[0]}"
    local lxc_name="${args[1]}"
    # Apply the monts to the lxc
    for ii in $(seq 0 $(( "${#lxc_volume_mount[@]}" - 1)) ); do
        local each="${lxc_volume_mount[ii]}"
        local mountedPaths="$(get_all_mounted_paths_from_containers "$cmd" "$lxc_name")"
        # Skip this path if already monuted
        if [[ "$mountedPaths" == *"$each"* ]]; then
            echo "INFO (add_lxc_mount_global): Skip '$each' because it is mounted"
            continue
        fi
        add_lxc_mount_global "$cmd" "$lxc_name" "d$ii" "$each"
        chown_lxc_mount_global "$cmd" "$lxc_name" "$each"
    done
}

# Check dependencies
check_dependencies() {
    # Check dependencies
    toexit=false
    for c in lxc jq ip fzf; do
        if ! command -v "$c" &>/dev/null; then
            echo "ERR: $c is not found in your PATH" >&2
            toexit=true
        fi
    done
    if [[ "$toexit" == true ]]; then
        echo "ERR: Please make sure you install all the necessary tool first" >&2
        exit 1
    fi
}

main() {
    # var
    local imgName='ubuntu:22.04'
    # local imgName='images:archlinux/current/default'
    local cmd='lxc'
    local brid='lxdbr0'
    local lxc_name='tom'
    # local lxc_name='btw'
    local lxc_volume_mount=()
    local vnc_port_on_host=15901
    local vnc_port=5901
    local remove=false
    local shell=false

    # parse the argumetns
    while getopts 'vf:i:b:x:p:n:w:sr' opt; do
        case "$opt" in
        v)
            set -x  # enable verbose trace
            ;;
        s)
            shell=true
            ;;
        r)
            remove=true
            ;;
        p)
            vnc_port="$OPTARG"
            ;;
        f)
            vnc_port_on_host="$OPTARG"
            ;;
        x)
            cmd="$OPTARG"
            ;;
        n)
            lxc_name="$OPTARG"
            ;;
        b)
            brid="$OPTARG"
            ;;
        i)
            imgName="ubuntu:$OPTARG"
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

    # var
    local containers="$("$cmd" list -f json | jq --raw-output ".[] | select(.name | test(\"^$lxc_name\$\")) | .name")"

    # When asking to delete
    if [[ "$remove" == 'true' ]]; then
        # Stop/remove the container if found
        if [[ -n "$containers" ]]; then
            echo "INFO: Stop and remove containers $lxc_name"
            "$cmd" stop "$lxc_name"
            if [[ "$?" -ne 0 ]]; then
                echo "ERR: Cannot stop the container $lxc_name" >&2
                return 1
            fi
        fi
        "$cmd" list -c ns4t,image.description:image

        # Remove the network forward port if any was set on this interface
        local forward="$("$cmd" network forward list "$brid" -f json)"
        echo "DEBUG: forward = $forward"
        local listenAddress="$(echo -n "$forward" | jq --raw-output '.[].listen_address')"
        echo "DEBUG: listenAddress = $listenAddress"
        local listenPort="$(echo -n "$forward" | jq --raw-output '.[].ports[].listen_port')"
        echo "DEBUG: listenPort = $listenPort"
        if [[ -n "$listenAddress" && "$listenPort" == "$vnc_port_on_host" ]]; then
            echo "INFO: Find the host address from the output"
            echo "INFO: Removing network forward port"
            local hostAddr="$(get_host_addr "$cmd" "$brid")"
            "$cmd" network forward port remove "$brid" "$hostAddr" tcp "$vnc_port_on_host"
            if [[ "$?" -ne 0 ]]; then
                echo "ERR: Cannot remove network forward port" >&2
                return 1
            fi
        fi
        "$cmd" network forward list "$brid"
        return 0
    fi

    # Create a new container if none found
    if [[ -z "$containers" ]]; then
        # Start an instance
        "$cmd" launch --ephemeral "$imgName" "$lxc_name"
        if [[ "$?" -ne 0 ]]; then
            echo "Err: Failed to create a container" >&2
            exit 1
        fi

        # Configure generic stuff
        apply_generic_configurations "$cmd" "$lxc_name"

        if [[ "$imgName" == *'ubuntu'* ]]; then
            # Fix the locale on debian
            "$cmd" exec "$lxc_name" -t -- bash -c 'export DEBIAN_FRONTEND=noninteractive && dpkg-reconfigure -f noninteractive locales \
                && locale-gen en_US.UTF-8 \
                && update-locale LC ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
                && locale-gen en_US.UTF-8'

            # Install vnc
            "$cmd" exec "$lxc_name" -t -- bash -c 'wget -q -O- https://packagecloud.io/dcommander/turbovnc/gpgkey | \
                gpg --dearmor >/etc/apt/trusted.gpg.d/TurboVNC.gpg \
                && wget -q -O/etc/apt/sources.list.d/turbovnc.list https://raw.githubusercontent.com/TurboVNC/repo/main/TurboVNC.list \
                && apt update \
                && apt install -y --no-install-recommends xorg xfce4 xfce4-goodies turbovnc'

            # Configure the vnc
            "$cmd" exec "$lxc_name" -t -- su - "$USER" bash -c "mkdir -p '/home/$USER/.vnc' \
                && echo -n aoeuaoeu | /opt/TurboVNC/bin/vncpasswd -f > '/home/$USER/.vnc/passwd' \
                && chown -R '$USER:$USER' '/home/$USER/.vnc' \
                && chmod 0600 '/home/$USER/.vnc/passwd' \
                && /opt/TurboVNC/bin/vncserver -depth 24 -geometry '1920x1080'"

        elif [[ "$imgName" == *'archlinux'* ]]; then
            # TODO: Fix this
            #   err msg: error: failed retrieving file 'alsa-ucm-conf-1.2.11-1-any.pkg.tar.zst' from mirrors.kernel.org : The requested URL returned error: 404
            # Install vnc
            "$cmd" exec "$lxc_name" -t -- bash -c 'pacman --noconfirm -S xfce4'
        fi

        # Update the container status
        containers="$("$cmd" list -f json | jq --raw-output ".[] | select(.name | test(\"^$lxc_name\$\")) | .name")"
    fi

    # Mount folders
    apply_lxc_mounts_global "$cmd" "$lxc_name"

    # Add forwarding rule
    local forward="$("$cmd" network forward list "$brid" -f json)"
    local containerAddr="$("$cmd" list -f json | jq --raw-output ".[] | select(.name | test(\"^$lxc_name\$\")) | .state.network.eth0.addresses[] | select (.family | test(\"^inet\$\")) | .address")"
    local detectedAddress="$(echo -n "$forward" | jq --raw-output '.[].ports[].target_address')"
    local detectedPort="$(echo -n "$forward" | jq --raw-output '.[].ports[].target_port')"
    local listenAddress="$(echo -n "$forward" | jq --raw-output '.[].listen_address')"
    local listenPort="$(echo -n "$forward" | jq --raw-output '.[].ports[].listen_port')"
    # TODO:
    # - Need to change the logic to be port specific. When a network forward is listed, filter based on the listening port, check whether dest ip/port match
    # Find any previous config
    if [[ -n "$listenPort" ]]; then
        # When any of the previous config is mismatched, delete them
        local hostAddr="$(get_host_addr "$cmd" "$brid")"
        if [[ "$detectedAddress" != "$containerAddr" || "$listenAddress" != "$hostAddr" || "$detectedPort" != "$vnc_port" || "$listenPort" != "$vnc_port_on_host" ]]; then
            echo "DEBUG: forward = $(echo -n "$forward" | jq .)"
            echo "DEBUG: containerAddr = $containerAddr"
            echo "DEBUG: detectedAddress = $detectedAddress"
            echo "DEBUG: detectedPort = $detectedPort"
            echo "DEBUG: listenAddress = $listenAddress"
            echo "DEBUG: listenPort = $listenPort"
            echo "DEBUG: hostAddr = $hostAddr"
            echo "ERR: The forward has a different container address/port configuration." >&2
            echo "ERR: Removing the old definition" >&2
            "$cmd" network forward port remove "$brid" "$hostAddr" tcp "$listenPort"
            # Reset this var to meet the next network forward creation code conditional
            listenPort=''
        fi
    fi
    if [[ "$listenPort" != "$vnc_port_on_host" ]]; then
        local hostAddr="$(get_host_addr "$cmd" "$brid")"
        # Create a network forward when none found
        if [[ -z "$listenAddress" ]]; then
            echo "INFO: Create a network forward to $listenAddress"
            "$cmd" network forward create "$brid" "$hostAddr"
        fi
        # Listen and forward a network port
        "$cmd" network forward port add "$brid" "$hostAddr" tcp "$vnc_port_on_host" "$containerAddr" "$vnc_port"
    fi

    # Just print status
    "$cmd" list -c ns4t,image.description:image
    "$cmd" network forward list "$brid"

    # "$cmd" exec "$lxc_name" -t -- bash -c "cat /etc/netplan/*"

    # # List the active vnc ports
    # "$cmd" exec "$lxc_name" -t -- su - "$USER" bash -c '/opt/TurboVNC/bin/vncserver -list'

    # # print ip
    # printf "Connect to VNC using '_vncconnect %s :1'\n" "$("$cmd" list -f json | jq --raw-output ".[] | select(.name | test(\"^$lxc_name\$\")) | .state.network.eth0.addresses[] | select (.family | test(\"^inet\$\")) | .address")"

    # # Install x11vnc
    # "$cmd" exec "$lxc_name" -t -- bash -c 'apt install -y --no-install-recommends x11vnc'

    # # start a bash shell as root
    # "$cmd" exec "$lxc_name" -t -- bash -l

    if [[ "$shell" == 'true' ]]; then
        # start a bash shell
        "$cmd" exec "$lxc_name" -t --cwd "/home/$USER" -- su - "$USER"
    fi

    # # stop the shell
    # "$cmd" stop "$lxc_name"
}

main "${args[@]}"

# vim:et ts=4 sts=4 sw=4
