#!/usr/bin/env bash

set -euo pipefail

: "${VAULT_ADDR:=http://127.0.0.1:8200}"
: "${VAULT_TOKEN:?VAULT_TOKEN must be set}"

CERT_DIR="${1:-./pki}"
VAULT_PATH="secret/kubernetes"

export VAULT_ADDR
export VAULT_TOKEN

if [[ ! -d "$CERT_DIR" ]]; then
    echo "ERROR: directory does not exist: $CERT_DIR" >&2
    exit 1
fi

echo "Vault:       ${VAULT_ADDR}"
echo "Source dir:  ${CERT_DIR}"
echo "Vault path:  ${VAULT_PATH}"
echo

count=0

for file in "${CERT_DIR}"/*.crt "${CERT_DIR}"/*.key "${CERT_DIR}"/*.pub; do

    [[ -f "$file" ]] || continue

    filename="$(basename "$file")"

    echo "Uploading: ${filename}"

    vault kv put \
        "${VAULT_PATH}/${filename}" \
        value=@"${file}"

    ((count+=1))

done

if [[ "$count" -eq 0 ]]; then
    echo "ERROR: no .crt or .key files found in ${CERT_DIR}" >&2
    exit 1
fi

echo
echo "Uploaded ${count} file(s)."
echo

echo "Secrets in ${VAULT_PATH}:"
vault kv list "${VAULT_PATH}"