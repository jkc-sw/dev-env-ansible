#!/usr/bin/env bash

: <<'20240423EOF'
SOURCE_THESE_VIMS_START
nnoremap <leader>ne <cmd> silent call execute(escape("!tmux send-keys -t :+1 './rr.sh start -v' Enter", '#'))<cr>
nnoremap <leader>na <cmd> silent call execute(escape("!tmux send-keys -t :+1 './rr.sh shell -v' Enter", '#'))<cr>
nnoremap <leader>nE <cmd> silent call execute(escape("!tmux send-keys -t :+1 './rr.sh stop -v' Enter", '#'))<cr>
nnoremap <leader>no <cmd> silent call execute(escape("!tmux send-keys -t :+1 './rr.sh stop -v' Enter", '#'))<cr>
let @h="\"lyoechodebug \"\<c-r>l = \$\<c-r>l\"\<esc>j"
echom 'Sourced'
SOURCE_THESE_VIMS_END
20240423EOF

set -euo pipefail

args=("$@")

# # const
# SCRIPT_DIR="$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )"

################################################################################
# @brief main
################################################################################
main() {
    # var

    # Ubuntu
    local imgName='images:ubuntu/noble/default' # ubunt 24.04
    local lxc_name='tom'
    local vnc_port_on_host=15900

    # # arch
    # local imgName='images:archlinux/current/default'
    # local lxc_name='btw'
    # local vnc_port_on_host=15902

    # # rockylinux or RHEL
    # local imgName='images:rockylinux/8/default'
    # local lxc_name='rock'
    # local vnc_port_on_host=15902

    # local imgName='images:nixos/24.05/default'
    # local lxc_name='nix'
    # local vnc_port_on_host=15903

    # local cmd='lxc'
    # local brid='incusbr0'

    # local cmd='lxc'
    # local brid='lxdbr0'
    local cmd='incus'
    local brid='incusbr0'

    local lxc_volume_mount=()
    local vnc_port=5900
    local remove=false
    local shell=false
    local installDesktopEnvironmentWithVNC=false
    local vm=false

    # parse the argumetns
    while getopts 'hvf:i:b:x:p:n:w:sr.dm' opt; do
        case "$opt" in
        .)
            return 0
            ;;
        m)
            vm=true
            ;;
        d)
            installDesktopEnvironmentWithVNC=true
            ;;
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
        h)
            displayHelp
            return 0
            ;;
        *)
            echo "Unrecognized option $opt" >&2
            displayHelp
            return 1
            ;;
        esac
    done

    # var
    local containerIsRunning
    containerIsRunning="$(test_container_present "$cmd" "$lxc_name")"

    # When asking to delete
    if [[ "$remove" == 'true' ]]; then
        # Stop/remove the container if found
        if [[ "$containerIsRunning" == 'true' ]]; then
            echo "INFO: Stop and remove containers $lxc_name"

            if ! "$cmd" delete -f "$lxc_name"; then
                echo "ERR: Cannot delete the container $lxc_name" >&2
                return 1
            fi
        fi
        "$cmd" list -c ns4t,image.description:image

        # Remove the network forward port if any was set on this interface
        local forward
        forward="$("$cmd" network forward list "$brid" -f json)"
        echodebug "forward = $forward"
        local listenAddress
        listenAddress="$(echo -n "$forward" | jq --raw-output '.[].listen_address')"
        echodebug "listenAddress = $listenAddress"
        local listenPort
        listenPort="$(echo -n "$forward" | jq --raw-output '.[].ports[].listen_port')"
        echodebug "listenPort = $listenPort"
        if [[ -n "$listenAddress" && "$listenPort" == "$vnc_port_on_host" ]]; then
            echo "INFO: Find the host address from the output"
            echo "INFO: Removing network forward port"
            local hostAddr
            hostAddr="$(get_host_addr "$cmd" "$brid")"
            # TODO: implement exit code check
            if ! "$cmd" network forward port remove "$brid" "$hostAddr" tcp "$vnc_port_on_host"; then
                echo "ERR: Cannot remove network forward port" >&2
                return 1
            fi
        fi
        "$cmd" network forward list "$brid"
        return 0
    fi

    # Create a new container if none found
    if [[ "$containerIsRunning" == 'false' ]]; then
        # Need to select whether to create a VM or not
        # Start an instance
        if ! init_new_guest "$cmd" "$lxc_name" "$imgName" "$vm"; then
            echo "Err: Failed to create a container" >&2
            exit 1
        fi

        # Configure container specific stuff while the guest is in off state
        local uid
        uid="$(id -u)"
        local gid
        gid="$(id -g)"
        apply_lxc_guest_specific_settings "$cmd" "$lxc_name" "$uid" "$gid"

        # Mount folders
        add_lxc_mount_devices_global "$cmd" "$lxc_name" "$USER" "$HOME"

        # Start the container
        "$cmd" start "$lxc_name"

        # Configure generic stuff
        local waitTime=3
        if [[ "$vm" == 'true' ]]; then
            waitTime=60
        fi
        echo "INFO: Sleeping $waitTime seconds to wait for the up network"
        sleep "$waitTime"
        apply_generic_configurations "$cmd" "$lxc_name" "$uid" "$gid" "$USER" "$HOME"

        if [[ "$imgName" == *'ubuntu'* ]]; then
            # # system update
            # "$cmd" exec "$lxc_name" -t -- bash -c 'export DEBIAN_FRONTEND=noninteractive \
            #     && apt update \
            #     && apt dist-upgrade -y --no-install-recommends \
            #     && apt autoremove -y'

            # Fix the locale on debian
            "$cmd" exec "$lxc_name" -t -- bash -c 'export DEBIAN_FRONTEND=noninteractive && dpkg-reconfigure -f noninteractive locales \
                && locale-gen en_US.UTF-8 \
                && update-locale LC ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
                && locale-gen en_US.UTF-8'

            if [[ "$installDesktopEnvironmentWithVNC" == 'true' ]]; then

                # Install turbovnc
                "$cmd" exec "$lxc_name" -t -- bash -c 'wget -q -O- https://packagecloud.io/dcommander/turbovnc/gpgkey | \
                    gpg --dearmor >/etc/apt/trusted.gpg.d/TurboVNC.gpg \
                    && wget -q -O/etc/apt/sources.list.d/turbovnc.list https://raw.githubusercontent.com/TurboVNC/repo/main/TurboVNC.list \
                    && apt update \
                    && apt install -y --no-install-recommends xorg xfce4 turbovnc'

                # Configure the vnc
                "$cmd" exec "$lxc_name" -t -- su - "$USER" bash -c "mkdir -p '/home/$USER/.vnc' \
                    && echo -n aoeuaoeu | /opt/TurboVNC/bin/vncpasswd -f > '/home/$USER/.vnc/passwd' \
                    && chown -R '$USER:$USER' '/home/$USER/.vnc' \
                    && chmod 0600 '/home/$USER/.vnc/passwd' \
                    && echo '! Use a truetype font and size.' >/home/$USER/.Xresources \
                    && echo 'xterm*faceName: Monospace' >/home/$USER/.Xresources \
                    && echo 'xterm*faceSize: 14' >/home/$USER/.Xresources \
                    && xrdb -merge /home/$USER/.Xresources \
                    && export TVNC_WM=xfce \
                    && /opt/TurboVNC/bin/vncserver :0 -depth 24 -geometry '1920x1080'"

            fi

        elif [[ "$imgName" == *'rockylinux'* ]]; then
            # # System upgrade for Rocky Linux
            # "$cmd" exec "$lxc_name" -t -- bash -c 'dnf update -y && dnf distrosync -y && dnf autoremove -y'

            # Fix the locale on Rocky Linux
            "$cmd" exec "$lxc_name" -t -- bash -c 'localedef -i en_US -f UTF-8 en_US.UTF-8 \
                && localectl set-locale LANG=en_US.UTF-8'

            if [[ "$installDesktopEnvironmentWithVNC" == 'true' ]]; then

                # Add TurboVNC repository and install TurboVNC and XFCE Desktop Environment
                "$cmd" exec "$lxc_name" -t -- bash -c "dnf install -y epel-release wget \
                    && wget -q -O /etc/yum.repos.d/TurboVNC.repo https://raw.githubusercontent.com/TurboVNC/repo/main/TurboVNC.repo \
                    && rpm --import https://packagecloud.io/dcommander/turbovnc/gpgkey \
                    && dnf groupinstall -y 'Xfce' 'base-x' \
                    && dnf install -y turbovnc perl \
                    && echo \"export PATH=\$PATH:/opt/TurboVNC/bin\" > /etc/profile.d/turbovnc.sh"

                # Configure the VNC
                "$cmd" exec "$lxc_name" -t -- su - "$USER" bash -c "mkdir -p '/home/$USER/.vnc' \
                    && echo -n aoeuaoeu | vncpasswd -f > '/home/$USER/.vnc/passwd' \
                    && chown -R '$USER:$USER' '/home/$USER/.vnc' \
                    && chmod 0600 '/home/$USER/.vnc/passwd' \
                    && echo '! Use a truetype font and size.' >/home/$USER/.Xresources \
                    && echo 'xterm*faceName: Monospace' >/home/$USER/.Xresources \
                    && echo 'xterm*faceSize: 14' >/home/$USER/.Xresources \
                    && export TVNC_WM=xfce \
                    && vncserver :0 -depth 24 -geometry '1920x1080'"

            fi
        elif [[ "$imgName" == *'archlinux'* ]]; then
            # TODO: Fix this
            #   err msg: error: failed retrieving file 'alsa-ucm-conf-1.2.11-1-any.pkg.tar.zst' from mirrors.kernel.org : The requested URL returned error: 404
            # Install vnc
            "$cmd" exec "$lxc_name" -t -- bash -c 'pacman --noconfirm -S xfce4'
        fi

        # Update the container status
        containerIsRunning="$(test_container_present "$cmd" "$lxc_name")"
    fi

    # Mount folders
    chown_lxc_mounts_global "$cmd" "$lxc_name" "$USER" "$HOME"

    # Add forwarding rule
    local forward
    forward="$("$cmd" network forward list "$brid" -f json)"
    # TODO: implement exit code check
    local containerAddr
    containerAddr="$("$cmd" list -f json | jq --raw-output ".[] | select(.name | test(\"^$lxc_name\$\")) | .state.network | with_entries(select(.key | test(\"lo\") | not))[] | .addresses[] | select (.family | test(\"^inet\$\")) | .address")"
    # TODO: implement exit code check
    local detectedAddress
    detectedAddress="$(echo -n "$forward" | jq --raw-output '.[].ports[].target_address')"
    # TODO: implement exit code check
    local detectedPort
    detectedPort="$(echo -n "$forward" | jq --raw-output '.[].ports[].target_port')"
    # TODO: implement exit code check
    local listenAddress
    listenAddress="$(echo -n "$forward" | jq --raw-output '.[].listen_address')"
    # TODO: implement exit code check
    local listenPort
    listenPort="$(echo -n "$forward" | jq --raw-output '.[].ports[].listen_port')"
    # TODO: implement exit code check
    # TODO:
    # - Need to change the logic to be port specific. When a network forward is listed, filter based on the listening port, check whether dest ip/port match
    # Find any previous config
    if [[ -n "$listenPort" ]]; then
        # When any of the previous config is mismatched, delete them
        local hostAddr
        hostAddr="$(get_host_addr "$cmd" "$brid")"
        # TODO: implement exit code check
        if [[ "$detectedAddress" != "$containerAddr" || "$listenAddress" != "$hostAddr" || "$detectedPort" != "$vnc_port" || "$listenPort" != "$vnc_port_on_host" ]]; then
            echodebug "forward = $(echo -n "$forward" | jq .)"
            echodebug "containerAddr = $containerAddr"
            echodebug "detectedAddress = $detectedAddress"
            echodebug "detectedPort = $detectedPort"
            echodebug "listenAddress = $listenAddress"
            echodebug "listenPort = $listenPort"
            echodebug "hostAddr = $hostAddr"
            echo "ERR: The forward has a different container address/port configuration." >&2
            echo "ERR: Removing the old definition" >&2
            "$cmd" network forward port remove "$brid" "$hostAddr" tcp "$listenPort"
            # Reset this var to meet the next network forward creation code conditional
            listenPort=''
        fi
    fi
    if [[ "$listenPort" != "$vnc_port_on_host" ]]; then
        local hostAddr
        hostAddr="$(get_host_addr "$cmd" "$brid")"
        # TODO: implement exit code check
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

displayHelp() {
    # print help here
    echo "${BASH_SOURCE[0]} [flags] Create lxc container for testing"
    echo ""
    echo "Flags:"
    echo " -c                        : Creat a new container instance"
    echo " -.                        : Source the command without executing"
    echo " -r                        : Remove this container instance"
    echo " -s                        : Drop me into a bash shell"
    echo ""
    echo " -b BRIDGE                 : Name of the default bridge. Default is lxdbr0"
    echo " -d                        : Run a desktop environment via TurboVNC"
    echo " -m                        : Run as a VM instead of a container. Default is a container"
    echo " -f VNC_PORT_ON_HOST       : The VNC port to map onto the host address. Default is 15901"
    echo " -i IMAGE_NAME             : Ubuntu image to use. Default is 24.04"
    echo " -n CONTAINER_NAME         : Name of the lxc container. Default is 'tom'"
    echo " -p VNC_PORT               : The VNC port inside the container. Default is 5901"
    echo " -w HOST_DIR:CONATINER_DIR : Map this folder to the container. Can call multiple times"
    echo " -x CMD                    : Command to use. Default is lxc"
    echo ""
    echo " -h                        : Print this help command"
    echo " -v                        : Verbose trace information"
}

# Function to echo debug
echodebug() {
    if [[ -n "${DEBUG_LXC:=}" ]]; then
        echo "DEBUG: $*"
    fi
}

################################################################################
# @brief Test whether my current system support virtualization
# @return 'true' if yes, 'false' otherwise
################################################################################
test_virtualization_enabled_or_capable() {
    local cpuinfo
    cpuinfo="$(</proc/cpuinfo)"
    if [[ "$cpuinfo" =~ vmx|svm ]]; then
        echo -n 'true'
        return
    fi
    echo -n 'false'
}

################################################################################
# @brief function to locate the hostAddr
# @param cmd - whether it is lxc or incus
# @param brid - network brigde name
# @return ipaddress of the host
################################################################################
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
    local forward
    forward="$("$cmd" network forward list "$brid" -f json)"
    local listenAddress
    listenAddress="$(echo -n "$forward" | jq --raw-output '.[].listen_address')"
    local currentIpOutput
    currentIpOutput="$(ip -j a|jq '.[].addr_info[]|select(.family | test("^inet$")).local' --raw-output)"
    # Find an existing one and return it
    if [[ -n "$listenAddress" ]]; then
        while read -r each; do
            if [[ "$currentIpOutput" == *"$each"* ]]; then
                echo -n "$each"
                return 0
            fi
        done <<<"$listenAddress"
    fi
    # otherwise, use fzf to search it
    local selectedHostIp
    selectedHostIp="$(echo -n "$currentIpOutput" | fzf)"
    if [[ "$?" -ne 0 || -z "$selectedHostIp" ]]; then
        echo "ERR (get_host_addr): Cannot get the host address using fzf" >&2
        return 1
    fi
    echo -n "$selectedHostIp"
    return 0
}

