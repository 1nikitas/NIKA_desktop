# NIKA — Local AI for your Mac

**English** · [Русский](README.ru.md)

**Chat offline. Ask your documents. Make it yours.**

A native macOS AI assistant built with **SwiftUI and llama.cpp**. Run local LLMs, work with your documents, and customize the desktop client to build your own assistant.

**No account needed for local chat. Works offline after model download. NIKA cloud is optional.**

![macOS 26+ · Apple Silicon](docs/assets/platform.svg)
![SwiftUI · Swift 6](docs/assets/swift.svg)

*Currently distributed as a source build. The app interface is in Russian.*

[Quick start](#quick-start) · [Local features](#what-runs-on-your-mac) · [Models](#local-models) · [Benchmarks](#benchmarks) · [Build on NIKA](#build-on-nika) · [Issues](https://github.com/1nikitas/NIKA_desktop/issues)

![NIKA's native macOS chat interface](docs/assets/conversation-dark.png)

<sub>Actual SwiftUI interface with a demonstration conversation.</sub>

**If NIKA is useful to you, [give it a star](https://github.com/1nikitas/NIKA_desktop) to support the project.**

## What runs on your Mac

- **Chat with local models.** Download a model or import a compatible GGUF and run it through llama.cpp.
- **Ask your documents.** Attach text documents and PDFs with extractable text. Image input requires a compatible vision projector.
- **Keep local history and memory.** Local conversations stay on your Mac. A local model error never silently sends the request to the cloud.
- **Work with Calendar and Reminders.** Review and confirm proposed local actions before they execute.
- **Use native Mac controls.** SwiftUI, multiple windows, a menu bar entry, keyboard shortcuts, and light and dark themes.

## Quick start

**Requires:** an Apple Silicon Mac, macOS 26+, Xcode 16.4+ with Swift 6, Python 3, and Homebrew.

Build from source:

```bash
brew install llama.cpp
git clone https://github.com/1nikitas/NIKA_desktop.git
cd NIKA_desktop
bash scripts/dev.sh
```

Then open **Локальные модели** (Local models), download **NIKA Smart**, and choose **Начать разговор** (Start conversation).

**Local chat needs no account.** The first build downloads WebRTC; model downloads are separate. Once a model is installed, local chat works offline.

This build uses an ad-hoc signature. A notarized release is not currently provided. [Full setup and development guide →](docs/DEVELOPMENT.en.md)

## Local models

The NIKA presets below use Qwen models. You can also import your own compatible GGUF.

| Model | In-app preset | Parameters | Quantization | File size |
| --- | --- | ---: | --- | ---: |
| **Qwen3.5-4B** | **NIKA Smart** | **4B** | **Q4_K_M** | **2.74 GB** |
| Qwen3.5-2B | NIKA Balance | 2B | Q5_K_M | 1.44 GB |
| Qwen3.5-4B | NIKA Quality | 4B | Q5_K_M | 3.14 GB |
| Qwen3.5-0.8B | NIKA Mini¹ | 0.8B | Q8_0 | 812 MB |
| Your own compatible GGUF | — | Model-dependent | Your choice | Model-dependent |

**Memory guidance:** physical **8 GB hardware has not yet been tested**. Based on memory estimates, start with Smart and a 4096-token context on an 8 GB Mac. Image input adds a 0.67 GB projector and needs a 2048-token context. Quality targets 16 GB or more; Balance uses less memory. The estimate reserves room for macOS.

¹ Mini is retained for existing installations and conversations. New installations offer Smart, Quality, and Balance.

<details>
<summary><strong>Other GGUF models to explore — not yet tested in NIKA</strong></summary>

Other GGUF options include [Gemma 4 12B](https://huggingface.co/google/gemma-4-12B-it-qat-q4_0-gguf), [Qwen3.5-9B](https://huggingface.co/bartowski/Qwen_Qwen3.5-9B-GGUF), and [gpt-oss-20b](https://huggingface.co/ggml-org/gpt-oss-20b-GGUF).

These imports need enough memory and support in your installed llama.cpp version. They have not been tested in NIKA and are not recommendations for an 8 GB Mac.

</details>

## Benchmarks

### Local engine speed

<!-- LOCAL-BENCHMARK:START -->
**Qwen3.5 4B Q4_K_M · Apple M4 Pro · 24 GB · Metal**

Measured October 13, 2026, with five repetitions after warm-up, llama.cpp `7fe450e19`.

| Workload | Mean throughput | Standard deviation |
| --- | ---: | ---: |
| Prompt processing · pp512 | **611.60 tokens/s** | ±0.72 |
| Token generation · tg128 | **57.50 tokens/s** | ±0.46 |

These results describe this 24 GB M4 Pro. Speed on an 8 GB Mac has not been measured.
<!-- LOCAL-BENCHMARK:END -->

This measures llama.cpp throughput with synthetic tokens, not app response latency, time to first token, or answer quality.

[Raw results](docs/benchmarks/m4-pro-24gb-qwen35-4b-q4/raw.json) · [Environment](docs/benchmarks/m4-pro-24gb-qwen35-4b-q4/environment.json) · [Method and reproduction instructions (Russian)](docs/BENCHMARKS.md)

<details>
<summary><strong>Base model quality — published Qwen results</strong></summary>

| Benchmark | Qwen3.5 4B |
| --- | ---: |
| MMLU-Pro | 79.1 |
| GPQA Diamond | 76.2 |
| IFEval | 89.8 |

Published results from the [official Qwen model card](https://huggingface.co/Qwen/Qwen3.5-4B#benchmark-results), **not NIKA or Q4_K_M evaluations**. Quantization, context, and generation settings can change results.

</details>

## Build on NIKA

**Fork the desktop client and make it your own.** Use the SwiftUI interface as a starting point, experiment with compatible local models, or extend the document workflow.

Open `Package.swift` in Xcode. The repository is self-contained: you do not need the iPhone repository or the NIKA cloud backend to build and modify the local client. Local inference uses llama.cpp; live cloud voice uses WebRTC.

- **Get started:** [setup, architecture, and tests](docs/DEVELOPMENT.en.md).
- **Report a bug:** [open an issue](https://github.com/1nikitas/NIKA_desktop/issues/new) with reproduction steps, your macOS version, and Mac model.
- **Contribute a change:** [open a pull request](https://github.com/1nikitas/NIKA_desktop/pulls). Keep it focused and explain the behavior and how you tested it.

## Keyboard shortcuts

<details>
<summary><strong>Show shortcuts</strong></summary>

| Action | Shortcut |
| --- | --- |
| New conversation / new window | `⌘N` / `⌘⇧N` |
| Send / stop | `⌘↩` / `⌘.` |
| Models / voice | `⌘⇧M` / `⌘⇧V` |
| Quick access | `⌃⌥Space` |
| Settings | `⌘,` |

</details>

## Optional NIKA cloud

Sign in through Telegram to access NIKA account conversations, cloud agents, tools, integrations, and custom assistants with their own instructions and materials. Live cloud voice uses WebRTC. These features require an account and an internet connection.

**This repository contains the desktop client. The NIKA cloud backend is not included.**

<details>
<summary><strong>More screenshots: light theme, cloud assistants, sign-in</strong></summary>

![Light theme](docs/assets/conversation-light.png)

| Cloud assistant editor | Telegram sign-in |
| --- | --- |
| ![Assistant editor with demonstration data](docs/assets/bot-editor.png) | ![Telegram sign-in](docs/assets/telegram-login.png) |

</details>

<details>
<summary><strong>NIKA on the web and Telegram</strong></summary>

[NIKA on the web](https://nika-agent.ru/) · [Telegram bot](https://t.me/nika_ai_2_bot)

The hosted service provides cloud LLMs, the agent runtime, and tools without installing the desktop client or downloading models. Sign in to use a personal assistant and customize its name, appearance, and instructions.

![NIKA web: home screen, personal assistants, customization, and example tasks](docs/assets/nika-web-overview.jpg)

</details>

Thanks to [Qwen](https://huggingface.co/Qwen), [llama.cpp](https://github.com/ggml-org/llama.cpp), and [WebRTC for macOS](https://github.com/stasel/WebRTC).

