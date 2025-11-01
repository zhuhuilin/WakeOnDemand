//
//  PingService.swift
//  WakeOnDemand
//
//  Created by Huilin Zhu on 10/31/25.
//


import Foundation
import Network
import Combine

class PingService: ObservableObject {
    @Published var isReachable = false
    @Published var pingAttempts: Int = 0
    @Published var statusMessage: String = "Starting..."
    @Published var machineStatuses: [UUID: Bool] = [:]
    @Published var machineLastChecked: [UUID: Date] = [:]
    @Published var checkingMachines: Set<UUID> = [] // Track which machines are being checked
    
    private var connection: NWConnection?
    private var timer: Timer?
    private var statusTimer: Timer?
    private var attempts = 0
    private let maxAttempts = 30
    private let pingInterval: TimeInterval = 2.0
    
    func startPinging(host: String, port: Int, completion: @escaping (Bool) -> Void) {
        reset()
        updateStatusMessage("Sending magic packet...")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.updateStatusMessage("Waiting for machine to respond... (Attempt 1/\(self.maxAttempts))")
            self.startPingCycle(host: host, port: port, completion: completion)
        }
    }
    
    private func startPingCycle(host: String, port: Int, completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            self.timer = Timer.scheduledTimer(withTimeInterval: self.pingInterval, repeats: true) { [weak self] timer in
                guard let self = self else { return }
                
                self.attempts += 1
                self.updatePingAttempts(self.attempts)
                
                if self.attempts > self.maxAttempts {
                    self.updateStatusMessage("Timeout: Machine did not respond within 1 minute")
                    timer.invalidate()
                    DispatchQueue.main.async {
                        completion(false)
                    }
                    return
                }
                
                self.updateStatusMessage("Pinging... (Attempt \(self.attempts)/\(self.maxAttempts))")
                self.ping(host: host, port: port) { success in
                    if success {
                        self.updateStatusMessage("✅ Success! Machine is now live")
                        self.updateIsReachable(true)
                        timer.invalidate()
                        DispatchQueue.main.async {
                            completion(true)
                        }
                    } else {
                        self.updateStatusMessage("Waiting for response... (Attempt \(self.attempts)/\(self.maxAttempts))")
                    }
                }
            }
        }
    }
    
    func checkMachineStatus(machine: Machine, completion: @escaping (Bool) -> Void) {
        // Mark this machine as being checked
        DispatchQueue.main.async {
            self.checkingMachines.insert(machine.id)
        }
        
        pingForStatus(host: machine.ipv4Address, port: machine.pingPort) { success in
            DispatchQueue.main.async {
                self.machineStatuses[machine.id] = success
                self.machineLastChecked[machine.id] = Date()
                self.checkingMachines.remove(machine.id)
                completion(success)
            }
        }
    }
    
    func startPeriodicStatusCheck(machines: [Machine], interval: TimeInterval = 120.0) {
        stopPeriodicStatusCheck()
        
        // Check status immediately for all machines
        checkAllMachinesStatus(machines: machines)
        
        // Then set up periodic checking
        DispatchQueue.main.async {
            self.statusTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
                self.checkAllMachinesStatus(machines: machines)
            }
        }
    }
    
    func checkAllMachinesStatus(machines: [Machine]) {
        // Use DispatchGroup to check all machines concurrently
        let group = DispatchGroup()
        
        for machine in machines {
            group.enter()
            checkMachineStatus(machine: machine) { _ in
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            print("All status checks completed")
        }
    }
    
    func stopPeriodicStatusCheck() {
        DispatchQueue.main.async {
            self.statusTimer?.invalidate()
            self.statusTimer = nil
        }
    }
    
    func getStatusForMachine(_ machine: Machine) -> Bool {
        return machineStatuses[machine.id] ?? false
    }
    
    func isCheckingMachine(_ machine: Machine) -> Bool {
        return checkingMachines.contains(machine.id)
    }
    
    private func pingForStatus(host: String, port: Int, completion: @escaping (Bool) -> Void) {
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: UInt16(port))!,
            using: .tcp
        )
        
        var hasCompleted = false
        
        let completionHandler: (Bool) -> Void = { success in
            guard !hasCompleted else { return }
            hasCompleted = true
            completion(success)
            connection.cancel()
        }
        
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                completionHandler(true)
            case .failed:
                completionHandler(false)
            case .waiting:
                break
            case .preparing:
                break
            case .cancelled:
                completionHandler(false)
            @unknown default:
                completionHandler(false)
            }
        }
        
        connection.start(queue: .global(qos: .background))
        
        // Shorter timeout for status checks - 2 seconds
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
            if !hasCompleted {
                completionHandler(false)
            }
        }
    }
    
    private func ping(host: String, port: Int, completion: @escaping (Bool) -> Void) {
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: UInt16(port))!,
            using: .tcp
        )
        
        var hasCompleted = false
        
        let completionHandler: (Bool) -> Void = { success in
            guard !hasCompleted else { return }
            hasCompleted = true
            completion(success)
            connection.cancel()
        }
        
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                completionHandler(true)
            case .failed:
                completionHandler(false)
            case .waiting:
                break
            case .preparing:
                break
            case .cancelled:
                completionHandler(false)
            @unknown default:
                completionHandler(false)
            }
        }
        
        connection.start(queue: .global(qos: .background))
        
        // Longer timeout for wake process - 5 seconds
        DispatchQueue.global().asyncAfter(deadline: .now() + 5.0) {
            if !hasCompleted {
                completionHandler(false)
            }
        }
    }
    
    // Helper methods to ensure main thread updates
    private func updateStatusMessage(_ message: String) {
        DispatchQueue.main.async {
            self.statusMessage = message
        }
    }
    
    private func updatePingAttempts(_ attempts: Int) {
        DispatchQueue.main.async {
            self.pingAttempts = attempts
        }
    }
    
    private func updateIsReachable(_ reachable: Bool) {
        DispatchQueue.main.async {
            self.isReachable = reachable
        }
    }
    
    func stopPinging() {
        DispatchQueue.main.async {
            self.timer?.invalidate()
            self.timer = nil
            self.connection?.cancel()
            self.connection = nil
        }
    }
    
    func reset() {
        stopPinging()
        DispatchQueue.main.async {
            self.isReachable = false
            self.pingAttempts = 0
            self.attempts = 0
            self.statusMessage = "Starting..."
        }
    }
}
