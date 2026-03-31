//===---*- Greatdori! -*---------------------------------------------------===//
//
// FrontendTeamBuilder.swift
//
// This source file is part of the Greatdori! open source project
//
// Copyright (c) 2026 the Greatdori! project authors
// Licensed under Apache License v2.0
//
// See https://greatdori.com/LICENSE.txt for license information
// See https://greatdori.com/CONTRIBUTORS.txt for the list of Greatdori! project authors
//
//===----------------------------------------------------------------------===//

import Foundation
internal import os

#if canImport(Metal)
internal import Metal
#endif

extension DoriFrontend {
    open class TeamBuilder: @unchecked Sendable {
        public var eventInformation: EventInformation?
        public var liveInformation: LiveInformation?
        public var songInformation: SongInformation?
        public var cards: [CardInformation] = []
        public var areaItems: [AreaItemInformation] = []
        public var isHardwareAccelerationDisabled = false
        
        private var allSkills: [DoriAPI.Skills.Skill]
        
        public init?() async {
            if let skills = await DoriAPI.Skills.all() {
                self.allSkills = skills
            } else {
                return nil
            }
        }
        
        private let areaItemGroups: [[Int]] = [
            [1, 2, 3, 4, 5, 73, 83, 90, 97], // Mic
            [6, 7, 8, 9, 10, 74, 84, 91, 98], // Guitar
            [11, 12, 13, 14, 15, 75, 85, 93, 99], // Bass, PAREO's Keyboard, Rana's Guitar
            [16, 17, 18, 19, 20, 76, 86, 92, 101], // Drum
            [21, 22, 23, 24, 25, 77, 87, 94, 100], // Keyboard, Misaki's DJ Decks, Rui's Violin, CHU²'s DJ Decks, Soyo's Bass
            [26, 27, 28, 29, 30, 78, 88, 95, 102], // Poster
            [80, 81, 82], // Magazine
            [31, 32, 33, 34, 35, 79, 89, 96, 103], // Entrance
            [66, 67, 69, 70], // Plaza
            [56, 57, 58, 60] // Menu
        ]
        private let bandIDCharacterMap: [Int: [Int]] = [
            1: [1, 2, 3, 4, 5],
            2: [6, 7, 8, 9, 10],
            3: [11, 12, 13, 14, 15],
            4: [16, 17, 18, 19, 20],
            5: [21, 22, 23, 24, 25],
            18: [31, 32, 33, 34, 35],
            21: [26, 27, 28, 29, 30],
            45: [36, 37, 38, 39, 40]
        ]
        
        #if canImport(Metal)
        // Hardware acceleration
        private var haDevice: MTLDevice!
        private var haLibrary: MTLLibrary!
        private var haCommandQueue: MTLCommandQueue!
        #endif // canImport(Metal)
        
        internal func _checkPreconditions() {
            precondition(liveInformation != nil, """
            'liveInformation' is required for team calculating
            """)
            precondition(songInformation != nil, """
            'songInformation' is required for team calculating
            """)
            if case .challengeLive = liveInformation! {
                precondition(eventInformation?.eventType == .challengeLive, """
                'liveInformation' could be 'challengeLive' only if 'eventType' \
                of 'eventInformation' is 'challengeLive'
                """)
            }
        }
        
