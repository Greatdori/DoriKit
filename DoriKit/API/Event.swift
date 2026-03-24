//===---*- Greatdori! -*---------------------------------------------------===//
//
// Event.swift
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
internal import SwiftyJSON

extension DoriAPI {
    /// Request and fetch data about events in Bandori.
    ///
    /// *Events* are periodic activities with new stories in GBP.
    ///
    /// ![Banner image of event:
    /// Hopeful Spring Chocolate Roll Cake](EventExampleImage)
    public enum Events {
        /// Get all events in Bandori.
        ///
        /// The results have guaranteed sorting by ID.
        ///
        /// - Returns: Requested events, nil if failed to fetch data.
        public static func all() async -> [PreviewEvent]? {
            // Response example:
            // {
            //     "1": {
            //         "eventType": "story",
            //         "eventName": [
            //             "SAKURA＊BLOOMING PARTY!",
            //             "SAKURA＊BLOOMING PARTY!",
            //             "SAKURA＊BLOOMING PARTY!",
            //             "SAKURA＊BLOOMING PARTY!",
            //             "CHERRY＊BLOOMING PARTY!"
            //         ],
            //         "assetBundleName": "sakura",
            //         "bannerAssetBundleName": "banner-016",
            //         "startAt": [
            //             "1490335200000",
            //             ...
            //         ],
            //         "endAt": [
            //             "1490875200000",
            //             ...
            //         ],
            //         "attributes": [
            //             {
            //                 "attribute": "pure",
            //                 "percent": 20
            //             }
            //         ],
            //         "characters": [
            //             {
            //                 "characterId": 5,
            //                 "percent": 70
            //             },
            //             ...
            //         ],
            //         "members": [],
            //         "limitBreaks": [],
            //         "rewardCards": [
            //             105,
            //             101
            //         ]
            //     },
            //     ...
            // }
            let request = await requestJSON("https://bestdori.com/api/events/all.6.json")
            if case let .success(respJSON) = request {
                let task = Task.detached(priority: .userInitiated) {
                    var result = [PreviewEvent]()
                    for (key, value) in respJSON {
                        var musicIDs: DoriAPI.LocalizedData<[Int]>?
                        for locale in DoriAPI.Locale.allCases {
                            let objects = value["musics"][locale._rawIntValue]
                            guard !objects.isEmpty else { continue }
                            
                            if musicIDs == nil {
                                musicIDs = .init(jp: nil, en: nil, tw: nil, cn: nil, kr: nil)
                            }
                            
                            var result: [Int] = []
                            for (_, music) in objects {
                                result.append(music["musicId"].intValue)
                            }
                            musicIDs!._set(result, forLocale: locale)
                        }
                        
                        result.append(.init(
                            id: Int(key) ?? 0,
                            eventType: .init(rawValue: value["eventType"].stringValue) ?? .normal,
                            eventName: .init(
                                jp: value["eventName"][0].string,
                                en: value["eventName"][1].string,
                                tw: value["eventName"][2].string,
                                cn: value["eventName"][3].string,
                                kr: value["eventName"][4].string
                            ),
                            assetBundleName: value["assetBundleName"].stringValue,
                            bannerAssetBundleName: value["bannerAssetBundleName"].stringValue,
                            startAt: .init(
                                jp: .init(apiTimeInterval: value["startAt"][0].string),
                                en: .init(apiTimeInterval: value["startAt"][1].string),
                                tw: .init(apiTimeInterval: value["startAt"][2].string),
                                cn: .init(apiTimeInterval: value["startAt"][3].string),
                                kr: .init(apiTimeInterval: value["startAt"][4].string)
                            ),
                            endAt: .init(
                                jp: .init(apiTimeInterval: value["endAt"][0].string),
                                en: .init(apiTimeInterval: value["endAt"][1].string),
                                tw: .init(apiTimeInterval: value["endAt"][2].string),
                                cn: .init(apiTimeInterval: value["endAt"][3].string),
                                kr: .init(apiTimeInterval: value["endAt"][4].string)
                            ),
                            attributes: value["attributes"].map {
                                EventAttribute(
                                    eventID: $0.1["eventId"].int,
                                    attribute: .init(rawValue: $0.1["attribute"].stringValue) ?? .pure,
                                    percent: $0.1["percent"].intValue
                                )
                            },
                            characters: value["characters"].map {
                                EventCharacter(
                                    eventID: $0.1["eventId"].int,
                                    characterID: $0.1["characterId"].intValue,
                                    percent: $0.1["percent"].intValue,
                                    seq: $0.1["seq"].int
                                )
                            },
                            eventAttributeAndCharacterBonus: value["eventAttributeAndCharacterBonus"]["eventId"].int != nil ? .init(
                                eventID: value["eventAttributeAndCharacterBonus"]["eventId"].intValue,
                                pointPercent: value["eventAttributeAndCharacterBonus"]["pointPercent"].intValue,
                                parameterPercent: value["eventAttributeAndCharacterBonus"]["parameterPercent"].intValue
                            ) : nil,
                            eventCharacterParameterBonus: value["eventCharacterParameterBonus"]["performance"].int != nil ? .init(
                                performance: value["eventCharacterParameterBonus"]["performance"].intValue,
                                technique: value["eventCharacterParameterBonus"]["technique"].intValue,
                                visual: value["eventCharacterParameterBonus"]["visual"].intValue
                            ) : nil,
                            members: value["members"].map {
                                EventMember(
                                    eventID: $0.1["eventId"].int,
                                    situationID: $0.1["situationId"].intValue,
                                    percent: $0.1["percent"].intValue,
                                    seq: $0.1["seq"].int
                                )
                            },
                            limitBreaks: value["limitBreaks"].map {
                                EventLimitBreak(
                                    rarity: $0.1["rarity"].intValue,
                                    rank: $0.1["rank"].intValue,
                                    percent: $0.1["percent"].doubleValue
                                )
                            },
                            musicIDs: musicIDs,
                            rewardCards: value["rewardCards"].map { $0.1.intValue }
                        ))
                    }
                    return result.sorted { $0.id < $1.id }
                }
                return await task.value
            }
            return nil
        }
        
