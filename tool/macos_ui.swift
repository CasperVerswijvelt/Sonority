// Agent-driven macOS UI testing helper: screenshot + drive the Sonority window.
//   swift tool/macos_ui.swift list
//   swift tool/macos_ui.swift shot [out.png]        (default /tmp/sonority.png)
//   swift tool/macos_ui.swift click <x> <y>         (window-relative points)
//   swift tool/macos_ui.swift type <text>
//   swift tool/macos_ui.swift key <return|tab|esc|up|down|left|right>
// Needs Screen Recording + Accessibility TCC for the host app (Terminal).

import CoreGraphics
import Foundation

let appName = "Sonority"

func windows() -> [[String: Any]] {
  CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                             kCGNullWindowID) as! [[String: Any]]
}

func sonorityWindow() -> [String: Any] {
  guard let w = windows().first(where: {
    ($0["kCGWindowOwnerName"] as? String) == appName
      && ($0["kCGWindowLayer"] as? Int) == 0
  }) else {
    FileHandle.standardError.write("error: no on-screen \(appName) window — is the app running?\n".data(using: .utf8)!)
    exit(1)
  }
  return w
}

func bounds(_ w: [String: Any]) -> CGRect {
  CGRect(dictionaryRepresentation: w["kCGWindowBounds"] as! CFDictionary)!
}

func activate() {
  // NSRunningApplication.activate() from a background process is ignored on
  // macOS 14+ (cooperative activation) — AppleScript still works.
  let p = Process()
  p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
  p.arguments = ["-e", "tell application \"\(appName)\" to activate"]
  try? p.run()
  p.waitUntilExit()
  usleep(300_000) // let focus settle
}

let args = CommandLine.arguments
let cmd = args.count > 1 ? args[1] : "help"

switch cmd {
case "list":
  for w in windows() {
    let owner = w["kCGWindowOwnerName"] as? String ?? "?"
    let name = w["kCGWindowName"] as? String ?? ""
    let id = w["kCGWindowNumber"] as? Int ?? 0
    let b = bounds(w)
    print("\(id)\t\(owner)\t\(name)\t\(Int(b.origin.x)) \(Int(b.origin.y)) \(Int(b.width)) \(Int(b.height))")
  }

case "shot":
  let out = args.count > 2 ? args[2] : "/tmp/sonority.png"
  let id = sonorityWindow()["kCGWindowNumber"] as! Int
  let p = Process()
  p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
  p.arguments = ["-o", "-x", "-l", String(id), out] // -o: no shadow, -x: no sound
  try! p.run()
  p.waitUntilExit()
  exit(p.terminationStatus == 0 ? { print(out); return 0 }() : 1)

case "click":
  guard args.count == 4, let x = Double(args[2]), let y = Double(args[3]) else {
    FileHandle.standardError.write("usage: click <x> <y> (window-relative)\n".data(using: .utf8)!)
    exit(2)
  }
  let b = bounds(sonorityWindow()) // CGWindow bounds are global, top-left origin — same space CGEvent uses
  activate()
  let pt = CGPoint(x: b.origin.x + x, y: b.origin.y + y)
  for (type, button) in [(CGEventType.leftMouseDown, CGMouseButton.left),
                         (CGEventType.leftMouseUp, CGMouseButton.left)] {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: pt,
            mouseButton: button)!.post(tap: .cghidEventTap)
    usleep(80_000)
  }

case "type":
  guard args.count > 2 else { exit(2) }
  activate()
  for ch in args[2].utf16 {
    for down in [true, false] {
      let ev = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)!
      var code = ch
      ev.keyboardSetUnicodeString(stringLength: 1, unicodeString: &code)
      ev.post(tap: .cghidEventTap)
      usleep(20_000)
    }
  }

case "key":
  let codes: [String: CGKeyCode] = ["return": 36, "tab": 48, "esc": 53,
                                    "left": 123, "right": 124, "down": 125, "up": 126]
  guard args.count > 2, let code = codes[args[2]] else {
    FileHandle.standardError.write("usage: key <\(codes.keys.sorted().joined(separator: "|"))>\n".data(using: .utf8)!)
    exit(2)
  }
  activate()
  for down in [true, false] {
    CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!.post(tap: .cghidEventTap)
    usleep(50_000)
  }

default:
  print("usage: macos_ui.swift list | shot [out.png] | click <x> <y> | type <text> | key <name>")
  exit(cmd == "help" ? 0 : 2)
}
