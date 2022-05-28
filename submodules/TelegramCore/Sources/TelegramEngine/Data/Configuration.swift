import SwiftSignalKit
import Postbox

public enum EngineConfiguration {
    public struct Limits: Equatable {
        public static let timeIntervalForever: Int32 = 0x7fffffff
        
        public var maxPinnedChatCount: Int32
        public var maxArchivedPinnedChatCount: Int32
        public var maxGroupMemberCount: Int32
        public var maxSupergroupMemberCount: Int32
        public var maxMessageForwardBatchSize: Int32
        public var maxSavedGifCount: Int32
        public var maxRecentStickerCount: Int32
        public var maxMessageEditingInterval: Int32
        public var maxMediaCaptionLength: Int32
        public var canRemoveIncomingMessagesInPrivateChats: Bool
        public var maxMessageRevokeInterval: Int32
        public var maxMessageRevokeIntervalInPrivateChats: Int32

        public init(
            maxPinnedChatCount: Int32,
            maxArchivedPinnedChatCount: Int32,
            maxGroupMemberCount: Int32,
            maxSupergroupMemberCount: Int32,
            maxMessageForwardBatchSize: Int32,
            maxSavedGifCount: Int32,
            maxRecentStickerCount: Int32,
            maxMessageEditingInterval: Int32,
            maxMediaCaptionLength: Int32,
            canRemoveIncomingMessagesInPrivateChats: Bool,
            maxMessageRevokeInterval: Int32,
            maxMessageRevokeIntervalInPrivateChats: Int32
        ) {
            self.maxPinnedChatCount = maxPinnedChatCount
            self.maxArchivedPinnedChatCount = maxArchivedPinnedChatCount
            self.maxGroupMemberCount = maxGroupMemberCount
            self.maxSupergroupMemberCount = maxSupergroupMemberCount
            self.maxMessageForwardBatchSize = maxMessageForwardBatchSize
            self.maxSavedGifCount = maxSavedGifCount
            self.maxRecentStickerCount = maxRecentStickerCount
            self.maxMessageEditingInterval = maxMessageEditingInterval
            self.maxMediaCaptionLength = maxMediaCaptionLength
            self.canRemoveIncomingMessagesInPrivateChats = canRemoveIncomingMessagesInPrivateChats
            self.maxMessageRevokeInterval = maxMessageRevokeInterval
            self.maxMessageRevokeIntervalInPrivateChats = maxMessageRevokeIntervalInPrivateChats
        }
    }
    
    public struct UserLimits: Equatable {
        public let maxPinnedChatCount: Int32
        public let maxChannelsCount: Int32
        public let maxPublicLinksCount: Int32
        public let maxSavedGifCount: Int32
        public let maxFavedStickerCount: Int32
        public let maxFoldersCount: Int32
        public let maxFolderChatsCount: Int32
        public let maxCaptionLength: Int32
        public let maxUploadFileParts: Int32
        public let maxAboutLength: Int32
        public let maxAnimatedEmojisInText: Int32
        
        public static var defaultValue: UserLimits {
            return UserLimits(UserLimitsConfiguration.defaultValue)
        }

        public init(
            maxPinnedChatCount: Int32,
            maxChannelsCount: Int32,
            maxPublicLinksCount: Int32,
            maxSavedGifCount: Int32,
            maxFavedStickerCount: Int32,
            maxFoldersCount: Int32,
            maxFolderChatsCount: Int32,
            maxCaptionLength: Int32,
            maxUploadFileParts: Int32,
            maxAboutLength: Int32,
            maxAnimatedEmojisInText: Int32
        ) {
            self.maxPinnedChatCount = maxPinnedChatCount
            self.maxChannelsCount = maxChannelsCount
            self.maxPublicLinksCount = maxPublicLinksCount
            self.maxSavedGifCount = maxSavedGifCount
            self.maxFavedStickerCount = maxFavedStickerCount
            self.maxFoldersCount = maxFoldersCount
            self.maxFolderChatsCount = maxFolderChatsCount
            self.maxCaptionLength = maxCaptionLength
            self.maxUploadFileParts = maxUploadFileParts
            self.maxAboutLength = maxAboutLength
            self.maxAnimatedEmojisInText = maxAnimatedEmojisInText
        }
    }
}

extension EngineConfiguration.Limits {
    init(_ limitsConfiguration: LimitsConfiguration) {
        self.init(
            maxPinnedChatCount: limitsConfiguration.maxPinnedChatCount,
            maxArchivedPinnedChatCount: limitsConfiguration.maxArchivedPinnedChatCount,
            maxGroupMemberCount: limitsConfiguration.maxGroupMemberCount,
            maxSupergroupMemberCount: limitsConfiguration.maxSupergroupMemberCount,
            maxMessageForwardBatchSize: limitsConfiguration.maxMessageForwardBatchSize,
            maxSavedGifCount: limitsConfiguration.maxSavedGifCount,
            maxRecentStickerCount: limitsConfiguration.maxRecentStickerCount,
            maxMessageEditingInterval: limitsConfiguration.maxMessageEditingInterval,
            maxMediaCaptionLength: limitsConfiguration.maxMediaCaptionLength,
            canRemoveIncomingMessagesInPrivateChats: limitsConfiguration.canRemoveIncomingMessagesInPrivateChats,
            maxMessageRevokeInterval: limitsConfiguration.maxMessageRevokeInterval,
            maxMessageRevokeIntervalInPrivateChats: limitsConfiguration.maxMessageRevokeIntervalInPrivateChats
        )
    }
}

