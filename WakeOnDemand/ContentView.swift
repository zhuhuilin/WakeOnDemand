//
//  ContentView.swift
//  WakeOnDemand
//
//  Created by Huilin Zhu on 10/31/25.
//

import SwiftUI
import Network
import UniformTypeIdentifiers
import AppKit
import Combine

struct ContentView: View {
    @State private var machines: [Machine] = []
    @State private var selectedMachineIDs = Set<UUID>()
    // We present Add/Edit in a standalone NSWindow so it can be moved/resized
    // (replacing the previous sheet-based presentation)
    @State private var showingExportSheet = false
    @State private var showingImportPanel = false
    @State private var showingWakeAlert = false
    @State private var sortOrder = [KeyPathComparator(\Machine.name)]
    @State private var editingMachine: Machine?
    @StateObject private var pingService = PingService()
    @State private var currentWakingMachine: Machine?
    // Keep strong references to window delegates so they aren't deallocated
    @State private var windowDelegates: [WindowDelegate] = []
    // Persisted status check interval (seconds)
    @State private var statusInterval: TimeInterval = UserDefaults.standard.double(forKey: "statusCheckInterval") == 0 ? 120.0 : UserDefaults.standard.double(forKey: "statusCheckInterval")

    // local tick to force view refreshes for timers
    @State private var refreshTick: Date = Date()

    // Computed export filename: WOD + timestamp + .json
    private var exportDefaultFilename: String {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmmss"
        return "WOD" + df.string(from: Date()) + ".json"
    }

