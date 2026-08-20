# Veil-Miner-SHA — AMD / OpenCL

Veil SHA256D miner for AMD GPUs (OpenCL). Companion to the NVIDIA/CUDA build
(ccminer) in the repository root. Same Veil `sha256dv` stratum protocol.

## Build

```
make
```

Needs OpenCL and libcrypto. On Ubuntu / HiveOS:
`sudo apt-get install ocl-icd-opencl-dev libssl-dev build-essential`.

## Run

```
./veil-miner-sha-amd -o stratum+tcp://veil.yadaminers.pl:3333 -u YOUR_VEIL_ADDRESS -p x
```

- auto-selects the first AMD GPU (so on a mixed rig it leaves NVIDIA cards to ccminer)
- `-d N`  pin a device index   `--list` list devices   `--batch N` nonces per launch (2^N, default 2^22)
- one GPU per process; on a multi-AMD rig launch one per card with `-d`

## HiveOS

`hiveos/` is a custom-miner package (h-manifest.conf, h-config.sh, h-run.sh,
h-stats.sh). Package it as `veilminersha.tar.gz` containing the built
`veil-miner-sha-amd`, `veil_sha256dv.cl` and the `h-*.sh` scripts, then add it
as a Custom miner in the flight sheet.

Status: validated end to end against the live pool (accepted shares); tuning
and multi-GPU-in-one-process are follow-ups.