        internal func _setupForHardwareAccelerationIfNeeded() -> Bool {
            #if canImport(Metal)
            if haDevice == nil {
                haDevice = MTLCreateSystemDefaultDevice()
                if haDevice == nil {
                    return false
                }
                
                haLibrary = try? haDevice.makeDefaultLibrary(bundle: #bundle)
                if haLibrary == nil {
                    return false
                }
                
                haCommandQueue = haDevice.makeCommandQueue()
                if haCommandQueue == nil {
                    return false
                }
            }
            return true
            #else
            return false
            #endif
        }
        
        open func calculateMaximize(
            target: MaximizeCalculationTarget,
            maxResults: Int = 10,
            centerSkill: DoriAPI.Skills.Skill? = nil
        ) async -> [TeamResult] {
            _checkPreconditions()
            
            switch target {
            case .bandPower:
                return await _calculateMaximizeTargetBandPower(
                    maxResults: maxResults
                )
            case .score:
                return await _calculateMaximizeTargetScore(
                    maxResults: maxResults,
                    centerSkill: centerSkill
                )
            case .eventPoint:
                fatalError("Not implemented")
            }
        }
        
        open func _calculateMaximizeTargetBandPower(
            maxResults: Int
        ) async -> [TeamResult] {
            // [CharacterID: [Attribute: (Card, BaseStat)]]
            var topCardsByAttr: [Int: [DoriAPI.Attribute: (CardInformation, DoriAPI.Cards.Stat)]] = [:]
            
            for card in self.cards {
                guard let baseStat = card.card.stat.calculated(
                    level: card.level, rarity: card.card.rarity,
                    masterRank: card.masterRank, viewedStoryCount: card.viewedStoryCount,
                    trained: card.trained
                ) else { continue }
                
                let charID = card.card.characterID
                let attr = card.card.attribute
                
                var factor = 1.0
                if let info = self.eventInformation {
                    factor += info.attributeBonuses[attr] ?? 0
                    factor += info.characterBonuses[charID] ?? 0
                    factor += info.masterRankBonus[card.card.rarity - 1][card.masterRank]
                    factor += info.cardBonus[card.card.id] ?? 0
                }
                let adjustedStat = baseStat * factor
                
                if topCardsByAttr[charID] == nil { topCardsByAttr[charID] = [:] }
                
                if let existing = topCardsByAttr[charID]?[attr] {
                    if adjustedStat.total > existing.1.total {
                        topCardsByAttr[charID]?[attr] = (card, adjustedStat)
                    }
                } else {
                    topCardsByAttr[charID]?[attr] = (card, adjustedStat)
                }
            }
            
            var bestTeams: [TeamResult] = []
            
            let attributes: [DoriAPI.Attribute] = [.powerful, .cool, .happy, .pure]
            
            if !isHardwareAccelerationDisabled && _setupForHardwareAccelerationIfNeeded() {
                #if canImport(Metal)
                let calcFunc = self.haLibrary.makeFunction(name: "maxBandPower")!
                let calcFuncPSO = try! await self.haDevice.makeComputePipelineState(function: calcFunc)
                
                for targetAttr in attributes {
                    let candidateChars = topCardsByAttr
                        .sorted { $0.key < $1.key }
                        .compactMap { (charID, attrs) -> (Int, (CardInformation, DoriAPI.Cards.Stat))? in
                            guard let data = attrs[targetAttr] else { return nil }
                            return (charID, data)
                        }
                    
                    guard candidateChars.count >= 5 else { continue }
                    
                    let allGroups = self.groupedAreaItems().compactMap {
                        let result = $0.filter {
                            $0.item.targetAttributes.contains(targetAttr)
                        }
                        return !result.isEmpty ? result : nil
                    }
                    
                    struct HAAreaItem {
                        var performanceBoost: Float
                        var techniqueBoost: Float
                        var visualBoost: Float
                        var targetAttributes: UInt32
                    }
                    struct HACardStats {
                        var performance: Int32
                        var technique: Int32
                        var visual: Int32
                    }
                    struct HAMaxBandPowerResult {
                        var index1: UInt32
                        var index2: UInt32
                        var power: UInt32
                    }
                    
                    var _groupCombinations: [[(Int, Int)]] = []
                    for groupingBandID in [0] + bandIDCharacterMap.keys {
                        var combination: [(Int, Int)] = []
                        for (groupIndex, itemGroup) in allGroups.enumerated() {
                            if groupingBandID == 0 {
                                if let itemIndex = itemGroup.firstIndex(where: {
                                    $0.item.targetBandIDs.count == bandIDCharacterMap.keys.count
                                }) {
                                    combination.append((groupIndex, itemIndex))
                                }
                            } else {
                                if let itemIndex = itemGroup.firstIndex(where: {
                                    $0.item.targetBandIDs.contains(groupingBandID)
                                }) {
                                    combination.append((groupIndex, itemIndex))
                                }
                            }
                        }
                        _groupCombinations.append(combination)
                    }
                    let groupCombinationStride = _groupCombinations.max { $0.count < $1.count }!.count
                    var groupCombinations: [[(Int, Int)]] = .init(
                        repeating: .init(repeating: (0, 0), count: groupCombinationStride),
                        count: _groupCombinations.count
                    )
                    for (i, combination) in _groupCombinations.enumerated() {
                        for (j, pair) in combination.enumerated() {
                            groupCombinations[i][j] = pair
                        }
                    }
                    
                    let charCombinations = combinations(for: Array(candidateChars), size: 5)
                    
                    let calcCommandBuffer = self.haCommandQueue.makeCommandBuffer()!
                    let calcEncoder = calcCommandBuffer.makeComputeCommandEncoder()!
                    calcEncoder.setComputePipelineState(calcFuncPSO)
                    
                    let _attrShifts: [DoriAPI.Attribute: Int] = [
                        .powerful: 0,
                        .cool: 1,
                        .happy: 2,
                        .pure: 3
                    ]
                    let areaItemBufferStride = allGroups.max { $0.count < $1.count }!.count
                    var areaItems = Array<[HAAreaItem]>(
                        repeating: .init(
                            repeating: .init(
                                performanceBoost: 1,
                                techniqueBoost: 1,
                                visualBoost: 1,
                                targetAttributes: 1
                            ),
                            count: areaItemBufferStride
                        ),
                        count: allGroups.count
                    )
                    for (i, items) in allGroups.enumerated() {
                        for (j, item) in items.enumerated() {
                            areaItems[i][j] = HAAreaItem(
                                performanceBoost: Float(item.item.performanceBoosts[item.level]!.jp!),
                                techniqueBoost: Float(item.item.techniqueBoosts[item.level]!.jp!),
                                visualBoost: Float(item.item.visualBoosts[item.level]!.jp!),
                                targetAttributes: item.item.targetAttributes.reduce(into: 0) {
                                    $0 |= 1 << _attrShifts[$1]!
                                }
                            )
                        }
                    }
                    let areaItemBuffer = unsafe areaItems.flatMap { $0 }.withUnsafeBytes { ptr in
                        unsafe self.haDevice.makeBuffer(
                            bytes: ptr.baseAddress!,
                            length: ptr.count,
                            options: .storageModeShared
                        )
                    }
                    let cardStats = candidateChars.map {
                        HACardStats(
                            performance: Int32($0.1.1.performance),
                            technique: Int32($0.1.1.technique),
                            visual: Int32($0.1.1.visual)
                        )
                    }
                    let cardStatsBuffer = unsafe cardStats.withUnsafeBytes { ptr in
                        unsafe self.haDevice.makeBuffer(
                            bytes: ptr.baseAddress!,
                            length: ptr.count,
                            options: .storageModeShared
                        )
                    }
                    struct _Pair {
                        let a: Int32
                        let b: Int32
                    }
                    let areaItemCombinationBuffer = unsafe groupCombinations.flatMap {
                        return $0.map {
                            _Pair(a: Int32($0.0), b: Int32($0.1))
                        }
                    }.withUnsafeBytes { ptr in
                        unsafe self.haDevice.makeBuffer(
                            bytes: ptr.baseAddress!,
                            length: ptr.count,
                            options: .storageModeShared
                        )
                    }
                    let cardStatCombinationBuffer = unsafe charCombinations.flatMap {
                        $0.map { Int32($0) }
                    }.withUnsafeBytes { ptr in
                        unsafe self.haDevice.makeBuffer(
                            bytes: ptr.baseAddress!,
                            length: ptr.count,
                            options: .storageModeShared
                        )
                    }
                    let flagBuffer = unsafe [
                        Int32(_attrShifts[targetAttr]!),
                        Int32(groupCombinations.count),
                        Int32(areaItemBufferStride),
                        Int32(groupCombinationStride)
                    ].withUnsafeBytes { ptr in
                        unsafe self.haDevice.makeBuffer(
                            bytes: ptr.baseAddress!,
                            length: ptr.count,
                            options: .storageModeShared
                        )
                    }
                    let resultBuffer = self.haDevice.makeBuffer(
                        length: groupCombinations.count * charCombinations.count * MemoryLayout<HAMaxBandPowerResult>.stride,
                        options: .storageModeShared
                    )

                    calcEncoder.setBuffer(areaItemBuffer, offset: 0, index: 0)
                    calcEncoder.setBuffer(cardStatsBuffer, offset: 0, index: 1)
                    calcEncoder.setBuffer(areaItemCombinationBuffer, offset: 0, index: 2)
                    calcEncoder.setBuffer(cardStatCombinationBuffer, offset: 0, index: 3)
                    calcEncoder.setBuffer(flagBuffer, offset: 0, index: 4)
                    calcEncoder.setBuffer(resultBuffer, offset: 0, index: 5)
                    
                    let gridSize = MTLSizeMake(
                        groupCombinations.count,
                        charCombinations.count,
                        1
                    )
                    let threadGroupSize = MTLSizeMake(32, 16, 1)
                    calcEncoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadGroupSize)
                    
                    calcEncoder.endEncoding()
                    calcCommandBuffer.commit()
                    await calcCommandBuffer.completed()
                    
                    func getTopK(from array: [HAMaxBandPowerResult], k: Int) -> [HAMaxBandPowerResult] {
                        func sinkDown(_ heap: inout [HAMaxBandPowerResult], index: Int) {
                            var parent = index
                            let count = heap.count
                            while true {
                                let left = 2 * parent + 1
                                let right = 2 * parent + 2
                                var candidate = parent
                                
                                if left < count && heap[left].power < heap[candidate].power {
                                    candidate = left
                                }
                                if right < count && heap[right].power < heap[candidate].power {
                                    candidate = right
                                }
                                if candidate == parent { break }
                                
                                heap.swapAt(parent, candidate)
                                parent = candidate
                            }
                        }
                        
                        guard k < array.count else {
                            return array.sorted { $0.power > $1.power }
                        }
                        
                        var heap = Array(array[0..<k])
                        heap.sort { $0.power < $1.power }
                        
                        for i in k..<array.count {
                            let current = array[i]
                            if current.power > heap[0].power {
                                heap[0] = current
                                sinkDown(&heap, index: 0)
                            }
                        }
                        
                        return heap.sorted { $0.power > $1.power }
                    }
                    
                    var results = unsafe Array(
                        UnsafeBufferPointer(
                            start: resultBuffer!.contents().bindMemory(
                                to: HAMaxBandPowerResult.self,
                                capacity: resultBuffer!.length / MemoryLayout<HAMaxBandPowerResult>.stride
                            ),
                            count: resultBuffer!.length / MemoryLayout<HAMaxBandPowerResult>.stride
                        )
                    )
                    results = getTopK(from: results, k: maxResults * 10)
                    bestTeams.append(
                        contentsOf: results
                            .prefix(maxResults * 10)
                            .map {
                                TeamResult(
                                    cards: charCombinations[Int($0.index2)].map {
                                        candidateChars[$0].1.0.card
                                    },
                                    areaItems: groupCombinations[Int($0.index1)].map {
                                        allGroups[$0.0][$0.1]
                                    },
                                    targetValue: Int($0.power)
                                )
                            }
                    )
                }
                #else
                preconditionFailure()
                #endif // canImport(Metal)
            } else {
                for targetAttr in attributes {
                    let candidateChars = topCardsByAttr
                        .sorted { $0.key < $1.key }
                        .compactMap { (charID, attrs) -> (Int, (CardInformation, DoriAPI.Cards.Stat))? in
                            guard let data = attrs[targetAttr] else { return nil }
                            return (charID, data)
                        }
                    
                    guard candidateChars.count >= 5 else { continue }
                    
                    let allGroups = self.groupedAreaItems().compactMap {
                        let result = $0.filter {
                            $0.item.targetAttributes.contains(targetAttr)
                        }
                        return !result.isEmpty ? result : nil
                    }
                    
                    var groupCombinations: [[(Int, Int)]] = []
                    for groupingBandID in [0] + bandIDCharacterMap.keys {
                        var combination: [(Int, Int)] = []
                        for (groupIndex, itemGroup) in allGroups.enumerated() {
                            if groupingBandID == 0 {
                                if let itemIndex = itemGroup.firstIndex(where: {
                                    $0.item.targetBandIDs.count == bandIDCharacterMap.keys.count
                                }) {
                                    combination.append((groupIndex, itemIndex))
                                }
                            } else {
                                if let itemIndex = itemGroup.firstIndex(where: {
                                    $0.item.targetBandIDs.contains(groupingBandID)
                                }) {
                                    combination.append((groupIndex, itemIndex))
                                }
                            }
                        }
                        groupCombinations.append(combination)
                    }
                    
                    for combination in groupCombinations {
                        let selectedItems = combination.map { allGroups[$0.0][$0.1] }
                        var pF = 1.0, tF = 1.0, vF = 1.0
                        for item in selectedItems where item.item.targetAttributes.contains(targetAttr) {
                            pF += (item.item.performanceBoosts[item.level]?.jp ?? 0) / 100.0
                            tF += (item.item.techniqueBoosts[item.level]?.jp ?? 0) / 100.0
                            vF += (item.item.visualBoosts[item.level]?.jp ?? 0) / 100.0
                        }
                        
                        performFastCombinations(from: Array(candidateChars), size: 5) { charCombo in
                            var teamPower = 0
                            var currentCards: [CardInformation] = []
                            
                            for (_, data) in charCombo {
                                let base = data.1
                                let total = Int(Double(base.performance) * pF) +
                                Int(Double(base.technique) * tF) +
                                Int(Double(base.visual) * vF)
                                teamPower += total
                                currentCards.append(data.0)
                            }
                            
                            bestTeams.append(.init(
                                cards: currentCards.map { $0.card },
                                areaItems: selectedItems,
                                targetValue: teamPower
                            ))
                            if bestTeams.count > maxResults * 20 {
                                bestTeams.sort { $0.targetValue > $1.targetValue }
                                bestTeams.removeLast(maxResults * 10)
                            }
                        }
                    }
                }
            }
            
            return Array(bestTeams.sorted { $0.targetValue > $1.targetValue }.prefix(maxResults))
        }
        