        /// Get detail of an event in Bandori.
        /// - Parameter id: ID of target event.
        /// - Returns: Detail data of requested event, nil if failed to fetch.
        public static func detail(of id: Int) async -> Event? {
            // Response example:
            // {
            //     "eventType": "mission_live",
            //     "eventName": [
            //         "雨上がり、瞳に映る空は",
            //         "After the Rain, What Sky Reflected in Her Eyes",
            //         null,
            //         null,
            //         null
            //     ],
            //     "assetBundleName": "ammeagari_sora",
            //     "bannerAssetBundleName": "banner_event297",
            //     "startAt": [
            //         "1749535200000",
            //         ...
            //     ],
            //     "endAt": [
            //         "1750247999000",
            //         ...
            //     ],
            //     "enableFlag": [ // This attribute is not provided in Swift API. How does it works?
            //         null,
            //         ...
            //     ],
            //     "publicStartAt": [
            //         "1749535200000",
            //         ...
            //     ],
            //     "publicEndAt": [
            //         "1750399199000",
            //         ...
            //     ],
            //     "distributionStartAt": [
            //         "1750298400000",
            //         ...
            //     ],
            //     "distributionEndAt": [
            //         "1751554800000",
            //         ...
            //     ],
            //     "bgmAssetBundleName": "sound/scenario/bgm/63_longing",
            //     "bgmFileName": "63_longing",
            //     "aggregateEndAt": [
            //         "1750249799000",
            //         ...
            //     ],
            //     "exchangeEndAt": [
            //         "1751025599000",
            //         ...
            //     ],
            //     "pointRewards": [
            //         [
            //             {
            //                 "point": "1000",
            //                 "rewardType": "star",
            //                 "rewardQuantity": 50
            //             },
            //             ...
            //         ],
            //         ...
            //     ],
            //     "rankingRewards": [
            //         [
            //             {
            //                 "fromRank": 1,
            //                 "toRank": 1,
            //                 "rewardType": "degree",
            //                 "rewardId": 8025,
            //                 "rewardQuantity": 1
            //             },
            //             ...
            //         ],
            //         ...
            //     ],
            //     "attributes": [
            //         {
            //             "attribute": "powerful",
            //             "percent": 10
            //         }
            //     ],
            //     "characters": [
            //         {
            //             "characterId": 36,
            //             "percent": 20
            //         },
            //         ...
            //     ],
            //     "eventAttributeAndCharacterBonus": {
            //         "pointPercent": 20,
            //         "parameterPercent": 0
            //     },
            //     "members": [
            //         {
            //             "eventId": 297,
            //             "situationId": 2231,
            //             "percent": 20,
            //             "seq": 1
            //         },
            //         ...
            //     ],
            //     "limitBreaks": [
            //         {
            //             "rarity": 1,
            //             "rank": 0,
            //             "percent": 0
            //         },
            //         ...
            //     ],
            //     "stories": [
            //         {
            //             "scenarioId": "event297-01",
            //             "coverImage": "297_0",
            //             "backgroundImage": "0",
            //             "releasePt": "0",
            //             "rewards": [
            //                 {
            //                     "rewardType": "item",
            //                     "rewardId": 13,
            //                     "rewardQuantity": 1
            //                 },
            //                 ...
            //             ],
            //             "caption": [
            //                 "オープニング",
            //                 ...
            //             ],
            //             "title": [
            //                 "幕が開いて",
            //                 ...
            //             ],
            //             "synopsis": [
            //                 "Ave Mujicaのライブを観に行った\n愛音とそよ。そこにいたのは――",
            //                 ...
            //             ],
            //             "releaseConditions": [
            //                 "オープニングシナリオ",
            //                 ...
            //             ]
            //         },
            //         ...
            //     ],
            //     "rewardCards": [
            //         2235,
            //         2234
            //     ]
            // }
            let request = await requestJSON("https://bestdori.com/api/events/\(id).json")
            if case let .success(respJSON) = request {
                let task = Task.detached(priority: .userInitiated) {
                    // We break up expressions because of:
                    // The compiler is unable to type-check this expression in reasonable time;
                    // try breaking up the expression into distinct sub-expressions
                    let pointRewards = DoriAPI.LocalizedData(
                        jp: respJSON["pointRewards"][0].map {
                            Event.PointReward(
                                point: Int($0.1["point"].stringValue) ?? 0,
                                reward: .init(
                                    itemID: $0.1["rewardId"].int,
                                    type: .init(rawValue: $0.1["rewardType"].stringValue) ?? .item,
                                    quantity: $0.1["rewardQuantity"].intValue
                                )
                            )
                        },
                        en: respJSON["pointRewards"][1].map {
                            Event.PointReward(
                                point: Int($0.1["point"].stringValue) ?? 0,
                                reward: .init(
                                    itemID: $0.1["rewardId"].int,
                                    type: .init(rawValue: $0.1["rewardType"].stringValue) ?? .item,
                                    quantity: $0.1["rewardQuantity"].intValue
                                )
                            )
                        },
                        tw: respJSON["pointRewards"][2].map {
                            Event.PointReward(
                                point: Int($0.1["point"].stringValue) ?? 0,
                                reward: .init(
                                    itemID: $0.1["rewardId"].int,
                                    type: .init(rawValue: $0.1["rewardType"].stringValue) ?? .item,
                                    quantity: $0.1["rewardQuantity"].intValue
                                )
                            )
                        },
                        cn: respJSON["pointRewards"][3].map {
                            Event.PointReward(
                                point: Int($0.1["point"].stringValue) ?? 0,
                                reward: .init(
                                    itemID: $0.1["rewardId"].int,
                                    type: .init(rawValue: $0.1["rewardType"].stringValue) ?? .item,
                                    quantity: $0.1["rewardQuantity"].intValue
                                )
                            )
                        },
                        kr: respJSON["pointRewards"][4].map {
                            Event.PointReward(
                                point: Int($0.1["point"].stringValue) ?? 0,
                                reward: .init(
                                    itemID: $0.1["rewardId"].int,
                                    type: .init(rawValue: $0.1["rewardType"].stringValue) ?? .item,
                                    quantity: $0.1["rewardQuantity"].intValue
                                )
                            )
                        }
                    )
                    let rankingRewards = DoriAPI.LocalizedData(
                        jp: respJSON["rankingRewards"][0].map {
                            Event.RankingReward(
                                rankRange: $0.1["fromRank"].intValue...$0.1["toRank"].intValue,
                                reward: .init(
                                    itemID: $0.1["rewardId"].int,
                                    type: .init(rawValue: $0.1["rewardType"].stringValue) ?? .item,
                                    quantity: $0.1["rewardQuantity"].intValue
                                )
                            )
                        },
                        en: respJSON["rankingRewards"][1].map {
                            Event.RankingReward(
                                rankRange: $0.1["fromRank"].intValue...$0.1["toRank"].intValue,
                                reward: .init(
                                    itemID: $0.1["rewardId"].int,
                                    type: .init(rawValue: $0.1["rewardType"].stringValue) ?? .item,
                                    quantity: $0.1["rewardQuantity"].intValue
                                )
                            )
                        },
                        tw: respJSON["rankingRewards"][2].map {
                            Event.RankingReward(
                                rankRange: $0.1["fromRank"].intValue...$0.1["toRank"].intValue,
                                reward: .init(
                                    itemID: $0.1["rewardId"].int,
                                    type: .init(rawValue: $0.1["rewardType"].stringValue) ?? .item,
                                    quantity: $0.1["rewardQuantity"].intValue
                                )
                            )
                        },
                        cn: respJSON["rankingRewards"][3].map {
                            Event.RankingReward(
                                rankRange: $0.1["fromRank"].intValue...$0.1["toRank"].intValue,
                                reward: .init(
                                    itemID: $0.1["rewardId"].int,
                                    type: .init(rawValue: $0.1["rewardType"].stringValue) ?? .item,
                                    quantity: $0.1["rewardQuantity"].intValue
                                )
                            )
                        },
                        kr: respJSON["rankingRewards"][4].map {
                            Event.RankingReward(
                                rankRange: $0.1["fromRank"].intValue...$0.1["toRank"].intValue,
                                reward: .init(
                                    itemID: $0.1["rewardId"].int,
                                    type: .init(rawValue: $0.1["rewardType"].stringValue) ?? .item,
                                    quantity: $0.1["rewardQuantity"].intValue
                                )
                            )
                        },
                    )
                    
                    // Musics
                    var musics: DoriAPI.LocalizedData<[Event.Music]>?
                    for locale in DoriAPI.Locale.allCases {
                        let objects = respJSON["musics"][locale._rawIntValue]
                        guard !objects.isEmpty else { continue }
                        
                        if musics == nil {
                            musics = .init(jp: nil, en: nil, tw: nil, cn: nil, kr: nil)
                        }
                        
                        var result: [Event.Music] = []
                        for (_, music) in objects {
                            result.append(.init(
                                id: music["musicId"].intValue,
                                rankingRewards: music["musicRankingRewards"].map {
                                    .init(
                                        rankRange: $0.1["fromRank"].intValue...$0.1["toRank"].intValue,
                                        reward: .init(
                                            itemID: $0.1["resourceId"].int,
                                            type: .init(rawValue: $0.1["resourceType"].stringValue) ?? .item,
                                            quantity: $0.1["quantity"].intValue
                                        )
                                    )
                                }
                            ))
                        }
                        musics!._set(result, forLocale: locale)
                    }
                    
                    // Live try missons
                    var liveTryMissions: [Int: Event.LiveTryMission]?
                    var liveTryMissionDetails: [Int: Event.LiveTryMissionDetail]?
                    var liveTryMissionTypeSequences: [Event.LiveTryMissionType: Int]?
                    var liveTryMissionRewards: [Int: [DoriAPI.Item]]?
                    if !respJSON["masterLiveTryMissionMap"]["entries"].isEmpty {
                        liveTryMissions = respJSON["masterLiveTryMissionMap"]["entries"].map {
                            (key: Int($0.0) ?? -1,
                             value: Event.LiveTryMission(
                                eventID: $0.1["eventId"].intValue,
                                missionID: $0.1["liveTryMissionId"].intValue,
                                missionDetailID: $0.1["liveTryMissionDetailId"].intValue,
                                missionType: .init(rawValue: $0.1["liveTryMissionType"].stringValue) ?? .score,
                                missionDifficultyType: .init(rawValue: $0.1["liveTryMissionDifficultyType"].stringValue) ?? .normal,
                                level: $0.1["level"].intValue
                             ))
                        }.reduce(into: [Int: Event.LiveTryMission]()) {
                            $0.updateValue($1.value, forKey: $1.key)
                        }
                    }
                    if !respJSON["masterLiveTryMissionDetailMap"]["entries"].isEmpty {
                        liveTryMissionDetails = respJSON["masterLiveTryMissionDetailMap"]["entries"].map {
                            (key: Int($0.0) ?? -1,
                             value: Event.LiveTryMissionDetail(
                                musicDescription: .init(
                                    jp: $0.1["musicDescription"][0].string,
                                    en: $0.1["musicDescription"][1].string,
                                    tw: $0.1["musicDescription"][2].string,
                                    cn: $0.1["musicDescription"][3].string,
                                    kr: $0.1["musicDescription"][4].string
                                ),
                                difficultyDescription: .init(
                                    jp: $0.1["difficultyDescription"][0].string,
                                    en: $0.1["difficultyDescription"][1].string,
                                    tw: $0.1["difficultyDescription"][2].string,
                                    cn: $0.1["difficultyDescription"][3].string,
                                    kr: $0.1["difficultyDescription"][4].string
                                ),
                                description: .init(
                                    jp: $0.1["description"][0].string,
                                    en: $0.1["description"][1].string,
                                    tw: $0.1["description"][2].string,
                                    cn: $0.1["description"][3].string,
                                    kr: $0.1["description"][4].string
                                )
                             ))
                        }.reduce(into: [Int: Event.LiveTryMissionDetail]()) {
                            $0.updateValue($1.value, forKey: $1.key)
                        }
                    }
                    if !respJSON["masterLiveTryMissionTypeSequenceMap"]["entries"].isEmpty {
                        liveTryMissionTypeSequences = respJSON["masterLiveTryMissionTypeSequenceMap"]["entries"].map {
                            (key: Event.LiveTryMissionType(rawValue: $0.0) ?? .score,
                             value: $0.1.intValue)
                        }.reduce(into: [Event.LiveTryMissionType: Int]()) {
                            $0.updateValue($1.value, forKey: $1.key)
                        }
                    }
                    if !respJSON["masterLiveTryMissionRewardMap"]["entries"].isEmpty {
                        liveTryMissionRewards = respJSON["masterLiveTryMissionRewardMap"]["entries"].map {
                            (key: Int($0.0) ?? -1,
                             value: $0.1["entries"].map {
                                DoriAPI.Item(
                                    itemID: $0.1["resourceId"].int,
                                    type: .init(rawValue: $0.1["resourceType"].stringValue) ?? .item,
                                    quantity: $0.1["quantity"].intValue
                                )}
                            )
                        }.reduce(into: [Int: [DoriAPI.Item]]()) {
                            $0.updateValue($1.value, forKey: $1.key)
                        }
                    }
                    
                    // Festival
                    var teamList: [Event.FestivalTeam]?
                    var teamRewards: [Event.FestivalTeamReward]?
                    if !respJSON["teamList"]["entries"].isEmpty {
                        teamList = respJSON["teamList"]["entries"].map {
                            .init(
                                eventID: $0.1["eventId"].intValue,
                                teamID: $0.1["teamId"].intValue,
                                teamName: $0.1["teamName"].stringValue,
                                iconFileName: $0.1["iconFileName"].stringValue,
                                themeTitle: $0.1["themeTitle"].stringValue
                            )
                        }
                    }
                    if !respJSON["teamRewards"]["entries"].isEmpty {
                        teamRewards = respJSON["teamRewards"]["entries"].map {
                            .init(
                                festivalResult: .init(rawValue: $0.1["festivalResultType"].stringValue) ?? .win,
                                item: .init(
                                    itemID: $0.1["resourceId"].int,
                                    type: .init(rawValue: $0.1["resourceType"].stringValue) ?? .item,
                                    quantity: $0.1["quantity"].intValue
                                )
                            )
                        }
                    }
                    
                    return Event(
                        id: id,
                        eventType: .init(rawValue: respJSON["eventType"].stringValue) ?? .normal,
                        eventName: .init(
                            jp: respJSON["eventName"][0].string,
                            en: respJSON["eventName"][1].string,
                            tw: respJSON["eventName"][2].string,
                            cn: respJSON["eventName"][3].string,
                            kr: respJSON["eventName"][4].string
                        ),
                        assetBundleName: respJSON["assetBundleName"].stringValue,
                        bannerAssetBundleName: respJSON["bannerAssetBundleName"].stringValue,
                        startAt: .init(
                            jp: .init(apiTimeInterval: respJSON["startAt"][0].string),
                            en: .init(apiTimeInterval: respJSON["startAt"][1].string),
                            tw: .init(apiTimeInterval: respJSON["startAt"][2].string),
                            cn: .init(apiTimeInterval: respJSON["startAt"][3].string),
                            kr: .init(apiTimeInterval: respJSON["startAt"][4].string)
                        ),
                        endAt: .init(
                            jp: .init(apiTimeInterval: respJSON["endAt"][0].string),
                            en: .init(apiTimeInterval: respJSON["endAt"][1].string),
                            tw: .init(apiTimeInterval: respJSON["endAt"][2].string),
                            cn: .init(apiTimeInterval: respJSON["endAt"][3].string),
                            kr: .init(apiTimeInterval: respJSON["endAt"][4].string)
                        ),
                        publicStartAt: .init(
                            jp: .init(apiTimeInterval: respJSON["publicStartAt"][0].string),
                            en: .init(apiTimeInterval: respJSON["publicStartAt"][1].string),
                            tw: .init(apiTimeInterval: respJSON["publicStartAt"][2].string),
                            cn: .init(apiTimeInterval: respJSON["publicStartAt"][3].string),
                            kr: .init(apiTimeInterval: respJSON["publicStartAt"][4].string)
                        ),
                        publicEndAt: .init(
                            jp: .init(apiTimeInterval: respJSON["publicEndAt"][0].string),
                            en: .init(apiTimeInterval: respJSON["publicEndAt"][1].string),
                            tw: .init(apiTimeInterval: respJSON["publicEndAt"][2].string),
                            cn: .init(apiTimeInterval: respJSON["publicEndAt"][3].string),
                            kr: .init(apiTimeInterval: respJSON["publicEndAt"][4].string)
                        ),
                        distributionStartAt: .init(
                            jp: .init(apiTimeInterval: respJSON["distributionStartAt"][0].string),
                            en: .init(apiTimeInterval: respJSON["distributionStartAt"][1].string),
                            tw: .init(apiTimeInterval: respJSON["distributionStartAt"][2].string),
                            cn: .init(apiTimeInterval: respJSON["distributionStartAt"][3].string),
                            kr: .init(apiTimeInterval: respJSON["distributionStartAt"][4].string)
                        ),
                        distributionEndAt: .init(
                            jp: .init(apiTimeInterval: respJSON["distributionEndAt"][0].string),
                            en: .init(apiTimeInterval: respJSON["distributionEndAt"][1].string),
                            tw: .init(apiTimeInterval: respJSON["distributionEndAt"][2].string),
                            cn: .init(apiTimeInterval: respJSON["distributionEndAt"][3].string),
                            kr: .init(apiTimeInterval: respJSON["distributionEndAt"][4].string)
                        ),
                        bgmAssetBundleName: respJSON["bgmAssetBundleName"].stringValue,
                        bgmFileName: respJSON["bgmFileName"].stringValue,
                        aggregateEndAt: .init(
                            jp: .init(apiTimeInterval: respJSON["aggregateEndAt"][0].string),
                            en: .init(apiTimeInterval: respJSON["aggregateEndAt"][1].string),
                            tw: .init(apiTimeInterval: respJSON["aggregateEndAt"][2].string),
                            cn: .init(apiTimeInterval: respJSON["aggregateEndAt"][3].string),
                            kr: .init(apiTimeInterval: respJSON["aggregateEndAt"][4].string)
                        ),
                        exchangeEndAt: .init(
                            jp: .init(apiTimeInterval: respJSON["exchangeEndAt"][0].string),
                            en: .init(apiTimeInterval: respJSON["exchangeEndAt"][1].string),
                            tw: .init(apiTimeInterval: respJSON["exchangeEndAt"][2].string),
                            cn: .init(apiTimeInterval: respJSON["exchangeEndAt"][3].string),
                            kr: .init(apiTimeInterval: respJSON["exchangeEndAt"][4].string)
                        ),
                        pointRewards: pointRewards,
                        rankingRewards: rankingRewards,
                        attributes: respJSON["attributes"].map {
                            EventAttribute(
                                eventID: $0.1["eventId"].int,
                                attribute: .init(rawValue: $0.1["attribute"].stringValue) ?? .pure,
                                percent: $0.1["percent"].intValue
                            )
                        },
                        characters: respJSON["characters"].map {
                            EventCharacter(
                                eventID: $0.1["eventId"].int,
                                characterID: $0.1["characterId"].intValue,
                                percent: $0.1["percent"].intValue,
                                seq: $0.1["seq"].int
                            )
                        },
                        eventAttributeAndCharacterBonus: respJSON["eventAttributeAndCharacterBonus"]["eventId"].int != nil ? .init(
                            eventID: respJSON["eventAttributeAndCharacterBonus"]["eventId"].intValue,
                            pointPercent: respJSON["eventAttributeAndCharacterBonus"]["pointPercent"].intValue,
                            parameterPercent: respJSON["eventAttributeAndCharacterBonus"]["parameterPercent"].intValue
                        ) : nil,
                        eventCharacterParameterBonus: respJSON["eventCharacterParameterBonus"]["performance"].int != nil ? .init(
                            performance: respJSON["eventCharacterParameterBonus"]["performance"].intValue,
                            technique: respJSON["eventCharacterParameterBonus"]["technique"].intValue,
                            visual: respJSON["eventCharacterParameterBonus"]["visual"].intValue
                        ) : nil,
                        members: respJSON["members"].map {
                            EventMember(
                                eventID: $0.1["eventId"].int,
                                situationID: $0.1["situationId"].intValue,
                                percent: $0.1["percent"].intValue,
                                seq: $0.1["seq"].int
                            )
                        },
                        limitBreaks: respJSON["limitBreaks"].map {
                            EventLimitBreak(
                                rarity: $0.1["rarity"].intValue,
                                rank: $0.1["rank"].intValue,
                                percent: $0.1["percent"].doubleValue
                            )
                        },
                        stories: respJSON["stories"].map {
                            Event.Story(
                                scenarioID: $0.1["scenarioId"].stringValue,
                                coverImage: $0.1["coverImage"].stringValue,
                                backgroundImage: $0.1["backgroundImage"].stringValue,
                                releasePt: Int($0.1["releasePt"].stringValue) ?? 0,
                                rewards: $0.1["rewards"].map {
                                    .init(
                                        itemID: $0.1["rewardId"].int,
                                        type: .init(rawValue: $0.1["rewardType"].stringValue) ?? .item,
                                        quantity: $0.1["rewardQuantity"].intValue
                                    )
                                },
                                caption: .init(
                                    jp: $0.1["caption"][0].string,
                                    en: $0.1["caption"][1].string,
                                    tw: $0.1["caption"][2].string,
                                    cn: $0.1["caption"][3].string,
                                    kr: $0.1["caption"][4].string
                                ),
                                title: .init(
                                    jp: $0.1["title"][0].string,
                                    en: $0.1["title"][1].string,
                                    tw: $0.1["title"][2].string,
                                    cn: $0.1["title"][3].string,
                                    kr: $0.1["title"][4].string
                                ),
                                synopsis: .init(
                                    jp: $0.1["synopsis"][0].string,
                                    en: $0.1["synopsis"][1].string,
                                    tw: $0.1["synopsis"][2].string,
                                    cn: $0.1["synopsis"][3].string,
                                    kr: $0.1["synopsis"][4].string
                                ),
                                releaseConditions: .init(
                                    jp: $0.1["releaseConditions"][0].string,
                                    en: $0.1["releaseConditions"][1].string,
                                    tw: $0.1["releaseConditions"][2].string,
                                    cn: $0.1["releaseConditions"][3].string,
                                    kr: $0.1["releaseConditions"][4].string
                                )
                            )
                        },
                        rewardCards: respJSON["rewardCards"].map { $0.1.intValue },
                        musics: musics,
                        liveTryMissions: liveTryMissions,
                        liveTryMissionDetails: liveTryMissionDetails,
                        liveTryMissionTypeSequences: liveTryMissionTypeSequences,
                        liveTryMissionRewards: liveTryMissionRewards,
                        teamList: teamList,
                        teamRewards: teamRewards
                    )
                }
                return await task.value
            }
            return nil
        }
        
