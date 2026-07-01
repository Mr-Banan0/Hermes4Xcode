# Hermes4Xcode Coding Standards

> Both **human contributors** and **Hermes coding agent** must follow these standards.
> SwiftLint enforces syntax rules; this document covers architecture, patterns, and conventions.

---

## 1. Swift Style

### Naming

- **Types** (struct, class, enum, protocol): `PascalCase` — `AgentManager`, `StoredMessage`, `Codable`
- **Properties, methods, parameters**: `camelCase` — `activeTabId`, `sendMessage()`, `effectiveSystemMessage`
- **Protocols**: Describe capability: `Codable`, `Equatable`, `XcodeBuildDelegate`
- **Enum cases**: `camelCase` — `case supervisor`, `case chatMode`
- **Booleans**: Use descriptive names — `isStreaming`, `hasNamedConversation`, `canReceiveDelegation`
- **Avoid needless abbreviations**: Use `count` not `cnt` (except `idx` for index variables is acceptable — follows standard Swift patterns like `firstIndex(where:)`)

### File Structure

Every `.swift` file follows this order:

```swift
import SwiftUI  // or Foundation

// MARK: - Section Title (from general to specific)

struct/class/enum Definition {
    // MARK: Properties
    // MARK: Init
    // MARK: Lifecycle
    // MARK: Public Methods
    // MARK: Private Helpers
}

// MARK: - Sub-types / Extensions (at bottom)
```

- One primary type per file (exceptions: closely related helpers)
- Use `// MARK: -` to split sections — Xcode shows these in the jump bar
- Extensions go at the bottom of the same file, not in separate files (unless the type is very large)

### Access Control

- Default to `internal`, only use `private`/`fileprivate` when needed
- Prefer `private` over `fileprivate` — limit scope
- Use `public` only for API-facing types (this is an app, not a library)
- `@Published` properties should be `internal` by default

---

## 2. SwiftUI Patterns

### State Management

```swift
// View-local state
@State private var isExpanded = false

// Observable model (shared)
@ObservedObject var manager: AgentManager

// App-wide singleton
@StateObject private var store = ConversationStore.shared

// Binding passed from parent
@Binding var isCollapsed: Bool
```

- **Use `@State`** for view-local, private state (toggles, text, selections)
- **Use `@ObservedObject`** for models owned by a parent view
- **Use `@StateObject`** when the view creates and owns the model
- **Use `@Binding`** to pass read/write access to a child view
- **Don't** put business logic in view `@State` — move to `ObservableObject`

### View Composition

```swift
var body: some View {
    VStack(spacing: 0) {
        header
            .padding(.horizontal, 10).padding(.vertical, 4)
        Divider().background(Color.hermes.opacity(0.3))
        content
    }
    .background(Color.black)
}

private var header: some View {
    HStack { /* ... */ }
}
```

- Break complex views into `private var` computed properties
- Prefer `VStack`/`HStack`/`ZStack` over `Group` for layout
- Use `.padding()` with explicit values, not defaults
- Chain modifiers in order: **layout → appearance → behavior**

### Color & Theme

```swift
// Use named colors from HermesColor.swift
.foregroundColor(.hermes)         // Gold #FFD700
.foregroundColor(.hermesAmber)    // Amber #FFBF00
.background(Color(white: 0.08))   // Dark backgrounds by gray value
```

- Never hardcode hex colors — use `HermesColor` extensions
- Backgrounds: black (`#000`), dark (`white: 0.08`), medium (`white: 0.12`)
- Text: white for primary, `secondary` for secondary, `gray` for disabled

---

## 3. Architecture

### MVVM-like Pattern

```
View (SwiftUI)          ← displays state, sends user actions
  │
  ▼
ViewModel (class)       ← holds @Published state, business logic
  │                        (we use AgentManager as the main ViewModel)
  ▼
Model (struct)          ← pure data, Codable, Equatable
```

- **Views** are stateless where possible — read from models, call methods
- **Models** are value types (structs) with `Codable` conformance
- **ViewModels** are classes with `@Published` properties

### Data Flow

```
User taps button → View calls manager.sendMessage()
  → Manager builds request → HermesAPIClient sends SSE
  → Stream comes back → Manager updates @Published properties
  → View auto-updates via SwiftUI data binding
```

- Unidirectional: **user action → manager method → API call → published update → view re-render**
- No two-way data flow between ViewModels

### Dependency Injection

```swift
// Pass dependencies via init, not singletons
struct HermesChatView: View {
    @ObservedObject var manager: AgentManager  // Injected from parent
}
```

