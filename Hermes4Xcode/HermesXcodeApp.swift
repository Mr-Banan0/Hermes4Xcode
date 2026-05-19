import SwiftUI
import AppKit

@main
struct Hermes4XcodeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup(id: "main") {
            HermesChatView(initialCode: nil)
                .frame(minWidth: 420, minHeight: 540)
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

            // Position right side of screen
            if let screenFrame = NSScreen.main?.visibleFrame {
                let w: CGFloat = 460
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
