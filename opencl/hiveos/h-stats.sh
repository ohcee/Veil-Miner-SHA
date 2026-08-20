#!/usr/bin/env bash
# Sourced by the hive agent. Must set khs (total kilohash) and stats (JSON).
# The miner prints "[hashrate] X.XX MH/s ... A/R a/r"; we read the latest line.
source /hive/miners/custom/veilminersha/h-manifest.conf

line=$(tail -n 60 "$CUSTOM_LOG_BASENAME.log" 2>/dev/null | grep '\[hashrate\]' | tail -1)
mhs=$(echo "$line" | sed -n 's/.*\] \([0-9.]*\) MH\/s.*/\1/p')
acc=$(echo "$line" | sed -n 's/.*A\/R \([0-9]*\)\/\([0-9]*\).*/\1/p')
rej=$(echo "$line" | sed -n 's/.*A\/R \([0-9]*\)\/\([0-9]*\).*/\2/p')
[[ -z $mhs ]] && mhs=0
khs=$(awk "BEGIN{printf \"%.0f\", $mhs*1000}")

# Real GPU temp/fan come from the hive agent's own telemetry; report a single
# card's hashrate here (this instance mines one GPU).
temp=$(jq -r '.temp[0] // 0' /run/hive/gpu-stats.json 2>/dev/null); temp=${temp:-0}
fan=$(jq  -r '.fan[0]  // 0' /run/hive/gpu-stats.json 2>/dev/null); fan=${fan:-0}

stats=$(jq -nc \
  --argjson khs "${khs:-0}" --argjson acc "${acc:-0}" --argjson rej "${rej:-0}" \
  --argjson temp "${temp:-0}" --argjson fan "${fan:-0}" \
  '{hs:[$khs], hs_units:"khs", temp:[$temp], fan:[$fan], ar:[$acc,$rej], algo:"sha256dv"}')
