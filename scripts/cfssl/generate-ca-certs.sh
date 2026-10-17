#!/usr/bin/env bash
set -Eeuo pipefail

for cmd in cfssl cfssljson openssl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: '$cmd' not found. Install it before running this script." >&2
        exit 1
    fi
done

if [[ ! -f "ca-csr.json" ]]; then
    echo "ERROR: ca-csr.json not found in the current directory." >&2
    exit 1
fi

generate_ca() {
    local name="$1"
    local common_name="$2"
    local cert="${name}.crt"
    local key="${name}.key"

    if [[ -f "$cert" && -f "$key" ]]; then
        echo "SKIP: $cert and $key already exist."
        return 0
    fi

    echo "Generating CA: $name"

    cfssl gencert \
        -initca \
        -cn="$common_name" \
        ca-csr.json |
        cfssljson -bare "$name" -

    mv "${name}.pem" "$cert"
    mv "${name}-key.pem" "$key"

#    chmod 600 "$key"
    echo "OK: Generated $cert and $key"
}

# Kubernetes CA
generate_ca "ca" "kubernetes-ca"

# Front-proxy CA
generate_ca "front-proxy-ca" "kubernetes-front-proxy-ca"

# Service Account keys
if [[ -f "sa.key" && -f "sa.pub" ]]; then
    echo "SKIP: sa.key and sa.pub already exist."
else
    echo "Generating Service Account keys..."

    openssl genrsa -out sa.key 2048
    openssl rsa -in sa.key -pubout -out sa.pub

#    chmod 600 sa.key
    echo "OK: Generated sa.key and sa.pub"
fi

# etcd CA
generate_ca "etcd-ca" "etcd-ca"

echo "All certificate and key generation tasks completed."

rm -f -- *.csr