        /// Get rotation musics for a festival event.
        /// - Parameter id: ID of target event.
        /// - Returns: Rotation musics for the event, nil if failed to fetch.
        public static func festivalRotationMusics(of id: Int) async -> [RotationMusic]? {
            // Response example:
            // [{
            //     "musicId": 672,
            //     "startAt": "1758524400000",
            //     "endAt": "1758529799000"
            // },
            // ...]
            let request = await requestJSON("https://bestdori.com/api/festival/rotationMusics/\(id).json")
            if case let .success(respJSON) = request {
                let task = Task.detached(priority: .userInitiated) {
                    respJSON.map {
                        RotationMusic(
                            musicID: $0.1["musicId"].intValue,
                            startAt: .init(apiTimeInterval: $0.1["startAt"].stringValue) ?? .init(timeIntervalSince1970: 0),
                            endAt: .init(apiTimeInterval: $0.1["endAt"].stringValue) ?? .init(timeIntervalSince1970: 0)
                        )
                    }
                }
                return await task.value
            }
            return nil
        }
        
        /// Get stages for a festival event.
        /// - Parameter id: ID of target event.
        /// - Returns: Stages for the event, nil if failed to fetch.
        public static func festivalStages(of id: Int) async -> [FestivalStage]? {
            // Response example:
            // [{
            //     "type": "life",
            //     "startAt": "1758524400000",
            //     "endAt": "1758535199000"
            // },
            // ...]
            let request = await requestJSON("https://bestdori.com/api/festival/stages/\(id).json")
            if case let .success(respJSON) = request {
                let task = Task.detached(priority: .userInitiated) {
                    respJSON.map {
                        FestivalStage(
                            type: .init(rawValue: $0.1["type"].stringValue) ?? .life,
                            startAt: .init(apiTimeInterval: $0.1["startAt"].stringValue) ?? .init(timeIntervalSince1970: 0),
                            endAt: .init(apiTimeInterval: $0.1["endAt"].stringValue) ?? .init(timeIntervalSince1970: 0)
                        )
                    }
                }
                return await task.value
            }
            return nil
        }
        
