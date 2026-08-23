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
 *
 * The sweep covers the whole 64 bit nonce. Word 19 is the inner loop on the
 * GPU; every time it wraps we step nonce_lo (word 18). Word 18 sits in the
 * second SHA block, so only the 16 byte tail changes and the midstate stays
 * put. State persists across scanhash calls so a call continues where the
 * last one stopped instead of re-hashing the same slice, and after a hit it
 * carries on past the hit instead of finding it again.
 */

#include <string.h>
#include <stdlib.h>
#include <time.h>
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

// Where the sweep is, kept between scanhash calls.
struct veil_scan_state {
	uint8_t  key[72];    // version | midstate | merkle | ntime
	uint32_t nonce_lo;   // header word 18, stepped each time word 19 wraps
	uint32_t next_w19;   // next message word 19 (== swab32(nonce_hi)) to hash
	bool     have_key;
};
static veil_scan_state scan_state[MAX_GPUS];

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

// Everything that identifies a job, so a new job is detected by content.
// veil_nonce_hi is deliberately left out: a hit overwrites it with the
// solving nonce, and keying on it would make that hit look like a new job
// and restart the sweep right on top of it.
static void veil_job_key(uint8_t key[72], const struct work *work)
{
	uint8_t *p = key;
	le32enc(p, work->veil_version);           p += 4;
	memcpy(p, work->veil_midstate_be, 32);    p += 32;
	memcpy(p, work->veil_merkle_be, 32);      p += 32;
	le32enc(p, work->veil_ntime);
}

// Upload the header for the given nonce_lo. Word 19 is swept by the kernel,
// so its value here is irrelevant.
static void veil_load_block(const struct work *work, uint32_t nonce_lo, uint32_t *ptarget)
{
	uint32_t _ALIGN(64) blk[20];
	uint8_t  stage2[80];
	veil_build_stage2(stage2, work, nonce_lo, 0);
	for (int k = 0; k < 20; k++)
		blk[k] = le32dec(stage2 + 4 * k);
	sha256d_setBlock_80(blk, ptarget);
}

extern "C" int scanhash_sha256dv(int thr_id, struct work* work, uint32_t max_nonce, unsigned long *hashes_done)
{
	uint8_t  stage2[80];
	uint8_t  key[72];
	uint32_t *ptarget = work->target;
	uint32_t throughput = cuda_default_throughput(thr_id, 1U << 25);
	veil_scan_state &st = scan_state[thr_id];

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
		// The miner's half of the 64 bit nonce starts somewhere random so
		// several miners on one proxy do not grind the same pairs.
		st.nonce_lo = (uint32_t) rand() ^ ((uint32_t) time(NULL) << 8) ^ ((uint32_t) thr_id * 0x9E3779B9u);
		st.have_key = false;
		init[thr_id] = true;
	}

	// New job: word 19 restarts from the pool's lane start. nonce_lo keeps
	// counting across jobs; any value is valid, it only has to differ between
	// miners that share a proxy.
	veil_job_key(key, work);
	if (!st.have_key || memcmp(key, st.key, sizeof(key)) != 0) {
		memcpy(st.key, key, sizeof(key));
		st.have_key = true;
		st.next_w19 = swab32(work->veil_nonce_hi);
	}

	veil_load_block(work, st.nonce_lo, ptarget);

	uint32_t n = st.next_w19;
	uint64_t done = 0;
	// hashes for this call: ccminer's scan time budget (our start nonce is
	// always 0, so max_nonce is a plain count), at least one batch
	uint64_t budget = max_nonce ? (uint64_t) max_nonce : (uint64_t) throughput * 64;
	if (budget < throughput) budget = throughput;

	do {
		sha256d_hash_80(thr_id, throughput, n, work->nonces);
		done += throughput;

		if (work->nonces[0] != UINT32_MAX) {
			uint32_t _ALIGN(64) vhash[8];
			const uint32_t N = work->nonces[0];
			const uint32_t nonce_hi = swab32(N);

			// CPU re-verify with the found nonce over the real 80 byte header.
			veil_build_stage2(stage2, work, st.nonce_lo, nonce_hi);
			sha256d_hash(vhash, stage2);
			if (vhash[7] <= ptarget[7] && fulltest(vhash, ptarget)) {
				work->valid_nonces = 1;
				work->veil_nonce_hi = nonce_hi;
				work->veil_nonce_lo = st.nonce_lo;
				work_set_target_ratio(work, vhash);
				*hashes_done = done;
				// resume past this batch next call, never back onto the hit
				uint32_t next = n + throughput;
				if (next < n) st.nonce_lo++;
				st.next_w19 = next;
				return 1;
			}
			else {
				gpu_increment_reject(thr_id);
				if (!opt_quiet)
					gpulog(LOG_WARNING, thr_id, "result for %08x does not validate on CPU!", N);
			}
		}

		// next batch; when word 19 wraps, step nonce_lo and reload the tail
		uint32_t next = n + throughput;
		if (next < n) {
			st.nonce_lo++;
			veil_load_block(work, st.nonce_lo, ptarget);
		}
		n = next;

	} while (!work_restart[thr_id].restart && done < budget);

	st.next_w19 = n;
	*hashes_done = done;
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
