#!/usr/bin/env bash
# Build the miner config from the flight sheet. Hive provides:
#   CUSTOM_TEMPLATE    wallet/worker (%WAL% already substituted)
#   CUSTOM_URL         pool host:port
#   CUSTOM_PASS        pool password (optional, defaults to x)
#   CUSTOM_USER_CONFIG extra args appended to the command line
source /hive/miners/custom/veilminersha/h-manifest.conf

[[ -z $CUSTOM_TEMPLATE ]] && echo "veilminersha: no wallet set in flight sheet" && exit 1
[[ -z $CUSTOM_URL ]]      && echo "veilminersha: no pool URL set in flight sheet" && exit 1

host="${CUSTOM_URL#stratum+tcp://}"; host="${host#stratum+ssl://}"; host="${host#stratum://}"

echo "POOL_URL=\"stratum+tcp://${host}\"" >  "$CUSTOM_CONFIG_FILENAME"
echo "WALLET=\"${CUSTOM_TEMPLATE}\""       >> "$CUSTOM_CONFIG_FILENAME"
echo "PASS=\"${CUSTOM_PASS:-x}\""          >> "$CUSTOM_CONFIG_FILENAME"
echo "EXTRA=\"${CUSTOM_USER_CONFIG}\""     >> "$CUSTOM_CONFIG_FILENAME"
