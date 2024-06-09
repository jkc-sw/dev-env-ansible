#!/usr/bin/env bash

: <<'20240423EOF'
SOURCE_THESE_VIMS_START
nnoremap <leader>ne <cmd> silent call execute(escape("!tmux send-keys -t :.+1 'scripts/start_lxc_container.sh' Enter", '#'))<cr>
nnoremap <leader>no <cmd> silent call execute(escape("!tmux send-keys -t :.+1 'scripts/start_lxc_container.sh -r' Enter", '#'))<cr>
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
    echo " -c CMD                    : Command to use. Default is lxc"
    echo " -i IMAGE_NAME             : Ubuntu image to use. Default is 22.04"
    echo " -n CONTAINER_NAME         : Name of the lxc container. Default is 'tom'"
    echo " -b BRIDGE                 : Name of the default bridge. Default is lxdbr0"
    echo " -w HOST_DIR:CONATINER_DIR : Map this folder to the container. Can call multiple times"
    echo " -f VNC_PORT_ON_HOST       : The VNC port to map onto the host address. Default is 15901"
    echo " -p VNC_PORT               : The VNC port inside the container. Default is 5901"
    echo " -r                        : Remove this container."
    echo " -h                        : Print this help command"
}

# const
SCRIPT_DIR="$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )"

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
    "$cmd" config device add "$lxc_name" "$name" disk source="${path#*:}" path="${path%:*}"
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
    # Apply the monts to the lxc
    for ii in $(seq 0 $(( "${#lxc_volume_mount[@]}" - 1)) ); do
        local each="${lxc_volume_mount[ii]}"
        add_lxc_mount_global "$cmd" "d$ii" "$each"
    done
}

