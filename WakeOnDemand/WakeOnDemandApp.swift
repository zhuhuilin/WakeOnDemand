//
//  WakeOnDemandApp.swift
//  WakeOnDemand
//
//  Created by Huilin Zhu on 10/31/25.
//

import SwiftUI

@main
struct WakeOnDemandApp: App {
    var body: some Scene {
        WindowGroup("WakeOnDemand") { // Set the window title here
            ContentView()
        }
        .windowStyle(DefaultWindowStyle())
        .commands {
            CommandGroup(replacing: .newItem) { }
            // Add Quit command to the menu for Cmd+Q
            CommandGroup(replacing: .appTermination) {
                Button("Quit WakeOnDemand") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
            CommandGroup(after: .saveItem) {
                Button("Export Machines...") {
                    // Notification-based export triggering removed.
                    // Use the Export button in the app UI instead.
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                
                Button("Import Machines...") {
                    // Notification-based import triggering removed.
                    // Use the Import button in the app UI instead.
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            }
        }
    }
}
