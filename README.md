
<img src="https://img.shields.io/badge/macOS-15.0%2B-brightgreen" alt="macOS">
<img src="https://img.shields.io/badge/Xcode-26%2B-blue" alt="Xcode">
<img src="https://img.shields.io/badge/License-MIT-yellow" alt="License">

```
██╗  ██╗███████╗██████╗ ███╗   ███╗███████╗███████╗       █████╗  ██████╗ ███████╗███╗   ██╗████████╗
██║  ██║██╔════╝██╔══██╗████╗ ████║██╔════╝██╔════╝      ██╔══██╗██╔════╝ ██╔════╝████╗  ██║╚══██╔══╝
███████║█████╗  ██████╔╝██╔████╔██║█████╗  ███████╗█████╗███████║██║  ███╗█████╗  ██╔██╗ ██║   ██║
██╔══██║██╔══╝  ██╔══██╗██║╚██╔╝██║██╔══╝  ╚════██║╚════╝██╔══██║██║   ██║██╔══╝  ██║╚██╗██║   ██║
██║  ██║███████╗██║  ██║██║ ╚═╝ ██║███████╗███████║      ██║  ██║╚██████╔╝███████╗██║ ╚████║   ██║
╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝╚══════╝      ╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚═╝  ╚═══╝   ╚═╝
```

**Hermes4Xcode** is a macOS companion app for Xcode that provides agentic coding assistance through the [Hermes Agent](https://hermes-agent.nousresearch.com) Gateway API. It sits alongside Xcode as a floating panel — you select code, chat with the agent, and it can read, modify, build, and test your project.

## Features

| Phase | Feature | Status |
|-------|---------|--------|
| 0 | Chat panel with Hermes Gateway (SSE streaming) | ✅ |
| 0 | Xcode selection detection with context pill | ✅ |
| 0 | Auto-replace selected code from agent response | ✅ |
| 1 | Build / Test with real-time output log | ✅ |
| 1 | Read current file, project info display | ✅ |
| 2 | Structured agent response (tool calls, diffs) | ✅ |
| 3 | Quick actions: fix errors, generate tests, review, refactor | ✅ |
| 4 | Project structure scanning, cross-session memory | ✅ |
| 5 | SourceKit-LSP code analysis | ✅ |

## Prerequisites

- **macOS 15+** (Sequoia)
- **Xcode 26+**
- **Hermes Agent** with Gateway API running:

```bash
hermes gateway start
```

The Gateway listens on `http://127.0.0.1:8642/v1`.

## Quick Start

```bash
# Open in Xcode
open Hermes4Xcode.xcodeproj

# Build & Run (Cmd+R)
# The floating panel appears on the right side of the screen
```

### First-Time Setup

1. **System Settings → Privacy & Security → Automation** → grant **Hermes4Xcode** permission to control **Xcode** (for selection detection and code replacement)
2. **Xcode → Settings → Intelligence → Add Custom Provider** (optional): add `http://127.0.0.1:8642/v1` for in-Xcode chat

## Usage

### Toolbar

| Button | Action |
|--------|--------|
| **Read** | Fetch current Xcode file content into chat input |
| **Build** | Compile the active Xcode scheme |
| **Test** | Run tests (or choose to create a test target) |
| **Quick** | Menu: fix build errors, generate tests, review file, refactor, commit message, project structure, LSP analysis |

### Chat

Select code in Xcode, then click the Hermes4Xcode window. A context pill appears above the input showing the selected file and lines. Type your question and the agent responds with the file context attached.

When the agent returns a ` ```swift ` code block, it is automatically applied to the Xcode selection.

## Project Structure

```
Hermes4Xcode/
├── Hermes4Xcode.xcodeproj/       # Xcode project
├── Hermes4Xcode.xcworkspace/     # Xcode workspace
├── Hermes4Xcode/                 # App source code
│   ├── HermesXcodeApp.swift      # App entry (WindowGroup + dark theme)
│   ├── HermesChatView.swift      # Chat UI + toolbar + build log
│   ├── HermesAPIClient.swift     # Gateway SSE client
│   ├── XcodeContext.swift        # AppleScript Xcode control
│   ├── MessageParser.swift       # Tool call + diff parser
│   ├── SourceKitLSP.swift        # SourceKit-LSP JSON-RPC client
│   ├── HermesColor.swift         # Brand colors (#FFD700 / #FFBF00)
│   └── Assets.xcassets/          # App icon + accent color
├── Config/                       # xcconfig build settings
└── README.md
```

## Architecture

```
                  ┌──────────────────┐
                  │   Hermes4Xcode    │
                  │   (macOS App)     │
                  │                   │
  ┌─────────┐     │  ┌─────────────┐  │     ┌──────────────┐
  │  Xcode   │◄────┤  │ AppleScript │  │     │ Hermes       │
  │  (IDE)   │─────►│  │ (read/edit) │  │     │ Gateway API  │
  └─────────┘     │  └─────────────┘  │     │ (port 8642)  │
                  │         │         │     └──────┬───────┘
                  │         ▼         │            │
                  │  ┌─────────────┐  │     ┌──────┴───────┐
                  │  │ SSE Client  │────────►│ Hermes Agent │
                  │  │ (chat)      │  │     │ (+ tool loop)│
                  │  └─────────────┘  │     └──────────────┘
                  └──────────────────┘
```

## Key Bindings

| Key | Action |
|-----|--------|
| `Enter` | Send message |
| `Tab` | Focus input field |
| `Esc` | Close build log panel |

## License

MIT