        /// Get top 10 data of an event in Bandori.
        /// - Parameters:
        ///   - id: ID of the event.
        ///   - locale: Locale for event data.
        ///   - interval: Interval of each data, the default value is 0.
        /// - Returns: Top 10 data of requested event, nil if failed to fetch.
        public static func topData(of id: Int, in locale: Locale, interval: TimeInterval = 0) async -> TopData? {
            // Response example:
            // {
            //     "points": [
            //         {
            //             "time": 1753600364600,
            //             "uid": 1000000001,
            //             "value": 175490
            //         },
            //         ...
            //     ],
            //     "users": [
            //         {
            //             "uid": 1000000001,
            //             "name": "工作人员一号",
            //             "introduction": "觉悟～fighting",
            //             "rank": 130,
            //             "sid": 2095,
            //             "strained": 1,
            //             "degrees": [
            //                 20061,
            //                 20077
            //             ]
            //         },
            //         ...
            //     ]
            // }
            let serverID = switch locale {
            case .jp: 0
            case .en: 1
            case .tw: 2
            case .cn: 3
            case .kr: 4
            }
            let request = await requestJSON("https://bestdori.com/api/eventtop/data?server=\(serverID)&event=\(id)&mid=0&interval=\(interval)")
            if case let .success(respJSON) = request {
                let task = Task.detached(priority: .userInitiated) {
                    return TopData(
                        points: respJSON["points"].map {
                            .init(
                                time: Date(timeIntervalSince1970: $0.1["time"].doubleValue / 1000),
                                uid: $0.1["uid"].intValue,
                                value: $0.1["value"].intValue
                            )
                        },
                        users: respJSON["users"].map {
                            .init(
                                uid: $0.1["uid"].intValue,
                                name: $0.1["name"].stringValue,
                                introduction: $0.1["introduction"].stringValue,
                                rank: $0.1["rank"].intValue,
                                sid: $0.1["sid"].intValue,
                                strained: $0.1["strained"].intValue != 0,
                                degrees: $0.1["degrees"].map { $0.1.intValue }
                            )
                        }
                    )
                }
                return await task.value
            }
            return nil
        }
        