- Prefer init injection over `EnvironmentObject` or singletons
- `ConversationStore.shared` is the only singleton (file I/O is inherently global)

---

## 4. Error Handling

### Pattern

```swift
enum BuildError: Error {
    case buildFailed(exitCode: Int32, output: String)
    case cancelled
}

// Use Result type for async operations
onComplete: { result in
    switch result {
    case .success(let text):  // handle response
    case .failure(let error): // show error in chat
    }
}
```

- Define specific error enums per domain, not a generic `AppError`
- Use `Result<Success, Failure>` for async callbacks
- Log errors with `NSLog("[Hermes4Xcode] ...")` for debugging
- Show user-visible errors in the chat as assistant messages

### Force-Unwrapping

- **Never** use `!` in production code
- Exception: `IBOutlets` in UIKit views (not applicable here)
- Use `guard let`, `if let`, or `??` with sensible defaults

---

## 5. Testing

### Test Structure

```swift
final class AgentManagerTests: XCTestCase {
    func test_methodName_whenCondition_expectedResult() {
        // Arrange
        let sut = AgentManager()

        // Act
        sut.someMethod()

        // Assert
        XCTAssertEqual(sut.someProperty, expectedValue)
    }
}
```

- Follow Arrange-Act-Assert with blank line separators
- Name tests: `test_methodName_whenCondition_expectedResult`
- SUT: name the system-under-test `sut`
- One logical assertion per test (multiple `XCTAssertEqual` for the same logical outcome is OK)

### What to Test

- **Models**: Codable round-trip, equality, computed properties
- **ViewModels**: State transitions, method side effects
- **Parsers**: Edge cases, empty input, malformed input
- **Not Views**: SwiftUI views are tested via snapshot/UI tests (future)

---

## 6. Project Organization

### File Groups (Xcode)

```
Hermes4Xcode/          ← All source files flat (file-system-synchronized)
Hermes4XcodeTests/     ← Test files, one per source module
Config/                ← xcconfig files, entitlements
```

- Keep files flat — Xcode's file-system-synchronized mode auto-discovers
- Don't create nested folders in the source directory
- Name files after the primary type: `AgentManager.swift`, not `managers.swift`

---

## 7. Git & PR Conventions

### Commit Messages

```
type: concise subject line (max 72 chars)

Optional body explaining what and why, not how.
```

Types: `feat:`, `fix:`, `refactor:`, `docs:`, `chore:`, `test:`

### Branch Names

```
feat/feature-name        # new features
fix/bug-description      # bug fixes
refactor/area            # code restructuring
```

### PR Checklist

Every PR must verify:
- [ ] Build succeeds (`xcodebuild build`)
- [ ] All tests pass (`xcodebuild test`)
- [ ] SwiftLint clean (`swiftlint --strict`)
- [ ] CHANGELOG updated

---

## 8. Coding Agent Safety Rules

When the Hermes coding agent modifies this project, it MUST follow:

1. **Never hand-write `project.pbxproj`.** Use `swift package init` or Xcode templates.
2. **Never hand-write Asset Catalog `Contents.json`.** Use SF Symbols or define colors in Swift code.
3. **Prefer MCP tools** (`xcodebuildmcp`) over raw `xcodebuild` when available.
4. **Prefer `patch`** (surgical find-and-replace) over `write_file` for existing files.
5. **Read before you write** — never edit a file without seeing its current content.
6. **Build after every logical change.** Only move on when `BUILD SUCCEEDED`.
7. **Don't switch projects mid-stream** without the user explicitly asking.

---

## 9. Design System (Hermes Theme)

| Token | Value | Usage |
|-------|-------|-------|
| Primary | `#FFD700` (Gold) | Accent, active, brand elements |
| Secondary | `#FFBF00` (Amber) | Secondary accents, user text |
| Background | `#000000` (Black) | Main background |
| Surface | `white: 0.08` | Cards, containers |
| Surface hover | `white: 0.12` | Input fields |
| Border | `.hermes.opacity(0.3)` | Dividers, outlines |
| Text primary | `white` / `Color(white: 0.9)` | Body text |
| Text secondary | `.secondary` / `Color(white: 0.6)` | Labels, metadata |
| Font | `.system(.monospaced)` / `.design(.monospaced)` | All UI text |
| Corner radius | `6` (standard), `8` (cards), `4` (pills) | Rounded corners |
| Terminal style | Box-drawing chars `╭─╰─` | Message headers, Hermes branding |
