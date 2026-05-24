# Contributing to Hermes4Xcode

Thanks for your interest in contributing! This document outlines the process for contributing to the project.

## Getting Started

1. **Fork** the repository on GitHub
2. **Clone** your fork: `git clone https://github.com/YOUR_USERNAME/Hermes4Xcode.git`
3. **Create a branch**: `git checkout -b feat/your-feature-name`
4. **Install dependencies**: make sure [Hermes Gateway](https://hermes-agent.nousresearch.com) is running on port 8642

## Development

### Prerequisites

- macOS 15.0+
- Xcode 26+
- Hermes Gateway (for chat features)

### Running the App

```bash
# Open the project
open Hermes4Xcode.xcodeproj

# Make sure the gateway is running
hermes gateway status
```

Then press `Cmd+R` in Xcode.

### Code Style

- Follow the [Hermes4Xcode Coding Standards](CODING_STANDARDS.md) for Swift style, architecture, and patterns.
- Use 4-space indentation (enforced by SwiftLint)
- Write documentation comments (`///`) for all public types and methods
- Use `MARK:` comments to organize sections within files

The project includes a SwiftLint configuration — run it before committing:

```bash
swiftlint --strict
```

## Pull Request Process

1. Create a branch with a descriptive name:
   - `feat/description` — new features
   - `fix/description` — bug fixes
   - `refactor/description` — code restructuring
   - `docs/description` — documentation
   - `ci/description` — CI/CD changes

2. Make your changes and ensure:
   - ✅ Build succeeds: `xcodebuild build -project Hermes4Xcode.xcodeproj -scheme Hermes4Xcode -destination "platform=macOS,arch=arm64" CODE_SIGNING_ALLOWED=NO`
   - ✅ Tests pass: `xcodebuild test -project Hermes4Xcode.xcodeproj -scheme Hermes4Xcode -destination "platform=macOS,arch=arm64" CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES`
   - ✅ SwiftLint passes: `swiftlint --strict`
   - ✅ CHANGELOG.md is updated if the change is user-facing

3. Commit with a conventional commit message:
   ```bash
   git commit -m "feat: add your feature description"
   ```
   Types: `feat`, `fix`, `refactor`, `docs`, `test`, `ci`, `chore`

4. Push and open a Pull Request

## Testing

- All new features should include XCTest unit tests
- Place tests in `Hermes4XcodeTests/`
- Use `@testable import HermesXcode` to access internal types
- Follow the Arrange-Act-Assert pattern
- Run all tests before pushing: `xcodebuild test -scheme Hermes4Xcode -destination "platform=macOS,arch=arm64" CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES`

## Project Structure

```
Hermes4Xcode/
├── Hermes4Xcode.xcodeproj/   # Xcode project
├── Hermes4Xcode/             # App source code
│   ├── HermesXcodeApp.swift  # Entry point
│   ├── HermesChatView.swift  # Chat UI
│   ├── AgentManager.swift    # Agent tab management
│   ├── XcodeContext.swift    # AppleScript bridge
│   └── ...
├── Hermes4XcodeTests/        # Unit tests
├── Config/                   # xcconfig build settings
├── .github/workflows/        # CI/CD
└── CHANGELOG.md
```

## Questions?

Open an issue or start a discussion on GitHub.
