import AppKit

class LoadingOverlay {
    static let shared = LoadingOverlay()

    private var window: NSWindow?
    private var spinner: NSProgressIndicator?

    func show() {
        guard window == nil else { return }
        guard let screen = NSScreen.main else { return }

        // Window size
        let windowSize: CGFloat = 64

        // Create window in bottom right
        let window = NSWindow(
            contentRect: NSRect(
                x: screen.frame.maxX - windowSize - 40,
                y: screen.frame.minY + 40,
                width: windowSize,
                height: windowSize
            ),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Create spinner
        let spinner = NSProgressIndicator(frame: NSRect(x: 16, y: 16, width: 32, height: 32))
        spinner.style = .spinning
        spinner.appearance = NSAppearance(named: .darkAqua)
        spinner.startAnimation(nil)

        window.contentView?.addSubview(spinner)
        window.orderFront(nil)

        self.window = window
        self.spinner = spinner
    }

    func hide() {
        spinner?.stopAnimation(nil)
        window?.orderOut(nil)
        window = nil
        spinner = nil
    }
}
