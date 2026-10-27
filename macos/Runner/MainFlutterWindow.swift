import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var startupChannel: FlutterMethodChannel?
  private var firstFrameReady = false

  // The nib normally orders the window onscreen before Flutter has rendered.
  // Keep it offscreen until Dart confirms that the first frame was rasterized.
  override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    guard firstFrameReady || place == .out else { return }
    super.order(place, relativeTo: otherWin)
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let startupBackground = NSColor(
      srgbRed: 246.0 / 255.0,
      green: 247.0 / 255.0,
      blue: 249.0 / 255.0,
      alpha: 1.0
    )
    backgroundColor = startupBackground
    flutterViewController.backgroundColor = startupBackground

    let channel = FlutterMethodChannel(
      name: "xlog/startup",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "firstFrameReady":
        if !self.firstFrameReady {
          self.firstFrameReady = true
          self.makeKeyAndOrderFront(nil)
          NSApp.activate(ignoringOtherApps: true)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    startupChannel = channel

    let windowFrame = frame
    contentViewController = flutterViewController
    setFrame(windowFrame, display: false)
    // An offscreen NSWindow does not trigger viewWillAppear, so start the
    // engine explicitly instead of waiting for the normal visible-window path.
    flutterViewController.engine.run(withEntrypoint: nil)
    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
