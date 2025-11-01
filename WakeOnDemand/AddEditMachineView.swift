//
//  AddEditMachineView.swift
//  WakeOnDemand
//
//  Created by Huilin Zhu on 10/31/25.
//


import SwiftUI

struct AddEditMachineView: View {
    @Binding var machines: [Machine]
    @Binding var isPresented: Bool
    var editingMachine: Machine?
    
    @State private var name: String
    @State private var macAddress: String
    @State private var ipv4Address: String
    @State private var mask: String
    @State private var broadcastAddress: String
    @State private var description: String
    @State private var pingPort: String
    
    @StateObject private var ipHelper = IPAddressHelper.shared
    @State private var showIPError = false
    @State private var showMaskError = false
    @State private var showBroadcastError = false
    @State private var ipModified = false
    @State private var maskModified = false
    // removed manual drag state; window is now a normal NSWindow with titlebar
    // Autosave debounce and UI indicator
    @State private var autosaveWorkItem: DispatchWorkItem? = nil
    @State private var isAutosaveIndicatorVisible: Bool = false
    private let autosaveDelay: TimeInterval = 0.6

    init(machines: Binding<[Machine]>, isPresented: Binding<Bool>, editingMachine: Machine? = nil) {
        self._machines = machines
        self._isPresented = isPresented
        self.editingMachine = editingMachine
        
        if let machine = editingMachine {
            _name = State(initialValue: machine.name)
            _macAddress = State(initialValue: machine.macAddress)
            _ipv4Address = State(initialValue: machine.ipv4Address)
            _mask = State(initialValue: machine.mask)
            _broadcastAddress = State(initialValue: machine.broadcastAddress)
            _description = State(initialValue: machine.description)
            _pingPort = State(initialValue: String(machine.pingPort))
        } else {
            // Use last entered values or defaults
            let lastValues = IPAddressHelper.shared.getLastValues()
            _name = State(initialValue: "")
            _macAddress = State(initialValue: "")
            _ipv4Address = State(initialValue: lastValues.ip)
            _mask = State(initialValue: lastValues.mask)
            _broadcastAddress = State(initialValue: lastValues.broadcast)
            _description = State(initialValue: "")
            _pingPort = State(initialValue: "22")
        }
    }
    
