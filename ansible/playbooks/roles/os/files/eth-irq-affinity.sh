#!/usr/bin/env bash
set -euo pipefail

CPU=0
PATTERN='eth|enx|gmac|ethernet'

log() {
    echo "eth-irq-affinity: $*"
}

IRQS=$(
    awk -v pattern="$PATTERN" '
        BEGIN { IGNORECASE=1 }
        /^[[:space:]]*[0-9]+:/ && $0 ~ pattern {
            gsub(/:/, "", $1)
            print $1
        }
    ' /proc/interrupts | sort -u
)

if [[ -z "$IRQS" ]]; then
    log "ERROR: Ethernet IRQs not found"
    exit 1
fi

for IRQ in $IRQS; do
    AFFINITY="/proc/irq/${IRQ}/smp_affinity_list"

    if [[ ! -e "$AFFINITY" ]]; then
        log "WARNING: $AFFINITY not found"
        continue
    fi

    echo "$CPU" > "$AFFINITY"

    log "IRQ $IRQ pinned to CPU $CPU"
done
