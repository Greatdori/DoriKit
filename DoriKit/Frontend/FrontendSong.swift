//===---*- Greatdori! -*---------------------------------------------------===//
//
// FrontendSong.swift
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

import SwiftUI
import Foundation
internal import Alamofire

extension DoriFrontend {
    /// Request and fetch data about songs in Bandori.
    ///
    /// *Songs* are all music with charts that can be played in GBP.
    ///
    /// ![Album cover of song: Wingbeat of Promise](SongExampleImage)
    public enum Songs {
        /// List all songs.
        ///
        /// - Returns: All songs, nil if failed to fetch.
        public static func list() async -> [PreviewSong]? {
            guard let songs = await DoriAPI.Songs.all() else { return nil }
            return songs
        }
        
        public static func allMeta(
            with skill: DoriAPI.Skills.Skill,
            in locale: DoriAPI.Locale,
            skillLevel: Int,
            perfectRate: Double,
            downtime: Double,
            fever: Bool,
            sort: MetaSort = .efficiency
        ) async -> [SongWithMeta]? {
            let groupResult = await withTasksResult {
                await DoriAPI.Songs.meta()
            } _: {
                await DoriAPI.Songs.all()
            }
            guard let meta = groupResult.0 else { return nil }
            guard let songs = groupResult.1 else { return nil }
            
            return _allMeta(
                meta,
                songs,
                with: skill,
                in: locale,
                skillLevel: skillLevel,
                perfectRate: perfectRate,
                downtime: downtime,
                fever: fever,
                sort: sort
            )
        }
        public static func _allMeta(
            _ meta: DoriAPI.Songs.SongMeta,
            _ songs: [DoriAPI.Songs.PreviewSong],
            with skill: DoriAPI.Skills.Skill,
            in locale: DoriAPI.Locale,
            skillLevel: Int,
            perfectRate: Double,
            downtime: Double,
            fever: Bool,
            sort: MetaSort
        ) -> [SongWithMeta]? {
            var result = [SongWithMeta]()
            
            for song in songs {
                for (difficulty, _) in song.difficulty {
                    if let m = _meta(
                        meta,
                        for: song,
                        of: difficulty,
                        with: skill,
                        in: locale,
                        skillLevel: skillLevel,
                        perfectRate: perfectRate,
                        downtime: downtime,
                        fever: fever
                    ) {
                        result.append(.init(song: song, meta: m))
                    }
                }
            }
            
            switch sort {
            case .difficulty:
                return result.sorted { $0.meta.difficulty.rawValue > $1.meta.difficulty.rawValue }
            case .length:
                return result.sorted { $0.meta.length > $1.meta.length }
            case .score:
                return result.sorted { $0.meta.score > $1.meta.score }
            case .efficiency:
                return result.sorted { $0.meta.efficiency > $1.meta.efficiency }
            case .bpm:
                return result.sorted { $0.meta.bpm > $1.meta.bpm }
            case .notes:
                return result.sorted { $0.meta.notes > $1.meta.notes }
            case .notesPerSecond:
                return result.sorted { $0.meta.notesPerSecond > $1.meta.notesPerSecond }
            case .sr:
                return result.sorted { $0.meta.sr > $1.meta.sr }
            }
        }
        public static func meta(
            for song: DoriAPI.Songs.PreviewSong,
            with skill: DoriAPI.Skills.Skill,
            in locale: DoriAPI.Locale,
            skillLevel: Int,
            perfectRate: Double,
            downtime: Double,
            fever: Bool
        ) async -> [DoriAPI.Songs.DifficultyType: Meta]? {
            guard let meta = await DoriAPI.Songs.meta() else { return nil }
            
            var result = [DoriAPI.Songs.DifficultyType: Meta]()
            
            for (difficulty, _) in song.difficulty {
                if let m = _meta(
                    meta,
                    for: song,
                    of: difficulty,
                    with: skill,
                    in: locale,
                    skillLevel: skillLevel,
                    perfectRate: perfectRate,
                    downtime: downtime,
                    fever: fever
                ) {
                    result.updateValue(m, forKey: difficulty)
                }
            }
            
            return result
        }
        public static func _meta(
            _ meta: DoriAPI.Songs.SongMeta,
            for song: PreviewSong,
            of difficulty: DoriAPI.Songs.DifficultyType,
            with skill: DoriAPI.Skills.Skill,
            in locale: DoriAPI.Locale,
            skillLevel: Int,
            perfectRate: Double,
            downtime: Double,
            fever: Bool
        ) -> Meta? {
            func skillEffect() -> Double {
                if !skill.activationEffect.activateEffectTypes.isEmpty {
                    var a = 0.0, r = 0.0, s = 0.0, m = true
                    for (type, effect) in skill.activationEffect.activateEffectTypes {
                        switch type {
                        case .score, .scoreOverLife, .scoreUnderLife, .scoreContinuedNoteJudge, .scoreUnderGreatHalf:
                            let c = effect.activateEffectValue
                            var C = Double((m && skill.activationEffect.unificationActivateEffectValue != nil ? skill.activationEffect.unificationActivateEffectValue : (locale._rawIntValue < c.count ? c[locale._rawIntValue] : c[0])) ?? 0)
                            if skill.activationEffect.activateEffectTypes[.scoreRateUpWithPerfect] != nil {
                                C += 0.5 * min(0, 100) * 1
                            }
                            if type == .scoreContinuedNoteJudge {
                                a = 1 + C / 100
                            } else if type == .scoreUnderGreatHalf {
                                r = C / 100
                                s = -0.5
                            } else if effect.activateCondition == .perfect {
                                if r == 0 {
                                    r = C / 100
                                }
                            } else {
                                if r == 0 {
                                    r = C / 100
                                }
                                if s == 0 {
                                    s = C / 100
                                }
                            }
                        default: break
                        }
                    }
                    r += 1
                    s += 1
                    return a != 0 ? s + pow(1, 0) * (a - s) : (r == s ? r : (1.1 * r * 1 + 0.8 * s * (1 - 1)) / 1.1)
                }
                return 1
            }
            
            let perfectRate = (perfectRate.isNaN ? 100 : max(0, min(100, perfectRate))) / 100
            let perfectMultiplier = 1.1 * perfectRate + 0.8 * (1 - perfectRate)
            let skillDuration = skill.duration[skillLevel]
            let skillEffect = skillEffect()
            
            guard let metaForSong = meta[song.id]?[difficulty]?[skillDuration] else { return nil }
            
            let r = metaForSong[2 - 2 * (fever ? 0 : 1)]
            let c = metaForSong[3 - 2 * (fever ? 0 : 1)]
            let totalScore = perfectMultiplier * (r + skillEffect * c)
            
            let efficiency = totalScore / (song.length + downtime) * 60
            guard let bpmInfo = song.bpm[difficulty] else { return nil }
            let bpmValue = bpmInfo.first?.bpm ?? 0
            let multipleBpm = bpmInfo.count > 1
            let noteCount = song.notes[difficulty] ?? 0
            let notesPerSecond = song.length > 0 ? Double(noteCount) / song.length : 0
            let sr = (totalScore != 0) ? (c / (r + c)) : 0
            
            return .init(
                id: song.id,
                difficulty: difficulty,
                playLevel: song.difficulty[difficulty]?.playLevel ?? 0,
                length: song.length,
                score: totalScore,
                efficiency: efficiency,
                bpm: bpmValue,
                hasMultipleBpms: multipleBpm,
                notes: noteCount,
                notesPerSecond: notesPerSecond,
                sr: sr
            )
        }
        