    var sortedMachines: [Machine] {
        machines.sorted(using: sortOrder)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Use the separate table view
            MachineTableView(
                machines: sortedMachines,
                selectedMachineIDs: $selectedMachineIDs,
                sortOrder: $sortOrder,
                pingService: pingService,
                onWake: { machine in
                    // Directly call wakeMachine when Wake is pressed
                    wakeMachine(machine)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Button bar
            buttonBar
        }
        .frame(minWidth: 560, minHeight: 360)
        .navigationTitle("WakeOnDemand")
        // NOTE: Add/Edit windows are presented as standalone NSWindows so
        // they can be moved and resized. See `openAddEditWindow` below.
        .alert("Waking Up \(currentWakingMachine?.name ?? "Machine")", isPresented: $showingWakeAlert) {
            wakeAlertButtons
        } message: {
            wakeAlertMessage
        }
        .fileExporter(
            isPresented: $showingExportSheet,
            document: MachinesDocument(machines: machines),
            contentType: .json,
            defaultFilename: exportDefaultFilename
        ) { result in
            if case .failure(let error) = result {
                print("Export failed: \(error)")
            }
        }
        .fileImporter(
            isPresented: $showingImportPanel,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .onAppear {
            loadMachines()
            // Start periodic checks using the persisted interval
            pingService.startPeriodicStatusCheck(machines: machines, interval: statusInterval)
        }
        .onDisappear {
            pingService.stopPeriodicStatusCheck()
        }
        // When machines change (e.g. via import), do NOT trigger an immediate check; just restart the countdown
        .onChange(of: machines) { newMachines in
            pingService.resetPeriodicStatusCheck(machines: newMachines, interval: statusInterval)
        }
        // Timer to refresh "Last Checked" relative timestamps every 60s
        .onReceive(Timer.publish(every: 60.0, on: .main, in: .common).autoconnect()) { _ in
            // Trigger a view refresh so RelativeDateTimeFormatter updates
            refreshTick = Date()
        }
        // Timer to update countdown indicator every second
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            // Update tick so countdown/progress recomputes
            refreshTick = Date()
        }
    }

    // MARK: - Extracted Views

    private var buttonBar: some View {
        VStack(spacing: 8) {
            HStack {
                // Action buttons group
                HStack {
                    Button("Add") { openAddEditWindow(editingMachine: nil) }

                    Button("Edit") {
                        if let selectedID = selectedMachineIDs.first,
                           let machine = machines.first(where: { $0.id == selectedID }) {
                            openAddEditWindow(editingMachine: machine)
                        }
                    }
                    .disabled(selectedMachineIDs.count != 1)

                    Button("Delete") { deleteSelectedMachines() }
                        .disabled(selectedMachineIDs.isEmpty)

                    Button("Refresh Status") { refreshAllStatuses() }
                }

                Spacer()

                // Utility buttons group
                HStack {
                    // Status interval picker
                    Picker(selection: $statusInterval) {
                        Text("30s").tag(TimeInterval(30.0))
                        Text("1m").tag(TimeInterval(60.0))
                        Text("2m").tag(TimeInterval(120.0))
                        Text("5m").tag(TimeInterval(300.0))
                        Text("10m").tag(TimeInterval(600.0))
                        Text("30m").tag(TimeInterval(1800.0))
                    } label: {
                        Text("Poll:")
                    }
                    .pickerStyle(.menu)
                    .onChange(of: statusInterval) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "statusCheckInterval")
                        // Do NOT trigger an immediate check. Set as pending interval to take effect after next scheduled check
                        pingService.setPendingInterval(newValue)
                    }

                    // Countdown indicator to next scheduled automatic check
                    if let next = pingService.nextCheckDate {
                        // remaining seconds until next check
                        let remainingSeconds = max(0.0, next.timeIntervalSinceNow)
                        // prefer pendingInterval (what user selected) so the countdown aligns with the picker selection
                        let totalInterval = pingService.pendingInterval ?? pingService.currentInterval ?? statusInterval
                        let total = max(1.0, totalInterval)
                        let fractionElapsed = min(1.0, max(0.0, 1.0 - (remainingSeconds / total)))
                        // Format remaining as mm:ss
                        let mins = Int(remainingSeconds) / 60
                        let secs = Int(remainingSeconds) % 60
                        let mmss = String(format: "%02d:%02d", mins, secs)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Next: \(mmss)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            ProgressView(value: fractionElapsed)
                                .progressViewStyle(LinearProgressViewStyle())
                                .frame(width: 100)
                        }
                    } else {
                        Text("Next: —")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Button("Export") { showingExportSheet = true }
                    Button("Import") { showingImportPanel = true }

                    Button("Quit") { NSApplication.shared.terminate(nil) }
                        .keyboardShortcut("q", modifiers: .command)
                        .foregroundColor(.red)
                }
            }
        }
        .padding()
        .frame(height: 60)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var wakeAlertButtons: some View {
        Group {
            if !pingService.isReachable && pingService.pingAttempts < 30 {
                Button("Cancel") {
                    pingService.stopPinging()
                    showingWakeAlert = false
                }
            } else {
                Button("OK") {
                    showingWakeAlert = false
                    if let machine = currentWakingMachine {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            pingService.checkMachineStatus(machine: machine) { _ in }
                        }
                    }
                }
            }
        }
    }

    private var wakeAlertMessage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(pingService.statusMessage)

            if pingService.pingAttempts > 0 {
                ProgressView(value: Double(pingService.pingAttempts), total: 30.0)
                    .progressViewStyle(LinearProgressViewStyle())

                HStack {
                    Text("Progress:")
                    Spacer()
                    Text("\(pingService.pingAttempts)/30 attempts")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if pingService.isReachable {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title2)
            }
        }
    }

    // MARK: - Methods

    private func wakeMachine(_ machine: Machine) {
        print("=== Starting Wake Process ===")
        print("Machine: \(machine.name)")
        print("MAC: \(machine.macAddress)")
        print("IP: \(machine.ipv4Address)")
        print("Ping Port: \(machine.pingPort)")

        currentWakingMachine = machine
        showingWakeAlert = true

        sendMagicPacket(macAddress: machine.macAddress, broadcastAddress: machine.broadcastAddress)

        pingService.startPinging(host: machine.ipv4Address, port: machine.pingPort) { success in
            print("Wake process result: \(success ? "SUCCESS" : "FAILED")")

            if success {
                DispatchQueue.main.async {
                    self.pingService.machineStatuses[machine.id] = true
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    showingWakeAlert = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                        pingService.checkMachineStatus(machine: machine) { success in
                            print("Final status check for \(machine.name): \(success ? "Online" : "Offline")")
                        }
                    }
                }
            } else {
                showingWakeAlert = false
            }
        }
    }

    private func refreshAllStatuses() {
        // Perform an immediate status update
        pingService.checkAllMachinesStatus(machines: machines)
        // Restart the periodic timer countdown (do not trigger an extra immediate check)
        pingService.resetPeriodicStatusCheck(machines: machines, interval: statusInterval)
    }

    private func deleteSelectedMachines() {
        machines.removeAll { machine in
            selectedMachineIDs.contains(machine.id)
        }
        selectedMachineIDs.removeAll()
        saveMachines()
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }

            if url.startAccessingSecurityScopedResource() {
                defer { url.stopAccessingSecurityScopedResource() }

                let data = try Data(contentsOf: url)
                let importedMachines = try JSONDecoder().decode([Machine].self, from: data)
                // Update machines but do not trigger an immediate status check; onChange will reset the countdown only
                machines = importedMachines
                saveMachines()
            } else {
                print("Failed to access selected file")
            }
        } catch {
            print("Import failed: \(error)")
        }
    }

    private func loadMachines() {
        if let data = UserDefaults.standard.data(forKey: "machines") {
            do {
                machines = try JSONDecoder().decode([Machine].self, from: data)
            } catch {
                print("Failed to load machines: \(error)")
            }
        }
    }

    private func saveMachines() {
        do {
            let data = try JSONEncoder().encode(machines)
            UserDefaults.standard.set(data, forKey: "machines")
        } catch {
            print("Failed to save machines: \(error)")
        }
    }
}

