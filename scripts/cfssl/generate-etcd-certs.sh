#!/usr/bin/env bash
set -Eeuo pipefail

CA_CERT="etcd-ca.crt"
CA_KEY="etcd-ca.key"
CA_CONFIG="ca-config.json"
HOSTNAME_LIST="hostname_list"

for cmd in cfssl cfssljson; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: '$cmd' not found. Install it before running this script." >&2
        exit 1
    fi
done

for file in "$CA_CERT" "$CA_KEY" "$CA_CONFIG" "$HOSTNAME_LIST"; do
    if [[ ! -f "$file" ]]; then
        echo "ERROR: Required file '$file' not found." >&2
        exit 1
    fi
done

generate_cert() {
    local hostname="$1"
    local profile="$2"
    local prefix="${hostname}-etcd-${profile}"
    local cert="${prefix}.crt"
    local key="${prefix}.key"
    local output_prefix="etcd-${profile}"

    if [[ -f "$cert" && -f "$key" ]]; then
        echo "SKIP: $cert and $key already exist."
        return 0
    fi

    if [[ ! -f "${hostname}.json" ]]; then
        echo "ERROR: CSR config '${hostname}.json' not found." >&2
        return 1
    fi

    echo "Generating $profile certificate for $hostname..."

    cfssl gencert \
        -ca="$CA_CERT" \
        -ca-key="$CA_KEY" \
        -config="$CA_CONFIG" \
        -profile="$profile" \
        "${hostname}.json" |
        cfssljson -bare "$output_prefix" -

    mv "${output_prefix}.pem" "$cert"
    mv "${output_prefix}-key.pem" "$key"

#    chmod 600 "$key"

    echo "OK: Generated $cert and $key"
}

while IFS= read -r hostname || [[ -n "$hostname" ]]; do
    hostname="${hostname#"${hostname%%[![:space:]]*}"}"
    hostname="${hostname%"${hostname##*[![:space:]]}"}"

    [[ -z "$hostname" || "$hostname" == \#* ]] && continue

    echo "Processing host: $hostname"

    generate_cert "$hostname" "peer"
    generate_cert "$hostname" "server"

done < "$HOSTNAME_LIST"

echo "All etcd peer and server certificate tasks completed."