################################################################################
# @brief get a list of all the mounted paths
# @param cmd - whether it is lxc or incus
# @param lxc_name - container name
# @return list of mounted paths, each per line
################################################################################
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
    local paths
    paths="$("$cmd" list -f json | jq --raw-output ".[] | select(.name | test(\"^$lxc_name\$\")) | .devices[] | \"\(.path):\(.source)\"")"
    echo -n "$paths"
}

################################################################################
# @brief add the new mount path to the container
# @param cmd - whether it is lxc or incus
# @param lxc_name - container name
# @param path - path to mount as <path on host>:<path in container>
# @return void
################################################################################
add_lxc_mount_device() {
    # Get arguments
    local args=("$@")
    # Need 1 argument
    if [[ "${#args[@]}" -ne 3 ]]; then
        echo "ERR (add_lxc_mount_device): need 3 arguments (bin, container name, path) only, but found ${#args[@]}" >&2
        return 1
    fi
    local cmd="${args[0]}"
    local lxc_name="${args[1]}"
    local path="${args[2]}"
    if [[ ! "$path" == *:* ]]; then
        echo "ERR (add_lxc_mount_device): path arg should have format '<src>:<dest>'" >&2
        return 1
    fi
    local src="${path%:*}"
    if [[ ! -e "$src" ]]; then
        echo "ERR (add_lxc_mount_device): src '$src' (before : in path arg) is not found." >&2
        return 1
    fi
    local dest="${path#*:}"
    if [[ -z "$dest" ]]; then
        echo "ERR (add_lxc_mount_device): dest (after : in path arg) cannot be empty" >&2
        return 1
    fi
    local out
    out="$(sha1sum <<<"$path")"
    local pathHash="${out%% *}"
    # Add this disk because it is not found
    "$cmd" config device add "$lxc_name" "$pathHash" disk source="$src" path="$dest"
    echo "INFO (add_lxc_mount_device): Added '$path'" >&2
}

