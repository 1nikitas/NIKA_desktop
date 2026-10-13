# Developing NIKA Desktop

[← README](../README.md) · **English** · [Русский](DEVELOPMENT.md)

## Requirements

- Apple Silicon and macOS 26+ for the currently bundled inference engine.
- Xcode 16.4+ with Swift 6, Python 3, and Homebrew.
- llama.cpp: `brew install llama.cpp`.
- Internet access for the initial WebRTC and model downloads. Installed local models work offline.

Complete Xcode's first-run setup. If only Command Line Tools are selected:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

The SwiftUI package declares macOS 14, but the currently bundled engine requires macOS 26. Earlier macOS versions and Intel Macs need a compatible engine and separate validation.

## Run from source

```bash
git clone https://github.com/1nikitas/NIKA_desktop.git
cd NIKA_desktop
bash scripts/dev.sh
```

The script builds a debug app, bundles the inference engine, WebRTC, resources, and App Intents metadata, applies an ad-hoc signature, and launches it. An Apple signing certificate is not needed for development. Logs appear in Terminal; quit with ⌘Q.

Development history is stored in `.dev-data/`. `NIKA_DESKTOP_DATA` changes the data directory and disables saved sign-in restoration, but does not fully isolate UserDefaults or Keychain. Use a separate macOS user for complete separation. Do not commit credentials or sessions.

In the app, choose **Локальные модели → NIKA Smart → скачать → Начать разговор** (Local models → NIKA Smart → download → Start conversation). On an 8 GB Mac, use a 4096-token context, or 2048 with a vision projector. Physical 8 GB hardware has not yet been tested.

Cloud features require Telegram sign-in. The server address can be changed on the sign-in screen. The backend is not included in this repository.

## Xcode workflow

```bash
open Package.swift
```

Select the `NIKADesktop` scheme and `My Mac`. To test camera, microphone, and system permissions, launch the packaged app with `scripts/dev.sh`, then use **Debug → Attach to Process → NIKADesktop** in Xcode.

| File or directory | Responsibility |
| --- | --- |
| `Sources/NIKADesktop/NIKADesktopApp.swift` | App entry point, windows, menus, and commands |
| `WorkspaceView.swift` | Navigation and conversation UI |
| `DesktopStore.swift` | Account, window, and history state |
| `SettingsView.swift` | Settings and Telegram sign-in |
| `PersonalBots.swift` | Cloud assistants and their editor |
| `ModelLibrary.swift`, `LocalProvider.swift` | Model downloads and local inference |
| `Shared/` | Data models, BFF transport, and parsers |
| `Tests/NIKADesktopTests/` | UI, data, and integration tests |

Short paths above are relative to `Sources/NIKADesktop/`. Shared files are standalone copies; the iPhone repository is not required.

## Build

```bash
# Compile only
swift build --disable-sandbox

# Package a release app with the engine and resources
bash scripts/build-app.sh
open 'build/NIKA Desktop.app'

# Package a debug app without launching it
NIKA_BUILD_CONFIGURATION=debug bash scripts/build-app.sh
```

WebRTC is pinned to 154.0.0 in SwiftPM. The local engine is taken from the installed `llama-server`. Ad-hoc signing is for development; this repository does not provide a notarized installer.

## Tests

```bash
CLANG_MODULE_CACHE_PATH=/tmp/nika-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/nika-swift-cache \
swift test --disable-sandbox
```

Recorded run on October 13, 2026: 39 passed, 5 integration tests skipped without external fixtures, no failures. To enable integration tests, supply:

| Variable | Value |
| --- | --- |
| `NIKA_TEST_GGUF` | Path to Qwen3.5 0.8B Q8_0 |
| `NIKA_TEST_PROJECTOR` | Path to a compatible mmproj projector |
| `NIKA_TEST_DOWNLOAD_URL` | Test HTTP file containing `abc` |
| `NIKA_TEST_ARTIFACT_DIR` | Optional output directory for a test conversation |

Run the HTTP fixture with `python3 scripts/download-fixture.py`. Its URL is `http://127.0.0.1:18283/model.gguf`; stop it with Ctrl-C. Memory-budget tests simulate 8/16 GB; they do not replace physical hardware tests. The separate 4B speed benchmark was run on an M4 Pro with 24 GB.

After changing chat behavior, check send, stop, retry, persistence, and reopening. Repeat a local question without internet access. For UI changes, check both themes, narrow windows, and multiline input. Cloud and voice checks require a live account and appropriate macOS permissions.

## Architecture

Each window owns a `Workspace`; `DesktopStore` owns the shared account, library, and history. Local `llama-server` runs in a separate process on 127.0.0.1 with a random access key. One local generation runs at a time.

Model downloads are sequential, resumable, and checked against file size and SHA-256. Local memory is separate from account memory. A local model error does not send the request to the cloud. Local actions require confirmation; changing modes starts a new conversation.

## Troubleshooting

- **`llama-server is required`:** install llama.cpp and check `command -v llama-server`.
- **WebRTC download fails:** check GitHub connectivity and retry `swift package resolve`.
- **SDK not found:** check `xcode-select -p` and finish Xcode's first-run setup.
- **Cache write errors:** use the temporary cache directories in the test command above.
- **Missing resources or permissions when running from Xcode:** launch the packaged app with `scripts/dev.sh` and attach the debugger.
