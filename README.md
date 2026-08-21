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

## Quick start, NVIDIA

Needs the NVIDIA driver and the CUDA toolkit (12.x).

```bash
git clone https://github.com/ohcee/Veil-Miner-SHA.git
cd Veil-Miner-SHA
./autogen.sh && ./configure.sh && make -j$(nproc)
./ccminer -a sha256dv -o stratum+tcp://veil.yadaminers.pl:3333 -u YOUR_VEIL_ADDRESS -p x
```

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

* **AMD (OpenCL):** validated end to end against the live pool, with pool-accepted
  shares. The sha256d kernel is checked against OpenSSL.
* **NVIDIA (CUDA):** builds in CI and reuses ccminer's sha256d kernel unchanged. It
  shares the exact stratum and header code the AMD build proved live, and the
  endianness was reviewed line by line. Real-card run is pending.

Every push is built by CI (a CUDA job for the NVIDIA tree, an OpenCL job for the AMD host).

## License

GPLv3, inherited from ccminer. See [`LICENSE.txt`](LICENSE.txt).
