import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Lock the window to a portrait phone-like size so the UI only ever has to
    // deal with one (mobile) layout. Fixed, non-resizable. Prefer 420x880 but
    // never exceed the screen's visible area (excludes menu bar + Dock) or the
    // window ends up clipped behind the Dock — App Review rejects that (G4).
    let preferred = NSSize(width: 420, height: 880)
    let visible = self.screen?.visibleFrame
      ?? NSScreen.main?.visibleFrame
      ?? NSRect(x: 0, y: 0, width: preferred.width, height: preferred.height)

    self.setContentSize(preferred)
    let titleBarOverhead = self.frame.height - preferred.height
    let size = NSSize(
      width: min(preferred.width, visible.width),
      height: min(preferred.height, visible.height - titleBarOverhead))
    self.setContentSize(size)
    self.contentMinSize = size
    self.contentMaxSize = size
    self.styleMask.remove(.resizable)

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
