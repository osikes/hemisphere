import SwiftUI

@main
struct HemisphereApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Empty - we use menu bar only
        Settings {
            EmptyView()
        }
    }
}