################################################################################
# @brief store the mount path to a global variable
# @param path - path to mount as <path on host>:<path in container>
# @return void
################################################################################
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
    echo "INFO (append_lxc_mount_global): Added '$path'" >&2
}

################################################################################
# @brief execute chmod inside the container
# @param cmd - whether it is lxc or incus
# @param lxc_name - container name
# @param path - path to mount as <path on host>:<path in container>
# @return void
################################################################################
chown_lxc_each_mount_device() {
    # Get arguments
    local args=("$@")
    # Need 1 argument
    if [[ "${#args[@]}" -ne 3 ]]; then
        echo "ERR (chown_lxc_each_mount_device): need 3 argument (bin, container name, path), but found ${#args[@]}" >&2
        return 1
    fi
    local cmd="${args[0]}"
    local lxc_name="${args[1]}"
    local path="${args[2]}"
    local dest="${path#*:}"
    "$cmd" exec "$lxc_name" -- chown -R "$USER:$USER" "$dest"
}

################################################################################
# @brief Apply some container or VM specific configuration in LXC on the host
#        VM should be off at this time
# @param cmd - whether it is lxc or incus
# @param lxc_name - container name
# @param uid - user id
# @param gid - user's group id
# @return void
################################################################################
apply_lxc_guest_specific_settings() {
    # Get arguments
    local args=("$@")
    # Need 1 argument
    if [[ "${#args[@]}" -ne 4 ]]; then
        echo "ERR (apply_lxc_guest_specific_settings): need 4 arguments (bin, container name, uid, gid) only, but found ${#args[@]}" >&2
        return 1
    fi
    local cmd="${args[0]}"
    local lxc_name="${args[1]}"
    local uid="${args[2]}"
    local gid="${args[3]}"
    # map the user id in the container
    echodebug "(apply_lxc_guest_specific_settings): lxc raw.idmap"
    "$cmd" config set "$lxc_name" raw.idmap "both $uid $uid"
}

