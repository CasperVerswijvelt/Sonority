import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Lock the window to a portrait phone-like size so the UI only ever has to
    // deal with one (mobile) layout. Fixed, non-resizable, centered.
    let phoneSize = NSSize(width: 420, height: 880)
    self.setContentSize(phoneSize)
    self.contentMinSize = phoneSize
    self.contentMaxSize = phoneSize
    self.styleMask.remove(.resizable)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
