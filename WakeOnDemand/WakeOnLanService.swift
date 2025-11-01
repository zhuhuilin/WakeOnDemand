//
//  WakeOnLanService.swift
//  WakeOnDemand
//
//  Created by Huilin Zhu on 10/31/25.
//

import Network
import Foundation

class WakeOnLANService {
    func sendMagicPacket(macAddress: String, broadcastAddress: String, port: UInt16 = 9) {
        print("=== Wake-on-LAN ===")
        print("Target MAC: \(macAddress)")
        print("Broadcast: \(broadcastAddress)")
        print("Port: \(port)")
        
        guard let macData = parseMACAddress(macAddress) else {
            print("❌ Invalid MAC address format")
            return
        }
        
        let packet = createMagicPacket(macData: macData)
        print("Packet size: \(packet.count) bytes")
        
        // Use BSD sockets as primary method (most reliable)
        print("--- Primary: BSD Sockets ---")
        let success = sendWithBSDSockets(packet: packet, to: broadcastAddress, port: port)
        
        if !success {
            // Fallback: Try universal broadcast with BSD sockets
            print("--- Fallback: Universal Broadcast ---")
            _ = sendWithBSDSockets(packet: packet, to: "255.255.255.255", port: port)
        }
        
        // Also try Network framework for universal broadcast (works sometimes)
        print("--- Secondary: Network Framework (Universal) ---")
        sendWithNetworkFramework(packet: packet, to: "255.255.255.255", port: port)
    }
    
    private func createMagicPacket(macData: Data) -> Data {
        var packet = Data()
        
        // 6 bytes of 0xFF
        for _ in 0..<6 {
            packet.append(0xFF)
        }
        
        // 16 repetitions of MAC address
        for _ in 0..<16 {
            packet.append(macData)
        }
        
        return packet
    }
    
    private func parseMACAddress(_ macAddress: String) -> Data? {
        let cleaned = macAddress.replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
        
        guard cleaned.count == 12 else {
            print("❌ MAC address must be 12 hex characters, got \(cleaned.count)")
            return nil
        }
        
        let hexChars = CharacterSet(charactersIn: "0123456789abcdef")
        guard cleaned.trimmingCharacters(in: hexChars).isEmpty else {
            print("❌ MAC address contains invalid characters")
            return nil
        }
        
        var data = Data()
        var index = cleaned.startIndex
        
        for _ in 0..<6 {
            let nextIndex = cleaned.index(index, offsetBy: 2)
            let byteString = cleaned[index..<nextIndex]
            
            if let byte = UInt8(byteString, radix: 16) {
                data.append(byte)
            } else {
                print("❌ Invalid hex in MAC address: \(byteString)")
                return nil
            }
            
            index = nextIndex
        }
        
        return data
    }
    
    @discardableResult
    private func sendWithBSDSockets(packet: Data, to host: String, port: UInt16) -> Bool {
        guard isValidIPAddress(host) else {
            print("❌ Invalid IP address: \(host)")
            return false
        }
        
        let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        if sock < 0 {
            print("❌ Failed to create socket: \(String(describing: strerror(errno)))")
            return false
        }
        
        defer { close(sock) }
        
        // Enable broadcast
        var broadcast: Int32 = 1
        if setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &broadcast, socklen_t(MemoryLayout<Int32>.size)) < 0 {
            print("❌ Failed to set broadcast option: \(String(describing: strerror(errno)))")
            return false
        }
        
        // Set a short timeout
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = inet_addr(host)
        
        let sentBytes = packet.withUnsafeBytes { rawBufferPointer -> Int in
            let bufferPointer = rawBufferPointer.bindMemory(to: UInt8.self)
            return withUnsafePointer(to: &addr) { addrPtr in
                let sockaddrPtr = UnsafeRawPointer(addrPtr).assumingMemoryBound(to: sockaddr.self)
                return sendto(sock, bufferPointer.baseAddress, packet.count, 0,
                             sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        if sentBytes < 0 {
            print("❌ BSD socket send failed: \(String(describing: strerror(errno)))")
            return false
        } else if sentBytes != packet.count {
            print("⚠️ BSD socket sent \(sentBytes) bytes (expected \(packet.count))")
            return false
        } else {
            print("✅ BSD socket sent \(sentBytes) bytes successfully to \(host):\(port)")
            return true
        }
    }
    
    private func sendWithNetworkFramework(packet: Data, to host: String, port: UInt16) {
        guard isValidIPAddress(host) else {
            print("❌ Invalid IP address: \(host)")
            return
        }
        
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .udp
        )
        
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("✅ Network framework ready for \(host):\(port)")
                connection.send(content: packet, completion: .contentProcessed({ error in
                    if let error = error {
                        print("❌ Network framework send failed: \(error.localizedDescription)")
                    } else {
                        print("✅ Magic packet sent via Network framework")
                    }
                    connection.cancel()
                }))
            case .failed(let error):
                print("❌ Network framework connection failed: \(error.localizedDescription)")
                connection.cancel()
            case .cancelled:
                print("🔴 Network framework connection cancelled")
            default:
                break
            }
        }
        
        connection.start(queue: .global(qos: .background))
    }
    
    private func isValidIPAddress(_ string: String) -> Bool {
        var sin = sockaddr_in()
        var sin6 = sockaddr_in6()
        
        return string.withCString { cString in
            return inet_pton(AF_INET, cString, &sin.sin_addr) == 1 ||
                   inet_pton(AF_INET6, cString, &sin6.sin6_addr) == 1
        }
    }
}

// Global function to send magic packet
func sendMagicPacket(macAddress: String, broadcastAddress: String) {
    let wolService = WakeOnLANService()
    wolService.sendMagicPacket(macAddress: macAddress, broadcastAddress: broadcastAddress)
}