################################################################################
# @brief Set the number of PCIe device in the lxc container config
# @param cmd - whether it is lxc or incus
# @param lxc_name - container name
# @param num - number of PCIe devices in the config limits
# @return void
################################################################################
set_container_pcie_cfg_limits() {
    # Get arguments
    local args=("$@")
    # Need 1 argument
    if [[ "${#args[@]}" -ne 3 ]]; then
        echo "ERR (set_container_pcie_cfg_limits): need 3 arguments (bin, container name, limits) only, but found ${#args[@]}" >&2
        return 1
    fi
    local cmd="${args[0]}"
    local lxc_name="${args[1]}"
    local limits="${args[2]}"
    # Remove default ubuntu user and add my user
    echodebug "(set_container_pcie_cfg_limits): set the limits.pcie to limits ($limits)"
    if ! "$cmd" config set "$lxc_name" "limits.pci=$limits"; then
        echo "ERR (set_container_pcie_cfg_limits): failed to set the config for $lxc_name" >&2
        return 1
    fi
}

################################################################################
# @brief upon container creation, add user of same uid/guid, grant sudo without
#        password, set timezone, then restart the container
# @param cmd - whether it is lxc or incus
# @param lxc_name - container name
# @param uid - user id
# @param gid - user's group id
# @param username - username
# @return void
################################################################################
apply_generic_configurations() {
    # Get arguments
    local args=("$@")
    # Need 1 argument
    if [[ "${#args[@]}" -ne 6 ]]; then
        echo "ERR (apply_generic_configurations): need 6 arguments (bin, container name, uid, gid, username, home dir) only, but found ${#args[@]}" >&2
        return 1
    fi
    local cmd="${args[0]}"
    local lxc_name="${args[1]}"
    local uid="${args[2]}"
    local gid="${args[3]}"
    local username="${args[4]}"
    local homePath="${args[5]}"
    # Remove default ubuntu user and add my user
    echodebug "(apply_generic_configurations): Removes ubuntu default user if found"
    "$cmd" exec "$lxc_name" -t -- bash -c "id -un $uid 2>/dev/null && userdel -f \"\$(id -un $uid)\"" || true
    echodebug "(apply_generic_configurations): Sets timezone"
    "$cmd" exec "$lxc_name" -t -- bash -c "timedatectl set-timezone America/Los_Angeles"
    echodebug "(apply_generic_configurations): Add user $username ($uid)"
    "$cmd" exec "$lxc_name" -t -- bash -c "export uid=$uid gid=$gid \
        && mkdir -p '${homePath}' \
        && echo \"${username}:x:\${uid}:\${gid}:${username},,,:${homePath}:/bin/bash\" >> /etc/passwd \
        && echo \"${username}:x:\${uid}:\" >> /etc/group \
        && echo \"${username} ALL=(ALL:ALL) NOPASSWD: ALL\" > /etc/sudoers.d/${username} \
        && chmod 0440 /etc/sudoers.d/${username} \
        && chown \${uid}:\${gid} -R ${homePath} \
        && echo ${username}:aoeu | chpasswd" || true
}

