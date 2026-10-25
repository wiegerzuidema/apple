import SwiftUI

@main struct MachineRemoteApp: App {
    @StateObject private var connection=Connection()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(connection).preferredColorScheme(.dark)
                .tint(Color(red: 0.92, green: 1.0, blue: 0.0))
                .onChange(of:scenePhase) { phase in
                    if phase == .active { connection.resume() }
                    else { connection.suspend() }
                }
        }
    }
}
