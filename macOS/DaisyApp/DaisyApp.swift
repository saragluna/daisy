import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        setApplicationIcon()
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            ServiceManager.shared.startAll()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ServiceManager.shared.stopAll()
    }

    private func setApplicationIcon() {
        let executableURL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        let executableDirectory = executableURL.deletingLastPathComponent()
        let resourcesDirectory = executableDirectory.deletingLastPathComponent().appendingPathComponent("Resources")

        let candidateURLs = [
            resourcesDirectory.appendingPathComponent("AppIcon.icns"),
            executableDirectory
                .appendingPathComponent("Daisy_Daisy.bundle")
                .appendingPathComponent("AppIcon.icns")
        ]

        for url in candidateURLs {
            if let iconImage = NSImage(contentsOf: url) {
                NSApplication.shared.applicationIconImage = iconImage
                return
            }
        }
    }
}

@main
struct DaisyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var serviceManager = ServiceManager.shared
    @StateObject private var settingsManager = SettingsManager.shared
    @StateObject private var logManager = LogManager.shared

    var body: some Scene {
        WindowGroup("Daisy", id: "main") {
            ContentView()
                .environmentObject(serviceManager)
                .environmentObject(settingsManager)
                .environmentObject(logManager)
                .frame(minWidth: 760, minHeight: 520)
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 860, height: 600)
        .commands {
            CommandMenu("Services") {
                ForEach(ServiceID.allCases) { serviceID in
                    let state = serviceManager.state(for: serviceID)
                    Button(state.isRunning ? "Stop \(serviceID.displayName)" : "Start \(serviceID.displayName)") {
                        state.isRunning ? serviceManager.stop(serviceID) : serviceManager.start(serviceID)
                    }
                }
            }
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(serviceManager)
        } label: {
            let allRunning = serviceManager.services.allSatisfy(\.isRunning)
            Image(systemName: allRunning ? "checkmark.circle.fill" : "circle")
                .symbolRenderingMode(.palette)
                .foregroundStyle(allRunning ? .green : .secondary, .primary)
        }
    }
}

struct MenuBarView: View {
    @EnvironmentObject var serviceManager: ServiceManager
    @Environment(\.openWindow) var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Daisy")
                .font(.headline)
                .padding(.horizontal, 8)
                .padding(.top, 4)

            Divider()

            ForEach(serviceManager.services) { service in
                Button {
                    service.isRunning ? serviceManager.stop(service.id) : serviceManager.start(service.id)
                } label: {
                    Label(
                        service.isRunning ? "Stop \(service.id.displayName)" : "Start \(service.id.displayName)",
                        systemImage: service.isRunning ? "stop.fill" : "play.fill"
                    )
                }
            }

            Divider()

            Button {
                openWindow(id: "main")
                NSApplication.shared.activate(ignoringOtherApps: true)
            } label: {
                Label("Open Daisy", systemImage: "macwindow")
            }
            .keyboardShortcut("O")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .keyboardShortcut("Q")
        }
        .padding(4)
    }
}
