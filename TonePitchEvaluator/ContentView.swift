import SwiftUI

@main struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}

struct ContentView: View {
    var body: some View {
        PracticeView()
    }
}

#Preview {
    ContentView()
}
