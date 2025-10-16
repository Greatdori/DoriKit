//===---*- Greatdori! -*---------------------------------------------------===//
//
// DoriStorage.swift
//
// This source file is part of the Greatdori! open source project
//
// Copyright (c) 2025 the Greatdori! project authors
// Licensed under Apache License v2.0
//
// See https://greatdori.memz.top/LICENSE.txt for license information
// See https://greatdori.memz.top/CONTRIBUTORS.txt for the list of Greatdori! project authors
//
//===----------------------------------------------------------------------===//

import Foundation

#if canImport(SwiftUI)
import SwiftUI

@propertyWrapper
public struct DoriStorage<Value: Sendable & DoriCacheable>: Sendable, DynamicProperty {
    private let key: String
    @State private var currentValue: Value
    
    public init(wrappedValue: Value, _ key: String) {
        self.key = key.replacingOccurrences(of: "/", with: "_")
        if let _data = try? Data(contentsOf: .init(filePath: NSHomeDirectory() + "/Documents/DoriStorage/\(key).plist")),
           let value = Value(fromCache: _data) {
            self._currentValue = .init(initialValue: value)
        } else {
            self._currentValue = .init(initialValue: wrappedValue)
        }
        
        if !FileManager.default.fileExists(atPath: NSHomeDirectory() + "/Documents/DoriStorage/") {
            try? FileManager.default.createDirectory(atPath: NSHomeDirectory() + "/Documents/DoriStorage/", withIntermediateDirectories: true)
        }
    }
    
    public var wrappedValue: Value {
        get {
            currentValue
        }
        nonmutating set {
            currentValue = newValue
            try? newValue.dataForCache.write(to: storageURL)
        }
    }
    
    public var projectedValue: Binding<Value> {
        $currentValue
    }
    
    private var storageURL: URL {
        .init(filePath: NSHomeDirectory() + "/Documents/DoriStorage/\(key).plist")
    }
}

#else

@propertyWrapper
public struct DoriStorage<Value: Sendable & DoriCacheable>: Sendable {
    private let key: String
    private let defaultValue: Value
    
    public init(wrappedValue: Value, _ key: String) {
        self.key = key.replacingOccurrences(of: "/", with: "_")
        self.defaultValue = wrappedValue
        
        if !FileManager.default.fileExists(atPath: NSHomeDirectory() + "/Documents/DoriStorage/") {
            try? FileManager.default.createDirectory(atPath: NSHomeDirectory() + "/Documents/DoriStorage/", withIntermediateDirectories: true)
        }
    }
    
    public var wrappedValue: Value {
        get {
            if let _data = try? Data(contentsOf: storageURL),
               let value = Value(fromCache: _data) {
                value
            } else {
                defaultValue
            }
        }
        nonmutating set {
            try? newValue.dataForCache.write(to: storageURL)
        }
    }
    
    private var storageURL: URL {
        .init(filePath: NSHomeDirectory() + "/Documents/DoriStorage/\(key).plist")
    }
}

#endif
