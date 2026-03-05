import Cocoa
import WebKit
import Carbon

// ── OVERLAY WINDOW ────────────────────────────────────────────
class OverlayPanel: NSPanel, WKScriptMessageHandler {
    var webView: WKWebView!

    init() {
        let w: CGFloat = 320
        let h: CGFloat = 600
        let screen = NSScreen.main?.frame ?? .init(x:0,y:0,width:1440,height:900)
        let x = screen.maxX - w - 20
        let y = screen.maxY - h - 40

        super.init(
            contentRect: .init(x:x, y:y, width:w, height:h),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Always on top — above fullscreen apps
        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)) + 1)
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true
        self.hidesOnDeactivate = false

        setupWebView(width: w, height: h)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func setupWebView(width: CGFloat, height: CGFloat) {
        let config = WKWebViewConfiguration()

        // Register JS → Swift message handlers
        config.userContentController.add(self, name: "closeWindow")

        // Allow local file access
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        webView = WKWebView(frame: .init(x:0,y:0,width:width,height:height), configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false
        webView.autoresizingMask = [.width, .height]

        self.contentView = webView

        // Load HTML from app bundle
        let htmlPath = Bundle.main.path(forResource: "overlay", ofType: "html")
            ?? (Bundle.main.bundlePath + "/Contents/MacOS/overlay.html")

        if FileManager.default.fileExists(atPath: htmlPath) {
            let url = URL(fileURLWithPath: htmlPath)
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            // Fallback: load from same dir as executable
            let exeDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
            let fallback = exeDir.appendingPathComponent("overlay.html")
            webView.loadFileURL(fallback, allowingReadAccessTo: exeDir)
        }
    }

    // Handle JS messages
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "closeWindow" {
            DispatchQueue.main.async { self.orderOut(nil) }
        }
    }

    func toggle() {
        if isVisible { orderOut(nil) }
        else { makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    }
}

// ── APP DELEGATE ──────────────────────────────────────────────
class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: OverlayPanel!
    var hotKeyRef: EventHotKeyRef?

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory) // no dock icon

        panel = OverlayPanel()
        panel.makeKeyAndOrderFront(nil)

        registerHotKey()
    }

    func registerHotKey() {
        // Cmd+Shift+K = toggle overlay
        var hkID = EventHotKeyID()
        hkID.signature = fourCC("SKov")
        hkID.id = 1

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, _, userData) -> OSStatus in
                let me = Unmanaged<AppDelegate>.fromOpaque(userData!).takeUnretainedValue()
                DispatchQueue.main.async { me.panel.toggle() }
                return noErr
            },
            1, &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            nil
        )

        RegisterEventHotKey(
            40,                              // K
            UInt32(cmdKey | shiftKey),
            hkID,
            GetApplicationEventTarget(),
            0, &hotKeyRef
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { false }
}

func fourCC(_ s: String) -> FourCharCode {
    s.unicodeScalars.reduce(0) { ($0 << 8) + FourCharCode($1.value) }
}

// ── MAIN ──────────────────────────────────────────────────────
let app = NSApplication.shared
let del = AppDelegate()
app.delegate = del
app.run()
