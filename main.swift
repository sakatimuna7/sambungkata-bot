import Cocoa
import WebKit
import Carbon
import Vision

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
        config.userContentController.add(self, name: "toggleSetup")
        config.userContentController.add(self, name: "startAutoDetect")
        config.userContentController.add(self, name: "stopAutoDetect")
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
        } else if message.name == "toggleSetup" {
            DispatchQueue.main.async {
                (NSApp.delegate as? AppDelegate)?.toggleSetupWindow()
            }
        } else if message.name == "startAutoDetect" {
            print("▶️ Starting Auto-Detect")
            DispatchQueue.main.async {
                (NSApp.delegate as? AppDelegate)?.startDetectionLoop()
            }
        } else if message.name == "stopAutoDetect" {
            print("⏹️ Stopping Auto-Detect")
            DispatchQueue.main.async {
                (NSApp.delegate as? AppDelegate)?.stopDetectionLoop()
            }
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
            Thread.sleep(forTimeInterval: Double.random(in: 0.08...0.15))
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

// ── DRAGGABLE VIEW (AREA SELECTOR) ────────────────────────────
class DraggableView: NSView {
    var label: String = ""
    var isDragging = false
    var isResizing = false
    var clickOffset: NSPoint = .zero
    var initialFrame: NSRect = .zero
    
    // To identify which layer this is (1, 2, or 3)
    var layerId: Int = 1

    init(frame: NSRect, label: String, color: NSColor, id: Int) {
        super.init(frame: frame)
        self.label = label
        self.layerId = id
        self.wantsLayer = true
        self.layer?.backgroundColor = color.withAlphaComponent(0.3).cgColor
        self.layer?.borderWidth = 2
        self.layer?.borderColor = color.cgColor
        self.layer?.cornerRadius = 4
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let text = NSString(string: "[\(label)]\nDrag to move\nBottom-Right to resize")
        let font = NSFont.systemFont(ofSize: 10, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.5)
        ]
        text.draw(at: NSPoint(x: 5, y: self.bounds.height - 35), withAttributes: attrs)
        
        // Resize handle
        let handleRect = NSRect(x: bounds.width - 15, y: 0, width: 15, height: 15)
        NSColor.white.withAlphaComponent(0.8).setFill()
        NSBezierPath(rect: handleRect).fill()
    }
    
    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let handleRect = NSRect(x: bounds.width - 20, y: 0, width: 20, height: 20)
        
        if handleRect.contains(location) {
            isResizing = true
            initialFrame = frame
            clickOffset = event.locationInWindow
        } else {
            isDragging = true
            clickOffset = location
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        if isDragging {
            let newLocation = event.locationInWindow
            var newOrigin = NSPoint(x: newLocation.x - clickOffset.x, y: newLocation.y - clickOffset.y)
            
            // Constrain to superview
            if let sup = superview {
                newOrigin.x = max(0, min(newOrigin.x, sup.bounds.width - frame.width))
                newOrigin.y = max(0, min(newOrigin.y, sup.bounds.height - frame.height))
            }
            frame.origin = newOrigin
        } else if isResizing {
            let deltaX = event.locationInWindow.x - clickOffset.x
            let deltaY = clickOffset.y - event.locationInWindow.y // Flipped Y for Cocoa
            
            var newWidth = max(50, initialFrame.width + deltaX)
            var newHeight = max(30, initialFrame.height + deltaY)
            
            // Constrain
            if let sup = superview {
                newWidth = min(newWidth, sup.bounds.width - initialFrame.minX)
                newHeight = min(newHeight, initialFrame.maxY) // Cannot grow taller than origin Y allows
            }
            
            // Update frame (adjusting Y origin to keep top stationary while resizing bottom)
            let newY = initialFrame.maxY - newHeight
            frame = NSRect(x: initialFrame.minX, y: newY, width: newWidth, height: newHeight)
            needsDisplay = true
        }
        
        // Save bounds to UserDefaults whenever it moves
        if let window = self.window {
            // Convert to screen coordinates
            let screenRect = window.convertToScreen(convert(bounds, to: nil))
            // Flip Y coordinate for CGWindowListCreateImage (starts top-left, not bottom-left)
            guard let screenHeight = NSScreen.main?.frame.height else { return }
            let cgRect = CGRect(x: screenRect.minX, y: screenHeight - screenRect.maxY, width: screenRect.width, height: screenRect.height)
            
            UserDefaults.standard.set(NSStringFromRect(cgRect), forKey: "SKAreaLayer\(layerId)")
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        isDragging = false
        isResizing = false
    }
}

class OCRManager {
    static let shared = OCRManager()
    
    // Captures a specific rect of the Roblox window specifically
    func captureScreenRect(_ rect: CGRect, isGlobal: Bool = true) -> CGImage? {
        let maxRetries = 3
        for _ in 0..<maxRetries {
            
            var robloxWindowID: CGWindowID? = nil
            
            // Find Roblox Window
            if let windowInfoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
                for info in windowInfoList {
                    if let appName = info[kCGWindowOwnerName as String] as? String,
                       appName == "Roblox" {
                        
                        if let windowID = info[kCGWindowNumber as String] as? CGWindowID {
                            robloxWindowID = windowID
                            break
                        }
                    }
                }
            }
            
            guard let winID = robloxWindowID else {
                logToJS("Roblox window not found. Please open Roblox first.", type: "error")
                return nil
            }
            
            // Create final rect
            let finalRect = rect
            
            // If the Area Selector passed us global OS coordinates, we can just capture those coordinates,
            // but we tell CGWindowListCreateImage to ONLY capture pixels from the Roblox window ID, ignoring overlays above it!
            
            if let image = CGWindowListCreateImage(
                finalRect,
                .optionIncludingWindow,
                winID,
                .boundsIgnoreFraming
            ) {
                return image
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return nil
    }

    // Performs OCR on a given CGImage
    func recognizeText(in image: CGImage, fast: Bool = false, completion: @escaping (String) -> Void) {
        let request = VNRecognizeTextRequest { (request, error) in
            guard let observations = request.results as? [VNRecognizedTextObservation], error == nil else {
                completion("")
                return
            }
            
            let recognizedStrings = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }
            
            completion(recognizedStrings.joined(separator: " "))
        }
        
        // Use fast mode for single characters/words as it's much faster
        request.recognitionLevel = fast ? .fast : .accurate
        
        // Disable language correction to prevent it from guessing words instead of raw characters
        request.usesLanguageCorrection = false
        
        if fast {
            // For fast mode (which we use for L1 and L2 mostly), we want pure characters.
            // But we don't want to over-constrain it if it reading symbols.
            // Let's at least disable language correction.
        }
        
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            logToJS("OCR Error: \(error)", type: "error")
            completion("")
        }
    }
    
    // Detects rectangles in L1 to trigger turn
    func detectRectangles(in image: CGImage, completion: @escaping (Int) -> Void) {
        let request = VNDetectRectanglesRequest { (request, error) in
            guard let results = request.results as? [VNRectangleObservation], error == nil else {
                completion(0)
                return
            }
            completion(results.count)
        }
        
        request.minimumConfidence = 0.3
        request.minimumAspectRatio = 0.3 // More lenient for rounded/skewed boxes
        request.maximumObservations = 10
        
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            completion(0)
        }
    }
}

