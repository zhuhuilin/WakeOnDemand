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
        VStack(spacing: 0) {
            // Header removed — window title bar already displays Add/Edit
            // Main content
            VStack(spacing: 16) {
                Form {
                    Section(header: Text("Machine Information")) {
                        TextField("Name", text: $name)
                        TextField("MAC Address", text: $macAddress)
                        TextField("Description", text: $description)
                    }
                    
                    Section(header: Text("Network Configuration")) {
                        TextField("IPv4 Address", text: $ipv4Address)
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
                                
                                // If editing an existing machine and network fields are valid, persist changes
                                if let _ = editingMachine,
                                   ipHelper.isValidIPAddress(newValue),
                                   ipHelper.isValidSubnetMask(mask),
                                   ipHelper.isValidBroadcast(ip: newValue, mask: mask, broadcast: broadcastAddress) {
                                    syncEditingMachineFields()
                                }
                            }
                        
                        if showIPError {
                            Text("Invalid IP address format")
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                        
                        TextField("Subnet Mask", text: $mask)
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
                                
                                // Persist if editing and validations are satisfied
                                if let _ = editingMachine,
                                   ipHelper.isValidIPAddress(ipv4Address),
                                   ipHelper.isValidSubnetMask(newValue),
                                   ipHelper.isValidBroadcast(ip: ipv4Address, mask: newValue, broadcast: broadcastAddress) {
                                    syncEditingMachineFields()
                                }
                            }
                        
                        if showMaskError {
                            Text("Invalid subnet mask")
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                        
                        TextField("Broadcast Address", text: $broadcastAddress)
                            .onChange(of: broadcastAddress) { newValue in
                                showBroadcastError = !ipHelper.isValidBroadcast(ip: ipv4Address, mask: mask, broadcast: newValue) && !newValue.isEmpty
                                
                                // Persist if editing and validations are satisfied
                                if let _ = editingMachine,
                                   ipHelper.isValidIPAddress(ipv4Address),
                                   ipHelper.isValidSubnetMask(mask),
                                   ipHelper.isValidBroadcast(ip: ipv4Address, mask: mask, broadcast: newValue) {
                                    syncEditingMachineFields()
                                }
                            }
                        
                        if showBroadcastError {
                            Text("Broadcast address doesn't match IP and subnet mask")
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                        
                        HStack {
                            Button("Calculate Broadcast") {
                                calculateBroadcast()
                            }
                            .disabled(!ipHelper.isValidIPAddress(ipv4Address) || !ipHelper.isValidSubnetMask(mask))
                            
                            Spacer()
                            
                            Button("Use Defaults") {
                                useDefaults()
                            }
                        }
                    }
                    
                    Section(header: Text("Wake Settings")) {
                        TextField("Ping Port", text: $pingPort)
                            .help("Port to check for machine availability (e.g., 22 for SSH, 3389 for RDP)")
                    }
                }
                .formStyle(.grouped)
                
                HStack {
                    Button("Cancel") {
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
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .padding(.top, 8)
        }
        // Use a flexible minimum height so the window can be resized and there is no forced blank space
        .frame(minWidth: 500, minHeight: 420)
    }
    
    private var isFormValid: Bool {
        // Require Name, MAC, IPv4, Broadcast, and Ping Port to be non-empty.
        // Keep a numeric check for ping port.
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !macAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !ipv4Address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !broadcastAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !pingPort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        Int(pingPort) != nil
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
    
    private func saveMachines() {
        do {
            let data = try JSONEncoder().encode(machines)
            UserDefaults.standard.set(data, forKey: "machines")
        } catch {
            print("Failed to save machines: \(error)")
        }
    }
}
