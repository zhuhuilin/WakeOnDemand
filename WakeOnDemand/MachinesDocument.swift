//
//  MachinesDocument.swift
//  WakeOnDemand
//
//  Created by Huilin Zhu on 10/31/25.
//


import UniformTypeIdentifiers
import SwiftUI

struct MachinesDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    
    var machines: [Machine]
    
    init(machines: [Machine]) {
        self.machines = machines
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        machines = try JSONDecoder().decode([Machine].self, from: data)
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder().encode(machines)
        return FileWrapper(regularFileWithContents: data)
    }
}
