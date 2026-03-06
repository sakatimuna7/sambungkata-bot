import Cocoa
import WebKit
import Carbon

// ── OVERLAY WINDOW ────────────────────────────────────────────
class OverlayPanel: NSPanel, WKScriptMessageHandler {
    var webView: WKWebView!

    init() {
        let w: CGFloat = 320
        let h: CGFloat = 650
        let screen = NSScreen.main?.visibleFrame ?? .init(x:0,y:0,width:1440,height:900)
        let x = screen.maxX - w - 20
        let y = screen.maxY - h - 20

        super.init(
            contentRect: .init(x:x, y:y, width:w, height:h),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

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
        config.userContentController.add(self, name: "closeWindow")
        config.userContentController.add(self, name: "typeInRoblox")
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        webView = WKWebView(frame: .init(x:0, y:0, width:width, height:height), configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false
        webView.autoresizingMask = [.width, .height]
        self.contentView = webView

        // Load HTML from app bundle
        var htmlUrl: URL?
        
        // 1. Try standard Resources folder
        if let bundleUrl = Bundle.main.url(forResource: "overlay", withExtension: "html") {
            htmlUrl = bundleUrl
            print("📁 Found overlay.html in Resources: \(bundleUrl.path)")
        } 
        // 2. Try same directory as executable (fallback)
        else {
            let exeDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
            let fallback = exeDir.appendingPathComponent("overlay.html")
            if FileManager.default.fileExists(atPath: fallback.path) {
                htmlUrl = fallback
                print("📁 Found overlay.html in MacOS folder: \(fallback.path)")
            }
        }

        if let url = htmlUrl {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            print("❌ Error: overlay.html not found anywhere!")
            // Try to load a simple error message
            webView.loadHTMLString("<html><body><h1>Error: overlay.html not found</h1></body></html>", baseURL: nil)
        }
    }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "closeWindow" {
            DispatchQueue.main.async { self.orderOut(nil) }
        } else if message.name == "typeInRoblox", let text = message.body as? String {
            print("📩 Received type request: \(text)")
            focusAndType(text: text)
        }
    }

    private var isTyping = false

    // ──────────────────────────────────────────────────────────────────
    // Improved Focus & Type
    // ──────────────────────────────────────────────────────────────────
    func focusAndType(text: String) {
        guard !isTyping else {
            print("⚠️ Already typing, ignoring.")
            return
        }
        isTyping = true

        let apps = NSWorkspace.shared.runningApplications
        let selfBundle = Bundle.main.bundleIdentifier ?? ""
        
        // Find target app: Roblox (RobloxPlayer) or TextEdit
        let targetApp =
            apps.first { $0.localizedName?.lowercased().contains("roblox") == true } ??
            apps.first { $0.bundleIdentifier?.lowercased().contains("roblox") == true } ??
            apps.first { $0.localizedName?.lowercased().contains("textedit") == true } ??
            apps.first {
                $0.activationPolicy == .regular &&
                $0.bundleIdentifier != selfBundle &&
                $0.bundleIdentifier != "com.apple.finder"
            }

        guard let app = targetApp else {
            print("❌ Error: No target application found.")
            finishTyping()
            return
        }

        let appName = app.localizedName ?? "Target"
        let pid = app.processIdentifier
        print("🎯 Using target app: \(appName) (PID: \(pid))")

        // 1. Hide ONLY the overlay window
        print("🫣 Hiding overlay window...")
        DispatchQueue.main.async {
            self.orderOut(nil)
        }

        // 2. Activate target application
        print("🚀 Activating \(appName)...")
        app.activate(options: .activateIgnoringOtherApps)

        // 3. Wait for focus transition to complete
        // Increased delay slightly for better reliability
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            print("⌨️ Starting typing sequence...")
            
            DispatchQueue.global(qos: .userInteractive).async {
                // Try both methods for maximum compatibility
                self.executeTypingSequence(text: text, pid: pid, appName: appName)
                
                // 4. Return control to overlay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.restoreOverlay()
                }
            }
        }
    }

    // ──────────────────────────────────────────────────────────────────
    // Robust Typing Sequence
    // ──────────────────────────────────────────────────────────────────
    private func executeTypingSequence(text: String, pid: pid_t, appName: String) {
        print("📜 Executing typing sequence for \"\(text)\" into \"\(appName)\"")
        
        // Strategy: Use AppleScript for TextEdit/System apps, 
        // and CGEvent for games like Roblox that might ignore AppleScript keystrokes.
        
        if appName.lowercased().contains("roblox") {
            print("🎮 Using CGEvent strategy for Roblox...")
            self.typeViaCGEvent(text: text, pid: pid)
        } else {
            print("🖥️ Using AppleScript strategy for \(appName)...")
            self.typeViaAppleScript(text: text)
        }
    }

    private func typeViaAppleScript(text: String) {
        let escapedText = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let scriptSource = """
        tell application "System Events"
            keystroke "\(escapedText)"
            delay 0.1
            key code 36
        end tell
        """
        
        var error: NSDictionary?
        if let script = NSAppleScript(source: scriptSource) {
            script.executeAndReturnError(&error)
        }
        
        if let err = error {
            print("❌ AppleScript Error: \(err)")
        } else {
            print("✅ AppleScript successful.")
        }
    }

    private func typeViaCGEvent(text: String, pid: pid_t) {
        let source = CGEventSource(stateID: .hidSystemState)
        
        for char in text {
            postKey(char: char, pid: pid, source: source)
            // Smaller random delay between characters for Roblox (80-150ms)
            Thread.sleep(forTimeInterval: Double.random(in: 0.08, out: 0.15))
        }
        
        // Press Enter
        Thread.sleep(forTimeInterval: 0.2)
        postSpecialKey(vk: 0x24, pid: pid, source: source) // kVK_Return
        print("✅ CGEvent sequence complete.")
    }

    private func postKey(char: Character, pid: pid_t, source: CGEventSource?) {
        let vk = keyCode(for: char)
        var utf16 = Array(String(char).utf16)
        
        let down = CGEvent(keyboardEventSource: source, virtualKey: vk, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: vk, keyDown: false)
        
        down?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
        up?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
        
        // Post to PID and Globally
        down?.postToPid(pid)
        down?.post(tap: .cgAnnotatedSessionEventTap)
        
        Thread.sleep(forTimeInterval: 0.05)
        
        up?.postToPid(pid)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    private func postSpecialKey(vk: CGKeyCode, pid: pid_t, source: CGEventSource?) {
        let down = CGEvent(keyboardEventSource: source, virtualKey: vk, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: vk, keyDown: false)
        
        down?.postToPid(pid)
        down?.post(tap: .cgAnnotatedSessionEventTap)
        
        Thread.sleep(forTimeInterval: 0.05)
        
        up?.postToPid(pid)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    private func restoreOverlay() {
        print("♻️ Restoring overlay...")
        DispatchQueue.main.async {
            self.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            self.isTyping = false
            self.webView.evaluateJavaScript("if(window.typingDone) window.typingDone();", completionHandler: nil)
        }
    }

    private func finishTyping() {
        DispatchQueue.main.async {
            self.isTyping = false
            self.webView.evaluateJavaScript("if(window.typingDone) window.typingDone();", completionHandler: nil)
        }
    }

    private func keyCode(for char: Character) -> CGKeyCode {
        let s = String(char).lowercased()
        let map: [String: CGKeyCode] = [
            "a":0x00,"b":0x0B,"c":0x08,"d":0x02,"e":0x0E,
            "f":0x03,"g":0x05,"h":0x04,"i":0x22,"j":0x26,
            "k":0x28,"l":0x25,"m":0x2E,"n":0x2D,"o":0x1F,
            "p":0x23,"q":0x0C,"r":0x0F,"s":0x01,"t":0x11,
            "u":0x20,"v":0x09,"w":0x0D,"x":0x07,"y":0x10,
            "z":0x06," ":0x31,
            "0":0x1D,"1":0x12,"2":0x13,"3":0x14,"4":0x15,
            "5":0x17,"6":0x16,"7":0x1A,"8":0x1C,"9":0x19
        ]
        return map[s] ?? 0x01 // Fallback to 's' or something safe if unknown
    }

    func toggle() {
        if isVisible { 
            print("📉 Hiding panel")
            orderOut(nil) 
        } else { 
            print("📈 Showing panel")
            makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true) 
        }
    }
}

extension Double {
    static func random(in min: Double, out max: Double) -> Double {
        return min + (Double(arc4random_uniform(1000)) / 1000.0) * (max - min)
    }
}

// ── APP DELEGATE ──────────────────────────────────────────────
class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: OverlayPanel!
    var hotKeyRef: EventHotKeyRef?

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panel = OverlayPanel()
        panel.makeKeyAndOrderFront(nil)
        registerHotKey()
        print("🚀 SambungKata started!")
    }

    func registerHotKey() {
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
            40, UInt32(cmdKey | shiftKey),
            hkID, GetApplicationEventTarget(),
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