        open func _calculateMaximizeTargetScore(
            maxResults: Int,
            centerSkill: DoriAPI.Skills.Skill? = nil
        ) async -> [TeamResult] {
            let possibleSkillOrders = [
                [0, 1, 2, 3, 4], [1, 0, 2, 3, 4], [2, 0, 1, 3, 4],
                [0, 2, 1, 3, 4], [1, 2, 0, 3, 4], [2, 1, 0, 3, 4],
                [2, 1, 3, 0, 4], [1, 2, 3, 0, 4], [3, 2, 1, 0, 4],
                [2, 3, 1, 0, 4], [1, 3, 2, 0, 4], [3, 1, 2, 0, 4],
                [3, 0, 2, 1, 4], [0, 3, 2, 1, 4], [2, 3, 0, 1, 4],
                [3, 2, 0, 1, 4], [0, 2, 3, 1, 4], [2, 0, 3, 1, 4],
                [1, 0, 3, 2, 4], [0, 1, 3, 2, 4], [3, 1, 0, 2, 4],
                [1, 3, 0, 2, 4], [0, 3, 1, 2, 4], [3, 0, 1, 2, 4],
                [4, 0, 1, 2, 3], [0, 4, 1, 2, 3], [1, 4, 0, 2, 3],
                [4, 1, 0, 2, 3], [0, 1, 4, 2, 3], [1, 0, 4, 2, 3],
                [1, 0, 2, 4, 3], [0, 1, 2, 4, 3], [2, 1, 0, 4, 3],
                [1, 2, 0, 4, 3], [0, 2, 1, 4, 3], [2, 0, 1, 4, 3],
                [2, 4, 1, 0, 3], [4, 2, 1, 0, 3], [1, 2, 4, 0, 3],
                [2, 1, 4, 0, 3], [4, 1, 2, 0, 3], [1, 4, 2, 0, 3],
                [0, 4, 2, 1, 3], [4, 0, 2, 1, 3], [2, 0, 4, 1, 3],
                [0, 2, 4, 1, 3], [4, 2, 0, 1, 3], [2, 4, 0, 1, 3],
                [3, 4, 0, 1, 2], [4, 3, 0, 1, 2], [0, 3, 4, 1, 2],
                [3, 0, 4, 1, 2], [4, 0, 3, 1, 2], [0, 4, 3, 1, 2],
                [0, 4, 1, 3, 2], [4, 0, 1, 3, 2], [1, 0, 4, 3, 2],
                [0, 1, 4, 3, 2], [4, 1, 0, 3, 2], [1, 4, 0, 3, 2],
                [1, 3, 0, 4, 2], [3, 1, 0, 4, 2], [0, 1, 3, 4, 2],
                [1, 0, 3, 4, 2], [3, 0, 1, 4, 2], [0, 3, 1, 4, 2],
                [4, 3, 1, 0, 2], [3, 4, 1, 0, 2], [1, 4, 3, 0, 2],
                [4, 1, 3, 0, 2], [3, 1, 4, 0, 2], [1, 3, 4, 0, 2],
                [2, 3, 4, 0, 1], [3, 2, 4, 0, 1], [4, 2, 3, 0, 1],
                [2, 4, 3, 0, 1], [3, 4, 2, 0, 1], [4, 3, 2, 0, 1],
                [4, 3, 0, 2, 1], [3, 4, 0, 2, 1], [0, 4, 3, 2, 1],
                [4, 0, 3, 2, 1], [3, 0, 4, 2, 1], [0, 3, 4, 2, 1],
                [0, 2, 4, 3, 1], [2, 0, 4, 3, 1], [4, 0, 2, 3, 1],
                [0, 4, 2, 3, 1], [2, 4, 0, 3, 1], [4, 2, 0, 3, 1],
                [3, 2, 0, 4, 1], [2, 3, 0, 4, 1], [0, 3, 2, 4, 1],
                [3, 0, 2, 4, 1], [2, 0, 3, 4, 1], [0, 2, 3, 4, 1],
                [1, 2, 3, 4, 0], [2, 1, 3, 4, 0], [3, 1, 2, 4, 0],
                [1, 3, 2, 4, 0], [2, 3, 1, 4, 0], [3, 2, 1, 4, 0],
                [3, 2, 4, 1, 0], [2, 3, 4, 1, 0], [4, 3, 2, 1, 0],
                [3, 4, 2, 1, 0], [2, 4, 3, 1, 0], [4, 2, 3, 1, 0],
                [4, 1, 3, 2, 0], [1, 4, 3, 2, 0], [3, 4, 1, 2, 0],
                [4, 3, 1, 2, 0], [1, 3, 4, 2, 0], [3, 1, 4, 2, 0],
                [2, 1, 4, 3, 0], [1, 2, 4, 3, 0], [4, 2, 1, 3, 0],
                [2, 4, 1, 3, 0], [1, 4, 2, 3, 0], [4, 1, 2, 3, 0]
            ]
            
            let topPowerBands = await _calculateMaximizeTargetBandPower(
                maxResults: maxResults * 10
            )
            
            let acc = self.songInformation!.accuracy
            let scoreUserFactor = 1.1 * acc + 0.8 * (1 - acc)
            let notes = self.songInformation!.chart.reduce(into: 0) {
                switch $1 {
                case .single, .long, .slide, .directional:
                    $0 += 1
                default: break
                }
            }
            let noteBaseFactor = (3 + 0.03 * Double(self.songInformation!.difficultyLevel - 5)) / Double(notes)
            
            if !isHardwareAccelerationDisabled && _setupForHardwareAccelerationIfNeeded() {
                #if canImport(Metal)
                struct HABandCard {
                    var skillEffectValue: Int32
                    var skillDuration: Float
                    var bandPower: Int32
                }
                struct HAChartElement {
                    var type: UInt8
                    var beat: Float
                    var skill: Bool
                    var fever: Bool
                };
                struct HAMaxScoreResult {
                    var index1: UInt32
                    var index2: UInt32
                    var index3: UInt32
                    var score: Float
                }
                
                let calcFunc = self.haLibrary.makeFunction(name: "maxScore")!
                let calcFuncPSO = try! await self.haDevice.makeComputePipelineState(function: calcFunc)
                let calcCommandBuffer = self.haCommandQueue.makeCommandBuffer()!
                let calcEncoder = calcCommandBuffer.makeComputeCommandEncoder()!
                calcEncoder.setComputePipelineState(calcFuncPSO)
                
                let _flattenBandCards = topPowerBands.flatMap {
                    let bp = $0.targetValue
                    return $0.cards.map { card in
                        let skill = self.allSkills.first { $0.id == card.skillID }!
                        let cardSettings = self.cards.first { $0.card.id == card.id }!
                        var effectValue = 0
                        for (type, effect) in skill.activationEffect.activateEffectTypes {
                            switch type {
                            case .score,
                                    .scoreOverLife,
                                    .scoreUnderLife,
                                    .scoreContinuedNoteJudge,
                                    .scoreOnlyPerfect,
                                    .scoreRateUpWithPerfect,
                                    .scoreUnderGreatHalf:
                                effectValue += effect.activateEffectValue[0]
                            default: break
                            }
                        }
                        return HABandCard(
                            skillEffectValue: Int32(effectValue),
                            skillDuration: Float(skill.duration[cardSettings.skillLevel]),
                            bandPower: Int32(bp)
                        )
                    }
                }
                let bandCardBuffer = unsafe _flattenBandCards.withUnsafeBytes { ptr in
                    unsafe self.haDevice.makeBuffer(
                        bytes: ptr.baseAddress!,
                        length: ptr.count,
                        options: .storageModeShared
                    )
                }
                let allSkillOrderBuffer = unsafe possibleSkillOrders.flatMap {
                    $0.map { Int32($0) }
                }.withUnsafeBytes { ptr in
                    unsafe self.haDevice.makeBuffer(
                        bytes: ptr.baseAddress!,
                        length: ptr.count,
                        options: .storageModeShared
                    )
                }
                var _bpm = 0
                var _nextItemFever = false
                let _flattenChart = self.songInformation!.chart.enumerated().compactMap {
                    switch $1 {
                    case .bpm(let bpmData):
                        _bpm = bpmData.bpm
                    case .system(let systemData):
                        if systemData.data == "cmd_fever_start.wav" {
                            _nextItemFever = true
                        } else if systemData.data == "cmd_fever_end.wav" {
                            _nextItemFever = false
                        }
                    case .single(let singleData):
                        return [HAChartElement(
                            type: 0,
                            beat: Float(singleData.beat),
                            skill: singleData.skill,
                            fever: _nextItemFever
                        )]
                    case .long(let longData):
                        return longData.connections.map {
                            HAChartElement(
                                type: 1,
                                beat: Float($0.beat),
                                skill: $0.skill,
                                fever: _nextItemFever
                            )
                        }
                    case .slide(let slideData):
                        return slideData.connections.map {
                            HAChartElement(
                                type: 2,
                                beat: Float($0.beat),
                                skill: false,
                                fever: _nextItemFever
                            )
                        }
                    case .directional(let directionalData):
                        return [HAChartElement(
                            type: 3,
                            beat: Float(directionalData.beat),
                            skill: false,
                            fever: _nextItemFever
                        )]
                    }
                    return nil
                }.flatMap { $0 }
                var skillStartIndexs: [Int32] = []
                for (index, element) in _flattenChart.enumerated() {
                    if element.skill {
                        skillStartIndexs.append(Int32(index))
                    }
                }
                let chartBuffer = unsafe _flattenChart.withUnsafeBytes { ptr in
                    unsafe self.haDevice.makeBuffer(
                        bytes: ptr.baseAddress!,
                        length: ptr.count,
                        options: .storageModeShared
                    )
                }
                let skillStartIndexBuffer = unsafe skillStartIndexs.withUnsafeBytes { ptr in
                    unsafe self.haDevice.makeBuffer(
                        bytes: ptr.baseAddress!,
                        length: ptr.count,
                        options: .storageModeShared
                    )
                }
                let flagsBuffer = unsafe [
                    Float(_flattenChart.count),
                    Float(scoreUserFactor),
                    Float(notes),
                    Float(noteBaseFactor),
                    Float(_bpm),
                    Float(topPowerBands.count),
                    Float(possibleSkillOrders.count)
                ].withUnsafeBytes { ptr in
                    unsafe self.haDevice.makeBuffer(
                        bytes: ptr.baseAddress!,
                        length: ptr.count,
                        options: .storageModeShared
                    )
                }
                let resultBuffer = self.haDevice.makeBuffer(
                    length: topPowerBands.count * possibleSkillOrders.count * 5 * MemoryLayout<HAMaxScoreResult>.stride,
                    options: .storageModeShared
                )

                calcEncoder.setBuffer(bandCardBuffer, offset: 0, index: 0)
                calcEncoder.setBuffer(allSkillOrderBuffer, offset: 0, index: 1)
                calcEncoder.setBuffer(chartBuffer, offset: 0, index: 2)
                calcEncoder.setBuffer(skillStartIndexBuffer, offset: 0, index: 3)
                calcEncoder.setBuffer(flagsBuffer, offset: 0, index: 4)
                calcEncoder.setBuffer(resultBuffer, offset: 0, index: 5)
                
                let gridSize = MTLSizeMake(
                    topPowerBands.count,
                    possibleSkillOrders.count,
                    5
                )
                let threadGroupSize = MTLSizeMake(16, 8, 2)
                calcEncoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadGroupSize)
                
                calcEncoder.endEncoding()
                calcCommandBuffer.commit()
                await calcCommandBuffer.completed()
                
                let haResults = unsafe Array(
                    UnsafeBufferPointer(
                        start: resultBuffer!.contents().bindMemory(
                            to: HAMaxScoreResult.self,
                            capacity: resultBuffer!.length / MemoryLayout<HAMaxScoreResult>.stride
                        ),
                        count: resultBuffer!.length / MemoryLayout<HAMaxScoreResult>.stride
                    )
                )
                return haResults.sorted { $0.score > $1.score }.prefix(maxResults).map {
                    .init(
                        cards: topPowerBands[Int($0.index1)].cards,
                        areaItems: topPowerBands[Int($0.index1)].areaItems,
                        targetValue: Int($0.score)
                    )
                }
                #else
                preconditionFailure()
                #endif // canImport(Metal)
            } else {
                return await withTaskGroup { group in
                    // It's easy to multi-threading by the fixed 'certerIndex'
                    for centerIndex in 0..<5 {
                        group.addTask { [self] in
                            var results: [TeamResult] = []
                            for band in topPowerBands {
                                var bandResults: [([Int], Double)] = []
                                for skillOrder in possibleSkillOrders {
                                    var score = 0.0
                                    var skillSelector = 0
                                    var bpm = 0.0
                                    var fever = false
                                    var currentSkill: DoriAPI.Skills.Skill?
                                    var skillEndBeat = 0.0
                                    
                                    func activateNextSkill(at beat: Double) {
                                        let card: DoriAPI.Cards.PreviewCard
                                        if skillSelector < skillOrder.count {
                                            card = band.cards[skillOrder[skillSelector]]
                                        } else {
                                            card = band.cards[centerIndex]
                                        }
                                        let cardSettings = self.cards.first { $0.card.id == card.id }!
                                        currentSkill = allSkills.first {
                                            $0.id == card.skillID
                                        }!
                                        let duration = currentSkill!.duration[cardSettings.skillLevel]
                                        skillEndBeat = beat + duration / 60 * bpm
                                        skillSelector += 1
                                    }
                                    func addScore() {
                                        var skillBonus = 1.0
                                        if let currentSkill {
                                            for (type, effect) in currentSkill.activationEffect.activateEffectTypes {
                                                switch type {
                                                case .score,
                                                        .scoreOverLife,
                                                        .scoreUnderLife,
                                                        .scoreContinuedNoteJudge,
                                                        .scoreOnlyPerfect,
                                                        .scoreRateUpWithPerfect,
                                                        .scoreUnderGreatHalf:
                                                    skillBonus += Double(effect.activateEffectValue[0]) / 100
                                                default: break
                                                }
                                            }
                                        }
                                        score += Double(band.targetValue) * noteBaseFactor * skillBonus * (fever ? 2 : 1) * scoreUserFactor
                                    }
                                    
                                    for chartElement in self.songInformation!.chart {
                                        switch chartElement {
                                        case .bpm(let bpmData):
                                            bpm = Double(bpmData.bpm)
                                        case .system(let systemData):
                                            if systemData.data == "cmd_fever_start.wav" {
                                                fever = true
                                            } else if systemData.data == "cmd_fever_end.wav" {
                                                fever = false
                                            }
                                        case .single(let singleData):
                                            if singleData.beat > skillEndBeat {
                                                currentSkill = nil
                                            }
                                            if singleData.skill {
                                                activateNextSkill(at: singleData.beat)
                                            }
                                            addScore()
                                        case .long(let longData):
                                            for conn in longData.connections {
                                                if conn.beat > skillEndBeat {
                                                    currentSkill = nil
                                                }
                                                if conn.skill {
                                                    activateNextSkill(at: conn.beat)
                                                }
                                                addScore()
                                            }
                                        case .slide(let slideData):
                                            for conn in slideData.connections {
                                                if conn.beat > skillEndBeat {
                                                    currentSkill = nil
                                                }
                                                addScore()
                                            }
                                        case .directional(let directionalData):
                                            if directionalData.beat > skillEndBeat {
                                                currentSkill = nil
                                            }
                                            addScore()
                                        }
                                    }
                                    
                                    bandResults.append((skillOrder, score))
                                }
                                bandResults.sort { $0.1 > $1.1 }
                                results.append(.init(
                                    cards: band.cards,
                                    areaItems: band.areaItems,
                                    targetValue: Int(bandResults[0].1)
                                ))
                            }
                            return results
                        }
                    }
                    
                    var results: [TeamResult] = []
                    for await result in group {
                        results.append(contentsOf: result)
                    }
                    return Array(results.sorted { $0.targetValue > $1.targetValue }.prefix(maxResults))
                }
            }
        }
        
