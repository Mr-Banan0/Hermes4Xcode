import SwiftUI
import AppKit

@main
struct Hermes4XcodeApp: App {
    @State private var selectedPage: AppPage = .chat
    @State private var sidebarWidth: CGFloat = 160
    @State private var isSidebarCollapsed = false
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    private let minSidebar: CGFloat = 100
    private let maxSidebar: CGFloat = 220
    private let collapsedWidth: CGFloat = 40

    var body: some Scene {
        WindowGroup(id: "main") {
            HStack(spacing: 0) {
                // Sidebar
                SidebarView(
                    selectedPage: $selectedPage,
                    isCollapsed: $isSidebarCollapsed,
                    onToggleCollapse: { withAnimation(.easeInOut(duration: 0.15)) { isSidebarCollapsed.toggle() } }
                )
                .frame(width: isSidebarCollapsed ? collapsedWidth : sidebarWidth)

                // Drag handle (only when expanded)
                if !isSidebarCollapsed {
                    DragHandle(width: $sidebarWidth, minWidth: minSidebar, maxWidth: maxSidebar)
                }

                // Main content
                Group {
                    switch selectedPage {
                    case .chat:
                        HermesChatView(initialCode: nil)
                    case .cron:
                        CronSettingsView()
                    case .provider:
                        ProviderSettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 480, minHeight: 540)
            .preferredColorScheme(.dark)
            .background(Color.black)
            .onAppear {
                DispatchQueue.global().async {
                    if SourceKitLSPClient.shared.start() {
                        NSLog("[Hermes4Xcode] SourceKit-LSP started")
                    }
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

// MARK: - Drag Handle

struct DragHandle: View {
    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat

    var body: some View {
        Rectangle()
            .fill(Color.hermes.opacity(0.15))
            .frame(width: 3)
            .onHover { inside in
                if inside {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let newWidth = width + value.translation.width
                        width = max(minWidth, min(maxWidth, newWidth))
                    }
            )
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate!

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        NSApp.setActivationPolicy(.regular)

        if let window = NSApp.windows.first {
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.title = "Hermes4Xcode"
            window.hidesOnDeactivate = false
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.backgroundColor = .black

            if let screenFrame = NSScreen.main?.visibleFrame {
                let w: CGFloat = 620
                let h: CGFloat = 700
                let x = screenFrame.maxX - w - 20
                let y = screenFrame.maxY - h - 40
                window.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
            }
        }
    }

    func runAppleScript(_ script: String) -> String? {
        guard let scriptObject = NSAppleScript(source: script) else { return nil }
        var error: NSDictionary?
        let result = scriptObject.executeAndReturnError(&error)
        if let error = error {
            NSLog("[Hermes4Xcode] AppleScript error: \(error)")
            return nil
        }
        return result.stringValue
    }
}
