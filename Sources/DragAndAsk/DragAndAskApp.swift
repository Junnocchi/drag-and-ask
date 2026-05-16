import SwiftUI

@main
struct DragAndAskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Empty — AppDelegate manages all windows manually so .accessory policy
        // plays nicely. (SwiftUI's Settings scene doesn't work reliably for
        // menu bar apps.)
        Settings { EmptyView() }
    }
}
