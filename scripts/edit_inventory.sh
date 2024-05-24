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

# # Check passwords are present
# if [[ -z "$PASSWORD_STORE_DIR" ]]; then
#     echo 'ERR: This command currently should only be run by Jerry ATM' >&2
#     exit 1
# fi
# if ! ( pass ls servers/ansible/vault-id/ | grep -F -e 'prod' ); then
#     echo 'ERR: need to setup teh password first. Contact Jerry' >&2
#     exit 1
# fi

# Edit it
pushd "$PROJECT_DIR"
# ansible-vault encrypt --vault-id "prod@$PROJECT_DIR/scripts/vault-client.sh" "$PROJECT_DIR/inventory/local.yaml"
ansible-vault edit --vault-id "prod@$PROJECT_DIR/scripts/vault-client.sh" "$PROJECT_DIR/inventory/local.yaml"
popd