main() {
    # var
    local imgName='ubuntu:22.04'
    local cmd='lxc'
    local brid='lxdbr0'
    local lxc_name='tom'
    local lxc_volume_mount=()
    local vnc_port_on_host=15901
    local vnc_port=5901
    local remove=false

    # parse the argumetns
    while getopts 'r:f:i:b:c:p:n:w:' opt; do
        case "$opt" in
        r)
            remove=true
            ;;
        p)
            vnc_port="$OPTARG"
            ;;
        f)
            vnc_port_on_host="$OPTARG"
            ;;
        c)
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

    echo 'INFO: Please select the host address from this list'
    local hostAddr="$(ip -j a|jq '.[].addr_info[]|select(.family | test("^inet$")).local' --raw-output | sort | fzf)"
    if [[ -z "$hostAddr" ]]; then
        echo 'ERR: No host address selected' >&2
        return 1
    fi

    # When asking to delete
    if [[ "$remove" == 'true' ]]; then
        # Stop/remove the container if found
        if [[ "$("$cmd" list -f json | jq --raw-output ".[] | select(.name | test(\"^$lxc_name\$\")) | .name" | wc -l)" -eq 1 ]]; then
            "$cmd" stop "$lxc_name"
        fi
        echo "INFO: Containers $lxc_name stopped and removed. The network forward is removed"
        "$cmd" list -c ns4t,image.description:image

        # Remove the network forward port if any was set on this interface
        local forward="$("$cmd" network forward list "$brid" -f json)"
        local listenAddress="$(<<<"$forward" jq --raw-output '.[].ports[].listen_address')"
        local listenPort="$(<<<"$forward" jq --raw-output '.[].ports[].listen_port')"
        if [[ -n "$listenAddress" && "$listenPort" == "$vnc_port_on_host" ]]; then
            $cmd network forward port remove "$brid" "$hostAddr" tcp "$vnc_port_on_host"
        fi
        echo "INFO: The network forward is removed"
        "$cmd" network forward list "$brid"
        return 0
    fi

    # Create a new container if none found
    if [[ "$("$cmd" list -f json | jq --raw-output ".[] | select(.name | test(\"^$lxc_name\$\")) | .name" | wc -l)" -ne 1 ]]; then
        # var
        local uid="$(id -u)"
        local gid="$(id -g)"

        # Start an instance
        "$cmd" launch --ephemeral "$imgName" "$lxc_name"

        # Remove default ubuntu user and add my user
        "$cmd" exec "$lxc_name" -- bash -c "deluser \"\$(id -un $uid)\""
        "$cmd" exec "$lxc_name" -- bash -c "export uid=$uid gid=$gid \
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

        # Mount folders
        apply_lxc_mounts_global "$cmd"

        # Fix the locale on debian
        "$cmd" exec "$lxc_name" -- bash -c 'export DEBIAN_FRONTEND=noninteractive && dpkg-reconfigure -f noninteractive locales \
            && locale-gen en_US.UTF-8 \
            && update-locale LC ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
            && locale-gen en_US.UTF-8'

        # Install vnc
        "$cmd" exec "$lxc_name" -- bash -c 'wget -q -O- https://packagecloud.io/dcommander/turbovnc/gpgkey | \
            gpg --dearmor >/etc/apt/trusted.gpg.d/TurboVNC.gpg \
            && wget -q -O/etc/apt/sources.list.d/turbovnc.list https://raw.githubusercontent.com/TurboVNC/repo/main/TurboVNC.list \
            && apt update \
            && apt install -y --no-install-recommends xorg xfce4 turbovnc'

        # Configure the vnc
        "$cmd" exec "$lxc_name" -- su - "$USER" bash -c "mkdir -p '/home/$USER/.vnc' \
            && echo -n aoeuaoeu | /opt/TurboVNC/bin/vncpasswd -f > '/home/$USER/.vnc/passwd' \
            && chown -R '$USER:$USER' '/home/$USER/.vnc' \
            && chmod 0600 '/home/$USER/.vnc/passwd' \
            && /opt/TurboVNC/bin/vncserver -depth 24 -geometry '1920x1080'"

    fi

    # Add forwarding rule
    local forward="$("$cmd" network forward list "$brid" -f json)"
    local containerAddr="$("$cmd" list -f json | jq --raw-output ".[] | select(.name | test(\"^$lxc_name\$\")) | .state.network.eth0.addresses[] | select (.family | test(\"^inet\$\")) | .address")"
    local detectedAddress="$(<<<"$forward" jq --raw-output '.[].ports[].target_address')"
    local detectedPort="$(<<<"$forward" jq --raw-output '.[].ports[].target_port')"
    local listenAddress="$(<<<"$forward" jq --raw-output '.[].listen_address')"
    local listenPort="$(<<<"$forward" jq --raw-output '.[].ports[].listen_port')"
    # TODO:
    # - Need to change the logic to be port specific. When a network forward is listed, filter based on the listening port, check whether dest ip/port match
    # Find any previous config
    if [[ -n "$detectedAddress" ]]; then
        # When any of the previous config is mismatched, delete them
        if [[ "$detectedAddress" != "$containerAddr" || "$listenAddress" != "$hostAddr" || "$detectedPort" != "$vnc_port" || "$listenPort" != "$vnc_port_on_host" ]]; then
            echo "DEBUG: forward = $(<<<"$forward" jq .)"
            echo "DEBUG: containerAddr = $containerAddr"
            echo "DEBUG: detectedAddress = $detectedAddress"
            echo "DEBUG: detectedPort = $detectedPort"
            echo "DEBUG: listenAddress = $listenAddress"
            echo "DEBUG: listenPort = $listenPort"
            echo "ERR: The forward has a different container address/port configuration." >&2
            echo "ERR: Removing the old definition" >&2
            $cmd network forward port remove "$brid" "$hostAddr" tcp "$listenPort"
            # Reset this var to meet the next network forward creation code conditional
            detectedPort=''
        fi
    fi
    if [[ "$detectedPort" != "$vnc_port" ]]; then
        # Create a network forward when none found
        if [[ -z "$listenAddress" ]]; then
            echo "INFO: Create a network forward to $listenAddress"
            "$cmd" network forward create "$brid" "$hostAddr"
        fi
        # Listen and forward a network port
        "$cmd" network forward port add "$brid" "$hostAddr" tcp "$vnc_port_on_host" "$("$cmd" list -f json | jq --raw-output ".[] | select(.name | test(\"^$lxc_name\$\")) | .state.network.eth0.addresses[] | select (.family | test(\"^inet\$\")) | .address")" "$vnc_port"
    fi

    # Just print status
    "$cmd" list -c ns4t,image.description:image
    "$cmd" network forward list "$bird"

    # "$cmd" exec "$lxc_name" -- bash -c "cat /etc/netplan/*"

    # # List the active vnc ports
    # "$cmd" exec "$lxc_name" -- su - "$USER" bash -c '/opt/TurboVNC/bin/vncserver -list'

    # # print ip
    # printf "Connect to VNC using '_vncconnect %s :1'\n" "$("$cmd" list -f json | jq --raw-output ".[] | select(.name | test(\"^$lxc_name\$\")) | .state.network.eth0.addresses[] | select (.family | test(\"^inet\$\")) | .address")"

    # # Install x11vnc
    # "$cmd" exec "$lxc_name" -- bash -c 'apt install -y --no-install-recommends x11vnc'

    # # start a bash shell as root
    # "$cmd" exec "$lxc_name" -- bash -l

    # # start a bash shell
    # "$cmd" exec "$lxc_name" --cwd "/home/$USER" -- su - "$USER"

    # # stop the shell
    # "$cmd" stop "$lxc_name"
}

main "${args[@]}"

# vim:et ts=4 sts=4 sw=4
