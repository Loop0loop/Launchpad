import AppKit
import LaunchpadApp

guard AppDelegate.acquireProcessOwnership() else { exit(EXIT_FAILURE) }
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