// ── GLOBAL LOGGING TO JS ─────────────────────────────────────
func logToJS(_ msg: String, type: String = "normal") {
    print("[\(type.uppercased())] \(msg)") // Still log to console
    
    // Escape string for JS safely
    let safeMsg = msg.replacingOccurrences(of: "\\", with: "\\\\")
                     .replacingOccurrences(of: "\"", with: "\\\"")
                     .replacingOccurrences(of: "'", with: "\\'")
                     .replacingOccurrences(of: "\n", with: " ")
                     
    let jsCode = "if(window.logOcr) { window.logOcr('\(safeMsg)', '\(type)'); }"
    
    DispatchQueue.main.async {
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.panel.webView.evaluateJavaScript(jsCode, completionHandler: nil)
        }
    }
}

// ── AREA SELECTOR WINDOW ──────────────────────────────────────
class AreaSelectorPanel: NSWindow {
    
    init() {
        let screenRect = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        
        super.init(
            contentRect: screenRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.level = .screenSaver // Force it above EVERYTHING, even full-screen games
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.isOpaque = false
        self.backgroundColor = NSColor.black.withAlphaComponent(0.2) // Slight dim
        self.ignoresMouseEvents = false
        
        let contentView = NSView(frame: screenRect)
        self.contentView = contentView
        
        // Close button
        let closeBtn = NSButton(frame: NSRect(x: screenRect.width / 2 - 50, y: screenRect.height - 50, width: 100, height: 30))
        closeBtn.title = "Selesai Setup"
        closeBtn.bezelStyle = .rounded
        closeBtn.target = self
        closeBtn.action = #selector(closeSetup)
        contentView.addSubview(closeBtn)
        
        // Define default rects or load from UserDefaults
        let h = screenRect.height
        let def1 = CGRect(x: 100, y: 200, width: 300, height: 50)
        let def2 = CGRect(x: 100, y: 260, width: 80, height: 80)
        let def3 = CGRect(x: 100, y: 350, width: 300, height: 50)
        
        let l1Rect = loadRect(id: 1, defaultCG: def1, screenHeight: h)
        let l2Rect = loadRect(id: 2, defaultCG: def2, screenHeight: h)
        let l3Rect = loadRect(id: 3, defaultCG: def3, screenHeight: h)
        
        let layer1 = DraggableView(frame: l1Rect, label: "L1: GILIRAN", color: .systemGreen, id: 1)
        let layer2 = DraggableView(frame: l2Rect, label: "L2: SALAH (x)", color: .systemRed, id: 2)
        let layer3 = DraggableView(frame: l3Rect, label: "L3: KATA", color: .systemBlue, id: 3)
        
        contentView.addSubview(layer1)
        contentView.addSubview(layer2)
        contentView.addSubview(layer3)
    }
    
    func loadRect(id: Int, defaultCG: CGRect, screenHeight: CGFloat) -> NSRect {
        if let savedStr = UserDefaults.standard.string(forKey: "SKAreaLayer\(id)") {
            let cgRect = NSRectFromString(savedStr)
            // Convert CG (top-left) to NS (bottom-left)
            return NSRect(x: cgRect.minX, y: screenHeight - cgRect.minY - cgRect.height, width: cgRect.width, height: cgRect.height)
        }
        // defaultCG is top-left based.
        return NSRect(x: defaultCG.minX, y: screenHeight - defaultCG.minY - defaultCG.height, width: defaultCG.width, height: defaultCG.height)
    }
    
    @objc func closeSetup() {
        self.orderOut(nil)
        // Resume game focus
        NSApp.hide(nil)
    }
}

// ── APP DELEGATE ──────────────────────────────────────────────
class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: OverlayPanel!
    var setupPanel: AreaSelectorPanel!
    var hotKeyRef: EventHotKeyRef?
    var detectionTimer: Timer?
    var isDetecting = false

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        // Request Screen Capture access (required for macOS 10.15+)
        if !CGPreflightScreenCaptureAccess() {
            print("⚠️ Screen recording permission not granted! Requesting access...")
            CGRequestScreenCaptureAccess()
        }
        
