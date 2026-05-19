
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

---

## Prerequisites

Before you can run this app, you need the following:

### 1. Xcode & macOS

| Requirement | Minimum Version |
|-------------|----------------|
| macOS | 15.0 (Sequoia) |
| Xcode | 26+ |
| Command Line Tools | `xcode-select --install` |

### 2. Hermes Agent (Required)

This app requires the **Hermes Agent Gateway API** running in the background. The app connects to `http://127.0.0.1:8642/v1` to send code and receive agent responses.

```bash
# Install Hermes Agent (one-time)
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash

# Start the Gateway API server
hermes gateway start

# Verify it's running
curl http://127.0.0.1:8642/v1/models
# Expected: {"object": "list", "data": [{"id": "hermes-agent", ...}]}
```

> **Note:** The Gateway must be running every time you use Hermes4Xcode. The app will show a red "Offline" indicator at the top if Gateway is not running.

### 3. Apple Events Permission (Required for Xcode Integration)

For the app to read your selected code and write code back to Xcode, you need to grant automation permission:

1. Run the app once (it will try to access Xcode)
2. Open **System Settings → Privacy & Security → Automation**
3. Find **Hermes4Xcode** in the list
4. Toggle the checkbox next to **Xcode**

> If you don't see Hermes4Xcode in the list, click the refresh button (🔄) inside the app while Xcode has a file open — macOS will prompt you to allow access.

### 4. (Optional) In-Xcode Chat Provider

If you want to chat with Hermes directly inside Xcode's chat panel:

1. Open **Xcode → Settings → Intelligence**
2. Click **Add Custom Provider**
3. Set Name: `Hermes`, URL: `http://127.0.0.1:8642/v1`
4. Leave API Key blank (localhost)

---

## Quick Start

```bash
# 1. Clone
git clone https://github.com/Mr-Banan0/Hermes4Xcode.git
cd Hermes4Xcode

# 2. Open in Xcode
open Hermes4Xcode.xcodeproj

# 3. Make sure Gateway is running
hermes gateway status

# 4. Build & Run (Cmd+R in Xcode)
```

### Post-Launch Checklist

| Check | How |
|-------|-----|
| 🟢 Gateway connected? | Look for green dot in top-right of the app |
| 📄 Xcode selection detected? | Select code in Xcode, click the app — a pill appears above input |
| 🏗 Build works? | Click Build button in the toolbar |

---

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

---

## Usage

### Toolbar

| Button | Action |
|--------|--------|
| **Read** | Fetch current Xcode file content into chat input |
| **Build** | Compile the active Xcode scheme (output shown in bottom panel) |
| **Test** | Run tests; if no test target exists, prompts to create one |
| **Quick** | Menu: fix build errors, generate tests, review, refactor, commit message, project structure, LSP analysis |

### Chat

Select code in Xcode, then click the Hermes4Xcode window. A gold pill appears above the input showing the selected file and line range. Type your question and the agent responds with the file context automatically attached.

When the agent returns a `` ```swift `` code block, it is automatically applied to the Xcode selection. You can also click **"Replace in Xcode"** on any assistant message that contains a code block.

---

## Project Structure

```
Hermes4Xcode/
├── Hermes4Xcode.xcodeproj/       # Xcode project (open this)
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
├── .gitignore
└── README.md
```

---

## Architecture

```
                  ┌──────────────────┐
                  │   Hermes4Xcode    │     ┌──────────────┐
                  │   (macOS App)     │     │              │
  ┌─────────┐     │  ┌─────────────┐  │     │ Hermes       │
  │  Xcode   │◄────┤  │ AppleScript │  │     │ Gateway API  │
  │  (IDE)   │─────►│  │ (read/edit) │  │     │ (port 8642)  │
  └─────────┘     │  └──────┬──────┘  │     └──────┬───────┘
                  │         │         │            │
                  │         ▼         │     ┌──────┴───────┐
                  │  ┌─────────────┐  │     │ Hermes Agent │
                  │  │ SSE Client  │────────►│ (+ tool loop)│
                  │  │ (chat)      │  │     └──────────────┘
                  │  └─────────────┘  │
                  └──────────────────┘

Actions:
  • Start Gateway → hermes gateway start
  • Gateway URL  → http://127.0.0.1:8642/v1
  • Build Xcode  → xcodebuild via AppleScript
  • Analyze code → SourceKit-LSP (background)
```

---

## Key Bindings

| Key | Action |
|-----|--------|
| `Enter` | Send message |
| `Tab` | Focus input field |
| `Esc` | Close build log panel |

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Red "Offline" dot | Run `hermes gateway start` in terminal |
| App can't read Xcode selection | Grant Automation permission in System Settings → Privacy & Security |
| Build button shows error | Check that Xcode has a workspace/project open |
| "Not authorized" for Apple Events | See prerequisite #3 above |

---

## License

MIT
