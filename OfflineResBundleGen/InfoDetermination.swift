//===---*- Greatdori! -*---------------------------------------------------===//
//
// InfoDetermination.swift
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

import DoriKit
import Foundation

func analyzePathBranch(_ path: String) -> String {
    if pathIsInUnavailableBranch(path) {
        return "unsupported"
    } else if path.hasPrefix("video") {
        return "video"
    } else if path.hasPrefix("sound") {
        return "sound"
    } else {
        return "basic"
    }
    
    func pathIsInUnavailableBranch(_ path: String) -> Bool {
        let unavailablePaths = ["characters/ingameresourceset", "live2d", "musicscore", "pickupsituation", "star3d"]
        for unavailablePath in unavailablePaths {
            if path.hasPrefix(unavailablePath) {
                return true
            }
        }
        return false
    }
}

func readLastID(allowInitialization: Bool = true) async -> Int? {
    do {
        let outputString = try String(contentsOfFile: NSHomeDirectory() + "/Library/Containers/GreatdoriOfflineResBundleGen/LastID.txt", encoding: .utf8).replacingOccurrences(of: "\n", with: "")
        if let outputInt = Int(outputString) {
            return outputInt
        } else {
            print("[×][LastID] Failed to parse Bash output as an integer. Output string: \(outputString).")
        }
    } catch {
        print("[!][LastID] Encounted an error while reading LastID. Error: \(error).")
        if !FileManager.default.fileExists(atPath: NSHomeDirectory() + "/Library/Containers/GreatdoriOfflineResBundleGen") {
            if allowInitialization {
                print("[$][LastID] Last ID initialization requested.")
                return await writeLastID(id: await fetchNewestID())
            } else {
                print("[×][LastID] Last ID isn't initialized. Auto-initialization is disabled.")
            }
        } else {
            print("[×][LastID] Cannot read LastID . Error: \(error).")
        }
    }
    return nil
}

@discardableResult
func writeLastID(id: Int?) async -> Int? {
    guard id != nil else {
        print("[×][LastID] LastID cannot be written as `nil`.")
        return nil
    }
    do {
        if !FileManager.default.fileExists(atPath: NSHomeDirectory() + "/Library/Containers/GreatdoriOfflineResBundleGen") {
            try FileManager.default.createDirectory(atPath: NSHomeDirectory() + "/Library/Containers/GreatdoriOfflineResBundleGen", withIntermediateDirectories: true)
        }
        let data = "\(id!)".data(using: .utf8)!
        try data.write(to: URL(filePath: NSHomeDirectory() + "/Library/Containers/GreatdoriOfflineResBundleGen/LastID.txt"))
        print("[$][LastID] LastID written as #\(id!).")
    } catch {
        print("[×][LastID] Cannot write LastID due to a Bash command failure. Error: \(error).")
    }
    return id
}

func fetchNewestID() async -> Int? {
    return await getRecentAssetPatchNotes(lastID: 0)?.first?.relatedID
}



