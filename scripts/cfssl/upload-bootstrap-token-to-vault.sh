#!/usr/bin/env bash
set -euo pipefail

VAULT_PATH="secret/kubernetes"
TOKEN_FILE="bootstrap_token"

if [[ ! -f "$TOKEN_FILE" ]]; then
    printf '%s.%s\n' \
        "$(openssl rand -hex 3)" \
        "$(openssl rand -hex 8)" > "$TOKEN_FILE"

#    chmod 600 "$TOKEN_FILE"
    echo "Bootstrap token generated and saved to $TOKEN_FILE"
else
    echo "File $TOKEN_FILE already exists, reusing existing token"
fi

vault kv put \
    "${VAULT_PATH}/${TOKEN_FILE}" \
    value=@"${TOKEN_FILE}"

echo
echo "Bootstrap token successfully uploaded to Vault: $VAULT_PATH"
echo
echo "Secrets in ${VAULT_PATH}:"
vault kv list "${VAULT_PATH}"