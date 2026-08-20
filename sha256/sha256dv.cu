/**
 * Veil SHA256D (sha256dv)
 *
 * Veil hashes a custom 80 byte header:
 *
 *   version_le(4) | midstate_be(32) | merkle_le(32) | ntime_le(4) | nonce_lo_le(4) | nonce_hi_le(4)
 *
 * where midstate = SHA256d(prevhash | witnessMerkleRoot | accumulators | nBits)
 * (supplied by the pool) and the block nonce is the full 64 bit
 * (nonce_hi << 32) | nonce_lo.
 *
 * Structurally this is Bitcoin sha256d with the last two header words being
 * the 64 bit nonce instead of nbits + 32 bit nonce, so we reuse the tuned
 * cuda_sha256d.cu kernel unchanged. The kernel sweeps message word 19; on
 * Veil that word maps to swab32(nonce_hi), so we seed it from the pool base
 * and recover nonce_hi = swab32(found).
 */

#include <string.h>
#include <miner.h>
#include <cuda_helper.h>
#include <openssl/sha.h>

// reuse the stock sha256d device kernel and its host driver
extern void sha256d_init(int thr_id);
extern void sha256d_free(int thr_id);
extern void sha256d_setBlock_80(uint32_t *pdata, uint32_t *ptarget);
extern void sha256d_hash_80(int thr_id, uint32_t threads, uint32_t startNonce, uint32_t *resNonces);
extern "C" void sha256d_hash(void *output, const void *input);

static bool init[MAX_GPUS] = { 0 };

// Build the 80 byte Veil stage2 header from the job fields.
static void veil_build_stage2(uint8_t out[80], const struct work *work,
                              uint32_t nonce_lo, uint32_t nonce_hi)
{
	uint8_t *p = out;
	le32enc(p, work->veil_version);           p += 4;   // version (little endian)
	memcpy(p, work->veil_midstate_be, 32);    p += 32;  // midstate, big endian as-is
	for (int i = 0; i < 32; i++) p[i] = work->veil_merkle_be[31 - i];
	p += 32;                                             // merkle, reversed to little endian
	le32enc(p, work->veil_ntime);             p += 4;
	le32enc(p, nonce_lo);                     p += 4;
	le32enc(p, nonce_hi);                     p += 4;
}

extern "C" int scanhash_sha256dv(int thr_id, struct work* work, uint32_t max_nonce, unsigned long *hashes_done)
{
	uint32_t _ALIGN(64) blk[20];
	uint8_t  stage2[80];
	uint32_t *ptarget = work->target;
	const uint32_t nonce_lo = 0;   // GPU sweeps the high word; keep the low word fixed
	uint32_t throughput = cuda_default_throughput(thr_id, 1U << 25);

	if (opt_benchmark)
		ptarget[7] = 0x03;

	if (!init[thr_id]) {
		cudaSetDevice(device_map[thr_id]);
		if (opt_cudaschedule == -1 && gpu_threads == 1) {
			cudaDeviceReset();
			cudaSetDeviceFlags(cudaDeviceScheduleBlockingSync);
			CUDA_LOG_ERROR();
		}
		gpulog(LOG_INFO, thr_id, "Intensity set to %g, %u cuda threads",
			throughput2intensity(throughput), throughput);
		sha256d_init(thr_id);
		init[thr_id] = true;
	}

	// Build the header once; the constant first 64 bytes feed the midstate.
	veil_build_stage2(stage2, work, nonce_lo, work->veil_nonce_hi);
	for (int k = 0; k < 20; k++)
		blk[k] = le32dec(stage2 + 4 * k);
	sha256d_setBlock_80(blk, ptarget);

	// The kernel iterates message word 19 == swab32(nonce_hi); seed from the pool base.
	const uint32_t first = be32dec(stage2 + 76);
	uint32_t n = first;
	if (init[thr_id])
		throughput = min(throughput, (max_nonce > first) ? (max_nonce - first) : throughput);

	do {
		*hashes_done = (uint64_t) n - first + throughput;

		sha256d_hash_80(thr_id, throughput, n, work->nonces);
		if (work->nonces[0] != UINT32_MAX) {
			uint32_t _ALIGN(64) vhash[8];
			const uint32_t N = work->nonces[0];
			const uint32_t nonce_hi = swab32(N);

			// CPU re-verify with the found nonce over the real 80 byte header.
			veil_build_stage2(stage2, work, nonce_lo, nonce_hi);
			sha256d_hash(vhash, stage2);
			if (vhash[7] <= ptarget[7] && fulltest(vhash, ptarget)) {
				work->valid_nonces = 1;
				work->veil_nonce_hi = nonce_hi;
				work->veil_nonce_lo = nonce_lo;
				work_set_target_ratio(work, vhash);
				*hashes_done = (uint64_t) n - first + throughput;
				return 1;
			}
			else {
				gpu_increment_reject(thr_id);
				if (!opt_quiet)
					gpulog(LOG_WARNING, thr_id, "result for %08x does not validate on CPU!", N);
				// rebuild the base header (verify overwrote the nonce bytes)
				veil_build_stage2(stage2, work, nonce_lo, work->veil_nonce_hi);
			}
		}

		if ((uint64_t) throughput + n >= max_nonce) {
			n = max_nonce;
			break;
		}
		n += throughput;

	} while (!work_restart[thr_id].restart);

	*hashes_done = (uint64_t) n - first;
	return 0;
}

extern "C" void free_sha256dv(int thr_id)
{
	if (!init[thr_id])
		return;
	cudaThreadSynchronize();
	sha256d_free(thr_id);
	init[thr_id] = false;
	cudaDeviceSynchronize();
}
