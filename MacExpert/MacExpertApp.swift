import SwiftUI

@main
struct MacExpertApp: App {
    @State private var viewModel = AmplifierViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(viewModel)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 400, height: 580)
    }
}
