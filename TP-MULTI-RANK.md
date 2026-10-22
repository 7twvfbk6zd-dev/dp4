# DeepSeek V4.1 Flash 多卡 TP（168 机器实测）

## 结论

168 机器（8 x RTX 4090 24GB）上，V4.1 Flash 已从单卡/双卡扩展到 4 卡、8 卡专家并行（expert parallel）。

128 completion tokens、`temperature=0`、同一提示词的稳态 decode：

| 配置 | decode t/s | 128 token wall | 相对单卡 |
|---|---:|---:|---:|
| 1 卡 | 13.2 | - | 1.00x |
| 2 卡（50/50 expert + shm） | 26.4 | 6.0-7.0s | 2.00x |
| 4 卡（expert parallel） | 35.2 | 4.0-4.5s | 2.67x |
| 8 卡（expert parallel） | 38.5 | 3.8-4.3s | 2.92x |

8 卡最后 28 token 可到 39.4 t/s；4 卡最后 28 token 约 36.8 t/s。
8 卡相对 4 卡只提升约 9%，已经接近当前方案的扩展上限。

## 方案

4090 不支持 CUDA P2P（`cudaDeviceCanAccessPeer` 双向为 0），因此没有走 GPUDirect/IPC，而是：

- 每个 rank 一个进程、一张 GPU（`CUDA_VISIBLE_DEVICES=0..N-1`）。
- `/dev/shm` 共享段，每个 rank 一段；GPU 直接写自己的段。
- `cudaHostRegister(..., cudaHostRegisterMapped)` 把共享段映射给 GPU。
- FFN gate 由 CPU 汇总所有 rank 的分片，再写回本 rank 的输入段。
- 用 release/acquire 原子 ready flag 做逐 gate 同步。

4/8 卡采用 **expert parallel**：

- attention、shared expert 以外的非专家权重整卡复制。
- routed experts 按 rank 连续分片：384 / world。
- 每层 FFN 做 N 路归约。
- shared expert 按 `rank == layer % world` 轮转，只算一次。
- logits 由 rank0 计算，不做 vocab split。

2 卡仍保留原来的 50/50 expert + attention head split 路径。

## 启动

### 2 卡

```bash
cd /mapdata1/tools/ds4-main
bash launch-tp2.sh
```

### 4 卡

```bash
cd /mapdata1/tools/ds4-main
DS4_TP_WORLD=4 bash launch-epn.sh
```

### 8 卡

```bash
cd /mapdata1/tools/ds4-main
DS4_TP_WORLD=8 bash launch-epn.sh
```

三者都监听：

```text
http://127.0.0.1:18080/v1/chat/completions
model = deepseek-v4.1-flash
```

本机体验：

```bash
curl -s http://127.0.0.1:18080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"deepseek-v4.1-flash","messages":[{"role":"user","content":"你好"}],"max_tokens":128,"temperature":0}'
```

外部机器通过 SSH 隧道：

```bash
ssh -L 18080:127.0.0.1:18080 xszn@172.16.0.168
```

然后访问本机 `http://127.0.0.1:18080`。

## 关键环境变量

| 变量 | 说明 |
|---|---|
| `DS4_TP_WORLD` | rank 数，2/4/8；所有 rank 必须一致 |
| `DS4_TP_EXPERT_ONLY` | world>2 时必须为 1，启用 expert parallel |
| `DS4_TP_SHM` | 1，启用共享内存 gate 数据面 |
| `DS4_TP_RUN_ID` | 每次启动唯一；launch 脚本自动生成 |
| `DS4_TP_GATE_TIMEOUT_MS` | 单个 gate 等待上限；冷启动建议 30000，热态可降到 5000 |

日志：

```text
tp-leader.log
tp-worker1.log ... tp-workerN.log
```

正常应看到：

```text
ds4-tp: leader/worker rank x/N connected
ds4-tp: shared-memory gate data plane active: rank x/N
tensor parallelism bound: rank x/N, expert parallel (attention replicated)
```

## 已验证

8 卡环境下已抽查：

- 算术：`13*17` -> `221`
- 应用题：40 人、60% 男生、男生 25% 戴眼镜 -> `6 人`
- Python 原地快速排序，代码与注释正常
- 中文长文生成正常

## 排障

1. **`shm gate timeout ... ready=0`**
   - 确认所有进程使用同一个 `DS4_TP_RUN_ID`（用 launch 脚本启动即可）。
   - 确认 `/dev/shm/ds4tp-19090-*` 没有上一轮残留被 worker 抢先打开。
   - 冷启动首次专家加载可能超过 5s，使用 30s gate timeout。

2. **只有部分 worker 连上**
   - 所有 rank 的 `DS4_TP_WORLD` 必须一致。
   - world>2 必须设置 `DS4_TP_EXPERT_ONLY=1`。

3. **回滚到 2 卡**

```bash
bash launch-tp2.sh
```

4. **显存**

4 卡实测每卡约 22.5 GiB（expert cache 1024）；GPU4-7 空闲。
8 卡实测每卡约 23 GiB。

## 后续可优化方向