################################################################################
# @brief Change the owner of the mount points
# @param cmd - whether it is lxc or incus
# @param lxc_name - container name
# @return void
################################################################################
chown_lxc_mounts_global() {
    # Get arguments
    local args=("$@")
    # Need 1 argument
    if [[ "${#args[@]}" -ne 4 ]]; then
        echo "ERR (chown_lxc_mounts_global): need 4 arguments (bin, container name, username, home dir) only, but found ${#args[@]}" >&2
        return 1
    fi
    local cmd="${args[0]}"
    local lxc_name="${args[1]}"
    local username="${args[2]}"
    local homePath="${args[3]}"
    local mountedPaths
    mountedPaths="$(get_all_mounted_paths_from_containers "$cmd" "$lxc_name")"
    # Apply the monts to the lxc
    for ii in $(seq 0 $(( "${#lxc_volume_mount[@]}" - 1)) ); do
        local each="${lxc_volume_mount[ii]}"
        # Skip this path if already monuted
        if [[ "$mountedPaths" == *"$each"* ]]; then
            echo "INFO (chown_lxc_mounts_global): Skip mounted '$each'"
            continue
        fi
        chown_lxc_each_mount_device "$cmd" "$lxc_name" "$each"
    done
    # chown the entire home dir
    "$cmd" exec "$lxc_name" -- chown -R "$username:$username" "$homePath"
}