        /// Get rates information of event tracker.
        /// - Returns: Rates information of event tracker.
        public static func trackerRates() async -> [TrackerRate]? {
            // Response example:
            // [{
            //     "type": "story",
            //     "server": 0,
            //     "tier": 100,
            //     "rate": 0.1864557607881584
            // },...]
            let request = await requestJSON("https://bestdori.com/api/tracker/rates.json")
            if case let .success(respJSON) = request {
                let task = Task.detached(priority: .userInitiated) {
                    return respJSON.map {
                        let locale = switch $0.1["server"].intValue {
                        case 0: Locale.jp
                        case 1: Locale.en
                        case 2: Locale.tw
                        case 3: Locale.cn
                        case 4: Locale.kr
                        default: Locale.jp
                        }
                        return TrackerRate(
                            type: .init(rawValue: $0.1["type"].stringValue) ?? .normal,
                            server: locale,
                            tier: $0.1["tier"].intValue,
                            rate: $0.1["rate"].doubleValue
                        )
                    }
                }
                return await task.value
            }
            return nil
        }
        
        /// Get cutoff data of event tracker.
        /// - Parameters:
        ///   - id: ID of event.
        ///   - locale: Locale for event data.
        ///   - tier: Tier. Possible values are 20, 30, 40, 50, 100, 200, 300, 400, 500, 1000, 2000, 3000, 4000, 5000, 10000, 20000 and 30000.
        /// - Returns: Cutoff data of requested event, nil if failed to fetch.
        public static func trackerData(of id: Int, in locale: Locale, tier: Int) async -> TrackerData? {
            // Response example:
            // {
            //     "result": true, // We emit this field in Swift API and return nil if it's false.
            //     "cutoffs": [
            //         {
            //             "time": 1753600511000,
            //             "ep": 51280
            //         },
            //         ...
            //     }
            // }
            let serverID = switch locale {
            case .jp: 0
            case .en: 1
            case .tw: 2
            case .cn: 3
            case .kr: 4
            }
            let request = await requestJSON("https://bestdori.com/api/tracker/data?server=\(serverID)&event=\(id)&tier=\(tier)")
            if case let .success(respJSON) = request {
                let task = Task.detached(priority: .userInitiated) { () async -> TrackerData? in
                    guard respJSON["result"].boolValue else { return nil }
                    return TrackerData(
                        cutoffs: respJSON["cutoffs"].map {
                            .init(
                                time: Date(timeIntervalSince1970: $0.1["time"].doubleValue / 1000),
                                ep: $0.1["ep"].intValue
                            )
                        }
                    )
                }
                return await task.value
            }
            return nil
        }
        
