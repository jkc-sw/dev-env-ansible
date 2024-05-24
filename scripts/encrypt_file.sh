#!/usr/bin/env bash

: <<EOF
SOURCE_THESE_VIMS_START
nnoremap <leader>ne <cmd>silent exec "!tmux send-keys -t :.+ './" . expand('%') . "' Enter"<cr>
let @h="yoecho \"\<c-r>\" = \$\<c-r>\"\"\<esc>j"
echom 'Sourced'
SOURCE_THESE_VIMS_END
EOF

# get location of this folder
PROJECT_DIR="$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )/.."

# Get arguments
args=("$@")

# validate all files exist or print help
if [[ $# -eq 0 ]]; then
    echo "$0: Encrypt all files passed in as arguments in place"
    echo ""
    echo "Example:"
    echo "\$ $0 roles/deploy_caddy/files/afile.txt roles/deploy_caddy/files/bfile.txt"
    exit 0
fi

# All args should exist
for arg in "${args[@]}"; do
    if [[ ! -f "$arg" ]]; then
        echo "ERR: file '$arg' did not exist" >&2
        exit 1
    fi
done

# Check dependencies
toexit=false
for c in ansible-vault; do
    if ! command -v "$c" &>/dev/null; then
        echo "ERR: $c is not found in your PATH" >&2
        toexit=true
    fi
done
if [[ "$toexit" == true ]]; then
    echo "ERR: Please make sure you install all the necessary tool first" >&2
    exit 1
fi

# Edit it
pushd "$PROJECT_DIR"
ansible-vault encrypt --vault-id "prod@$PROJECT_DIR/scripts/vault-client.sh" "${args[@]}"
popd

# vim:et ts=4 sts=4 sw=4