// Small NSWindowDelegate class used to call back when a window closes
final class WindowDelegate: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?
    // optional key used to persist window frame in UserDefaults
    let frameUserDefaultsKey: String?

    init(frameUserDefaultsKey: String? = nil, onClose: (() -> Void)? = nil) {
        self.frameUserDefaultsKey = frameUserDefaultsKey
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        // Persist the window frame if key provided
        if let key = frameUserDefaultsKey,
           let window = notification.object as? NSWindow {
            let f = window.frame
            let dict: [String: Double] = [
                "x": Double(f.origin.x),
                "y": Double(f.origin.y),
                "width": Double(f.size.width),
                "height": Double(f.size.height)
            ]
            UserDefaults.standard.set(dict, forKey: key)
        }

        onClose?()
    }
}

// Helper to present Add/Edit in a standalone, resizable NSWindow
extension ContentView {
     private func openAddEditWindow(editingMachine: Machine?) {
        // Record editing machine so ContentView state is consistent while the window is open
        self.editingMachine = editingMachine

        // Create an NSWindow first so we can reference it from the Binding below
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 420),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = editingMachine == nil ? "Add Machine" : "Edit Machine"
        window.center()
        window.isReleasedWhenClosed = false
        // Allow moving the window by clicking and dragging the background/content area
        window.isMovableByWindowBackground = true
        // Ensure the title is visible (so the window isn't using a hidden titlebar layout)
        window.titleVisibility = .visible
        // Ensure the window can be resized but has a sensible minimum matching the view's min frame
        window.minSize = NSSize(width: 500, height: 380)

        // Create and retain a delegate to observe window close events and persist frame
        let delegate = WindowDelegate(frameUserDefaultsKey: "AddEditWindowFrame")
        window.delegate = delegate
        // Keep strong reference to the delegate so it doesn't get deallocated
        windowDelegates.append(delegate)

        // When the window closes clear editingMachine and release the delegate reference
        delegate.onClose = { [weak delegate] in
            DispatchQueue.main.async {
                // `self` is a struct (View) — capture normally here to update state
                self.editingMachine = nil
                if let d = delegate, let idx = self.windowDelegates.firstIndex(where: { $0 === d }) {
                    self.windowDelegates.remove(at: idx)
                }
            }
        }

        // Binding that stays "true" while the window is open and will close the window when set to false
        let isPresentedBinding = Binding<Bool>(
            get: { true },
            set: { newValue in
                if !newValue {
                    window.close()
                }
            }
        )

        // Restore previously saved frame if available
        if let dict = UserDefaults.standard.dictionary(forKey: "AddEditWindowFrame") as? [String: Double],
           let x = dict["x"], let y = dict["y"], let w = dict["width"], let h = dict["height"] {
            let savedRect = NSRect(x: x, y: y, width: w, height: h)
            window.setFrame(savedRect, display: true)
        }

        let hosting = NSHostingController(rootView: AddEditMachineView(machines: $machines, isPresented: isPresentedBinding, editingMachine: editingMachine))
        window.contentViewController = hosting
        window.makeKeyAndOrderFront(nil)
     }
}
