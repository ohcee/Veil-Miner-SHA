#!/usr/bin/env bash
# One-shot setup for the Veil AMD OpenCL miner on Ubuntu 22.04.
#
#   ./setup-ubuntu.sh          deps + build + detect GPUs (light)
#   ./setup-ubuntu.sh --rocm   also install AMD ROCm OpenCL (needed for RX 6600 XT etc.)
#
# After --rocm you must log out/in (or reboot) so the render/video groups apply.
set -e
cd "$(dirname "$0")"

echo "== build dependencies =="
sudo apt-get update
sudo apt-get install -y build-essential ocl-icd-opencl-dev opencl-headers \
  libssl-dev clinfo git mesa-opencl-icd

if [[ "$1" == "--rocm" ]]; then
  echo "== AMD ROCm OpenCL runtime =="
  CODENAME="$(. /etc/os-release; echo "$VERSION_CODENAME")"
  # If this link 404s, grab the current amdgpu-install .deb from
  # https://repo.radeon.com/amdgpu-install/  and 'sudo apt install ./<file>.deb'
  URL="https://repo.radeon.com/amdgpu-install/6.2.2/ubuntu/${CODENAME}/amdgpu-install_6.2.60202-1_all.deb"
  if wget -q "$URL" -O /tmp/amdgpu-install.deb; then
    sudo apt-get install -y /tmp/amdgpu-install.deb
    sudo amdgpu-install -y --usecase=opencl --opencl=rocr --no-dkms || true
    sudo usermod -aG render,video "$USER"
    echo ">> ROCm OpenCL installed. LOG OUT/IN (or reboot) before mining."
    echo ">> The 6600 XT is gfx1032; run the miner with HSA_OVERRIDE_GFX_VERSION=10.3.0 (see below)."
  else
    echo "!! amdgpu-install download failed — see https://repo.radeon.com/amdgpu-install/ for the current .deb"
  fi
fi

echo "== building veil-miner-sha-amd =="
make

echo
echo "== OpenCL devices detected =="
clinfo -l 2>/dev/null || echo "(clinfo found no platforms yet)"

cat <<'TIP'

--------------------------------------------------------------------
If your Radeon RX 6600 XT is listed above, start mining:

  ./veil-miner-sha-amd -o stratum+tcp://veil.yadaminers.pl:3333 -u YOUR_VEIL_ADDR -p x

If ROCm was just installed, the 6600 XT needs the gfx1030 override:

  HSA_OVERRIDE_GFX_VERSION=10.3.0 ./veil-miner-sha-amd -o stratum+tcp://veil.yadaminers.pl:3333 -u YOUR_VEIL_ADDR -p x

If NO AMD GPU is listed, install the AMD runtime and log out/in:

  ./setup-ubuntu.sh --rocm
--------------------------------------------------------------------
TIP
