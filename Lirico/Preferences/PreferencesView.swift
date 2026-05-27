import SwiftUI

struct PreferencesView: View {
    var body: some View {
        TabView {
            GeneralPreferencesView()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(0)

            DisplayPreferencesView()
                .tabItem { Label("Display", systemImage: "tv") }
                .tag(1)

            ShortcutPreferencesView()
                .tabItem { Label("Shortcut", systemImage: "keyboard") }
                .tag(2)

            FilterPreferencesView()
                .tabItem { Label("Filter", systemImage: "line.3.horizontal.decrease.circle") }
                .tag(3)

            LabPreferencesView()
                .tabItem { Label("Lab", systemImage: "flask") }
                .tag(4)

            SourcePreferencesView()
                .tabItem { Label("Source", systemImage: "list.bullet") }
                .tag(5)
        }
        .frame(minWidth: 550, minHeight: 400)
    }
}
