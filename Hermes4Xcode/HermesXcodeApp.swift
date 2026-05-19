import SwiftUI
import AppKit

@main
struct Hermes4XcodeApp: App {
    @State private var selectedPage: AppPage = .chat
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup(id: "main") {
            HSplitView {
                // Left sidebar
                SidebarView(selectedPage: $selectedPage)
                    .frame(minWidth: 56, maxWidth: 56)

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
                .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 480, minHeight: 540)
            .preferredColorScheme(.dark)
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
                let w: CGFloat = 560
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