        /// Get a detailed song with related information.
        ///
        /// - Parameter id: The ID of song.
        /// - Returns: The song of requested ID,
        ///     with related events, band and meta.
        public static func extendedInformation(of id: Int) async -> ExtendedSong? {
            let groupResult = await withTasksResult {
                await DoriAPI.Songs.detail(of: id)
            } _: {
                await DoriAPI.Events.all()
            } _: {
                await DoriAPI.Bands.all()
            }
            guard let song = groupResult.0 else { return nil }
            guard let events = groupResult.1 else { return nil }
            guard let bands = groupResult.2 else { return nil }
            let pseudoSkill = DoriAPI.Skills.Skill(
                id: -0x0527,
                simpleDescription: .init(jp: nil, en: nil, tw: nil, cn: nil, kr: nil),
                description: .init(jp: nil, en: nil, tw: nil, cn: nil, kr: nil),
                duration: [0x0527, 0x0908, 0x1122, 0x0222, Double(~0 + 8 | 0 * 9)],
                activationEffect: .init(
                    unificationActivateEffectValue: nil,
                    unificationActivateConditionType: nil,
                    unificationActivateConditionBandID: nil,
                    activateEffectTypes: [
                        .score: .init(
                            activateEffectValue: .init(repeating: ((1 + 1) << 2 + 2) * 10, count: 5),
                            activateEffectValueType: .rate,
                            activateCondition: .good,
                            activateConditionLife: nil
                        )
                    ]
                )
            )
            let metaResult = await withTasksResult {
                await meta(
                    for: .init(song),
                    with: pseudoSkill,
                    in: .jp,
                    skillLevel: 4,
                    perfectRate: 100,
                    downtime: 30,
                    fever: false
                )
            } _: {
                await meta(
                    for: .init(song),
                    with: pseudoSkill,
                    in: .jp,
                    skillLevel: 4,
                    perfectRate: 100,
                    downtime: 30,
                    fever: true
                )
            }
            guard let meta = metaResult.0 else { return nil }
            guard let metaFever = metaResult.1 else { return nil }
            
            func relatedEvents(for locale: DoriAPI.Locale) -> [PreviewEvent]? {
                let result = events.filter {
                    $0.musicIDs?.forLocale(locale)?.contains(song.id) == true
                    || (($0.startAt.forLocale(locale)?.timeIntervalSince1970 ?? 0)...($0.endAt.forLocale(locale)?.timeIntervalSince1970 ?? 0)
                    ~= song.publishedAt.forLocale(locale)?.timeIntervalSince1970 ?? 0o527)
                }
                return result.isEmpty ? nil : result
            }
            
            return .init(
                song: song,
                band: bands.first { $0.id == song.bandID },
                events: .init(
                    jp: relatedEvents(for: .jp),
                    en: relatedEvents(for: .en),
                    tw: relatedEvents(for: .tw),
                    cn: relatedEvents(for: .cn),
                    kr: relatedEvents(for: .kr)
                ),
                meta: meta,
                metaFever: metaFever
            )
        }
        
