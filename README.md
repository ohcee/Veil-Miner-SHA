# Veil-Miner-SHA

![build](https://github.com/ohcee/Veil-Miner-SHA/actions/workflows/build.yml/badge.svg)

GPU miner for Veil (VEIL), SHA256D only. No dev fee. NVIDIA and AMD.

Veil's SHA256D is its ASIC slot, but no ASICs actually mine it (the whole
network is a fraction of a single modern ASIC), so a GPU can take a real
share of that block reward. This repo ships a miner for each vendor:

* **NVIDIA (CUDA):** a stripped-down ccminer at the repository root
* **AMD (OpenCL):** a small standalone miner in [`opencl/`](opencl/)

Both speak the Veil `sha256dv` stratum protocol used by the yadaminers pool.

## Quick start, AMD (Ubuntu 22.04)

```bash
git clone https://github.com/ohcee/Veil-Miner-SHA.git
cd Veil-Miner-SHA/opencl
./setup-ubuntu.sh --rocm      # build deps + AMD OpenCL runtime + build the miner
# log out and back in so the render/video group applies, then:
HSA_OVERRIDE_GFX_VERSION=10.3.0 ./veil-miner-sha-amd \
    -o stratum+tcp://veil.yadaminers.pl:3333 -u YOUR_VEIL_ADDRESS -p x
```

The `HSA_OVERRIDE_GFX_VERSION=10.3.0` is only needed on RDNA2 cards such as
the RX 6600 XT. The miner auto-selects the first AMD GPU, so on a mixed rig it
leaves NVIDIA cards to ccminer. See [`opencl/README.md`](opencl/README.md) for
device selection, tuning flags, and the HiveOS package.

### Prebuilt binary (skip the build)

You still need an AMD OpenCL runtime (`./setup-ubuntu.sh --rocm`, or
`amdgpu-install --usecase=opencl`), but you can skip compiling:

```bash
wget https://github.com/ohcee/Veil-Miner-SHA/releases/latest/download/veil-miner-sha-amd-linux-x64.tar.gz
tar xzf veil-miner-sha-amd-linux-x64.tar.gz && cd veil-miner-sha-amd
HSA_OVERRIDE_GFX_VERSION=10.3.0 ./veil-miner-sha-amd \
    -o stratum+tcp://veil.yadaminers.pl:3333 -u YOUR_VEIL_ADDRESS -p x
```

## Quick start, NVIDIA

Needs the NVIDIA driver and the CUDA toolkit (12.x).

```bash
git clone https://github.com/ohcee/Veil-Miner-SHA.git
cd Veil-Miner-SHA
./autogen.sh && ./configure.sh && make -j$(nproc)
./ccminer -a sha256dv -o stratum+tcp://veil.yadaminers.pl:3333 -u YOUR_VEIL_ADDRESS -p x
```

Building from source needs the CUDA 12.x toolkit (the tree targets sm_75 through
sm_90). If you only have the stock Ubuntu apt CUDA (11.5), use the prebuilt binary.

### Prebuilt binary (skip the build)

Needs only the **NVIDIA driver** (`libcudart` is bundled), plus two small libs:

```bash
sudo apt install -y libcurl4 libjansson4
wget https://github.com/ohcee/Veil-Miner-SHA/releases/latest/download/veil-miner-sha-nvidia-linux-x64.tar.gz
tar xzf veil-miner-sha-nvidia-linux-x64.tar.gz && cd veil-miner-sha-nvidia
./run.sh -o stratum+tcp://veil.yadaminers.pl:3333 -u YOUR_VEIL_ADDRESS -p x
```

`run.sh` sets `LD_LIBRARY_PATH` and passes `-a sha256dv` for you.

## Verify a download

Every release ships a `SHA256SUMS.txt` file written by the same CI job that built the
release, covering every file attached to it: both tarballs, the bare
`veil-miner-sha-amd` executable and the `veil_sha256dv.cl` kernel. Fetch it from the
release you downloaded from and check your download against it:

```bash
wget https://github.com/ohcee/Veil-Miner-SHA/releases/latest/download/SHA256SUMS.txt
sha256sum -c --ignore-missing SHA256SUMS.txt
```

`--ignore-missing` skips whatever you did not download. You want a line ending
in `OK`. Anything else means the file is not what CI built, so do not run it.

Releases up to v0.1.6 shipped this file as `SHA256SUMS` with no extension, and it
covered only the two tarballs.

## Algorithm

Veil SHA256D hashes an 80 byte header:

```
version_le(4) | midstate_be(32) | merkle_le(32) | ntime_le(4) | nonce_lo_le(4) | nonce_hi_le(4)
```

`midstate = SHA256d(prevhash | witnessMerkleRoot | accumulators | nBits)` and the
block nonce is the full 64 bit `(nonce_hi << 32) | nonce_lo`. The pool assembles
the block and hands over the midstate and merkle root in a custom 11 field
`mining.notify`, so the miner only rolls the nonce. No coinbase or merkle branch
work happens on the miner side.

## Status

Both miners are proven on live chains, not only in CI:

* **AMD (OpenCL):** pool accepted shares on the live pool, and real testnet blocks
  solo mined through a local node at a hard share target.
* **NVIDIA (CUDA):** real testnet blocks solo mined on an RTX 3060 and an RTX 3080 Ti,
  and on 2026-08-22 an RTX 3080 Ti mined **mainnet block 3968142**, the first GPU
  mined Veil SHA256D block on mainnet.

Use v0.1.5 or later. Earlier builds only swept a 32 bit slice of the 64 bit Veil
nonce, which was enough for testnet but could not find blocks at mainnet difficulty.
The sha256d kernel is checked against OpenSSL, and every push is built by CI (a CUDA
job for the NVIDIA tree, an OpenCL job for the AMD host).

## License

GPLv3, inherited from ccminer. See [`LICENSE.txt`](LICENSE.txt).
