//
//  IPAddressHelper.swift
//  WakeOnDemand
//
//  Created by Huilin Zhu on 10/31/25.
//


import Foundation
import Combine

class IPAddressHelper: ObservableObject {
    static let shared = IPAddressHelper()
    
    private let defaults = UserDefaults.standard
    private let lastIPKey = "lastIPAddress"
    private let lastMaskKey = "lastSubnetMask"
    private let lastBroadcastKey = "lastBroadcastAddress"
    
    // Default values
    let defaultIP = "192.168.1.100"
    let defaultMask = "255.255.255.0"
    let defaultBroadcast = "192.168.1.255"
    
    // Published properties to make it ObservableObject
    @Published var lastIP: String = "192.168.1.100"
    @Published var lastMask: String = "255.255.255.0"
    @Published var lastBroadcast: String = "192.168.1.255"
    
    private init() {
        // Load last values on initialization
        let values = getLastValues()
        lastIP = values.ip
        lastMask = values.mask
        lastBroadcast = values.broadcast
    }
    
    // Store last entered values
    func saveLastValues(ip: String, mask: String, broadcast: String) {
        defaults.set(ip, forKey: lastIPKey)
        defaults.set(mask, forKey: lastMaskKey)
        defaults.set(broadcast, forKey: lastBroadcastKey)
        
        // Update published properties
        lastIP = ip
        lastMask = mask
        lastBroadcast = broadcast
    }
    
    // Get last entered values
    func getLastValues() -> (ip: String, mask: String, broadcast: String) {
        let ip = defaults.string(forKey: lastIPKey) ?? defaultIP
        let mask = defaults.string(forKey: lastMaskKey) ?? defaultMask
        let broadcast = defaults.string(forKey: lastBroadcastKey) ?? defaultBroadcast
        return (ip, mask, broadcast)
    }
    
    // Calculate broadcast address from IP and mask
    func calculateBroadcast(ip: String, mask: String) -> String? {
        guard isValidIPAddress(ip), isValidIPAddress(mask) else { return nil }
        
        let ipParts = ip.split(separator: ".").compactMap { Int($0) }
        let maskParts = mask.split(separator: ".").compactMap { Int($0) }
        
        guard ipParts.count == 4, maskParts.count == 4 else { return nil }
        
        var broadcastParts = [Int]()
        for i in 0..<4 {
            let broadcastPart = (ipParts[i] & maskParts[i]) | (~maskParts[i] & 0xFF)
            broadcastParts.append(broadcastPart)
        }
        
        return broadcastParts.map(String.init).joined(separator: ".")
    }
    
    // Calculate network address from IP and mask
    func calculateNetwork(ip: String, mask: String) -> String? {
        guard isValidIPAddress(ip), isValidIPAddress(mask) else { return nil }
        
        let ipParts = ip.split(separator: ".").compactMap { Int($0) }
        let maskParts = mask.split(separator: ".").compactMap { Int($0) }
        
        guard ipParts.count == 4, maskParts.count == 4 else { return nil }
        
        var networkParts = [Int]()
        for i in 0..<4 {
            let networkPart = ipParts[i] & maskParts[i]
            networkParts.append(networkPart)
        }
        
        return networkParts.map(String.init).joined(separator: ".")
    }
    
    // Validate IP address format
    func isValidIPAddress(_ string: String) -> Bool {
        let parts = string.split(separator: ".")
        guard parts.count == 4 else { return false }
        
        for part in parts {
            guard let number = Int(part) else { return false }
            if number < 0 || number > 255 { return false }
        }
        
        return true
    }
    
    // Validate subnet mask
    func isValidSubnetMask(_ string: String) -> Bool {
        guard isValidIPAddress(string) else { return false }
        
        let parts = string.split(separator: ".").compactMap { Int($0) }
        var binaryMask = ""
        
        for part in parts {
            binaryMask += String(part, radix: 2).leftPadding(toLength: 8, withPad: "0")
        }
        
        // Check if mask has contiguous 1s followed by 0s
        var foundZero = false
        for char in binaryMask {
            if char == "0" {
                foundZero = true
            } else if foundZero && char == "1" {
                return false
            }
        }
        
        return true
    }
    
    // Validate that broadcast matches IP and mask
    func isValidBroadcast(ip: String, mask: String, broadcast: String) -> Bool {
        guard isValidIPAddress(ip), isValidSubnetMask(mask), isValidIPAddress(broadcast) else {
            return false
        }
        
        if let calculatedBroadcast = calculateBroadcast(ip: ip, mask: mask) {
            return broadcast == calculatedBroadcast
        }
        
        return false
    }
    
    // Auto-calculate mask and broadcast when IP changes
    func autoCalculateNetworkSettings(ip: String) -> (mask: String, broadcast: String)? {
        // Common subnet patterns for private networks
        let commonSubnets = [
            "10.": "255.0.0.0",
            "172.16.": "255.255.0.0",
            "172.17.": "255.255.0.0",
            "172.18.": "255.255.0.0",
            "172.19.": "255.255.0.0",
            "172.20.": "255.255.0.0",
            "172.21.": "255.255.0.0",
            "172.22.": "255.255.0.0",
            "172.23.": "255.255.0.0",
            "172.24.": "255.255.0.0",
            "172.25.": "255.255.0.0",
            "172.26.": "255.255.0.0",
            "172.27.": "255.255.0.0",
            "172.28.": "255.255.0.0",
            "172.29.": "255.255.0.0",
            "172.30.": "255.255.0.0",
            "172.31.": "255.255.0.0",
            "192.168.": "255.255.255.0"
        ]
        
        // Find matching subnet
        for (prefix, mask) in commonSubnets {
            if ip.hasPrefix(prefix) {
                if let broadcast = calculateBroadcast(ip: ip, mask: mask) {
                    return (mask, broadcast)
                }
            }
        }
        
        // Default to /24 if no match found
        let defaultMask = "255.255.255.0"
        if let broadcast = calculateBroadcast(ip: ip, mask: defaultMask) {
            return (defaultMask, broadcast)
        }
        
        return nil
    }
}

// String extension for padding
extension String {
    func leftPadding(toLength: Int, withPad character: Character) -> String {
        let stringLength = self.count
        if stringLength < toLength {
            return String(repeatElement(character, count: toLength - stringLength)) + self
        } else {
            return String(self.suffix(toLength))
        }
    }
}
