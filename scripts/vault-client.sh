#!/usr/bin/env bash

: <<EOF
SOURCE_THESE_VIMS_START
nnoremap <leader>ne <cmd>silent exec "!tmux send-keys -t :.+ './scripts/vault-client.sh prod' Enter"<cr>
let @h="yoecho \"\<c-r>\" = \$\<c-r>\"\"\<esc>j"
echom 'Sourced'
SOURCE_THESE_VIMS_END
EOF

# get location of this folder
PROJECT_DIR="$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )/.."

# For Jerry only
if [[ -z "$JERRY_DEBUG_VAULT_CLIENT" && -n "$PASSWORD_STORE_DIR" ]]; then
    # Check dependencies
    toexit=false
    for c in pass; do
        if ! command -v "$c" &>/dev/null; then
            echo "ERR: $c is not found in your PATH" >&2
            toexit=true
        fi
    done
    if [[ "$toexit" == true ]]; then
        echo "ERR: Please make sure you install all the necessary tool first" >&2
        exit 1
    fi

    # The arguments looks like below when called with --vault-id prod@<client-path>
    # 1: --vault-id
    # 2: prod
    pass "devenv/vault-$2"
    exit 0
fi

toexit=false
for c in bw; do
    if ! command -v "$c" &>/dev/null; then
        echo "ERR: $c is not found in your PATH" >&2
        toexit=true
    fi
done
if [[ "$toexit" == true ]]; then
    echo "ERR: Please make sure you install all the necessary tool first" >&2
    exit 1
fi
# For using bitwarden
if [[ -z "$BW_SESSION" ]]; then
    echo 'ERR: Bitwarden is not unlocked yet' >&2
    echo '     To sign in, use "bw login --apikey" or "bw login --sso",' >&2
    echo '     following with "bw unlock" and setting "export BW_SESSION=...".' >&2
    exit 1
fi
# bw get password 65d4e638-980a-4f0f-9c9d-aff50103c687
echo 'ERR: not supported yet' >&2
exit 1
if [[ "$?" -ne 0 ]]; then
    echo 'ERR: Password is not in your bitwarden vault. Talk to the team member in #ps-devop-admin slack channel' >"$(tty)"
    exit "$?"
fi
exit 0

# vim:et ts=4 sts=4 sw=4