        private func groupedAreaItems() -> [[AreaItemInformation]] {
            var result: [[AreaItemInformation]] = .init(
                repeating: [],
                count: areaItemGroups.count
            )
            
            for item in areaItems {
                if let index = areaItemGroups
                    .firstIndex(where: { $0.contains(item.item.id) }) {
                    result[index].append(item)
                } else {
                    logger.fault("""
                    Ignoring area item with id \(item.item.id) due to unknown \
                    group. Please file a bug report
                    """)
                }
            }
            
            return result.filter { !$0.isEmpty }
        }
        
        private func performFastCombinations<T>(
            from input: [T],
            size: Int,
            handler: ([T]) -> Void
        ) {
            var buffer = [T](repeating: input[0], count: size)
            func backtrack(start: Int, pos: Int) {
                if pos == size {
                    handler(buffer)
                    return
                }
                for i in start..<(input.count - (size - pos) + 1) {
                    buffer[pos] = input[i]
                    backtrack(start: i + 1, pos: pos + 1)
                }
            }
            backtrack(start: 0, pos: 0)
        }
        private func performGroupedCombinations<T>(
            from input: [[T]],
            handler: ([T]) -> Void
        ) {
            func combine(index: Int, currentPath: [T]) {
                if index == input.count {
                    handler(currentPath)
                    return
                }
                
                for item in input[index] {
                    var newPath = currentPath
                    newPath.append(item)
                    combine(index: index + 1, currentPath: newPath)
                }
            }
            
            combine(index: 0, currentPath: [])
        }
        private func combinations<T>(for input: [T], size: Int) -> [[Int]] {
            var result: [[Int]] = []
            var buffer = [Int](repeating: 0, count: size)
            
            func backtrack(start: Int, pos: Int) {
                if pos == size {
                    result.append(buffer)
                    return
                }
                
                for i in start..<(input.count - (size - pos) + 1) {
                    buffer[pos] = i
                    backtrack(start: i + 1, pos: pos + 1)
                }
            }
            
            backtrack(start: 0, pos: 0)
            return result
        }
        private func groupedCombinations<T>(for input: [[T]]) -> [[(Int, Int)]] {
            var allResults: [[(Int, Int)]] = []
            var currentPath: [(Int, Int)] = []
            
            func backtrack(row: Int) {
                if row == input.count {
                    allResults.append(currentPath)
                    return
                }
                
                for col in 0..<input[row].count {
                    currentPath.append((row, col))
                    backtrack(row: row + 1)
                    currentPath.removeLast()
                }
            }
            
            if !input.isEmpty {
                backtrack(row: 0)
            }
            
            return allResults
        }
        private func permutations<T>(for input: [T]) -> [[T]] {
            var result: [[T]] = []
            var current: [T] = []
            var used = Array(repeating: false, count: input.count)
            
            func backtrack() {
                if current.count == input.count {
                    result.append(current)
                    return
                }
                
                for i in 0..<input.count {
                    if used[i] {
                        continue
                    }
                    
                    used[i] = true
                    current.append(input[i])
                    
                    backtrack()
                    
                    current.removeLast()
                    used[i] = false
                }
            }
            
            backtrack()
            return result
        }
    }
}

