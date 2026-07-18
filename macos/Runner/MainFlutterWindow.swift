import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Resizable: the Flutter UI is now responsive (a bottom nav bar when narrow,
    // a NavigationRail + centered/multi-column content when wide — see
    // kWideLayoutBreakpoint). Open at a comfortable desktop size that shows the
    // wide layout, allow shrinking down to a phone-width minimum, and never
    // exceed the screen's visible area (excludes menu bar + Dock) or the window
    // clips behind the Dock — App Review rejects that (G4).
    let preferred = NSSize(width: 1100, height: 900)
    let minimum = NSSize(width: 380, height: 640)
    let visible = self.screen?.visibleFrame
      ?? NSScreen.main?.visibleFrame
      ?? NSRect(x: 0, y: 0, width: preferred.width, height: preferred.height)

    self.setContentSize(preferred)
    let titleBarOverhead = self.frame.height - preferred.height
    self.setContentSize(NSSize(
      width: min(preferred.width, visible.width),
      height: min(preferred.height, visible.height - titleBarOverhead)))
    self.contentMinSize = NSSize(
      width: min(minimum.width, visible.width),
      height: min(minimum.height, visible.height - titleBarOverhead))

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()

    // Center within the *visible* frame (not the full screen) so the Dock/menu
    // bar never clips the window. Done after super so the frame is settled.
    if let vf = self.screen?.visibleFrame {
      self.setFrameOrigin(NSPoint(
        x: vf.midX - self.frame.width / 2,
        y: vf.midY - self.frame.height / 2))
    }
  }
}
