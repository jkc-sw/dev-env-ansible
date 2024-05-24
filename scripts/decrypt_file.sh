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
if [[ "${#args[@]}" -eq 0 ]]; then
    echo "$0: Decrypet an inventory file using ansible-vault"
    echo "$0 ENCRYPTED_FILE_PATH DECRYPTED_OUTPUT_PATH"
    echo ""
    echo "Parameter:"
    echo "  ENCRYPTED_FILE_PATH   - File encrypted using ansible-vault."
    echo "  DECRYPTED_OUTPUT_PATH - Output of decrypted file. Use - for stdout"
    echo ""
    echo "Example:"
    echo "\$ $0 encrypted.txt decrypted.txt"
    echo "\$ $0 encrypted.txt -"
    exit 0
fi

# validate all files exist or print help
if [[ "${#args[@]}" -ne 2 ]]; then
    echo "ERR: $0 needs 2 arguments, encrypted path and output path"
    exit 0
fi

# Check if the source exist
srcpath="${args[0]}"
outpath="${args[1]}"
if [[ ! -r "$srcpath" ]]; then
    echo "ERR ($0): cannot find '$srcpath' encrypted file" >&2
    exit 1
fi

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
ansible-vault decrypt --vault-id "prod@$PROJECT_DIR/scripts/vault-client.sh" "$srcpath" --output "$outpath"
popd

# vim:et ts=4 sts=4 sw=4