        /// Get all events with stories in Bandori.
        /// - Returns: Requested events with stories, nil if failed to fetch.
        public static func allStories() async -> [EventStory]? {
            let request = await requestJSON("https://bestdori.com/api/events/all.stories.json")
            if case let .success(respJSON) = request {
                let task = Task.detached(priority: .userInitiated) {
                    var result = [EventStory]()
                    for (key, value) in respJSON {
                        result.append(.init(
                            id: Int(key) ?? 0,
                            eventName: .init(
                                jp: value["eventName"][0].string,
                                en: value["eventName"][1].string,
                                tw: value["eventName"][2].string,
                                cn: value["eventName"][3].string,
                                kr: value["eventName"][4].string
                            ),
                            stories: value["stories"].map {
                                .init(
                                    scenarioID: $0.1["scenarioId"].stringValue,
                                    caption: .init(
                                        jp: $0.1["caption"][0].string,
                                        en: $0.1["caption"][1].string,
                                        tw: $0.1["caption"][2].string,
                                        cn: $0.1["caption"][3].string,
                                        kr: $0.1["caption"][4].string
                                    ),
                                    title: .init(
                                        jp: $0.1["title"][0].string,
                                        en: $0.1["title"][1].string,
                                        tw: $0.1["title"][2].string,
                                        cn: $0.1["title"][3].string,
                                        kr: $0.1["title"][4].string
                                    ),
                                    synopsis: .init(
                                        jp: $0.1["synopsis"][0].string,
                                        en: $0.1["synopsis"][1].string,
                                        tw: $0.1["synopsis"][2].string,
                                        cn: $0.1["synopsis"][3].string,
                                        kr: $0.1["synopsis"][4].string
                                    )
                                )
                            }
                        ))
                    }
                    return result.sorted { $0.id < $1.id }
                }
                return await task.value
            }
            return nil
        }
    }
}

extension DoriAPI.Events {
    /// Represent simplified data of an event.
    public struct PreviewEvent: Sendable, Identifiable, Hashable, DoriCache.Cacheable {
        /// A unique ID of event.
        public var id: Int
        /// Type of event.
        public var eventType: EventType
        /// Localized name of event.
        public var eventName: DoriAPI.LocalizedData<String>
        /// Name of resource bundle, used for combination of resource URLs.
        public var assetBundleName: String
        /// Name of banner resource bundle, used for combination of resource URLs.
        public var bannerAssetBundleName: String
        /// Localized start date of event.
        public var startAt: DoriAPI.LocalizedData<Date> // String(JSON) -> Date(Swift)
        /// Localized end date of event.
        public var endAt: DoriAPI.LocalizedData<Date> // String(JSON) -> Date(Swift)
        /// Attributes related to this event, with bonus percentage.
        public var attributes: [EventAttribute]
        /// Characters related to this event, with bonus percentage.
        public var characters: [EventCharacter]
        public var eventAttributeAndCharacterBonus: EventAttributeAndCharacterBonus?
        public var eventCharacterParameterBonus: DoriAPI.Cards.Stat?
        /// Members related to this event, with bonus percentage.
        ///
        /// A *member* related to event is a card with bonus during the event.
        public var members: [EventMember]
        public var limitBreaks: [EventLimitBreak]
        public var musicIDs: DoriAPI.LocalizedData<[Int]>?
        /// IDs of cards that can be gotten by participating this event.
        public var rewardCards: [Int]
        
        internal init(
            id: Int,
            eventType: EventType,
            eventName: DoriAPI.LocalizedData<String>,
            assetBundleName: String,
            bannerAssetBundleName: String,
            startAt: DoriAPI.LocalizedData<Date>,
            endAt: DoriAPI.LocalizedData<Date>,
            attributes: [EventAttribute],
            characters: [EventCharacter],
            eventAttributeAndCharacterBonus: EventAttributeAndCharacterBonus?,
            eventCharacterParameterBonus: DoriAPI.Cards.Stat?,
            members: [EventMember],
            limitBreaks: [EventLimitBreak],
            musicIDs: DoriAPI.LocalizedData<[Int]>?,
            rewardCards: [Int]
        ) {
            self.id = id
            self.eventType = eventType
            self.eventName = eventName
            self.assetBundleName = assetBundleName
            self.bannerAssetBundleName = bannerAssetBundleName
            self.startAt = startAt
            self.endAt = endAt
            self.attributes = attributes
            self.characters = characters
            self.eventAttributeAndCharacterBonus = eventAttributeAndCharacterBonus
            self.eventCharacterParameterBonus = eventCharacterParameterBonus
            self.members = members
            self.limitBreaks = limitBreaks
            self.musicIDs = musicIDs
            self.rewardCards = rewardCards
        }
    }
    
