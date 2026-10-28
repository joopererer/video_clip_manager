# AI Stability and Player UX Report

Branch: `feat/dark-ui-workspace` (started from `dc41489`).
Status: **in progress.** Not merged to master. No GitHub Release created.

Legend: **Automated** = ran in `flutter test` / `flutter analyze`. **Build** = compiled. **Reproduced** = I ran the real tool on this machine and saw the result. **Manual** = a person ran it on a real window. **Not verified** = not done.

## 0. Recorded user acceptance (Stage 5 preview round)

The user reported, from manual testing on a real Windows desktop, that the original-video preview acceptance passed 8/8:

1. Landscape and portrait playback.
2. Local video and M3U8 playback.
3. Seek, mute, fullscreen, Esc.
4. Create clip from the preview.
5. Play and Create Clip entry points are separated.
6. Ten consecutive open/close cycles: no black screen, crash or leftover audio.

This is **user manual acceptance**. I did not run these checks.

## 1. Audit (done before any code change)

Environment on this machine: Flutter 3.41.7, Windows 10.0.26200, `ffmpeg.exe` at `D:\ffmpeg\bin\ffmpeg.exe` on PATH. Sidecar `local-media-ai.exe` exists in `D:\workspace\local-media-ai\target\{debug,release}` (outside this repo). I did not read the sidecar source, so statements about its behavior below come from running it, not from reading it. User clip data was read only (`videoPath/start/end` fields). Paths below are anonymised.

### 1.1 Call chain

```
AiSettingsDialog "为所有片段构建特征"
  -> AppState.indexAllClips()                      lib/data/app_state.dart
     -> DeltaEngine.syncClipRange()                lib/services/delta_engine.dart
        -> FrameEmbeddingPool.loadFromDisk()       lib/services/frame_embedding_pool.dart
        -> AiService.extractClipFrames()           Process.run(local-media-ai extract-clip ...)
        -> AiService.embedFrames()                 Process.run(local-media-ai embed-frames ...)
        -> FrameEmbeddingPool.saveToDisk()         swallows every exception
```

There is no separate frame-extraction service. FFmpeg is called by the `local-media-ai` sidecar, not by Dart.

### 1.2 A. LM Studio connection