- 8 卡只有 6 个 routed expert/token，rank 间负载天然不均，gate 等待最慢 rank。
- 当前 gate 同步是逐层的，无法与下一层计算重叠；要再大幅提升需要流水线化 gate。
- 8 卡可以把机器拆成两组 4 卡实例，提高并发吞吐（单请求 35 t/s，双请求约 2x 聚合吞吐）。

## API 能力（168 实测）

- `/v1/models` 返回的模型 ID 是 `deepseek-v4.1-flash`，显示名是 `DeepSeek V4.1 Flash`。
- 旧别名 `deepseek-v4-flash` 仍可请求，但服务端会把它规范化为 `deepseek-v4.1-flash`；不传 `model` 也返回 V4.1 ID。
- 已支持 OpenAI `tools` / `tool_choice` / `tool_calls`，以及 `/v1/responses` 的 function call。
- V4.1 在 IQ2 + 4 卡专家并行下，`reasoning_effort=high/max` 叠加 tools 会退化出乱码。
  服务端会把“带 tools 的 high/max”自动降为 `medium`；也可显式传 `"reasoning_effort":"medium"` 或 `"thinking":false`。
- **图像推理不可用**：官方 `docs/MODELS.md` 明确写明 V4.1 vision 目前仅支持 Metal；CUDA 不支持。
  168 上加载视觉侧车后可以完成编码和 prefill，但语言模型输出是乱码；单卡大图还会在 expert prefill 处 OOM。
  因此 CUDA 启动参数不要加 `--vision`。未加载时图像请求返回：
  `image input requires starting ds4-server with --vision FILE`。
- 侧车文件 `DeepSeek-V4.1-Flash-Vision.gguf`（0.9 GiB）已下载并校验，可留给 Metal 机器使用；在 168 上不用加载。
- 需要图像能力时，实际可行的是：换 Metal Mac 跑 V4.1 vision，或另起一个 CUDA 支持的视觉模型（如 Qwen3.8-Flash-Next / GLM-5.3）做前置图像理解，再把文本交给 V4.1 Agent。
- 当前验证配置为 `--ctx 131072`（128K），长 Agent 可用，详见下一节。

最小 Agent 请求：

```bash
curl -s http://127.0.0.1:18080/v1/chat/completions -H 'Content-Type: application/json' -d '{
  "model":"deepseek-v4.1-flash",
  "messages":[{"role":"user","content":"北京天气怎么样？必须调用工具。"}],
  "tools":[{"type":"function","function":{"name":"get_weather","description":"查询天气","parameters":{"type":"object","properties":{"city":{"type":"string"}},"required":["city"]}}}],
  "tool_choice":"auto",
  "reasoning_effort":"medium",
  "max_tokens":256,
  "temperature":0
}'
```


## 长上下文（128K）实测与修复（2026-10-21）

### 关键 bug：TP 专家并行下 >=256 token 的 prefill 乱码

- 现象：4 卡 TP 时 prompt <=251 tokens 正常，>=257 tokens 全部乱码；同一提示词单卡 5K tokens 正常。
- 根因：`ds41_moe_batch()` 在 `tp_expert_world > 2` 时进入 routed MoE owned + aligned IQ2/Q2K fused 路径；
  该批次路径使用 slot 压缩后的 id 映射，256 行以上批量会损坏。
- 修复：`ds4_cuda.cu` 的 `routed_moe_launch()` 中，`owned_filtered && n_tokens > 8` 时跳过 aligned tier，
  回落到普通 mmq 路径；decode（n_tokens == 1）与短 append 仍保留 aligned。
- 验证：257 / 261 / 265 / 269 / 273 / 281 / 301 / 341 tokens 全部正确。

### 128K 启动

必须使用窄 prefill chunk：

```bash
cd /mapdata1/tools/ds4-main
DS4_TP_WORLD=4 DS4_CTX=131072 DS4_EXPERT_CACHE=768 bash launch-epn.sh
```

32K 宽 chunk 在约 126K 上下文时会因 staging 显存不足失败：

```text
ds4: CUDA SSD cache cannot stage 71 experts with system headroom
ds4: V4.1 layer-major prefill failed at layer 19
```

### 实测（4 卡，ctx=131072，cache=768，chunk=2048）

| prompt tokens | 召回 | wall |
|---:|---|---:|
| 14,729 | 正确 | 22.4s |
| 25,229 | 正确 | 32.0s |
| 50,429 | 正确 | 89.3s |
| 92,429 | 正确 | 125.0s |
| 126,029 | 正确 | 170.2s |

- prefill 平均约 744 t/s（126K 档）。
- decode：短上下文约 35 t/s，24K 约 14 t/s，126K 约 10.3 t/s。
- 长上下文 decode 变慢主要来自全序列 attention 与逐 token TP gate，属预期。

### 长 Agent 工具链（实测）

- 24,250 tokens + `tools`：`finish_reason=tool_calls`，参数 `get_weather({"city":"Chengdu"})`。
- 工具结果回填后第二轮：正常生成，`finish_reason=stop`。

### 编译注意

非登录 shell 里 `make` 会使用 `/usr/local/cuda`（13.3），而驱动只支持 12.8，
运行时会报 `ds4: cannot determine a safe V4.1 memory budget`。必须显式指定：

```bash
make cuda CUDA_ARCH=sm_89 CUDA_HOME=/mapdata1/tools/cuda-12.8
```