extension DoriFrontend.TeamBuilder {
    public struct EventInformation: Sendable, Hashable {
        public var eventType: DoriAPI.Events.EventType
        public var attributeBonuses: [DoriAPI.Attribute: Double]
        public var characterBonuses: [Int: Double]
        public var matchBonus: Double
        public var masterRankBonus: [[Double]]
        public var cardBonus: [Int: Double]
        public var eventParameter: EventParameter?
        public var formula: EventFormula
        
        public init(
            eventType: DoriAPI.Events.EventType,
            attributeBonuses: [DoriAPI.Attribute: Double],
            characterBonuses: [Int: Double],
            matchBonus: Double,
            masterRankBonus: [[Double]],
            cardBonus: [Int: Double],
            eventParameter: EventParameter? = nil,
            formula: EventFormula
        ) {
            self.eventType = eventType
            self.attributeBonuses = attributeBonuses
            self.characterBonuses = characterBonuses
            self.matchBonus = matchBonus
            self.masterRankBonus = masterRankBonus
            self.cardBonus = cardBonus
            self.eventParameter = eventParameter
            self.formula = formula
        }
        
        public enum EventParameter: Int, Sendable, Hashable {
            case performance = 1
            case technique
            case visual
        }
        public enum EventFormula: Int, Sendable, Hashable {
            case v1
            case v2
            case v3
        }
    }
    
