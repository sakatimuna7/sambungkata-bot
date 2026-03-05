import Cocoa
import WebKit
import Carbon

// ── OVERLAY WINDOW ────────────────────────────────────────────
class OverlayPanel: NSPanel, WKScriptMessageHandler {
    var webView: WKWebView!

    init() {
        let w: CGFloat = 320
        let h: CGFloat = 650 // Slightly taller for more results
        let screen = NSScreen.main?.visibleFrame ?? .init(x:0,y:0,width:1440,height:900)
        let x = screen.maxX - w - 20
        let y = screen.maxY - h - 20

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
        self.isMovableByWindowBackground = true // Enable dragging
        self.hidesOnDeactivate = false

        setupWebView(width: w, height: h)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func setupWebView(width: CGFloat, height: CGFloat) {
        let config = WKWebViewConfiguration()

        // Register JS → Swift message handlers
        config.userContentController.add(self, name: "closeWindow")
        config.userContentController.add(self, name: "typeInRoblox")

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
            let exeDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
            let fallback = exeDir.appendingPathComponent("overlay.html")
            webView.loadFileURL(fallback, allowingReadAccessTo: exeDir)
        }
    }

    // Handle JS messages
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "closeWindow" {
            DispatchQueue.main.async { self.orderOut(nil) }
        } else if message.name == "typeInRoblox", let text = message.body as? String {
            focusRobloxAndType(text: text)
        }
    }

    private var isTyping = false

    func focusRobloxAndType(text: String) {
        if isTyping { return }
        isTyping = true
        
        let apps = NSWorkspace.shared.runningApplications
        // Prioritize Roblox, then TextEdit for testing
        let targetApp = apps.first { $0.localizedName?.lowercased().contains("roblox") == true }
                     ?? apps.first { $0.localizedName?.lowercased().contains("textedit") == true }

        guard let app = targetApp else {
            print("❌ Target app (Roblox/TextEdit) not found!")
            isTyping = false
            return
        }

        let pid = app.processIdentifier
        let appName = app.localizedName ?? "Unknown"
        print("🎯 Target: \(appName) (PID: \(pid))")
        
        // Hide overlay to ensure OS focus switch is clean
        print("🚀 Hiding overlay...")
        NSApp.hide(nil)
        
        print("🚀 Activating \(appName)...")
        app.activate(options: .activateIgnoringOtherApps)
        
        // Wait longer for full application switch (0.7s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            print("⌨️ Starting accurate typing for: \(text)")
            self.typeCharactersSequentially(Array(text), pid: pid, index: 0)
        }
    }

    private func typeCharactersSequentially(_ chars: [Character], pid: pid_t, index: Int) {
        guard index < chars.count else {
            print("✨ All characters sent. Pressing Enter...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.simulateEnter(pid: pid)
                
                // Final cleanup: Wait then restore app
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    print("🏁 Sequence complete. Restoring SambungKata...")
                    NSApp.unhide(nil)
                    self.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                    self.isTyping = false
                    
                    // Reset JS processing state
                    self.webView.evaluateJavaScript("if(window.typingDone) window.typingDone();", completionHandler: nil)
                }
            }
            return
        }

        let char = chars[index]
        self.simulateKey(char: char, pid: pid)

        // Random pause between characters for more natural feel (120-200ms)
        let delayMs = Int.random(in: 120...200)
        let deadline = DispatchTime.now() + .milliseconds(delayMs)

        DispatchQueue.main.asyncAfter(deadline: deadline) {
            self.typeCharactersSequentially(chars, pid: pid, index: index + 1)
        }
    }

    private func keyCode(for char: Character) -> CGKeyCode? {
        let charStr = String(char).lowercased()
        let mapping: [String: CGKeyCode] = [
            "a": 0x00, "b": 0x0B, "c": 0x08, "d": 0x02, "e": 0x0E, "f": 0x03, "g": 0x05, "h": 0x04,
            "i": 0x22, "j": 0x26, "k": 0x28, "l": 0x25, "m": 0x2E, "n": 0x2D, "o": 0x1F, "p": 0x23,
            "q": 0x0C, "r": 0x0F, "s": 0x01, "t": 0x11, "u": 0x20, "v": 0x09, "w": 0x0D, "x": 0x07,
            "y": 0x10, "z": 0x06, "0": 0x1D, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "5": 0x17,
            "6": 0x16, "7": 0x1A, "8": 0x1C, "9": 0x19, " ": 0x31
        ]
        return mapping[charStr]
    }

    func simulateKey(char: Character, pid: pid_t) {
        // Use HID event source to mimic real hardware input
        let source = CGEventSource(stateID: .hidSystemState)
        
        let vk = keyCode(for: char) ?? 0 // Fallback to 0 if unknown
        
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vk, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vk, keyDown: false)
        
        // Also set Unicode for backup/non-HID listeners
        let utf16Chars = Array(String(char).utf16)
        keyDown?.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: utf16Chars)
        keyUp?.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: utf16Chars)
        
        keyDown?.flags = []
        keyUp?.flags = []
        
        print("   [DOWN] '\(char)' (VK: \(vk))")
        keyDown?.postToPid(pid)
        
        Thread.sleep(forTimeInterval: 0.08)
        
        print("   [UP]   '\(char)' (VK: \(vk))")
        keyUp?.postToPid(pid)
        
        Thread.sleep(forTimeInterval: 0.06)
    }

    func simulateEnter(pid: pid_t) {
        let source = CGEventSource(stateID: .hidSystemState)
        let kEnter: CGKeyCode = 0x24
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: kEnter, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: kEnter, keyDown: false)
        
        keyDown?.flags = []
        keyUp?.flags = []
        
        print("   [DOWN] ENTER")
        keyDown?.postToPid(pid)
        Thread.sleep(forTimeInterval: 0.08)
        print("   [UP]   ENTER")
        keyUp?.postToPid(pid)
        Thread.sleep(forTimeInterval: 0.06)
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
