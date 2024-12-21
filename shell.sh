PROJECT_DIR="$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )"
# Check if nix is available
export LOCALE_ARCHIVE=/usr/lib/locale/locale-archive
# Source nix if using nix-installer
if [[ -r "/nix/var/nix/profiles/default/etc/profile.d/nix.sh" ]]; then
    . "/nix/var/nix/profiles/default/etc/profile.d/nix.sh"
fi
# Source nix if using nix official installer
if [[ -r "$HOME/.nix-profile/etc/profile.d/nix.sh" ]]; then
    . "$HOME/.nix-profile/etc/profile.d/nix.sh"
fi
if [[ -r /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi
if ! command -v nix &>/dev/null; then
    # Ask people to install
    echo 'WARN: nix is not found in your PATH' >&2
    echo 'WARN: --------------------------------------------------------------------------' >&2
    echo 'WARN: To install nix, the following commands would be run.' >&2
    echo "WARN: \$ curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install" >&2
    echo 'WARN: --------------------------------------------------------------------------' >&2
    totalCount=3
    for count in $(seq $totalCount); do
        echo "WARN: Asking $count/$totalCount. Select 'y' to automatically run the scripts above, or 'n' to abort." >&2
        read -r -p "> " res
        if [[ "$res" == 'y' || "$res" == 'Y' ]]; then
            if curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install; then
                echo 'INFO: Installation completed.' >&2
                if [[ ! -r /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
                    echo 'ERR: Nix installation failed or nix not found' >&2
                    exit 1
                fi
                . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
                break
            else
                echo 'ERR: Installation failed. Check error above.' >&2
                exit 1
            fi
        fi
        if [[ "$res" == 'n' || "$res" == 'N' ]]; then
            echo 'INFO: Installation aborted.' >&2
            exit 0
        fi
    done
fi
if ! command -v nix &>/dev/null; then
    echo 'ERR: Dependencies are not met. See error message above.' >&2
    exit 1
fi
( cd "$PROJECT_DIR" ; export NIXPKGS_ALLOW_UNFREE=1 ; nix develop "$PROJECT_DIR" )

