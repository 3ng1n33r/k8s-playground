#!/bin/zsh

REMOTE_HOST=pi@192.168.31.20
NS=flux-system
MANIFEST=private.key

cat "${MANIFEST}" |
ssh "${REMOTE_HOST}" \
  "kubectl create namespace ${NS} --dry-run=client -o yaml | kubectl apply -f - && kubectl apply -f -"
