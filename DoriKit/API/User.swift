//===---*- Greatdori! -*---------------------------------------------------===//
//
// User.swift
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
internal import Alamofire
internal import SwiftyJSON

extension DoriAPI {
    /// Request and fetch data about users in Bestdori.
    ///
    /// You use the Bestdori account to join the community.
    public enum User {
        @inlinable
        public static func login(username: String, password: String) async throws(LoginError) -> Token {
            try await login(.init(username: username, password: password))
        }
        
        /// Login Bestdori by account credential.
        ///
        /// - Parameter credential: A credential of account.
        /// - Returns: A Token that you use for authentication in other places.
        ///
        /// - Throws:
        ///     A ``LoginError`` if any errors occurred during logging in.
        ///     
        public static func login(_ credential: LoginCredential) async throws(LoginError) -> Token {
            // We don't use 'throwing' continuation
            // to keep the error type
            let result: (JSON, HTTPHeaders)? = await withCheckedContinuation { continuation in
                AF.request(
                    "https://bestdori.com/api/user/login",
                    method: .post,
                    parameters: credential,
                    encoder: JSONParameterEncoder.default
                ).response { response in
                    if let data = response.data,
                       let json = try? JSON(data: data),
                       let headers = response.response?.headers {
                        continuation.resume(returning: (json, headers))
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
            
            if let (json, headers) = result {
                if json["result"].boolValue,
                   let setCookie = headers["Set-Cookie"],
                   let token = _parseTokenHeader(setCookie) {
                    return token
                } else {
                    throw .init(rawValue: json["code"].stringValue) ?? .unknown
                }
            } else {
                throw .badNetwork
            }
        }
        
        /// Signup for a Bestdori account.
        ///
        /// - Parameter form: A form with information required to signup.
        /// - Returns: A Token that you use for authentication in other places.
        ///
        /// - Throws:
        ///     A ``SignupError`` if any errors occurred during signing up.
        public static func signup(_ form: SignupForm) async throws(SignupError) -> Token {
            // We don't use 'throwing' continuation
            // to keep the error type
            let result: (JSON, HTTPHeaders)? = await withCheckedContinuation { continuation in
                AF.request(
                    "https://bestdori.com/api/user/signup",
                    method: .post,
                    parameters: form,
                    encoder: JSONParameterEncoder.default
                ).response { response in
                    if let data = response.data,
                       let json = try? JSON(data: data),
                       let headers = response.response?.headers {
                        continuation.resume(returning: (json, headers))
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
            
            if let (json, headers) = result {
                if json["result"].boolValue,
                   let setCookie = headers["Set-Cookie"],
                   let token = _parseTokenHeader(setCookie) {
                    return token
                } else {
                    throw .init(rawValue: json["code"].stringValue) ?? .unknown
                }
            } else {
                throw .badNetwork
            }
        }
        
        /// Get self-related information.
        ///
        /// - Returns: Self-related information, nil if failed to fetch.
        ///
        /// - NOTE:
        ///     Getting self information requires login first.
        ///
        /// - SeeAlso:
        ///     Use ``withUserToken(_:_:)-45z2w`` to attach a token.
        ///     Use ``login(_:)`` to get a token.
        public static func myInformation() async -> MyInformation? {
            let request = await requestJSON("https://bestdori.com/api/user/me")
            if case let .success(respJSON) = request {
                let task = Task.detached(priority: .userInitiated) { () async -> MyInformation? in
                    if respJSON["result"].bool == true {
                        return .init(
                            username: respJSON["username"].stringValue,
                            nickname: respJSON["nickname"].stringValue,
                            titles: respJSON["titles"].map {
                                .init(
                                    id: $0.1["id"].intValue,
                                    type: .init(rawValue: $0.1["type"].stringValue) ?? .bandori,
                                    server: .init(_rawIntValue: $0.1["server"].intValue) ?? .jp
                                )
                            },
                            email: respJSON["email"].stringValue,
                            messageCount: respJSON["messageCount"].intValue
                        )
                    } else {
                        return nil
                    }
                }
                return await task.value
            }
            return nil
        }
        
        /// Get information of a user.
        ///
        /// - Parameter username: The username of user.
        /// - Returns: The information of the user, nil if failed to fetch.
        ///
        /// - NOTE:
        ///     A login is required to get the right ``UserInformation/isFollowed`` value.
        ///     If there's no tokens attached, the value is always `false`.
        ///
        /// - SeeAlso:
        ///     Use ``withUserToken(_:_:)-45z2w`` to attach a token.
        ///     Use ``login(_:)`` to get a token.
        public static func userInformation(username: String) async -> UserInformation? {
            let request = await requestJSON("https://bestdori.com/api/user?username=\(username)")
            if case let .success(respJSON) = request {
                let task = Task.detached(priority: .userInitiated) { () async -> UserInformation? in
                    if respJSON["result"].bool == true {
                        var posterCard: UserInformation.PosterCard?
                        if let id = respJSON["posterCard"]["id"].int {
                            posterCard = .init(
                                id: id,
                                offset: respJSON["posterCard"]["offset"].doubleValue,
                                isTrained: respJSON["posterCard"]["trainedArt"].boolValue
                            )
                        }
                        
                        return .init(
                            followingCount: respJSON["followingCount"].intValue,
                            followedByCount: respJSON["followedByCount"].intValue,
                            isFollowed: respJSON["followed"].boolValue,
                            nickname: respJSON["nickname"].stringValue,
                            titles: respJSON["titles"].map {
                                .init(
                                    id: $0.1["id"].intValue,
                                    type: .init(rawValue: $0.1["type"].stringValue) ?? .bandori,
                                    server: .init(_rawIntValue: $0.1["server"].intValue) ?? .jp
                                )
                            },
                            posterCard: posterCard,
                            selfIntroduction: respJSON["selfIntro"].stringValue,
                            accounts: respJSON["serverIds"].map {
                                .init(
                                    server: .init(_rawIntValue: $0.1["server"].intValue) ?? .jp,
                                    uid: $0.1["id"].intValue
                                )
                            },
                            socialMedia: respJSON["socialMedia"].stringValue,
                            favoriteCharacterIDs: respJSON["favCharacters"].map { $0.1.intValue },
                            favoriteCardIDs: respJSON["favCards"].map { $0.1.intValue },
                            favoriteBandIDs: respJSON["favBands"].map { $0.1.intValue },
                            favoriteSongIDs: respJSON["favSongs"].map { $0.1.intValue },
                            favoriteCostumeIDs: respJSON["favCostumes"].map { $0.1.intValue }
                        )
                    } else {
                        return nil
                    }
                }
                return await task.value
            }
            return nil
        }
        
        /// Updates own user information.
        ///
        /// - Parameter information: New user information.
        /// - Returns: `true` if the request is sent successfully, otherwise `false`.
        ///
        /// The new information provided overrides old information competely.
        ///
        /// - NOTE:
        ///     Updating user information requires login first.
        ///
        /// - SeeAlso:
        ///     Use ``withUserToken(_:_:)-45z2w`` to attach a token.
        ///     Use ``login(_:)`` to get a token.
        public static func updateUserInformation(_ information: NewUserInformation) async -> Bool {
            let result = await requestJSON(
                "https://bestdori.com/api/user",
                method: .post,
                parameters: information,
                encoder: JSONParameterEncoder.default
            )
            if case .success(let respJSON) = result {
                return respJSON["result"].boolValue
            } else {
                return false
            }
        }
        
        /// Get the latest request status.
        ///
        /// Use this function to check the request status
        /// after sending a request by functions that start with `request`.
        ///
        /// - NOTE:
        ///     Getting a request status requires login first.
        ///
        /// - SeeAlso:
        ///     Use ``withUserToken(_:_:)-45z2w`` to attach a token.
        ///     Use ``login(_:)`` to get a token.
        public static func latestRequestStatus() async -> RequestStatus? {
            let request = await requestJSON("https://bestdori.com/api/sync")
            if case let .success(respJSON) = request {
                let task = Task.detached(priority: .userInitiated) { () async -> RequestStatus? in
                    if let status = respJSON["syncRequest"]["status"].string {
                        return .init(
                            status: .init(rawValue: status) ?? .notStarted,
                            uid: respJSON["syncRequest"]["params"]["uid"].intValue,
                            type: .init(rawValue: respJSON["syncRequest"]["params"]["type"].stringValue) ?? .link,
                            code: respJSON["syncRequest"]["params"]["code"].string,
                            server: .init(_rawIntValue: respJSON["syncRequest"]["params"]["server"].intValue) ?? .jp,
                            linkResult: respJSON["syncRequest"]["result"]["result"].bool
                        )
                    } else {
                        return nil
                    }
                }
                return await task.value
            }
            return nil
        }
        
        /// Request prepare to link to a game account.
        ///
        /// - Parameters:
        ///   - locale: The locale of game account.
        ///   - uid: The UID of game account.
        ///
        /// - Returns: `true` if the request is sent successfully, otherwise `false`.
        ///
        /// To link a game account to a Bestdori account,
        /// use this function to send a preparation request first.
        /// Then call ``latestRequestStatus()`` to get its status.
        /// You'll get a ``RequestStatus/Status/notStarted`` status
        /// in the result. Show the ``RequestStatus/code`` to users.
        ///
        /// The users need to set the `code` as their introductions manually
        /// in GBP. After they finishing this, call ``requestStartLinkGameAccount()``
        /// to let the Bestdori verify the identity and finish the link.
        ///
        /// A ``RequestStatus/linkResult`` will be reported when the status
        /// is ``RequestStatus/Status/completed``.
        /// It may take several seconds for Bestdori to complete the request.
        ///
        /// - NOTE:
        ///     Sending a request requires login first.
        ///
        /// - SeeAlso:
        ///     Use ``withUserToken(_:_:)-45z2w`` to attach a token.
        ///     Use ``login(_:)`` to get a token.
        public static func requestPrepareLinkGameAccount(
            locale: DoriAPI.Locale,
            uid: Int
        ) async -> Bool {
            let result = await requestJSON(
                "https://bestdori.com/api/sync",
                method: .post,
                parameters: _SyncParameterList(
                    type: "linkPrepare",
                    server: locale._rawIntValue,
                    uid: uid
                ),
                encoder: JSONParameterEncoder.default
            )
            if case .success(let respJSON) = result {
                return respJSON["result"].boolValue
            } else {
                return false
            }
        }
        
        /// Request start to link to a game account.
        ///
        /// - Returns: `true` if the request is sent successfully, otherwise `false`.
        ///
        /// - IMPORTANT:
        ///     The ``requestPrepareLinkGameAccount(locale:uid:)``
        ///     should be called before sending this request.
        ///     See its documentation to learn more about the linking workflow.
        ///
        /// A ``RequestStatus/linkResult`` will be reported when the status
        /// is ``RequestStatus/Status/completed``.
        /// It may take several seconds for Bestdori to complete the request.
        ///
        /// - NOTE:
        ///     Sending a request requires login first.
        ///
        /// - SeeAlso:
        ///     Use ``withUserToken(_:_:)-45z2w`` to attach a token.
        ///     Use ``login(_:)`` to get a token.
        public static func requestStartLinkGameAccount() async -> Bool {
            let result = await requestJSON(
                "https://bestdori.com/api/sync",
                method: .post,
                parameters: ["type": "linkStart"],
                encoder: JSONParameterEncoder.default
            )
            if case .success(let respJSON) = result {
                return respJSON["result"].boolValue
            } else {
                return false
            }
        }
        
        /// Get a list of game accounts.
        ///
        /// - NOTE:
        ///     Getting an account list requires login first.
        ///
        /// - SeeAlso:
        ///     Use ``withUserToken(_:_:)-45z2w`` to attach a token.
        ///     Use ``login(_:)`` to get a token.
        public static func gameAccountList() async -> [GameAccount]? {
            let request = await requestJSON("https://bestdori.com/api/sync/account")
            if case let .success(respJSON) = request {
                let task = Task.detached(priority: .userInitiated) { () async -> [GameAccount]? in
                    if respJSON["result"].bool == true {
                        return respJSON["accounts"].map {
                            .init(
                                server: .init(_rawIntValue: $0.1["server"].intValue) ?? .jp,
                                uid: $0.1["uid"].intValue
                            )
                        }
                    } else {
                        return nil
                    }
                }
                return await task.value
            }
            return nil
        }
        
        /// Get details of game account.
        ///
        /// - Parameter account: A game account from ``gameAccountList()``.
        ///
        /// - NOTE:
        ///     Getting account details requires login first.
        ///
        /// - SeeAlso:
        ///     This function is only used for getting game account details
        ///     for a linked account. To get information of game accounts
        ///     owned by anyone, use ``DoriAPI/Misc/playerProfile(of:in:)``.
        ///
        ///     Use ``withUserToken(_:_:)-45z2w`` to attach a token.
        ///     Use ``login(_:)`` to get a token.
        public static func gameAccountDetail(of account: GameAccount) async -> GameAccountDetail? {
            let request = await requestJSON("https://bestdori.com/api/sync/account?server=\(account.server._rawIntValue)")
            if case let .success(respJSON) = request {
                let task = Task.detached(priority: .userInitiated) { () async -> GameAccountDetail? in
                    if respJSON["result"].bool == true {
                        var publicInfoFlags: UInt8 = 0
                        if respJSON["account"]["uidFlag"].boolValue {
                            publicInfoFlags |= GameAccountDetail.PublicInfoFlag.uid.rawValue
                        }
                        if respJSON["account"]["rankFlag"].boolValue {
                            publicInfoFlags |= GameAccountDetail.PublicInfoFlag.rank.rawValue
                        }
                        if respJSON["account"]["clearCountFlag"].boolValue {
                            publicInfoFlags |= GameAccountDetail.PublicInfoFlag.clearCount.rawValue
                        }
                        if respJSON["account"]["fullComboCountFlag"].boolValue {
                            publicInfoFlags |= GameAccountDetail.PublicInfoFlag.fullComboCount.rawValue
                        }
                        if respJSON["account"]["allPerfectCountFlag"].boolValue {
                            publicInfoFlags |= GameAccountDetail.PublicInfoFlag.allPerfectCount.rawValue
                        }
                        if respJSON["account"]["hsrFlag"].boolValue {
                            publicInfoFlags |= GameAccountDetail.PublicInfoFlag.highScoreRating.rawValue
                        }
                        if respJSON["account"]["dtrFlag"].boolValue {
                            publicInfoFlags |= GameAccountDetail.PublicInfoFlag.detailedTrackRating.rawValue
                        }
                        if respJSON["account"]["titleFlag"].boolValue {
                            publicInfoFlags |= GameAccountDetail.PublicInfoFlag.titles.rawValue
                        }
                        
                        return .init(
                            server: .init(_rawIntValue: respJSON["account"]["server"].intValue) ?? .jp,
                            uid: respJSON["account"]["uid"].intValue,
                            rank: respJSON["account"]["rank"].intValue,
                            clearCount: respJSON["account"]["clearCount"].intValue,
                            fullComboCount: respJSON["account"]["fullComboCount"].intValue,
                            allPerfectCount: respJSON["account"]["allPerfectCount"].intValue,
                            highScoreRating: respJSON["account"]["hsr"].intValue,
                            titleIDs: respJSON["account"]["titles"].map { $0.1.intValue },
                            publicInfoFlags: .init(rawValue: publicInfoFlags)
                        )
                    } else {
                        return nil
                    }
                }
                return await task.value
            }
            return nil
        }
        
        internal static func _parseTokenHeader(_ value: String) -> Token? {
            let fields = value.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            let cookies = fields.compactMap {
                let components = $0.components(separatedBy: "=")
                if components.count >= 2 {
                    return (components[0], components[1])
                } else {
                    return nil
                }
            }.reduce(into: [String: String]()) { partialResult, pair in
                partialResult.updateValue(pair.1, forKey: pair.0)
            }
            if let token = cookies["token"],
               let _expiration = cookies["Expires"],
               let expirationDate = Date(httpDate: _expiration) {
                return .init(token, expirationDate: expirationDate)
            } else {
                return nil
            }
        }
    }
}

extension DoriAPI.User {
    public struct LoginCredential: Sendable, Hashable, Codable {
        public var username: String
        public var password: String
        
        public init(username: String, password: String) {
            self.username = username
            self.password = password
        }
    }
    
    public enum LoginError: String, Sendable, Error {
        case invalidUsername = "USERNAME_INVALID"
        case invalidPassword = "PASSWORD_INVALID"
        case invalidCredential = "CREDENTIALS_INVALID"
        case blocked = "BLOCKED"
        case badNetwork = "NETWORK"
        case unknown = "UNKNOWN"
        
        public var localizedDescription: String {
            NSLocalizedString("LOGIN_ERROR_\(self.rawValue)", bundle: #bundle, comment: "")
        }
    }
}

extension DoriAPI.User {
    public struct SignupForm: Sendable, Hashable, Codable {
        public var username: String
        public var password: String
        public var email: String
        
        public init(username: String, password: String, email: String) {
            self.username = username
            self.password = password
            self.email = email
        }
    }
    
    public enum SignupError: String, Sendable, Error {
        case invalidUsername = "USERNAME_INVALID"
        case invalidPassword = "PASSWORD_INVALID"
        case invalidEmail = "EMAIL_INVALID"
        case duplicateUsername = "USERNAME_TAKEN"
        case duplicateEmail = "EMAIL_TAKEN"
        case blocked = "BLOCKED"
        case badNetwork = "NETWORK"
        case unknown = "UNKNOWN"
        
        public var localizedDescription: String {
            NSLocalizedString("SIGNUP_ERROR_\(self.rawValue)", bundle: #bundle, comment: "")
        }
    }
}

extension DoriAPI.User {
    public struct Token: Sendable, Hashable {
        public let value: String
        
        public let expirationDate: Date
        
        public init(_ value: String, expirationDate: Date) {
            self.value = value
            self.expirationDate = expirationDate
        }
        
        @inlinable
        public var isExpired: Bool {
            expirationDate < .now
        }
    }
}

extension DoriAPI.User {
    public struct Title: Sendable, Identifiable, Hashable, DoriCache.Cacheable {
        public var id: Int
        public var type: TitleType
        public var server: DoriAPI.Locale
        
        public init(id: Int, type: TitleType, server: DoriAPI.Locale) {
            self.id = id
            self.type = type
            self.server = server
        }
        @inlinable
        public init(_ degree: DoriAPI.Degrees.Degree, server: DoriAPI.Locale) {
            self.init(id: degree.id, type: .bandori, server: server)
        }
        
        public enum TitleType: String, Sendable, Hashable, DoriCache.Cacheable {
            case bandori
        }
    }
    
    public struct MyInformation: Sendable, Hashable, DoriCache.Cacheable {
        public var username: String
        public var nickname: String
        public var titles: [Title]
        public var email: String
        public var messageCount: Int
    }
    
    public struct UserInformation: Sendable, Hashable, DoriCache.Cacheable {
        public var followingCount: Int
        public var followedByCount: Int
        public var isFollowed: Bool
        public var nickname: String
        public var titles: [Title]
        public var posterCard: PosterCard?
        public var selfIntroduction: String
        public var accounts: [GameAccount]
        public var socialMedia: String
        public var favoriteCharacterIDs: [Int]
        public var favoriteCardIDs: [Int]
        public var favoriteBandIDs: [Int]
        public var favoriteSongIDs: [Int]
        public var favoriteCostumeIDs: [Int]
        
        public struct PosterCard: Sendable, Hashable, DoriCache.Cacheable {
            public var id: Int
            public var offset: Double
            public var isTrained: Bool
        }
    }
    
    public struct NewUserInformation: Sendable, Hashable, Encodable {
        public var nickname: String
        public var titles: [Title]
        public var posterCard: PosterCard?
        public var selfIntroduction: String
        public var accounts: [GameAccount]
        public var socialMedia: String
        public var favoriteCharacterIDs: [Int]
        public var favoriteCardIDs: [Int]
        public var favoriteBandIDs: [Int]
        public var favoriteSongIDs: [Int]
        public var favoriteCostumeIDs: [Int]
        
        public init(
            nickname: String,
            titles: [Title],
            posterCard: PosterCard? = nil,
            selfIntroduction: String,
            accounts: [GameAccount],
            socialMedia: String,
            favoriteCharacterIDs: [Int],
            favoriteCardIDs: [Int],
            favoriteBandIDs: [Int],
            favoriteSongIDs: [Int],
            favoriteCostumeIDs: [Int]
        ) {
            self.nickname = nickname
            self.titles = titles
            self.posterCard = posterCard
            self.selfIntroduction = selfIntroduction
            self.accounts = accounts
            self.socialMedia = socialMedia
            self.favoriteCharacterIDs = favoriteCharacterIDs
            self.favoriteCardIDs = favoriteCardIDs
            self.favoriteBandIDs = favoriteBandIDs
            self.favoriteSongIDs = favoriteSongIDs
            self.favoriteCostumeIDs = favoriteCostumeIDs
        }
        @inlinable
        public init(_ information: UserInformation) {
            self.init(
                nickname: information.nickname,
                titles: information.titles,
                posterCard: information.posterCard != nil ? .init(information.posterCard!) : nil,
                selfIntroduction: information.selfIntroduction,
                accounts: information.accounts,
                socialMedia: information.socialMedia,
                favoriteCharacterIDs: information.favoriteCharacterIDs,
                favoriteCardIDs: information.favoriteCardIDs,
                favoriteBandIDs: information.favoriteBandIDs,
                favoriteSongIDs: information.favoriteSongIDs,
                favoriteCostumeIDs: information.favoriteCostumeIDs
            )
        }
        
        internal enum CodingKeys: CodingKey {
            case nickname
            case titles
            case posterCard
            case selfIntro
            case serverIds
            case socialMedia
            case favCharacters
            case favCards
            case favBands
            case favSongs
            case favCostumes
        }
        public func encode(to encoder: any Encoder) throws {
            struct EncodingTitle: Encodable {
                var id: Int
                var type: Title.TitleType
                var server: DoriAPI.Locale
                
                init(_ title: Title) {
                    self.id = title.id
                    self.type = title.type
                    self.server = title.server
                }
                
                enum CodingKeys: CodingKey {
                    case id
                    case type
                    case server
                }
                func encode(to encoder: any Encoder) throws {
                    var container = encoder.container(keyedBy: CodingKeys.self)
                    try container.encode(id, forKey: .id)
                    try container.encode(type.rawValue, forKey: .type)
                    try container.encode(server._rawIntValue, forKey: .server)
                }
            }
            struct EncodingServerID: Encodable {
                var server: DoriAPI.Locale
                var uid: Int
                
                init(_ account: GameAccount) {
                    self.server = account.server
                    self.uid = account.uid
                }
                
                enum CodingKeys: CodingKey {
                    case id
                    case server
                }
                func encode(to encoder: any Encoder) throws {
                    var container = encoder.container(keyedBy: CodingKeys.self)
                    try container.encode(uid, forKey: .id)
                    try container.encode(server, forKey: .server)
                }
            }
            
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(nickname, forKey: .nickname)
            try container.encode(titles.map { EncodingTitle($0) }, forKey: .titles)
            try container.encode(posterCard, forKey: .posterCard)
            try container.encode(selfIntroduction, forKey: .selfIntro)
            try container.encode(accounts.map { EncodingServerID($0) }, forKey: .serverIds)
            try container.encode(socialMedia, forKey: .socialMedia)
            try container.encode(favoriteCharacterIDs, forKey: .favCharacters)
            try container.encode(favoriteCardIDs, forKey: .favCards)
            try container.encode(favoriteBandIDs, forKey: .favBands)
            try container.encode(favoriteSongIDs, forKey: .favSongs)
            try container.encode(favoriteCostumeIDs, forKey: .favCostumes)
        }
        
        public struct PosterCard: Sendable, Hashable, Encodable {
            public var id: Int
            public var offset: Double
            public var isTrained: Bool
            
            public init(id: Int, offset: Double, isTrained: Bool) {
                self.id = id
                self.offset = offset
                self.isTrained = isTrained
            }
            @inlinable
            public init(_ posterCard: UserInformation.PosterCard) {
                self.init(
                    id: posterCard.id,
                    offset: posterCard.offset,
                    isTrained: posterCard.isTrained
                )
            }
            @inlinable
            public init(_ card: DoriAPI.Cards.PreviewCard, offset: Double, isTrained: Bool) {
                self.init(id: card.id, offset: offset, isTrained: isTrained)
            }
            @inlinable
            public init(_ card: DoriAPI.Cards.Card, offset: Double, isTrained: Bool) {
                self.init(id: card.id, offset: offset, isTrained: isTrained)
            }
            
            internal enum CodingKeys: CodingKey {
                case id
                case offset
                case trainedArt
            }
            public func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(id, forKey: .id)
                try container.encode(offset, forKey: .offset)
                try container.encode(isTrained, forKey: .trainedArt)
            }
        }
    }
}

extension DoriAPI.User {
    public struct RequestStatus: Sendable, Hashable, DoriCache.Cacheable {
        public var status: Status
        public var uid: Int
        public var type: RequestType
        public var code: String?
        public var server: DoriAPI.Locale // Int(JSON) -> ~(Swift)
        public var linkResult: Bool?
        
        internal init(
            status: Status,
            uid: Int,
            type: RequestType,
            code: String?,
            server: DoriAPI.Locale,
            linkResult: Bool?
        ) {
            self.status = status
            self.uid = uid
            self.type = type
            self.code = code
            self.server = server
            self.linkResult = linkResult
        }
        
        public enum Status: String, Sendable, Hashable, DoriCache.Cacheable {
            case notStarted = "NOT_STARTED"
            case inQueue = "IN_QUEUE"
            case completed = "COMPLETED"
        }
        public enum RequestType: String, Sendable, Hashable, DoriCache.Cacheable {
            case link
            case update
        }
    }
    
    internal struct _SyncParameterList: Sendable, Encodable {
        var type: String
        var server: Int
        var uid: Int
    }
}

extension DoriAPI.User {
    public struct GameAccount: Sendable, Hashable, DoriCache.Cacheable {
        public var server: DoriAPI.Locale
        public var uid: Int
        
        public init(server: DoriAPI.Locale, uid: Int) {
            self.server = server
            self.uid = uid
        }
    }
    
    public struct GameAccountDetail: Sendable, Hashable, DoriCache.Cacheable {
        public var server: DoriAPI.Locale
        public var uid: Int
        public var rank: Int
        public var clearCount: Int
        public var fullComboCount: Int
        public var allPerfectCount: Int
        public var highScoreRating: Int
        public var titleIDs: [Int]
        public var publicInfoFlags: PublicInfoFlag
        
        public struct PublicInfoFlag: Sendable, OptionSet, Hashable, DoriCache.Cacheable {
            public var rawValue: UInt8
            
            public init(rawValue: UInt8) {
                self.rawValue = rawValue
            }
            
            public static let uid                 = PublicInfoFlag(rawValue: 1 << 0)
            public static let rank                = PublicInfoFlag(rawValue: 1 << 1)
            public static let clearCount          = PublicInfoFlag(rawValue: 1 << 2)
            public static let fullComboCount      = PublicInfoFlag(rawValue: 1 << 3)
            public static let allPerfectCount     = PublicInfoFlag(rawValue: 1 << 4)
            public static let highScoreRating     = PublicInfoFlag(rawValue: 1 << 5)
            public static let detailedTrackRating = PublicInfoFlag(rawValue: 1 << 6)
            public static let titles              = PublicInfoFlag(rawValue: 1 << 7)
        }
    }
}
