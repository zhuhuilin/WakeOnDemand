//
//  Machine.swift
//  WakeOnDemand
//
//  Created by Huilin Zhu on 10/31/25.
//

import Foundation

struct Machine: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var macAddress: String
    var ipv4Address: String
    var mask: String
    var broadcastAddress: String
    var description: String
    var pingPort: Int
    
    init(id: UUID = UUID(), name: String, macAddress: String, ipv4Address: String, mask: String, broadcastAddress: String, description: String, pingPort: Int = 22) {
        self.id = id
        self.name = name
        self.macAddress = macAddress
        self.ipv4Address = ipv4Address
        self.mask = mask
        self.broadcastAddress = broadcastAddress
        self.description = description
        self.pingPort = pingPort
    }
    
    static func == (lhs: Machine, rhs: Machine) -> Bool {
        lhs.id == rhs.id
    }
}
