# Veil-Miner-SHA

GPU miner for Veil (VEIL), SHA256D only. No dev fee.

Fork of [tpruvot/ccminer](https://github.com/tpruvot/ccminer) 2.3.1 (GPLv3),
stripped down to the Veil SHA256D algorithm and taught the Veil `sha256dv`
stratum protocol (custom `mining.notify`, 64 bit nonce, midstate + merkle
supplied by the pool).

**NVIDIA (CUDA):** the ccminer-derived miner at the repository root.
**AMD (OpenCL):** see [`opencl/`](opencl/).

Status: work in progress. See the `build` workflow for CI compile status.

## Algorithm

Veil SHA256D hashes an 80 byte header laid out as:

```
version_le(4) | midstate_be(32) | merkle_le(32) | ntime_le(4) | nonce_lo_le(4) | nonce_hi_le(4)
```

where `midstate = SHA256d(prevhash | witnessMerkleRoot | accumulators | nBits)`
and the block nonce is the full 64 bit `(nonce_hi << 32) | nonce_lo`.

## License

GPLv3, inherited from ccminer. See `LICENSE.txt`.