    public enum LiveInformation: Sendable, Hashable {
        case freeLive
        case multiLive(MultiLiveInformation)
        case challengeLive
        case vsLive
        
        public struct MultiLiveInformation: Sendable, Hashable {
            public var roomType: RoomType
            public var averageBandPower: Int?
            public var encore: Int
            public var centerSkills: [SkillWithLevel]
            
            public init(
                roomType: RoomType,
                averageBandPower: Int? = nil,
                encore: Int,
                centerSkills: [SkillWithLevel]
            ) {
                self.roomType = roomType
                self.averageBandPower = averageBandPower
                self.encore = encore
                self.centerSkills = centerSkills
            }
            
            public enum RoomType: Int, Sendable, Hashable {
                case `public`
                case standard
                case grand
                case legend
            }
            public struct SkillWithLevel: Sendable, Hashable {
                public var skill: DoriAPI.Skills.Skill
                public var level: Int
                
                public init(skill: DoriAPI.Skills.Skill, level: Int) {
                    self.skill = skill
                    self.level = level
                }
            }
        }
    }
    
    public struct SongInformation: Sendable, Hashable {
        public var chart: [DoriAPI.Songs.Chart]
        public var difficultyLevel: Int
        public var accuracy: Double
        
        public init(
            chart: [DoriAPI.Songs.Chart],
            difficultyLevel: Int,
            accuracy: Double
        ) {
            self.chart = chart
            self.difficultyLevel = difficultyLevel
            self.accuracy = accuracy
        }
    }
    