    /// Represent detailed data of an event.
    public struct Event: Sendable, Identifiable, Hashable, DoriCache.Cacheable {
        /// A unique ID of event.
        public var id: Int
        /// Type of event.
        public var eventType: EventType
        /// Localized name of event.
        public var eventName: DoriAPI.LocalizedData<String>
        /// Name of resource bundle, used for combination of resource URLs.
        public var assetBundleName: String
        /// Name of banner resource bundle, used for combination of resource URLs.
        public var bannerAssetBundleName: String
        /// Localized start date of event.
        public var startAt: DoriAPI.LocalizedData<Date> // String(JSON) -> Date(Swift)
        /// Localized end date of event.
        public var endAt: DoriAPI.LocalizedData<Date> // String(JSON) -> Date(Swift)
        public var publicStartAt: DoriAPI.LocalizedData<Date> // String(JSON) -> Date(Swift)
        public var publicEndAt: DoriAPI.LocalizedData<Date> // String(JSON) -> Date(Swift)
        public var distributionStartAt: DoriAPI.LocalizedData<Date> // String(JSON) -> Date(Swift)
        public var distributionEndAt: DoriAPI.LocalizedData<Date> // String(JSON) -> Date(Swift)
        /// Name of BGM resource bundle, used for combination of resource URLs.
        public var bgmAssetBundleName: String
        /// Name of BGM file, used for combination of resource URLs.
        public var bgmFileName: String
        public var aggregateEndAt: DoriAPI.LocalizedData<Date> // String(JSON) -> Date(Swift)
        public var exchangeEndAt: DoriAPI.LocalizedData<Date> // String(JSON) -> Date(Swift)
        public var pointRewards: DoriAPI.LocalizedData<[PointReward]>
        public var rankingRewards: DoriAPI.LocalizedData<[RankingReward]>
        /// Attributes related to this event, with bonus percentage.
        public var attributes: [EventAttribute]
        /// Characters related to this event, with bonus percentage.
        public var characters: [EventCharacter]
        public var eventAttributeAndCharacterBonus: EventAttributeAndCharacterBonus?
        public var eventCharacterParameterBonus: DoriAPI.Cards.Stat?
        /// Members related to this event, with bonus percentage.
        ///
        /// A *member* related to event is a card with bonus during the event.
        public var members: [EventMember]
        public var limitBreaks: [EventLimitBreak]
        public var stories: [Story]
        /// IDs of cards that can be gotten by participating this event.
        public var rewardCards: [Int]
        public var musics: DoriAPI.LocalizedData<[Music]>?
        public var liveTryMissions: [Int: LiveTryMission]?
        public var liveTryMissionDetails: [Int: LiveTryMissionDetail]?
        public var liveTryMissionTypeSequences: [LiveTryMissionType: Int]?
        public var liveTryMissionRewards: [Int: [DoriAPI.Item]]?
        public var teamList: [FestivalTeam]?
        public var teamRewards: [FestivalTeamReward]?
        
        internal init(
            id: Int,
            eventType: EventType,
            eventName: DoriAPI.LocalizedData<String>,
            assetBundleName: String,
            bannerAssetBundleName: String,
            startAt: DoriAPI.LocalizedData<Date>,
            endAt: DoriAPI.LocalizedData<Date>,
            publicStartAt: DoriAPI.LocalizedData<Date>,
            publicEndAt: DoriAPI.LocalizedData<Date>,
            distributionStartAt: DoriAPI.LocalizedData<Date>,
            distributionEndAt: DoriAPI.LocalizedData<Date>,
            bgmAssetBundleName: String,
            bgmFileName: String,
            aggregateEndAt: DoriAPI.LocalizedData<Date>,
            exchangeEndAt: DoriAPI.LocalizedData<Date>,
            pointRewards: DoriAPI.LocalizedData<[PointReward]>,
            rankingRewards: DoriAPI.LocalizedData<[RankingReward]>,
            attributes: [EventAttribute],
            characters: [EventCharacter],
            eventAttributeAndCharacterBonus: EventAttributeAndCharacterBonus?,
            eventCharacterParameterBonus: DoriAPI.Cards.Stat?,
            members: [EventMember],
            limitBreaks: [EventLimitBreak],
            stories: [Story],
            rewardCards: [Int],
            musics: DoriAPI.LocalizedData<[Music]>?,
            liveTryMissions: [Int: LiveTryMission]?,
            liveTryMissionDetails: [Int: LiveTryMissionDetail]?,
            liveTryMissionTypeSequences: [LiveTryMissionType: Int]?,
            liveTryMissionRewards: [Int: [DoriAPI.Item]]?,
            teamList: [FestivalTeam]?,
            teamRewards: [FestivalTeamReward]?
        ) {
            self.id = id
            self.eventType = eventType
            self.eventName = eventName
            self.assetBundleName = assetBundleName
            self.bannerAssetBundleName = bannerAssetBundleName
            self.startAt = startAt
            self.endAt = endAt
            self.publicStartAt = publicStartAt
            self.publicEndAt = publicEndAt
            self.distributionStartAt = distributionStartAt
            self.distributionEndAt = distributionEndAt
            self.bgmAssetBundleName = bgmAssetBundleName
            self.bgmFileName = bgmFileName
            self.aggregateEndAt = aggregateEndAt
            self.exchangeEndAt = exchangeEndAt
            self.pointRewards = pointRewards
            self.rankingRewards = rankingRewards
            self.attributes = attributes
            self.characters = characters
            self.eventAttributeAndCharacterBonus = eventAttributeAndCharacterBonus
            self.eventCharacterParameterBonus = eventCharacterParameterBonus
            self.members = members
            self.limitBreaks = limitBreaks
            self.stories = stories
            self.rewardCards = rewardCards
            self.musics = musics
            self.liveTryMissions = liveTryMissions
            self.liveTryMissionDetails = liveTryMissionDetails
            self.liveTryMissionTypeSequences = liveTryMissionTypeSequences
            self.liveTryMissionRewards = liveTryMissionRewards
            self.teamList = teamList
            self.teamRewards = teamRewards
        }
        
        public struct PointReward: Sendable, Hashable, DoriCache.Cacheable {
            public var point: Int
            public var reward: DoriAPI.Item
        }
        public struct RankingReward: Sendable, Hashable, DoriCache.Cacheable {
            public var rankRange: ClosedRange<Int> // keys{fromRank, toRank}(JSON) -> ClosedRange(Swift)
            public var reward: DoriAPI.Item
        }
        
        public struct Story: Sendable, Hashable, DoriCache.Cacheable {
            public var scenarioID: String
            public var coverImage: String
            public var backgroundImage: String
            public var releasePt: Int
            public var rewards: [DoriAPI.Item]
            public var caption: DoriAPI.LocalizedData<String>
            public var title: DoriAPI.LocalizedData<String>
            public var synopsis: DoriAPI.LocalizedData<String>
            public var releaseConditions: DoriAPI.LocalizedData<String>
        }
        
