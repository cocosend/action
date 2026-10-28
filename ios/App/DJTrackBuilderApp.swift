import SwiftUI

@main
struct DJTrackBuilderApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var audio = AudioController()

    var body: some Scene {
        WindowGroup {
            ConsoleView()
                .environmentObject(audio)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { phase in
                    if phase == .background { audio.saveNow() }
                }
        }
    }
}
