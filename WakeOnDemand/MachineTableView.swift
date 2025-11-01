//
//  MachineTableView.swift
//  WakeOnDemand
//
//  Created by Huilin Zhu on 10/31/25.
//


import SwiftUI

struct MachineTableView: View {
    let machines: [Machine]
    @Binding var selectedMachineIDs: Set<UUID>
    @Binding var sortOrder: [KeyPathComparator<Machine>]
    @ObservedObject var pingService: PingService
    // Callback to perform wake action; provided by parent view
    var onWake: (Machine) -> Void
    
    var body: some View {
        Table(machines, selection: $selectedMachineIDs, sortOrder: $sortOrder) {
            // Name column
            TableColumn("Name", value: \.name)
                .width(min: 100, max: 200)
            
            // IP Address column
            TableColumn("IP Address", value: \.ipv4Address)
                .width(min: 100, max: 150)
            
            // MAC Address column
            TableColumn("MAC Address", value: \.macAddress)
                .width(min: 120, max: 180)
            
            // Description column
            TableColumn("Description", value: \.description)
                .width(min: 100, max: 200)
            
            // Ping Port column
            TableColumn("Ping Port") { machine in
                Text("\(machine.pingPort)")
            }
            .width(80)
            
            // Status column
            TableColumn("Status") { machine in
                statusView(for: machine)
            }
            .width(90)
            
            // Last Checked column
            TableColumn("Last Checked") { machine in
                lastCheckedView(for: machine)
            }
            .width(min: 120, max: 180)
             
             // Action column
             TableColumn("Action") { machine in
                 actionButton(for: machine)
             }
             .width(80)
         }
     }
    
    @ViewBuilder
    private func statusView(for machine: Machine) -> some View {
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
            HStack {
                Circle()
                    .fill(pingService.getStatusForMachine(machine) ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(pingService.getStatusForMachine(machine) ? "Online" : "Offline")
                    .foregroundColor(pingService.getStatusForMachine(machine) ? .green : .red)
                    .font(.caption)
            }
        }
    }
    
    private func actionButton(for machine: Machine) -> some View {
        Button("Wake") {
            // Call the provided wake closure on the parent
            onWake(machine)
        }
        .buttonStyle(.borderedProminent)
    }
    
    private func lastCheckedView(for machine: Machine) -> some View {
        if let date = pingService.machineLastChecked[machine.id] {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            return Text(formatter.localizedString(for: date, relativeTo: Date()))
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            return Text("—")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