    var body: some View {
        VStack(spacing: 6) { // tightened spacing
            // Form rows with left labels
            VStack(alignment: .leading, spacing: 6) { // tightened spacing
                fieldRow(label: "Name") {
                    TextField("", text: $name)
                }

                fieldRow(label: "MAC Address") {
                    TextField("", text: $macAddress)
                }

                fieldRow(label: "IPv4 Address") {
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("", text: $ipv4Address)
                            .onChange(of: ipv4Address) { newValue in
                                ipModified = true
                                showIPError = !ipHelper.isValidIPAddress(newValue) && !newValue.isEmpty

                                // Auto-calculate mask and broadcast when IP changes
                                if ipHelper.isValidIPAddress(newValue) && !maskModified {
                                    if let settings = ipHelper.autoCalculateNetworkSettings(ip: newValue) {
                                        mask = settings.mask
                                        broadcastAddress = settings.broadcast
                                    }
                                }

                                // Validate broadcast when IP changes
                                if !broadcastAddress.isEmpty {
                                    showBroadcastError = !ipHelper.isValidBroadcast(ip: newValue, mask: mask, broadcast: broadcastAddress)
                                }

                                // Debounced autosave if editing
                                if let _ = editingMachine,
                                   ipHelper.isValidIPAddress(newValue),
                                   ipHelper.isValidSubnetMask(mask),
                                   ipHelper.isValidBroadcast(ip: newValue, mask: mask, broadcast: broadcastAddress) {
                                    scheduleAutosaveIfEditing()
                                }
                            }

                        if showIPError {
                            Text("Invalid IP address format")
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    }
                }

                fieldRow(label: "Subnet Mask") {
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("", text: $mask)
                            .onChange(of: mask) { newValue in
                                maskModified = true
                                showMaskError = !ipHelper.isValidSubnetMask(newValue) && !newValue.isEmpty

                                // Auto-calculate broadcast when mask changes
                                if ipHelper.isValidIPAddress(ipv4Address) && ipHelper.isValidSubnetMask(newValue) {
                                    if let broadcast = ipHelper.calculateBroadcast(ip: ipv4Address, mask: newValue) {
                                        broadcastAddress = broadcast
                                    }
                                }

                                // Validate broadcast when mask changes
                                if !broadcastAddress.isEmpty {
                                    showBroadcastError = !ipHelper.isValidBroadcast(ip: ipv4Address, mask: newValue, broadcast: broadcastAddress)
                                }

                                // Debounced autosave if editing
                                if let _ = editingMachine,
                                   ipHelper.isValidIPAddress(ipv4Address),
                                   ipHelper.isValidSubnetMask(newValue),
                                   ipHelper.isValidBroadcast(ip: ipv4Address, mask: newValue, broadcast: broadcastAddress) {
                                    scheduleAutosaveIfEditing()
                                }
                            }

                        if showMaskError {
                            Text("Invalid subnet mask")
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    }
                }

                fieldRow(label: "Broadcast") {
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("", text: $broadcastAddress)
                            .onChange(of: broadcastAddress) { newValue in
                                showBroadcastError = !ipHelper.isValidBroadcast(ip: ipv4Address, mask: mask, broadcast: newValue) && !newValue.isEmpty

                                // Debounced autosave if editing
                                if let _ = editingMachine,
                                   ipHelper.isValidIPAddress(ipv4Address),
                                   ipHelper.isValidSubnetMask(mask),
                                   ipHelper.isValidBroadcast(ip: ipv4Address, mask: mask, broadcast: newValue) {
                                    scheduleAutosaveIfEditing()
                                }
                            }

                        if showBroadcastError {
                            Text("Broadcast address doesn't match IP and subnet mask")
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    }
                }

                // Description (optional)
                fieldRow(label: "Description") {
                    TextField("", text: $description)
                }

                // Ping Port
                fieldRow(label: "Ping Port") {
                    TextField("", text: $pingPort)
                        .frame(maxWidth: 120)
                }
            }

            HStack {
                Button("Cancel") {
                    cancelAutosave()
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(editingMachine == nil ? "Add" : "Save") {
                    saveMachine()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isFormValid)
            }
            .padding(.horizontal, 10)

            // Autosave indicator
            if isAutosaveIndicatorVisible {
                HStack {
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Autosaved")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                    Spacer()
                }
                .transition(.opacity)
            }
        }
        // Use a tighter minimum height so there's no blank top/bottom
        .frame(minWidth: 500, minHeight: 380)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .onDisappear {
            // Ensure any pending autosave is cancelled when the view/window closes
            cancelAutosave()
        }
    }
    
    private var isFormValid: Bool {
        // Name, MAC, IPv4, Mask, Broadcast, and Ping Port are required and must be valid where applicable.
        let nonEmptyFields = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !macAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !ipv4Address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !mask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !broadcastAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !pingPort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            Int(pingPort) != nil

        let networkValid = ipHelper.isValidIPAddress(ipv4Address) && ipHelper.isValidSubnetMask(mask) && ipHelper.isValidBroadcast(ip: ipv4Address, mask: mask, broadcast: broadcastAddress)

        return nonEmptyFields && networkValid
    }
    
    private func calculateBroadcast() {
        if let broadcast = ipHelper.calculateBroadcast(ip: ipv4Address, mask: mask) {
            broadcastAddress = broadcast
            showBroadcastError = false
        }
    }
    
    private func useDefaults() {
        ipv4Address = ipHelper.defaultIP
        mask = ipHelper.defaultMask
        broadcastAddress = ipHelper.defaultBroadcast
        ipModified = false
        maskModified = false
        showIPError = false
        showMaskError = false
        showBroadcastError = false
    }
    
    private func saveMachine() {
        // If there's a pending autosave, cancel it to avoid duplicate writes
        cancelAutosave()

        let port = Int(pingPort) ?? 22
        
        let machine: Machine
        if let editingMachine = editingMachine {
            // Update existing machine
            machine = Machine(
                id: editingMachine.id,
                name: name,
                macAddress: macAddress,
                ipv4Address: ipv4Address,
                mask: mask,
                broadcastAddress: broadcastAddress,
                description: description,
                pingPort: port
            )
        } else {
            // Create new machine
            machine = Machine(
                name: name,
                macAddress: macAddress,
                ipv4Address: ipv4Address,
                mask: mask,
                broadcastAddress: broadcastAddress,
                description: description,
                pingPort: port
            )
            
            // Save these values as last used
            ipHelper.saveLastValues(ip: ipv4Address, mask: mask, broadcast: broadcastAddress)
        }
        
        if let editingMachine = editingMachine,
           let index = machines.firstIndex(where: { $0.id == editingMachine.id }) {
            machines[index] = machine
        } else {
            machines.append(machine)
        }
        
        saveMachines()
        isPresented = false
    }
    
    // If editing an existing machine, update the machines array and persist it
    private func syncEditingMachineFields() {
        guard let editing = editingMachine,
              let index = machines.firstIndex(where: { $0.id == editing.id }) else { return }

        // Update fields on the existing machine entry
        var updated = machines[index]
        updated.name = name
        updated.macAddress = macAddress
        updated.ipv4Address = ipv4Address
        updated.mask = mask
        updated.broadcastAddress = broadcastAddress
        updated.description = description
        updated.pingPort = Int(pingPort) ?? updated.pingPort

        machines[index] = updated
        saveMachines()
    }
    
    // Debounced autosave helpers
    private func scheduleAutosaveIfEditing() {
        // cancel previous scheduled work
        autosaveWorkItem?.cancel()

        let workItem = DispatchWorkItem {
            // Note: `self` is a struct (View). Using `weak` on a struct is invalid.
            // This work item runs on the main queue, so capturing `self` here is safe.
            self.syncEditingMachineFields()
            self.showAutosaveIndicator()
            // clear the reference
            DispatchQueue.main.async {
                self.autosaveWorkItem = nil
            }
        }

        autosaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + autosaveDelay, execute: workItem)
    }

    private func showAutosaveIndicator() {
        DispatchQueue.main.async {
            withAnimation { self.isAutosaveIndicatorVisible = true }
            // Hide after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                withAnimation { self.isAutosaveIndicatorVisible = false }
            }
        }
    }

    private func cancelAutosave() {
        autosaveWorkItem?.cancel()
        autosaveWorkItem = nil
    }
    
    private func saveMachines() {
        do {
            let data = try JSONEncoder().encode(machines)
            UserDefaults.standard.set(data, forKey: "machines")
        } catch {
            print("Failed to save machines: \(error)")
        }
    }
    
    // Cancel any pending autosave when the view disappears
    // Attach as view modifier so closing the window cancels pending autosaves
    // and avoids orphaned scheduled work
    
    // Add view lifecycle handlers
    
    // Small helper to render a labeled row (label + input on one line)
    @ViewBuilder
    private func fieldRow<Content: View>(label: String, @ViewBuilder input: () -> Content) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.callout) // slightly larger than subheadline
                    .foregroundColor(.secondary)
                if label != "Description" {
                    Text("*")
                        .font(.callout)
                        .foregroundColor(.red)
                }
            }
            .frame(width: 140, alignment: .leading)
            input()
            Spacer()
        }
    }
}
