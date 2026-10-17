#!/usr/bin/env bash
set -Eeuo pipefail

CERT_NAME="apiserver-etcd-client"

for cmd in cfssl cfssljson; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: '$cmd' not found. Install it before running this script." >&2
        exit 1
    fi
done

for file in etcd-ca.crt etcd-ca.key ca-config.json etcd-client.json; do
    if [[ ! -f "$file" ]]; then
        echo "ERROR: Required file '$file' not found." >&2
        exit 1
    fi
done

CERT="${CERT_NAME}.crt"
KEY="${CERT_NAME}.key"

if [[ -f "$CERT" && -f "$KEY" ]]; then
    echo "SKIP: $CERT and $KEY already exist."
else
    echo "Generating $CERT_NAME certificate..."

    cfssl gencert \
        -ca=etcd-ca.crt \
        -ca-key=etcd-ca.key \
        -config=ca-config.json \
        -profile=client \
        etcd-client.json |
        cfssljson -bare "$CERT_NAME" -

    mv "${CERT_NAME}.pem" "$CERT"
    mv "${CERT_NAME}-key.pem" "$KEY"

#    chmod 600 "$KEY"
    echo "OK: Generated $CERT and $KEY"
fi

echo "All tasks completed successfully."
rm -f -- *csr
