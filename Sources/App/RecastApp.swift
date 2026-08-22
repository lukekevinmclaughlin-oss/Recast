import SwiftUI

@main
struct RecastApp: App {
    @StateObject private var coordinator = ConversionCoordinator.shared
    @StateObject private var settings = ConversionSettings.shared
    @StateObject private var pro = ProManager.shared
    @StateObject private var engagement = EngagementManager.shared

    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        #if os(macOS)
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(coordinator)
                .environmentObject(settings)
                .environmentObject(pro)
                .environmentObject(engagement)
        } label: {
            Image("StatusItem")
                .renderingMode(.template)
        }
        .menuBarExtraStyle(.window)

        Window("Recast", id: "main") {
            MainWindowView()
                .environmentObject(coordinator)
                .environmentObject(settings)
                .environmentObject(pro)
                .environmentObject(engagement)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1000, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Files…") { coordinator.presentOpenPanel() }
                    .keyboardShortcut("o", modifiers: .command)
                Button("Floating Drop Window") { AppDelegate.shared?.toggleFloatingWindow() }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
            }
            CommandGroup(after: .pasteboard) {
                Button("Clear Completed") { coordinator.clearFinished() }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                    .disabled(!coordinator.hasFinishedJobs)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(coordinator)
                .environmentObject(pro)
                .environmentObject(engagement)
        }
        #else
        WindowGroup {
            MainContentView()
                .environmentObject(coordinator)
                .environmentObject(settings)
                .environmentObject(pro)
                .environmentObject(engagement)
        }
        #endif
    }
}