################################################################################
# @brief Add all the stored filepath to the mounts of container
# @param cmd - whether it is lxc or incus
# @param lxc_name - container name
# @param username - user name to map from the host and container/vm
# @param home - home path on the host and in the container/vm
# @return void
################################################################################
add_lxc_mount_devices_global() {
    # Get arguments
    local args=("$@")
    # Need 1 argument
    if [[ "${#args[@]}" -ne 4 ]]; then
        echo "ERR (add_lxc_mount_devices_global): need 4 arguments (bin, container name, username, home dir) only, but found ${#args[@]}" >&2
        return 1
    fi
    local cmd="${args[0]}"
    local lxc_name="${args[1]}"
    local username="${args[2]}"
    local homePath="${args[3]}"
    local mountedPaths
    mountedPaths="$(get_all_mounted_paths_from_containers "$cmd" "$lxc_name")"
    # Apply the monts to the lxc
    for ii in $(seq 0 $(( "${#lxc_volume_mount[@]}" - 1)) ); do
        local each="${lxc_volume_mount[ii]}"
        # Skip this path if already monuted
        if [[ "$mountedPaths" == *"$each"* ]]; then
            echo "INFO (add_lxc_mount_devices_global): Skip mounted '$each'"
            continue
        fi
        add_lxc_mount_device "$cmd" "$lxc_name" "$each"
    done
}

