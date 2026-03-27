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
        
        public init() {}
        
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
            centerSkill: DoriAPI.Skills.Skill? = nil
        ) async -> [[DoriAPI.Cards.PreviewCard]] {
            _checkPreconditions()
            
            switch target {
            case .bandPower:
                return await _calculateMaximizeTargetBandPower(
                    centerSkill: centerSkill
                )
            case .score:
                fatalError("Not implemented")
            case .eventPoint:
                fatalError("Not implemented")
            }
        }
        
        open func _calculateMaximizeTargetBandPower(
            centerSkill: DoriAPI.Skills.Skill? = nil
        ) async -> [[DoriAPI.Cards.PreviewCard]] {
            func performFastCombinations<T>(from input: [T], size: Int, handler: ([T]) -> Void) {
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
            func combinations<T>(for input: [T], size: Int) -> [[Int]] {
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
            
            let allGroups = self.groupedAreaItems()
            let filteredGroups = allGroups.compactMap { $0.sorted(by: { $0.level > $1.level }).first }
            
            var bestTeams: [(cards: [CardInformation], power: Int)] = []
            
            let attributes: [DoriAPI.Attribute] = [.powerful, .cool, .happy, .pure]
            
            if !isHardwareAccelerationDisabled && _setupForHardwareAccelerationIfNeeded() {
                #if canImport(Metal)
                let calcFunc = self.haLibrary.makeFunction(name: "maxBandPower")!
                let calcFuncPSO = try! await self.haDevice.makeComputePipelineState(function: calcFunc)
                
                for targetAttr in attributes {
                    let candidateChars = topCardsByAttr.compactMap { (charID, attrs) -> (Int, (CardInformation, DoriAPI.Cards.Stat))? in
                        guard let data = attrs[targetAttr] else { return nil }
                        return (charID, data)
                    }.sorted { $0.1.1.total > $1.1.1.total }.prefix(15)
                    
                    guard candidateChars.count >= 5 else { continue }
                    
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
                    
                    let groupCombinations = combinations(for: filteredGroups, size: 5)
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
                    let areaItems = filteredGroups.map {
                        HAAreaItem(
                            performanceBoost: Float($0.item.performanceBoosts[$0.level]!.jp!),
                            techniqueBoost: Float($0.item.techniqueBoosts[$0.level]!.jp!),
                            visualBoost: Float($0.item.visualBoosts[$0.level]!.jp!),
                            targetAttributes: $0.item.targetAttributes.reduce(into: 0) {
                                $0 |= 1 << _attrShifts[$1]!
                            }
                        )
                    }
                    let areaItemBuffer = unsafe areaItems.withUnsafeBytes { ptr in
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
                    let areaItemCombinationBuffer = unsafe groupCombinations.flatMap { $0 }.withUnsafeBytes { ptr in
                        unsafe self.haDevice.makeBuffer(
                            bytes: ptr.baseAddress!,
                            length: ptr.count,
                            options: .storageModeShared
                        )
                    }
                    let cardStatCombinationBuffer = unsafe charCombinations.flatMap { $0 }.withUnsafeBytes { ptr in
                        unsafe self.haDevice.makeBuffer(
                            bytes: ptr.baseAddress!,
                            length: ptr.count,
                            options: .storageModeShared
                        )
                    }
                    let flagBuffer = unsafe [
                        _attrShifts[targetAttr]!,
                        groupCombinations.count,
                        charCombinations.count
                    ].withUnsafeBytes { ptr in
                        unsafe self.haDevice.makeBuffer(
                            bytes: ptr.baseAddress!,
                            length: ptr.count,
                            options: .storageModeShared
                        )
                    }
                    let resultBuffer = self.haDevice.makeBuffer(
                        length: groupCombinations.count * charCombinations.count,
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
                    
                    let results = unsafe Array(
                        UnsafeBufferPointer(
                            start: resultBuffer!.contents().bindMemory(
                                to: HAMaxBandPowerResult.self,
                                capacity: resultBuffer!.length / MemoryLayout<HAMaxBandPowerResult>.stride
                            ),
                            count: resultBuffer!.length / MemoryLayout<HAMaxBandPowerResult>.stride
                        )
                    )
                    bestTeams.append(
                        contentsOf: results
                            .sorted { $0.power > $1.power }
                            .prefix(100)
                            .map {
                                (charCombinations[Int($0.index2)].map {
                                    candidateChars[$0].1.0
                                }, Int($0.power))
                            }
                    )
                }
                #endif // canImport(Metal)
            } else {
                for targetAttr in attributes {
                    let candidateChars = topCardsByAttr.compactMap { (charID, attrs) -> (Int, (CardInformation, DoriAPI.Cards.Stat))? in
                        guard let data = attrs[targetAttr] else { return nil }
                        return (charID, data)
                    }.sorted { $0.1.1.total > $1.1.1.total }.prefix(15)
                    
                    guard candidateChars.count >= 5 else { continue }
                    
                    performFastCombinations(from: filteredGroups, size: 5) { selectedItems in
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
                            
                            bestTeams.append((currentCards, teamPower))
                            if bestTeams.count > 100 {
                                bestTeams.sort { $0.power > $1.power }
                                bestTeams.removeLast(50)
                            }
                        }
                    }
                }
            }
            
            return bestTeams.sorted { $0.power > $1.power }.prefix(10).map { team in
                team.cards.map { $0.card }
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
        public var song: DoriAPI.Songs.PreviewSong
        public var difficulty: DoriAPI.Songs.DifficultyType
        public var accuracy: Double
        
        public init(
            song: DoriAPI.Songs.PreviewSong,
            difficulty: DoriAPI.Songs.DifficultyType,
            accuracy: Double
        ) {
            self.song = song
            self.difficulty = difficulty
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
