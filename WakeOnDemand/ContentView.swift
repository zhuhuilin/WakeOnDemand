//
//  ContentView.swift
//  WakeOnDemand
//
//  Created by Huilin Zhu on 10/31/25.
//

import SwiftUI
import Network
import UserNotifications
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var machines: [Machine] = []
    @State private var selectedMachineIDs = Set<UUID>()
    @State private var showingAddSheet = false
    @State private var showingEditSheet = false
    @State private var showingExportSheet = false
    @State private var showingImportPanel = false
    @State private var showingWakeAlert = false
    @State private var sortOrder = [KeyPathComparator(\Machine.name)]
    @State private var editingMachine: Machine?
    @State private var notificationPermissionGranted = false
    @StateObject private var pingService = PingService()
    @State private var currentWakingMachine: Machine?
    
    var sortedMachines: [Machine] {
        machines.sorted(using: sortOrder)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Main table
            mainTable
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Button bar
            buttonBar
        }
        .navigationTitle("WakeOnDemand")
        .sheet(isPresented: $showingAddSheet) {
            AddEditMachineView(machines: $machines, isPresented: $showingAddSheet)
        }
        .sheet(isPresented: $showingEditSheet) {
            editSheetView
        }
        .alert("Waking Up \(currentWakingMachine?.name ?? "Machine")", isPresented: $showingWakeAlert) {
            wakeAlertButtons
        } message: {
            wakeAlertMessage
        }
        .fileExporter(
            isPresented: $showingExportSheet,
            document: MachinesDocument(machines: machines),
            contentType: .json,
            defaultFilename: "machines"
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
            checkNotificationPermission()
            pingService.startPeriodicStatusCheck(machines: machines)
        }
        .onDisappear {
            pingService.stopPeriodicStatusCheck()
        }
        .onChange(of: showingEditSheet) { isShowing in
            if !isShowing {
                editingMachine = nil
            }
        }
        .onChange(of: machines) { newMachines in
            pingService.startPeriodicStatusCheck(machines: newMachines)
        }
    }
    
    // MARK: - Main Table (Broken down into smaller parts)
    
    private var mainTable: some View {
        Table(sortedMachines, selection: $selectedMachineIDs, sortOrder: $sortOrder) {
            // Basic columns with simple values
            TableColumn("Name", value: \.name)
                .width(min: 100, max: 200)
            
            TableColumn("IP Address", value: \.ipv4Address)
                .width(min: 100, max: 150)
            
            TableColumn("MAC Address", value: \.macAddress)
                .width(min: 120, max: 180)
            
            TableColumn("Description", value: \.description)
                .width(min: 100, max: 200)
            
            // Ping Port column
            TableColumn("Ping Port") { machine in
                Text("\(machine.pingPort)")
            }
            .width(80)
            
            // Status column
            TableColumn("Status") { machine in
                statusColumnView(for: machine)
            }
            .width(90)
            
            // Action column
            TableColumn("Action") { machine in
                actionColumnView(for: machine)
            }
            .width(80)
        }
    }
    
    private func statusColumnView(for machine: Machine) -> some View {
        Group {
            if pingService.isCheckingMachine(machine) {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(width: 8, height: 8)
                    Text("Checking...")
                        .foregroundColor(.blue)
                        .font(.caption)
                }
            } else {
                let isOnline = pingService.getStatusForMachine(machine)
                HStack {
                    Circle()
                        .fill(isOnline ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(isOnline ? "Online" : "Offline")
                        .foregroundColor(isOnline ? .green : .red)
                        .font(.caption)
                }
            }
        }
    }
    
    private func actionColumnView(for machine: Machine) -> some View {
        let isOnline = pingService.getStatusForMachine(machine)
        return Button("Wake") {
            wakeMachine(machine)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isOnline)
    }
    
    // MARK: - Extracted Views
    
    private var buttonBar: some View {
        VStack(spacing: 8) {
            if !notificationPermissionGranted {
                Text("Notifications disabled - enable in System Settings")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            
            HStack {
                // Action buttons group
                HStack {
                    Button("Add") { showingAddSheet = true }
                    
                    Button("Edit") {
                        if let selectedID = selectedMachineIDs.first,
                           let machine = machines.first(where: { $0.id == selectedID }) {
                            editingMachine = machine
                            showingEditSheet = true
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
                    Button("Request Notifications") { requestNotificationPermission() }
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
    
    private var editSheetView: some View {
        Group {
            if let machine = editingMachine {
                AddEditMachineView(
                    machines: $machines,
                    isPresented: $showingEditSheet,
                    editingMachine: machine
                )
            } else {
                VStack {
                    Text("No machine selected")
                        .font(.headline)
                    Button("Close") {
                        showingEditSheet = false
                    }
                    .padding()
                }
                .frame(width: 200, height: 100)
            }
        }
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
        pingService.checkAllMachinesStatus(machines: machines)
    }
    
    private func checkNotificationPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.notificationPermissionGranted = (settings.authorizationStatus == .authorized)
            }
        }
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                self.notificationPermissionGranted = granted
                
                if let error = error {
                    print("Notification permission error: \(error.localizedDescription)")
                    self.showAlert(title: "Notification Error", message: "Failed to request notification permission: \(error.localizedDescription)")
                } else if granted {
                    print("Notification permission granted")
                    self.showAlert(title: "Notifications Enabled", message: "You will now receive notifications when Wake-on-LAN packets are sent.")
                } else {
                    print("Notification permission denied")
                    self.showAlert(title: "Notifications Disabled", message: "You can enable notifications later in System Settings > Notifications > WakeOnDemand.")
                }
            }
        }
    }
    
    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
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
                machines = importedMachines
                saveMachines()
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