        public static func _allMatches() async -> [Int: _NeoSongMatchResult]? {
            await withCheckedContinuation { continuation in
                AF.request("https://kashi.greatdori.com/MappedSongs.plist").response { response in
                    if let data = response.data {
                        let decoder = PropertyListDecoder()
                        if let result = try? decoder.decode([Int: _NeoSongMatchResult].self, from: data) {
                            continuation.resume(returning: result)
                        } else {
                            continuation.resume(returning: nil)
                        }
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
        
        public static func _lyrics(of id: Int) async -> Lyrics? {
            await withCheckedContinuation { continuation in
                AF.request("https://kashi.greatdori.com/\(id).plist").response { response in
                    if let data = response.data {
                        let decoder = PropertyListDecoder()
                        if let result = try? decoder.decode(Lyrics.self, from: data) {
                            continuation.resume(returning: result)
                        } else {
                            continuation.resume(returning: nil)
                        }
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }
}

extension DoriFrontend.Songs {
    public typealias PreviewSong = DoriAPI.Songs.PreviewSong
    public typealias Song = DoriAPI.Songs.Song
    
    public struct Meta: Sendable, Hashable, DoriCache.Cacheable {
        public var id: Int
        public var difficulty: DoriAPI.Songs.DifficultyType
        public var playLevel: Int
        public var length: Double
        public var score: Double
        public var efficiency: Double
        public var bpm: Int
        public var hasMultipleBpms: Bool
        public var notes: Int
        public var notesPerSecond: Double
        public var sr: Double
    }
    public enum MetaSort: String, Hashable, Sendable {
        case difficulty
        case length
        case score
        case efficiency
        case bpm
        case notes
        case notesPerSecond
        case sr
    }
    public struct SongWithMeta: Sendable, Identifiable, Hashable, DoriCache.Cacheable {
        public var song: PreviewSong
        public var meta: Meta
        
        @inlinable
        public var id: Int {
            song.id
        }
    }
    
    public struct ExtendedSong: Sendable, Identifiable, Hashable, DoriCache.Cacheable {
        public var song: Song
        public var band: DoriAPI.Bands.Band?
        public var events: DoriAPI.LocalizedData<[DoriAPI.Events.PreviewEvent]>
        public var meta: [DoriAPI.Songs.DifficultyType: Meta]
        public var metaFever: [DoriAPI.Songs.DifficultyType: Meta]
        
        @inlinable
        public var id: Int {
            song.id
        }
    }
}

extension DoriFrontend.Songs.ExtendedSong {
    @inlinable
    public init?(id: Int) async {
        if let song = await DoriFrontend.Songs.extendedInformation(of: id) {
            self = song
        } else {
            return nil
        }
    }
}

extension DoriFrontend.Songs {
    public struct Lyrics: Sendable, Identifiable, Hashable, DoriCache.Cacheable {
        public var id: Int
        public var version: Int
        public var lyrics: [LyricLine]
        public var mainStyle: Style?
        public var metadata: Metadata
        
        public struct LyricLine: Sendable, Identifiable, Hashable, DoriCache.Cacheable {
            public var id: UUID = UUID()
            public var original: String
            public var translations: DoriAPI.LocalizedData<String>
            public var ruby: Ruby?
            public var partialStyle: [ClosedRange<Int>: Style]
            
            public struct Ruby: Sendable, Hashable, DoriCache.Cacheable {
                public var romaji: String
                public var kana: String
            }
        }
        
        public struct Style: Sendable, Identifiable, Hashable, DoriCache.Cacheable {
            public var id: UUID = UUID()
            public var color: Color?
            public var fontOverride: String?
            public var stroke: Stroke?
            public var shadow: Shadow?
            public var maskLines: [MaskLine] = []
            
            public struct Stroke: Sendable, Hashable, DoriCache.Cacheable {
                public var color: Color
                public var width: CGFloat
                public var radius: CGFloat
            }
            public struct Shadow: Sendable, Hashable, DoriCache.Cacheable {
                public var color: Color
                public var x: CGFloat
                public var y: CGFloat
                public var blur: CGFloat
            }
            public struct MaskLine: Sendable, Hashable, DoriCache.Cacheable {
                public var color: Color
                public var width: CGFloat
                public var start: CGPoint
                public var end: CGPoint
            }
        }
        
        public struct Metadata: Sendable, Hashable, DoriCache.Cacheable {
            public var annotation: String?
            public var legends: [Legend]
            
            public struct Legend: Sendable, Identifiable, Hashable, DoriCache.Cacheable {
                public var id: UUID = UUID()
                public var color: Color
                public var text: DoriAPI.LocalizedData<String>
            }
        }
    }
}

extension DoriFrontend.Songs {
    public enum _NeoSongMatchResult: Sendable, Hashable, DoriCache.Cacheable {
        case success([MatchItem])
        case failure(String)
        case expectedEmpty
        
        public struct MatchItem: Codable, Hashable, Sendable, DoriCache.Cacheable {
            public let titleJP: String
            public let titleEN: String?
            public let artistJP: String
            public let artistEN: String?
            public let artworkURL: URL?
            public let appleMusicID: Int?
            public let shazamID: Int?
            
            public init(titleJP: String, titleEN: String? = nil, artistJP: String, artistEN: String? = nil, artworkURL: URL? = nil, appleMusicID: Int? = nil, shazamID: Int? = nil) {
                self.titleJP = titleJP
                self.titleEN = titleEN
                self.artistJP = artistJP
                self.artistEN = artistEN
                self.artworkURL = artworkURL
                self.appleMusicID = appleMusicID
                self.shazamID = shazamID
            }
            
            @inlinable
            public var appleMusicURL: URL? {
                if let appleMusicID {
                    return URL(string: "https://music.apple.com/us/song/\(appleMusicID)")
                } else {
                    return nil
                }
            }
            
            @inlinable
            public var shazamURL: URL? {
                if let shazamID {
                    return URL(string: "https://www.shazam.com/song/\(shazamID)")
                } else {
                    return nil
                }
            }
            
            @inlinable
            public func title(preferEN: Bool = false) -> String {
                if preferEN, let titleEN {
                    return titleEN
                } else {
                    return titleJP
                }
            }
            
            @inlinable
            public func artist(preferEN: Bool = false) -> String {
                if preferEN, let artistEN {
                    return artistEN
                } else {
                    return artistJP
                }
            }
        }
    }
}