public extension EngineConfiguration.UserLimits {
    init(_ userLimitsConfiguration: UserLimitsConfiguration) {
        self.init(
            maxPinnedChatCount: userLimitsConfiguration.maxPinnedChatCount,
            maxChannelsCount: userLimitsConfiguration.maxChannelsCount,
            maxPublicLinksCount: userLimitsConfiguration.maxPublicLinksCount,
            maxSavedGifCount: userLimitsConfiguration.maxSavedGifCount,
            maxFavedStickerCount: userLimitsConfiguration.maxFavedStickerCount,
            maxFoldersCount: userLimitsConfiguration.maxFoldersCount,
            maxFolderChatsCount: userLimitsConfiguration.maxFolderChatsCount,
            maxCaptionLength: userLimitsConfiguration.maxCaptionLength,
            maxUploadFileParts: userLimitsConfiguration.maxUploadFileParts,
            maxAboutLength: userLimitsConfiguration.maxAboutLength,
            maxAnimatedEmojisInText: userLimitsConfiguration.maxAnimatedEmojisInText
        )
    }
}

public extension EngineConfiguration {
    struct SearchBots {
        public var imageBotUsername: String?
        public var gifBotUsername: String?
        public var venueBotUsername: String?
        
        public init(
            imageBotUsername: String?,
            gifBotUsername: String?,
            venueBotUsername: String?
        ) {
            self.imageBotUsername = imageBotUsername
            self.gifBotUsername = gifBotUsername
            self.venueBotUsername = venueBotUsername
        }
    }
}

public extension EngineConfiguration.SearchBots {
    init(_ configuration: SearchBotsConfiguration) {
        self.init(
            imageBotUsername: configuration.imageBotUsername,
            gifBotUsername: configuration.gifBotUsername,
            venueBotUsername: configuration.venueBotUsername
        )
    }
}

public extension TelegramEngine.EngineData.Item {
    enum Configuration {
        public struct Limits: TelegramEngineDataItem, PostboxViewDataItem {
            public typealias Result = EngineConfiguration.Limits

            public init() {
            }

            var key: PostboxViewKey {
                return .preferences(keys: Set([PreferencesKeys.limitsConfiguration]))
            }

            func extract(view: PostboxView) -> Result {
                guard let view = view as? PreferencesView else {
                    preconditionFailure()
                }
                guard let limitsConfiguration = view.values[PreferencesKeys.limitsConfiguration]?.get(LimitsConfiguration.self) else {
                    return EngineConfiguration.Limits(LimitsConfiguration.defaultValue)
                }
                return EngineConfiguration.Limits(limitsConfiguration)
            }
        }
        
        public struct UserLimits: TelegramEngineDataItem, PostboxViewDataItem {
            public typealias Result = EngineConfiguration.UserLimits
            
            fileprivate let isPremium: Bool
            public init(isPremium: Bool) {
                self.isPremium = isPremium
            }
            
            var key: PostboxViewKey {
                return .preferences(keys: Set([PreferencesKeys.appConfiguration]))
            }
            
            func extract(view: PostboxView) -> Result {
                guard let view = view as? PreferencesView else {
                    preconditionFailure()
                }
                guard let appConfiguration = view.values[PreferencesKeys.appConfiguration]?.get(AppConfiguration.self) else {
                    return EngineConfiguration.UserLimits(UserLimitsConfiguration.defaultValue)
                }
                return EngineConfiguration.UserLimits(UserLimitsConfiguration(appConfiguration: appConfiguration, isPremium: self.isPremium))
            }
        }
        
        public struct SuggestedLocalization: TelegramEngineDataItem, PostboxViewDataItem {
            public typealias Result = SuggestedLocalizationEntry?
            
            public init() {
            }
            
            var key: PostboxViewKey {
                return .preferences(keys: Set([PreferencesKeys.suggestedLocalization]))
            }
            
            func extract(view: PostboxView) -> Result {
                guard let view = view as? PreferencesView else {
                    preconditionFailure()
                }
                guard let suggestedLocalization = view.values[PreferencesKeys.suggestedLocalization]?.get(SuggestedLocalizationEntry.self) else {
                    return nil
                }
                return suggestedLocalization
            }
        }

        public struct SearchBots: TelegramEngineDataItem, PostboxViewDataItem {
            public typealias Result = EngineConfiguration.SearchBots
            
            public init() {
            }
            
            var key: PostboxViewKey {
                return .preferences(keys: Set([PreferencesKeys.searchBotsConfiguration]))
            }
            
            func extract(view: PostboxView) -> Result {
                guard let view = view as? PreferencesView else {
                    preconditionFailure()
                }
                guard let value = view.values[PreferencesKeys.searchBotsConfiguration]?.get(SearchBotsConfiguration.self) else {
                    return EngineConfiguration.SearchBots(SearchBotsConfiguration.defaultValue)
                }
                return EngineConfiguration.SearchBots(value)
            }
        }
    }
}