    public struct CardInformation: Sendable, Hashable {
        public var card: DoriAPI.Cards.PreviewCard
        public var level: Int
        public var masterRank: Int
        public var skillLevel: Int
        public var viewedStoryCount: Int
        public var trained: Bool
        
        public init(
            card: DoriAPI.Cards.PreviewCard,
            level: Int,
            masterRank: Int,
            skillLevel: Int,
            viewedStoryCount: Int,
            trained: Bool
        ) {
            self.card = card
            self.level = level
            self.masterRank = masterRank
            self.skillLevel = skillLevel
            self.viewedStoryCount = viewedStoryCount
            self.trained = trained
        }
    }
    
    public struct AreaItemInformation: Sendable, Hashable {
        public var item: DoriAPI.Misc.AreaItem
        public var level: Int
        
        public init(item: DoriAPI.Misc.AreaItem, level: Int) {
            self.item = item
            self.level = level
        }
    }
    
    public struct TeamResult: Sendable, Hashable {
        public var cards: [DoriAPI.Cards.PreviewCard]
        public var areaItems: [AreaItemInformation]
        public var targetValue: Int
    }
    
    public enum MaximizeCalculationTarget: Sendable, Hashable {
        case bandPower
        case score
        case eventPoint
    }
}
extension DoriFrontend.TeamBuilder.EventInformation {
    public init(_ event: DoriAPI.Events.Event) {
        self.init(
            eventType: event.eventType,
            attributeBonuses: event.attributes.map {
                (key: $0.attribute, value: Double($0.percent) / 100)
            }.reduce(into: [:]) { $0.updateValue($1.value, forKey: $1.key) },
            characterBonuses: event.characters.map {
                (key: $0.characterID, value: Double($0.percent) / 100)
            }.reduce(into: [:]) { $0.updateValue($1.value, forKey: $1.key) },
            matchBonus: event.eventAttributeAndCharacterBonus != nil
            ? (event.eventAttributeAndCharacterBonus!.pointPercent != 0
               ? Double(event.eventAttributeAndCharacterBonus!.pointPercent) / 100
               : Double(event.eventAttributeAndCharacterBonus!.parameterPercent) / 100)
            : 0,
            masterRankBonus: {
                var result = Array<[Double]>(
                    repeating: .init(repeating: 0, count: 5),
                    count: 5
                )
                for limitBreak in event.limitBreaks {
                    result[limitBreak.rarity - 1][limitBreak.rank]
                    = round(limitBreak.percent * 10) / 10
                }
                return result
            }(),
            cardBonus: event.members.map {
                (key: $0.situationID, value: Double($0.percent) / 100)
            }.reduce(into: [:]) { $0.updateValue($1.value, forKey: $1.key) },
            eventParameter: event.eventCharacterParameterBonus != nil
            ? (event.eventCharacterParameterBonus!.performance != 0
               ? .performance
               : event.eventCharacterParameterBonus!.technique != 0
               ? .technique
               : event.eventCharacterParameterBonus!.visual != 0
               ? .visual : nil)
            : nil,
            formula: {
                let locale = event.startAt.availableLocale()!
                let ranges: [Double] = [
                    // Some magic date ranges, a great thank to Burrito
                    // for these data
                    [1533880800, 1647583200, .infinity],
                    [1553821200, 1674003600, .infinity],
                    [1542956400, 1659596400, .infinity],
                    [1573534800, 1670389200, .infinity],
                    [1557295200, .infinity,  .infinity]
                ][locale._rawIntValue]
                return .init(rawValue: ranges.firstIndex {
                    $0 > event.startAt[locale]!.timeIntervalSince1970
                } ?? 2 /* v3 */) ?? .v3
            }()
        )
    }
}
