# DeepSeek V4.1 Flash on 168

## Fast path

```bash
cd /mapdata1/tools/ds4-main
./run-v41.sh -p "用一句中文介绍你自己。" -n 64 --nothink --temp 0
```

- `DS4_CUDA_NO_DIRECT_IO=1` reads through the host page cache.
- `DS4_CUDA_KEEP_MODEL_PAGES=1` stops the loader from dropping those pages.
- `DS4_CUDA_LOAD_THREADS=6` spreads expert misses over six reader threads.
- `DS4_CUDA_NO_ATTN_Q_B_F16_CACHE=1` and
  `DS4_CUDA_NO_ATTENTION_OUTPUT_F16_CACHE=1` trade the optional Q8->F16
  pre-dequant cache (~3.7 GiB) for a much larger expert cache.

Measured on one RTX 4090, short prompt, 128 generated tokens:
prefill `10.5 t/s`, generation `13.2-14.2 t/s`, steady-state expert-cache hit
rate ~75-82%.

## Where the time goes

Instrumentation (`DS4_V41_STEP_PROFILE=1`, `DS4_CUDA_LOAD_PROFILE=1`) shows the
decode step is not compute bound:

| stage | ms/token |
|---|---|
| expert misses -> pinned buffer -> H2D | 40-55 |
| GPU kernels (attention + 40 MoE layers) | 17-20 |
| per-layer stream sync | 5 |
| logits readback | 0.8 |
| Engram wait | 0.02 |

The GPU is idle most of the time. Each token routes 240 experts
(40 layers x 6); a cache miss costs ~9.5 MiB of PCIe traffic.
At 887 cache slots the miss rate is 20-45%, i.e. 400-1100 MiB/token.

## Progression

| configuration | prefill | generation |
|---|---|---|
| original O_DIRECT streaming | 2.47 | 2.35 |
| page cache, pread staging | 4.00 | 1.87 |
| page cache, mmap direct copy | 4.98 | 5.06 |
| warmed pages + mmap direct | 5.53 | 5.25 |
| + parallel expert loader (4 threads) | 9.30 | 10.48 |
| + 6 threads, bigger cache, no Q8-F16 caches | 10.5 | **13.2-14.2** |

## Cold cache

The fast path expects the 340.6 GiB GGUF to be resident in RAM.

```bash
./warm-v41.sh
```

Four parallel readers, about 2 minutes; `fincore` reached 336.6/340.6 GiB.

## SSD fallback

```bash
./run-v41-ssd.sh -p "..." -n 64 --nothink --temp 0
```

O_DIRECT path, about `2.35 t/s` generation.

## Local source changes (reapply after upstream updates)

1. `ds4_cuda.cu`: CUDA expert-cache safety reserve 8 GiB -> 1 GiB.
2. `ds4_cuda.cu`: persistent 6-thread parallel expert loader. Misses are split
   into pinned-buffer tasks, fanned out, each read with pread and copied H2D on
   its own stream. Env: `DS4_CUDA_LOAD_THREADS`, `DS4_CUDA_LOAD_BUF_MB`,
   `DS4_CUDA_DISABLE_PARALLEL_LOAD`.
3. `ds4_cuda.cu`: model arena chunks now exact for requests >= 8 MiB and 512
   MiB otherwise, instead of always 1792 MiB.
4. `ds4_cuda.cu`: prefetch path honors `DS4_CUDA_KEEP_MODEL_PAGES`.
5. `ds4_cuda.cu`: optional `DS4_CUDA_MMAP_STREAM_COPY` (mmap -> H2D direct).
   Kept for experiments, not used by the scripts.
6. `ds4.c`: env-gated step profiling (`DS4_V41_STEP_PROFILE`) and CUDA memory
   tracing (`DS4_MEM_TRACE`).
7. `download_model.sh`: refreshed the stale V4.1 Q2 SHA-256.

The Q8-F16 cache is a stock upstream knob, not a local patch.

## Notes

- V4.1 CUDA streaming is single-GPU per process (`g_n_gpus != 1` is rejected).
  Multi-GPU uses multi-process expert parallel; see `TP-MULTI-RANK.md`.
- Decode is PCIe-bound: 240 experts/token x 9.5 MiB at ~16 GiB/s. Larger caches
  and fewer F16 duplicates are the remaining single-rank levers.

## V4.1 CUDA streaming cache budget (2026-10-22)

The --ssd-streaming-cache-experts N option is a decode-cache target. The
generic prefill path reserves two full expert layers inside that same target
for MMQ staging. V4.1 CUDA already stages prefill experts in its own compact
arena and frees it before decode, so the reserve was counted twice: with 768
requested, memory admission re-fitted the target to 720, then split it into
6.66 GiB prefill reserve plus 0.01 GiB decode cache, collapsing decode to 6-12
expert slots per card.

Skip the reservation only for V4.1 CUDA streaming. The prefill arena is
allocated on demand and released on the first decode step. Measured on 4x
RTX 4090, ctx=131072, prefill-chunk=2048:

| cache target | short prompt, 128 tok | 60k prompt + 256 tok | steady decode |
|---|---:|---:|---:|
| 512 (before) | 15.5 t/s | - | 25.9-27.3 t/s |
| 640 | 18.2-18.8 t/s | - | 26.8-28.6 t/s |
| 768 (after fix) | 18.1-18.8 t/s | 80.0 s wall, 861 t/s prefill | 26-28.4 t/s |

640 is the deployment default: it captures the decode gain without asking
admission to trim 768 at startup. The runtime still expands the cache to the
largest count that fits after context buffers are allocated.

Rejected experiments: prefill-chunk=1024 (mixed/no consistent gain: fewer
decode slots and a short-prompt regression; the 3.78 GiB workspace is not
chunk-sized) and choosing the shared-expert owner by lowest local routed load
(identical wall time; gate waits are dominated by the slowest routed-expert
count, not the one shared expert).

## TP shared-memory startup race (2026-10-22)

Workers attached the CUDA TP slab as soon as `shm_open` found the leader's
name. The leader creates that name before calling `ftruncate`, so a worker
could map an incompletely sized object; `cudaHostRegister` then failed and
the worker silently fell back to pinned staging. In practice all three
workers took the fallback on a normal concurrent start.

Wait for `fstat(fd).st_size` to reach the negotiated slab size before mapping.
With workers delayed past the leader's `ftruncate`, ranks 1-3 report the
shared-memory gate data plane active and short-prompt decode rises from
16.3-16.5 to 16.9-17.1 t/s. The remaining TP profile is 80 gates/token with
about 4.0-4.6 ms GPU sync and 13-31 ms exchange; exchange is dominated by the
slowest rank's routed-expert work, not by the data plane itself.

## Multi-rank TP (4/8 GPUs)

V4.1 Flash now supports expert-parallel TP on 4 or 8 GPUs. See
`TP-MULTI-RANK.md` for launch commands, measured t/s, and troubleshooting.