        panel = OverlayPanel()
        setupPanel = AreaSelectorPanel()
        
        panel.makeKeyAndOrderFront(nil)
        registerHotKey()
        print("🚀 SambungKata started!")
    }
    
    // ── DETECTION LOOP ────────────────────────────────────────────
    func startDetectionLoop() {
        if isDetecting { return }
        isDetecting = true
        logToJS("Starting OCR Detection Loop...", type: "info")
        
        // Reduce interval from 0.8 to 0.5 for faster response
        detectionTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.runDetectionCycle()
        }
    }
    
    func stopDetectionLoop() {
        isDetecting = false
        detectionTimer?.invalidate()
        detectionTimer = nil
        logToJS("Stopped OCR Detection Loop", type: "info")
    }
    
    private func getLayerRect(id: Int) -> CGRect? {
        if let savedStr = UserDefaults.standard.string(forKey: "SKAreaLayer\(id)") {
            return NSRectFromString(savedStr)
        }
        return nil
    }
    
    private func runDetectionCycle() {
        guard let l1Rect = getLayerRect(id: 1),
              let l2Rect = getLayerRect(id: 2),
              let l3Rect = getLayerRect(id: 3) else { return }
        
        let l1Image = OCRManager.shared.captureScreenRect(l1Rect)
        let l2Image = OCRManager.shared.captureScreenRect(l2Rect)
        let l3Image = OCRManager.shared.captureScreenRect(l3Rect)
        
        guard let l1Img = l1Image, let l2Img = l2Image, let l3Img = l3Image else { return }

        // 1. Detect Rectangles in L1 (Shape Trigger)
        OCRManager.shared.detectRectangles(in: l1Img) { [weak self] count in
            guard let self = self else { return }
            
            if count > 0 {
                // ADDITIONAL VALIDATION: L1 MUST also contain OCR text to avoid noise
                OCRManager.shared.recognizeText(in: l1Img, fast: true) { l1Raw in
                    let l1Clean = l1Raw.lowercased().components(separatedBy: CharacterSet.letters.inverted).joined()
                    
                    if !l1Clean.isEmpty {
                        logToJS("L1 Active (Box + Text: \(l1Clean))", type: "success")
                        
                        // 2. Perform OCR on L3
                        // Use .accurate mode for L3 as requested for better precision
                        OCRManager.shared.recognizeText(in: l3Img, fast: false) { l3Raw in
                            let l3Filtered = l3Raw.replacingOccurrences(of: "|", with: "")
                                                  .replacingOccurrences(of: "l", with: "")
                                                  .trimmingCharacters(in: .whitespacesAndNewlines)
                            
                            let l3Clean = l3Filtered.lowercased().components(separatedBy: CharacterSet.letters.inverted).joined()
                            
                            // Pick the better result (L3 is primary, L1 is fallback)
                            let bestResult = l3Clean.count >= l1Clean.count ? l3Clean : l1Clean
                            
                            if !bestResult.isEmpty {
                                logToJS("Target Word: \(bestResult)", type: "info")
                                DispatchQueue.main.async {
                                    self.panel.webView.evaluateJavaScript("window.handleOCRTargetWord && window.handleOCRTargetWord('\(bestResult)');", completionHandler: nil)
                                }
                            }
                        }
                    } else {
                        // print("L1 Rectangle detected but no text found - skipping noise")
                    }
                }
            }
        }
        
        // 3. Independently check L2 for incorrect answer indicators
        OCRManager.shared.recognizeText(in: l2Img, fast: true) { [weak self] l2Raw in
            let l2Clean = l2Raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if l2Clean.contains("x") || l2Clean.contains("salah") {
                logToJS("Layer 2 Detected Potential Error!", type: "error")
                DispatchQueue.main.async {
                    self?.panel.webView.evaluateJavaScript("window.handleIncorrectAnswer && window.handleIncorrectAnswer();", completionHandler: nil)
                }
            }
        }
    }
    
    func toggleSetupWindow() {
        if setupPanel.isVisible {
            print("📉 Hiding setup panel")
            setupPanel.orderOut(nil)
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            print("📈 Showing setup panel")
            setupPanel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
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
