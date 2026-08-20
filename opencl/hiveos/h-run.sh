#!/usr/bin/env bash
cd "$(dirname "$0")"
source h-manifest.conf
[[ ! -f $CUSTOM_CONFIG_FILENAME ]] && echo "veilminersha: config missing, apply the flight sheet first" && exit 1
source "$CUSTOM_CONFIG_FILENAME"
[[ -z $POOL_URL ]] && echo "veilminersha: no POOL_URL" && exit 1

# By default the miner auto-picks the first AMD GPU (leaves NVIDIA cards to
# a CUDA miner). Use EXTRA="-d N" from the flight sheet to pin a device, or
# run --list once to see indices.
./veil-miner-sha-amd -o "$POOL_URL" -u "$WALLET" -p "$PASS" $EXTRA 2>&1 | tee "$CUSTOM_LOG_BASENAME.log"