        public struct Music: Sendable, Identifiable, Hashable, DoriCache.Cacheable {
            public var id: Int
            public var rankingRewards: [RankingReward]
        }
        
        public struct LiveTryMission: Sendable, Hashable, DoriCache.Cacheable {
            public var eventID: Int
            public var missionID: Int
            public var missionDetailID: Int
            public var missionType: LiveTryMissionType
            public var missionDifficultyType: DifficultyType
            public var level: Int
            
            public enum DifficultyType: String, Sendable, Hashable, DoriCache.Cacheable {
                case normal
                case extra
            }
        }
        
        public enum LiveTryMissionType: String, Sendable, Hashable, DoriCache.Cacheable {
            case score
            case life
            case combo
            case judge
            case multi
        }
        
        public struct LiveTryMissionDetail: Sendable, Hashable, DoriCache.Cacheable {
            public var musicDescription: DoriAPI.LocalizedData<String>
            public var difficultyDescription: DoriAPI.LocalizedData<String>
            public var description: DoriAPI.LocalizedData<String>
        }
        
        public struct FestivalTeam: Sendable, Identifiable, Hashable, DoriCache.Cacheable {
            public var eventID: Int
            public var teamID: Int
            public var teamName: String
            public var iconFileName: String
            public var themeTitle: String
            
            @inlinable
            public var id: Int { teamID }
        }
        
        public struct FestivalTeamReward: Sendable, Hashable, DoriCache.Cacheable {
            public var festivalResult: FestivalResult
            public var item: DoriAPI.Item
        }
        
        public enum FestivalResult: String, Sendable, Hashable, DoriCache.Cacheable {
            case win
            case lose
        }
    }
    
    public struct RotationMusic: Sendable, Hashable, DoriCache.Cacheable {
        public var musicID: Int
        public var startAt: Date
        public var endAt: Date
    }
    
    public struct FestivalStage: Sendable, Hashable, DoriCache.Cacheable {
        public var type: StageType
        public var startAt: Date
        public var endAt: Date
        
        public enum StageType: String, Sendable, Codable, Hashable {
            case life
            case judge
            case combo
        }
    }
    
    /// Represent top 10 data of an event.
    public struct TopData: Sendable, Hashable, DoriCache.Cacheable {
        public var points: [Point]
        public var users: [User]
        
        public struct Point: Sendable, Hashable, DoriCache.Cacheable {
            public var time: Date
            public var uid: Int
            public var value: Int
        }
        public struct User: Sendable, Hashable, DoriCache.Cacheable {
            public var uid: Int
            public var name: String
            public var introduction: String
            public var rank: Int
            public var sid: Int
            public var strained: Bool // Int(JSON) -> Bool(Swift)
            public var degrees: [Int]
        }
    }
    
    public struct TrackerRate: Sendable, Hashable, DoriCache.Cacheable {
        public var type: EventType
        public var server: DoriAPI.Locale
        public var tier: Int
        public var rate: Double
    }
    /// Represent cutoff data of an event.
    public struct TrackerData: Sendable, Hashable, DoriCache.Cacheable {
        public var cutoffs: [Cutoff]
        
        public struct Cutoff: Sendable, Hashable, DoriCache.Cacheable {
            public var time: Date
            public var ep: Int
        }
    }
    
    /// Represent type of an event.
    public enum EventType: String, Sendable, CaseIterable, Hashable, DoriCache.Cacheable {
        case normal = "story"
        case challengeLive = "challenge"
        case vsLive = "versus"
        case liveGoals = "live_try"
        case missionLive = "mission_live"
        case teamLiveFestival = "festival"
        case medleyLive = "medley"
    }
    
    /// Represent an attribute with bonus related to an event.
    public struct EventAttribute: Sendable, Hashable, DoriCache.Cacheable {
        /// Related event ID.
        public var eventID: Int?
        /// Attribute.
        public var attribute: DoriAPI.Attribute
        /// Percentage of bonus.
        public var percent: Int
        
        internal init(eventID: Int?, attribute: DoriAPI.Attribute, percent: Int) {
            self.eventID = eventID
            self.attribute = attribute
            self.percent = percent
        }
    }
    /// Represent a character with bonus related to an event.
    public struct EventCharacter: Sendable, Hashable, DoriCache.Cacheable {
        /// Related event ID.
        public var eventID: Int?
        /// Character ID.
        public var characterID: Int
        /// Percentage of bonus.
        public var percent: Int
        public var seq: Int?
        
        internal init(eventID: Int?, characterID: Int, percent: Int, seq: Int?) {
            self.eventID = eventID
            self.characterID = characterID
            self.percent = percent
            self.seq = seq
        }
    }
    /// Represent a member with bonus related to an event.
    ///
    /// A *member* related to event is a card with bonus during the event.
    public struct EventMember: Sendable, Hashable, DoriCache.Cacheable {
        /// Related event ID.
        public var eventID: Int?
        /// Card ID.
        public var situationID: Int
        /// Percentage of bonus.
        public var percent: Int
        public var seq: Int?
        
        internal init(eventID: Int?, situationID: Int, percent: Int, seq: Int?) {
            self.eventID = eventID
            self.situationID = situationID
            self.percent = percent
            self.seq = seq
        }
    }
    public struct EventLimitBreak: Sendable, Hashable, DoriCache.Cacheable {
        public var rarity: Int
        public var rank: Int
        public var percent: Double
    }
    public struct EventAttributeAndCharacterBonus: Sendable, Hashable, DoriCache.Cacheable {
        public var eventID: Int
        public var pointPercent: Int
        public var parameterPercent: Int
    }
    
    public struct EventStory: Sendable, Identifiable, Hashable, DoriCache.Cacheable {
        public var id: Int
        public var eventName: DoriAPI.LocalizedData<String>
        public var stories: [DoriAPI.Story]
    }
}

extension DoriAPI.Events.PreviewEvent {
    public init(_ full: DoriAPI.Events.Event) {
        self.init(
            id: full.id,
            eventType: full.eventType,
            eventName: full.eventName,
            assetBundleName: full.assetBundleName,
            bannerAssetBundleName: full.bannerAssetBundleName,
            startAt: full.startAt,
            endAt: full.endAt,
            attributes: full.attributes,
            characters: full.characters,
            eventAttributeAndCharacterBonus: full.eventAttributeAndCharacterBonus,
            eventCharacterParameterBonus: full.eventCharacterParameterBonus,
            members: full.members,
            limitBreaks: full.limitBreaks,
            musicIDs: full.musics?.map { $0?.map { $0.id } },
            rewardCards: full.rewardCards
        )
    }
}
extension DoriAPI.Events.Event {
    @inlinable
    public init?(id: Int) async {
        if let event = await DoriAPI.Events.detail(of: id) {
            self = event
        } else {
            return nil
        }
    }
    
    @inlinable
    public init?(preview: DoriAPI.Events.PreviewEvent) async {
        await self.init(id: preview.id)
    }
}
