//===---*- Greatdori! -*---------------------------------------------------===//
//
// IRCoding.swift
//
// This source file is part of the Greatdori! open source project
//
// Copyright (c) 2025 the Greatdori! project authors
// Licensed under Apache License v2.0
//
// See https://greatdori.com/LICENSE.txt for license information
// See https://greatdori.com/CONTRIBUTORS.txt for the list of Greatdori! project authors
//
//===----------------------------------------------------------------------===//

import Foundation
internal import Compression

extension StoryIR {
    public func binaryEncoded() -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let plistEncodedData = try! encoder.encode(self.actions)
        
        let pageSize = 1024
        var compressedData = Data()
        let filter = try! OutputFilter(.compress, using: .lzfse) { data in
            if let data {
                compressedData.append(data)
            }
        }
        
        var index = 0
        let bufferSize = plistEncodedData.count
        while true {
            let rangeLength = min(pageSize, bufferSize - index)
            
            let subdata = plistEncodedData.subdata(
                in: index..<(index + rangeLength)
            )
            index += rangeLength
            
            try! filter.write(subdata)
            
            if rangeLength == 0 {
                break
            }
        }
        
        var headerMagic: UInt32 = 0x52495a
        compressedData.replaceSubrange(
            0..<3,
            with: unsafe Data(bytes: &headerMagic,
                              count: 3)
        )
        
        var eofMagic: UInt32 = 0x2452495a
        compressedData.replaceSubrange(
            (compressedData.endIndex - 4)..<compressedData.endIndex,
            with: unsafe Data(bytes: &eofMagic,
                              count: MemoryLayout.size(ofValue: eofMagic))
        )
        
        var metadata: UInt64 = 0
        
        metadata |= UInt64(self.locale._rawIntValue)
        
        compressedData.insert(
            contentsOf: unsafe Data(
                bytes: &metadata,
                count: MemoryLayout.size(ofValue: metadata)
            ),
            at: 4
        )
        
        return compressedData
    }
    
    public convenience init?(binary data: Data) {
        guard unsafe data.prefix(2).bytes
            .unsafeLoadUnaligned(as: UInt16.self) == 0x495a
                && data[2] == 0x52 else {
            return nil
        }
        guard unsafe data.suffix(4).bytes
            .unsafeLoadUnaligned(as: UInt32.self) == 0x2452495a else {
            return nil
        }
        
        var compressedData = data
        
        var metadata: UInt64 = 0
        metadata = unsafe compressedData[4..<12].bytes
            .unsafeLoadUnaligned(as: UInt64.self)
        compressedData.removeSubrange(4..<12)
        
        guard let metaLocale = DoriAPI.Locale(
            _rawIntValue: Int(metadata & 0x00000000000000FF)
        ) else { return nil }
        
        var bvxHeader: UInt32 = 0x787662
        compressedData.replaceSubrange(
            0..<3,
            with: unsafe Data(bytes: &bvxHeader,
                              count: 3)
        )
        
        var bvxEof: UInt32 = 0x24787662
        compressedData.replaceSubrange(
            (compressedData.endIndex - 4)..<compressedData.endIndex,
            with: unsafe Data(bytes: &bvxEof,
                              count: MemoryLayout.size(ofValue: bvxEof))
        )
        
        var decompressedData = Data()
        do {
            let pageSize = 1024
            var index = 0
            let bufferSize = compressedData.count
            let filter = try InputFilter(.decompress, using: .lzfse) { length in
                let rangeLength = min(length, bufferSize - index)
                let subdata = compressedData.subdata(in: index..<index + rangeLength)
                index += rangeLength
                return subdata
            }
            while let page = try filter.readData(ofLength: pageSize) {
                decompressedData.append(page)
            }
            
            let decoder = PropertyListDecoder()
            let actions = try decoder.decode(
                [StepAction].self,
                from: decompressedData
            )
            self.init(locale: metaLocale, actions: actions)
        } catch {
            return nil
        }
    }
}