################################################################################
# @brief Create a new guest, container or VM
# @param cmd - whether it is lxc or incus
# @param lxc_name - container name
# @param imgName - The image to spawn the container or VM
# @param vm - Create the guest as a VM when 'true', otherwise 'false'
# @return void
################################################################################
init_new_guest() {
    # Get arguments
    local args=("$@")
    # Need 1 argument
    if [[ "${#args[@]}" -ne 4 ]]; then
        echo "ERR (init_new_guest): need 4 arguments (bin, container name, username, home dir) only, but found ${#args[@]}" >&2
        return 1
    fi
    local cmd="${args[0]}"
    local lxc_name="${args[1]}"
    local imgName="${args[2]}"
    local vm="${args[3]}"
    local initArgs=(init "$imgName" "$lxc_name")
    if [[ "$vm" == 'true' ]]; then
        initArgs+=(--vm --device 'root,size=32GiB')
    fi
    echodebug "initArgs = ${initArgs[*]}"
    if ! "$cmd" "${initArgs[@]}"; then
        echo "Err: Failed to create a container" >&2
        return 1
    fi
    return 0
}

################################################################################
# @brief Check that all dependencies are available
# @throw When any dependency is not met, exit
################################################################################
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

# # Remove containers
# remove_container() {
# }

################################################################################
# @brief test whether the named container is present
# @param cmd - whether it is lxc or incus
# @param lxc_name - container name
# @return 'true' if running, etherwise 'false'
################################################################################
test_container_present() {
    # Get arguments
    local args=("$@")
    # Need 1 argument
    if [[ "${#args[@]}" -ne 2 ]]; then
        echo "ERR (test_container_present): need 2 arguments (bin, container name) only, but found ${#args[@]}" >&2
        return 1
    fi
    local cmd="${args[0]}"
    local lxc_name="${args[1]}"
    # var
    if [[ -n "$("$cmd" list -f json | jq --raw-output ".[] | select(.name | test(\"^$lxc_name\$\")) | .name")" ]]; then
        echo -n 'true'
        return 0
    fi
    echo -n 'false'
}

main "${args[@]}"

# vim:et ts=4 sts=4 sw=4