Official documentation (https://lmstudio.ai/docs/developer/openai-compat and https://lmstudio.ai/docs/developer/core/server, fetched 2026-10-28):

- The server is started from the Developer tab ("Start server") or `lms server start`; default `http://localhost:1234`.
- OpenAI-compatible endpoints: `GET /v1/models`, `POST /v1/chat/completions`. Base URL is `http://localhost:1234/v1`.
- The `model` field must be the model identifier LM Studio shows. By default no API key is required, but the server can be configured to require a token.

The app preset (`http://localhost:1234/v1`, chat at `<base>/chat/completions`) matches the documentation.

Evidence collected here:

| Check | Result |
|---|---|
| TCP connect `127.0.0.1:1234` | closed |
| TCP connect `127.0.0.1:11434` | open |
| Process matching `lm.?studio` | none running |
| Process matching `ollama` | none running |
| Process matching `llama` | `llama-server` (PID 10984) |
| User PowerShell diagnostic (from the user) | `127.0.0.1:1234` TCP failed, `/v1/models` unreachable |

Conclusion: errno 1225 (`ERROR_CONNECTION_REFUSED`) is the correct answer for "nothing listens on 1234". **This is an environment state, not a program bug**: LM Studio's API server is not running (or listens on another port). What the program does wrong is the message: it shows a raw `SocketException` and never calls `/v1/models`, so "server down", "wrong port", "model not loaded", "wrong model id", and "API key required" all look alike.

Second finding: on this machine nothing named `ollama` is running, while `llama-server` answers on 11434. The connection test auto-starts the built-in llama.cpp server when the URL contains port 11434 (`ensureBuiltInLlamaServerRunning`). So a passing "Ollama" test may be the app's built-in llama.cpp server, not Ollama. I cannot tell from the process list who started PID 10984.

### 1.3 B. EmbeddingGemma 2 download and verification

Actual program: `scripts/fetch_embedding_models.ps1`, started by `AiSettingsDialog._runDownloadScript` as `powershell -NoProfile -ExecutionPolicy Bypass -File <script> -OutDir models -Mirror https://hf-mirror.com`, with **no `workingDirectory`** (inherits the app's cwd).

Defects found in code:

1. **Check dir and download dir are computed differently.** "Ready" comes from `AiService.resolveEmbeddingModelDir()` (several candidate dirs, including hard-coded `D:\workspace\...` paths). The download always uses the literal relative `models`, i.e. `<process cwd>\models`.
2. **stderr is never read.** `Invoke-WebRequest` failures are written to stderr under `$ErrorActionPreference = 'Stop'`. The app only listens to stdout, so the UI shows `下载退出代码: 1` with no cause.
3. **The script is not shipped.** The Release output folder contains no `scripts\` folder. The script is found only through hard-coded developer paths.
4. **"Ready" means two files exist** (`tokenizer.json`, `onnx/model_quantized.onnx`). Size and sha256 are not checked, and the vision encoder files are ignored.
5. The label "重新校验 / 更新" always runs the download script, so "verify" and "download" are one action and can contradict the green "已就绪" badge.

Reproduced:

| Run | Result |
|---|---|
| Script from repo root, `-OutDir models`, all files present | exit 0, all 10 files `already present, sha256 ok`, 3.3 s, no files touched |
| Script with cwd = empty temp dir, mirror unreachable | exit 1, `Invoke-WebRequest : 无法连接到远程服务器` on stderr, no file written |

I **could not reproduce the user's exact failure**. The most likely chain, consistent with the code but **unproven**: the app is started from a folder whose `models\` is empty, "ready" is true through a fallback dir, the button downloads into `<cwd>\models`, the mirror is unreachable, exit 1. Diagnostic steps for the user are in section 7.

Existing model files in `models\` are intact: all 10 files match the manifest sizes and the script confirmed sha256.

### 1.4 C. Vector index build failure

The message `抽取视频帧失败: ` (empty tail) is reproduced exactly by the code path below.

`AiService.extractClipFrames` throws `Exception('抽取视频帧失败: ${res.stderr}')`. The sidecar writes its error as JSON on **stdout** (`{"ok":false,"error":...}`) and leaves stderr empty. The real reason is dropped.

I ran the real sidecar once per local clip in the user's database (6 local clips, same arguments `indexAllClips` produces: `--every-ms 2000 --max-frames 12 --max-edge 768`):

| Clip | start / end (ms) | Result |
|---|---|---|
| #2 | 21708 / 89998 | exit 0, 12 frames |
| #3 | 226305 / 593237 | exit 0, 12 frames |
| #4 | 1863 / 10604 | exit 0, 4 frames |
| #5 | 9833 / 90651 | exit 0, 12 frames |
| #6 | 87500 / 421033 | exit 0, 12 frames |
| #8 | 41900 / 107266 | exit 0, 12 frames |
| **#1** | **0 / 0** | **exit 1**, 0 frames |

Clip #1 stdout (stderr empty):

```
{"ok": false, "error": "ffmpeg 执行失败: ... -to value smaller than -ss; aborting. ... Error opening input files: Invalid argument"}
```

**Root cause 1 (proven):** a clip with `end == 0` means "to the end of the video" elsewhere in the app (`ClipPlaybackScreen` only enforces the end when `endTime > Duration.zero`). `indexAllClips` passes `end = 0`, FFmpeg gets `-to 0` with `-ss 0`, fails, and the exception aborts the whole loop. A zero-length request at `100000/100000` also returns exit 1 / 0 frames.

**Root cause 2 (proven):** one failing clip aborts every remaining clip (`try` wraps the whole `for`). Clips processed earlier are already saved to disk, but the remaining ones are never attempted, and the message does not say which clip or why.

**Root cause 3 (output proven, separate bug): relative vs absolute time label.** The sidecar's `t_ms` is absolute when its `method` is `Seek` but **relative to `--start-ms` when `method` is `Filter`**. What is proven is the numbers the sidecar returns and that the app stores them unchanged. I did **not** verify that the image pixels of a `Filter` frame come from the expected source second (a frame-content comparison was attempted and not completed), so only the timestamp label is claimed to be wrong:

| Request (start-end ms) | method | `t_ms` returned |
|---|---|---|
| 87500 - 421033 | Seek | 101400, 129200, ... (absolute) |
| 100000 - 108000 | Filter | 0, 2000, 4000, 6000 (relative) |
| 9000 - 15000 | Filter | 0, 2000, 4000 (relative) |
| 1863 - 10604 | Filter | 4, 2004, 4004, 6004 (relative) |

`DeltaEngine` stores `t_ms` as returned and `FrameEmbeddingPool` documents it as absolute source time. The cache file for clip #4 on this machine confirms the damage: its frames are stored at 4, 2004, 4004, 6004 although the clip starts at 1863. Short clips (< ~10 s, the `Filter` path) are therefore stored with clip-relative timestamps, and `getFramesInRange(source start, source end)` will not find them or will match the wrong range. The method switch point (~10 s) is inferred from four requests, not from the sidecar source, which I did not read. This conflates clip-relative time with source time, which AGENTS.md forbids.

Other checks:

- FFmpeg present and found by the sidecar (`doctor`: `ffmpeg_found: true`). The Release folder does not contain `local-media-ai.exe`; the sidecar is found only through hard-coded developer paths or `PATH`. On a machine without it, `Process.run` throws `ProcessException`, which today also becomes the vague message.
- `indexAllClips` skips http(s) clips and missing files before calling the sidecar, so M3U8/online clips are not extracted. Unicode paths (a Korean file name and a path with `#`) and a 720p source worked. I did not have a portrait local file in this database; portrait extraction is **not verified**.
- `FrameEmbeddingPool.saveToDisk` writes the cache file in place and swallows every exception. A failed or interrupted write can truncate an existing cache, and storage failures are invisible.
- Existing design limit (not changed): `syncClipRange` asks the sidecar for `minMissing..maxMissing` with `--max-frames 12`. Long clips yield 12 spread-out frames, not one per 2 s, so `planDelta` still sees "missing" timestamps on the next run and re-extracts. The incremental mechanism is kept as is.

### 1.5 Existing AI model download behaviour (the "unified download" question)

There was never one unified downloader. Today there are two separate PowerShell scripts called from the same dialog:

| Model | Script | Detection | Download button |
|---|---|---|---|
| EmbeddingGemma 2 (~530 MB) | `fetch_embedding_models.ps1` | `tokenizer.json` + `onnx/model_quantized.onnx` in a candidate dir | Always shown ("一键下载" or "重新校验 / 更新") |
| Qwen2-VL 2B GGUF (~2.2 GB) | `fetch_qwen2vl_models.ps1` | two `.gguf` files in a candidate dir | Shown only in Ollama mode when missing |

`MainScreen` also shows a "go download" prompt when semantic search is used without the embedding model. So detection plus a download button exists, but detection is existence-only and the download path is fragile as described in 1.3.

(Sections 2 onward are added as each task is completed.)
