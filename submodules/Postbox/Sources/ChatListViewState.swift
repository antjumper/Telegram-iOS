
enum ChatListViewSpacePinned {
    case notPinned
    case includePinned
    case includePinnedAsUnpinned
    
    var include: Bool {
        switch self {
        case .notPinned:
            return false
        case .includePinned, .includePinnedAsUnpinned:
            return true
        }
    }
}

enum ChatListViewSpace: Hashable {
    case group(groupId: PeerGroupId, pinned: ChatListViewSpacePinned)
}

private func mappedChatListFilterPredicate(postbox: Postbox, groupId: PeerGroupId, predicate: ChatListFilterPredicate) -> (ChatListIntermediateEntry) -> Bool {
    return { entry in
        switch entry {
        case let .message(index, _):
            if let peer = postbox.peerTable.get(index.messageIndex.id.peerId) {
                let isUnread = postbox.readStateTable.getCombinedState(index.messageIndex.id.peerId)?.isUnread ?? false
                let notificationsPeerId = peer.notificationSettingsPeerId ?? peer.id
                let isContact = postbox.contactsTable.isContact(peerId: notificationsPeerId)
                if predicate.includes(peer: peer, groupId: groupId, notificationSettings: postbox.peerNotificationSettingsTable.getEffective(notificationsPeerId), isUnread: isUnread, isContact: isContact) {
                    return true
                } else {
                    return false
                }
            } else {
                return false
            }
        case .hole:
            return true
        }
    }
}

private func updateMessagePeers(_ message: Message, updatedPeers: [PeerId: Peer]) -> Message? {
    var updated = false
    for (peerId, currentPeer) in message.peers {
        if let updatedPeer = updatedPeers[peerId], !arePeersEqual(currentPeer, updatedPeer) {
            updated = true
            break
        }
    }
    if updated {
        var peers = SimpleDictionary<PeerId, Peer>()
        for (peerId, currentPeer) in message.peers {
            if let updatedPeer = updatedPeers[peerId] {
                peers[peerId] = updatedPeer
            } else {
                peers[peerId] = currentPeer
            }
        }
        return Message(stableId: message.stableId, stableVersion: message.stableVersion, id: message.id, globallyUniqueId: message.globallyUniqueId, groupingKey: message.groupingKey, groupInfo: message.groupInfo, timestamp: message.timestamp, flags: message.flags, tags: message.tags, globalTags: message.globalTags, localTags: message.localTags, forwardInfo: message.forwardInfo, author: message.author, text: message.text, attributes: message.attributes, media: message.media, peers: peers, associatedMessages: message.associatedMessages, associatedMessageIds: message.associatedMessageIds)
    }
    return nil
}

private func updatedRenderedPeer(_ renderedPeer: RenderedPeer, updatedPeers: [PeerId: Peer]) -> RenderedPeer? {
    var updated = false
    for (peerId, currentPeer) in renderedPeer.peers {
        if let updatedPeer = updatedPeers[peerId], !arePeersEqual(currentPeer, updatedPeer) {
            updated = true
            break
        }
    }
    if updated {
        var peers = SimpleDictionary<PeerId, Peer>()
        for (peerId, currentPeer) in renderedPeer.peers {
            if let updatedPeer = updatedPeers[peerId] {
                peers[peerId] = updatedPeer
            } else {
                peers[peerId] = currentPeer
            }
        }
        return RenderedPeer(peerId: renderedPeer.peerId, peers: peers)
    }
    return nil
}

private final class ChatListViewSpaceState {
    private let space: ChatListViewSpace
    private let anchorIndex: MutableChatListEntryIndex
    private let filterPredicate: ChatListFilterPredicate?
    private let summaryComponents: ChatListEntrySummaryComponents
    private let halfLimit: Int
    
    var orderedEntries: OrderedChatListViewEntries
    
    init(postbox: Postbox, space: ChatListViewSpace, anchorIndex: MutableChatListEntryIndex, filterPredicate: ChatListFilterPredicate?, summaryComponents: ChatListEntrySummaryComponents, halfLimit: Int) {
        self.space = space
        self.anchorIndex = anchorIndex
        self.filterPredicate = filterPredicate
        self.summaryComponents = summaryComponents
        self.halfLimit = halfLimit
        self.orderedEntries = OrderedChatListViewEntries(lowerOrAtAnchor: [], higherThanAnchor: [])
        self.fillSpace(postbox: postbox)
    }
    
    private func fillSpace(postbox: Postbox) {
        switch self.space {
        case let .group(groupId, pinned):
            let lowerBound: MutableChatListEntryIndex
            let upperBound: MutableChatListEntryIndex
            if pinned.include {
                upperBound = .absoluteUpperBound
                lowerBound = MutableChatListEntryIndex(index: ChatListIndex.pinnedLowerBound, isMessage: true)
            } else {
                upperBound = MutableChatListEntryIndex(index: ChatListIndex.pinnedLowerBound.predecessor, isMessage: true)
                lowerBound = .absoluteLowerBound
            }
            let resolvedAnchorIndex = min(upperBound, max(self.anchorIndex, lowerBound))
            
            var lowerOrAtAnchorMessages: [MutableChatListEntry] = self.orderedEntries.lowerOrAtAnchor.reversed()
            var higherThanAnchorMessages: [MutableChatListEntry] = self.orderedEntries.higherThanAnchor
            
            func mapEntry(_ entry: ChatListIntermediateEntry) -> MutableChatListEntry {
                switch entry {
                case let .message(index, messageIndex):
                    var updatedIndex = index
                    if case .includePinnedAsUnpinned = pinned {
                        updatedIndex = ChatListIndex(pinningIndex: nil, messageIndex: index.messageIndex)
                    }
                    return .IntermediateMessageEntry(index: updatedIndex, messageIndex: messageIndex)
                case let .hole(hole):
                    return .HoleEntry(hole)
                }
            }
            
            if case .includePinnedAsUnpinned = pinned {
                if lowerOrAtAnchorMessages.count < self.halfLimit || higherThanAnchorMessages.count < self.halfLimit {
                    let loadedMessages = postbox.chatListTable.entries(groupId: groupId, from: (ChatListIndex.pinnedLowerBound, true), to: (ChatListIndex.absoluteUpperBound, true), peerChatInterfaceStateTable: postbox.peerChatInterfaceStateTable, count: self.halfLimit * 2, predicate: self.filterPredicate.flatMap { mappedChatListFilterPredicate(postbox: postbox, groupId: groupId, predicate: $0) }).map(mapEntry).sorted(by: { $0.entryIndex < $1.entryIndex })
                    
                    if lowerOrAtAnchorMessages.count < self.halfLimit {
                        var nextLowerIndex: MutableChatListEntryIndex
                        if let lastMessage = lowerOrAtAnchorMessages.min(by: { $0.entryIndex < $1.entryIndex }) {
                            nextLowerIndex = lastMessage.entryIndex.predecessor
                        } else {
                            nextLowerIndex = resolvedAnchorIndex
                        }
                        var loadedLowerMessages = Array(loadedMessages.filter({ $0.entryIndex <= nextLowerIndex }).reversed())
                        let lowerLimit = self.halfLimit - lowerOrAtAnchorMessages.count
                        if loadedLowerMessages.count > lowerLimit {
                            loadedLowerMessages.removeLast(loadedLowerMessages.count - lowerLimit)
                        }
                        lowerOrAtAnchorMessages.append(contentsOf: loadedLowerMessages)
                    }
                    if higherThanAnchorMessages.count < self.halfLimit {
                        var nextHigherIndex: MutableChatListEntryIndex
                        if let lastMessage = higherThanAnchorMessages.max(by: { $0.entryIndex < $1.entryIndex }) {
                            nextHigherIndex = lastMessage.entryIndex.successor
                        } else {
                            nextHigherIndex = resolvedAnchorIndex
                        }
                        var loadedHigherMessages = loadedMessages.filter({ $0.entryIndex >= nextHigherIndex })
                        let higherLimit = self.halfLimit - higherThanAnchorMessages.count
                        if loadedHigherMessages.count > higherLimit {
                            loadedHigherMessages.removeLast(loadedHigherMessages.count - higherLimit)
                        }
                        higherThanAnchorMessages.append(contentsOf: loadedHigherMessages)
                    }
                }
            } else {
                if lowerOrAtAnchorMessages.count < self.halfLimit {
                    var nextLowerIndex: MutableChatListEntryIndex
                    if let lastMessage = lowerOrAtAnchorMessages.min(by: { $0.entryIndex < $1.entryIndex }) {
                        nextLowerIndex = lastMessage.entryIndex.predecessor
                    } else {
                        nextLowerIndex = resolvedAnchorIndex
                    }
                    let loadedLowerMessages = postbox.chatListTable.entries(groupId: groupId, from: (nextLowerIndex.index, nextLowerIndex.isMessage), to: (lowerBound.index, lowerBound.isMessage), peerChatInterfaceStateTable: postbox.peerChatInterfaceStateTable, count: self.halfLimit - lowerOrAtAnchorMessages.count, predicate: self.filterPredicate.flatMap { mappedChatListFilterPredicate(postbox: postbox, groupId: groupId, predicate: $0) }).map(mapEntry)
                    lowerOrAtAnchorMessages.append(contentsOf: loadedLowerMessages)
                }
                if higherThanAnchorMessages.count < self.halfLimit {
                    var nextHigherIndex: MutableChatListEntryIndex
                    if let lastMessage = higherThanAnchorMessages.max(by: { $0.entryIndex < $1.entryIndex }) {
                        nextHigherIndex = lastMessage.entryIndex.successor
                    } else {
                        nextHigherIndex = resolvedAnchorIndex
                    }
                    let loadedHigherMessages = postbox.chatListTable.entries(groupId: groupId, from: (nextHigherIndex.index, nextHigherIndex.isMessage), to: (upperBound.index, upperBound.isMessage), peerChatInterfaceStateTable: postbox.peerChatInterfaceStateTable, count: self.halfLimit - higherThanAnchorMessages.count, predicate: self.filterPredicate.flatMap { mappedChatListFilterPredicate(postbox: postbox, groupId: groupId, predicate: $0) }).map(mapEntry)
                    higherThanAnchorMessages.append(contentsOf: loadedHigherMessages)
                }
            }
            
            lowerOrAtAnchorMessages.reverse()
            
            assert(lowerOrAtAnchorMessages.count <= self.halfLimit)
            assert(higherThanAnchorMessages.count <= self.halfLimit)
            
            let allIndices = (lowerOrAtAnchorMessages + higherThanAnchorMessages).map { $0.entryIndex }
            assert(Set(allIndices).count == allIndices.count)
            assert(allIndices.sorted() == allIndices)
            
            let entries = OrderedChatListViewEntries(lowerOrAtAnchor: lowerOrAtAnchorMessages, higherThanAnchor: higherThanAnchorMessages)
            self.orderedEntries = entries
        }
    }
    
    func replay(postbox: Postbox, transaction: PostboxTransaction) -> Bool {
        var hasUpdates = false
        var hadRemovals = false
        for (groupId, operations) in transaction.chatListOperations {
            let matchesSpace: Bool
            switch self.space {
            case .group(groupId, _):
                matchesSpace = true
            default:
                matchesSpace = false
            }
            if !matchesSpace {
                continue
            }
            
            inner: for operation in operations {
                switch operation {
                case let .InsertEntry(index, messageIndex):
                    switch self.space {
                    case let .group(_, pinned) where (index.pinningIndex != nil) == pinned.include:
                        var updatedIndex = index
                        if case .includePinnedAsUnpinned = pinned {
                            updatedIndex = ChatListIndex(pinningIndex: nil, messageIndex: index.messageIndex)
                        }
                        if let filterPredicate = self.filterPredicate {
                            if let peer = postbox.peerTable.get(updatedIndex.messageIndex.id.peerId) {
                                let notificationsPeerId = peer.notificationSettingsPeerId ?? peer.id
                                if !filterPredicate.includes(peer: peer, groupId: groupId, notificationSettings: postbox.peerNotificationSettingsTable.getEffective(notificationsPeerId), isUnread: postbox.readStateTable.getCombinedState(peer.id)?.isUnread ?? false, isContact: postbox.contactsTable.isContact(peerId: notificationsPeerId)) {
                                    continue inner
                                }
                            } else {
                                continue inner
                            }
                        }
                        if self.add(entry: .IntermediateMessageEntry(index: updatedIndex, messageIndex: messageIndex)) {
                            hasUpdates = true
                        }
                    default:
                        break
                    }
                case let .InsertHole(hole):
                    switch self.space {
                    case let .group(_, pinned) where !pinned.include:
                        if self.add(entry: .HoleEntry(hole)) {
                            hasUpdates = true
                        }
                    default:
                        break
                    }
                case let .RemoveEntry(indices):
                    for index in indices {
                        var updatedIndex = index
                        if case .group(_, .includePinnedAsUnpinned) = self.space {
                            updatedIndex = ChatListIndex(pinningIndex: nil, messageIndex: index.messageIndex)
                        }
                        
                        if self.orderedEntries.remove(index: MutableChatListEntryIndex(index: updatedIndex, isMessage: true)) {
                            hasUpdates = true
                            hadRemovals = true
                        }
                    }
                case let .RemoveHoles(indices):
                    for index in indices {
                        if self.orderedEntries.remove(index: MutableChatListEntryIndex(index: index, isMessage: false)) {
                            hasUpdates = true
                            hadRemovals = true
                        }
                    }
                }
            }
        }
        
        if !transaction.currentUpdatedPeerNotificationSettings.isEmpty, let filterPredicate = self.filterPredicate, case let .group(groupId, _) = self.space {
            var removeEntryIndices: [MutableChatListEntryIndex] = []
            let _ = self.orderedEntries.mutableScan { entry in
                let entryPeer: Peer
                let entryNotificationsPeerId: PeerId
                switch entry {
                case let .MessageEntry(messageEntry):
                    if let peer = messageEntry.renderedPeer.peer {
                        entryPeer = peer
                        entryNotificationsPeerId = peer.notificationSettingsPeerId ?? peer.id
                    } else {
                        return nil
                    }
                case let .IntermediateMessageEntry(intermediateMessageEntry):
                    if let peer = postbox.peerTable.get(intermediateMessageEntry.index.messageIndex.id.peerId) {
                        entryPeer = peer
                        entryNotificationsPeerId = peer.notificationSettingsPeerId ?? peer.id
                    } else {
                        return nil
                    }
                case .HoleEntry:
                    return nil
                }
                if let settingsChange = transaction.currentUpdatedPeerNotificationSettings[entryNotificationsPeerId] {
                    let isUnread = postbox.readStateTable.getCombinedState(entryPeer.id)?.isUnread ?? false
                    let wasIncluded = filterPredicate.includes(peer: entryPeer, groupId: groupId, notificationSettings: settingsChange.0, isUnread: isUnread, isContact: postbox.contactsTable.isContact(peerId: entryNotificationsPeerId))
                    let isIncluded = filterPredicate.includes(peer: entryPeer, groupId: groupId, notificationSettings: settingsChange.1, isUnread: isUnread, isContact: postbox.contactsTable.isContact(peerId: entryNotificationsPeerId))
                    if wasIncluded != isIncluded {
                        if !isIncluded {
                            removeEntryIndices.append(entry.entryIndex)
                        }
                    }
                }
                return nil
            }
            if !removeEntryIndices.isEmpty {
                hasUpdates = true
                hadRemovals = true
                for index in removeEntryIndices {
                    let _ = self.orderedEntries.remove(index: index)
                }
            }
            for (peerId, settingsChange) in transaction.currentUpdatedPeerNotificationSettings {
                if let mainPeer = postbox.peerTable.get(peerId) {
                    var peers: [Peer] = [mainPeer]
                    for associatedId in postbox.reverseAssociatedPeerTable.get(peerId: mainPeer.id) {
                        if let associatedPeer = postbox.peerTable.get(associatedId) {
                            peers.append(associatedPeer)
                        }
                    }
                    assert(Set(peers.map { $0.id }).count == peers.count)
                    
                    let isUnread = postbox.readStateTable.getCombinedState(peerId)?.isUnread ?? false
                    let wasIncluded = filterPredicate.includes(peer: mainPeer, groupId: groupId, notificationSettings: settingsChange.0, isUnread: isUnread, isContact: postbox.contactsTable.isContact(peerId: peerId))
                    let isIncluded = filterPredicate.includes(peer: mainPeer, groupId: groupId, notificationSettings: settingsChange.1, isUnread: isUnread, isContact: postbox.contactsTable.isContact(peerId: peerId))
                    if wasIncluded != isIncluded {
                        if isIncluded {
                            for peer in peers {
                                let tableEntry: ChatListIntermediateEntry?
                                tableEntry = postbox.chatListTable.getEntry(peerId: peer.id, messageHistoryTable: postbox.messageHistoryTable, peerChatInterfaceStateTable: postbox.peerChatInterfaceStateTable)
                                if let entry = tableEntry {
                                    switch entry {
                                    case let .message(index, messageIndex):
                                        if self.add(entry: .IntermediateMessageEntry(index: index, messageIndex: messageIndex)) {
                                            hasUpdates = true
                                        }
                                    default:
                                        break
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        if !transaction.currentUpdatedPeerNotificationSettings.isEmpty {
            if self.orderedEntries.mutableScan({ entry in
                switch entry {
                case let .MessageEntry(messageEntry):
                    if let peer = messageEntry.renderedPeer.peer {
                        let notificationsPeerId = peer.notificationSettingsPeerId ?? peer.id
                        if let (_, updated) = transaction.currentUpdatedPeerNotificationSettings[notificationsPeerId] {
                            return .MessageEntry(index: messageEntry.index, message: messageEntry.message, readState: messageEntry.readState, notificationSettings: updated, embeddedInterfaceState: messageEntry.embeddedInterfaceState, renderedPeer: messageEntry.renderedPeer, presence: messageEntry.presence, tagSummaryInfo: messageEntry.tagSummaryInfo, hasFailedMessages: messageEntry.hasFailedMessages, isContact: messageEntry.isContact)
                        } else {
                            return nil
                        }
                    } else {
                        return nil
                    }
                default:
                    return nil
                }
            }) {
                hasUpdates = true
            }
        }
        
        if !transaction.updatedFailedMessagePeerIds.isEmpty {
            if self.orderedEntries.mutableScan({ entry in
                switch entry {
                case let .MessageEntry(messageEntry):
                    if transaction.updatedFailedMessagePeerIds.contains(messageEntry.index.messageIndex.id.peerId) {
                        return .MessageEntry(index: messageEntry.index, message: messageEntry.message, readState: messageEntry.readState, notificationSettings: messageEntry.notificationSettings, embeddedInterfaceState: messageEntry.embeddedInterfaceState, renderedPeer: messageEntry.renderedPeer, presence: messageEntry.presence, tagSummaryInfo: messageEntry.tagSummaryInfo, hasFailedMessages: postbox.messageHistoryFailedTable.contains(peerId: messageEntry.index.messageIndex.id.peerId), isContact: messageEntry.isContact)
                    } else {
                        return nil
                    }
                default:
                    return nil
                }
            }) {
                hasUpdates = true
            }
        }
        
        if !transaction.currentUpdatedPeers.isEmpty {
            if self.orderedEntries.mutableScan({ entry in
                switch entry {
                case let .MessageEntry(messageEntry):
                    var updatedMessage: Message?
                    if let message = messageEntry.message {
                        updatedMessage = updateMessagePeers(message, updatedPeers: transaction.currentUpdatedPeers)
                    }
                    let renderedPeer = updatedRenderedPeer(messageEntry.renderedPeer, updatedPeers: transaction.currentUpdatedPeers)
                    
                    if updatedMessage != nil || renderedPeer != nil {
                        return .MessageEntry(index: messageEntry.index, message: updatedMessage ?? messageEntry.message, readState: messageEntry.readState, notificationSettings: messageEntry.notificationSettings, embeddedInterfaceState: messageEntry.embeddedInterfaceState, renderedPeer: renderedPeer ?? messageEntry.renderedPeer, presence: messageEntry.presence, tagSummaryInfo: messageEntry.tagSummaryInfo, hasFailedMessages: messageEntry.hasFailedMessages, isContact: messageEntry.isContact)
                    } else {
                        return nil
                    }
                default:
                    return nil
                }
            }) {
                hasUpdates = true
            }
        }
        
        if !transaction.currentUpdatedPeerPresences.isEmpty {
            if self.orderedEntries.mutableScan({ entry in
                switch entry {
                case let .MessageEntry(messageEntry):
                    var presencePeerId = messageEntry.renderedPeer.peerId
                    if let peer = messageEntry.renderedPeer.peers[messageEntry.renderedPeer.peerId], let associatedPeerId = peer.associatedPeerId {
                        presencePeerId = associatedPeerId
                    }
                    if let presence = transaction.currentUpdatedPeerPresences[presencePeerId] {
                        return .MessageEntry(index: messageEntry.index, message: messageEntry.message, readState: messageEntry.readState, notificationSettings: messageEntry.notificationSettings, embeddedInterfaceState: messageEntry.embeddedInterfaceState, renderedPeer: messageEntry.renderedPeer, presence: presence, tagSummaryInfo: messageEntry.tagSummaryInfo, hasFailedMessages: messageEntry.hasFailedMessages, isContact: messageEntry.isContact)
                    } else {
                        return nil
                    }
                default:
                    return nil
                }
            }) {
                hasUpdates = true
            }
        }
        
        if !transaction.currentUpdatedMessageTagSummaries.isEmpty || !transaction.currentUpdatedMessageActionsSummaries.isEmpty {
            if self.orderedEntries.mutableScan({ entry in
                switch entry {
                case let .MessageEntry(messageEntry):
                    var updatedTagSummaryCount: Int32?
                    var updatedActionsSummaryCount: Int32?
                    
                    if let tagSummary = self.summaryComponents.tagSummary {
                        let key = MessageHistoryTagsSummaryKey(tag: tagSummary.tag, peerId: messageEntry.index.messageIndex.id.peerId, namespace: tagSummary.namespace)
                        if let summary = transaction.currentUpdatedMessageTagSummaries[key] {
                            updatedTagSummaryCount = summary.count
                        }
                    }
                    
                    if let actionsSummary = self.summaryComponents.actionsSummary {
                        let key = PendingMessageActionsSummaryKey(type: actionsSummary.type, peerId: messageEntry.index.messageIndex.id.peerId, namespace: actionsSummary.namespace)
                        if let count = transaction.currentUpdatedMessageActionsSummaries[key] {
                            updatedActionsSummaryCount = count
                        }
                    }
                    
                    if updatedTagSummaryCount != nil || updatedActionsSummaryCount != nil {
                        let summaryInfo = ChatListMessageTagSummaryInfo(tagSummaryCount: updatedTagSummaryCount ?? messageEntry.tagSummaryInfo.tagSummaryCount, actionsSummaryCount: updatedActionsSummaryCount ?? messageEntry.tagSummaryInfo.actionsSummaryCount)
                        
                        return .MessageEntry(index: messageEntry.index, message: messageEntry.message, readState: messageEntry.readState, notificationSettings: messageEntry.notificationSettings, embeddedInterfaceState: messageEntry.embeddedInterfaceState, renderedPeer: messageEntry.renderedPeer, presence: messageEntry.presence, tagSummaryInfo: summaryInfo, hasFailedMessages: messageEntry.hasFailedMessages, isContact: messageEntry.isContact)
                    } else {
                        return nil
                    }
                default:
                    return nil
                }
            }) {
                hasUpdates = true
            }
        }
        
        if hadRemovals {
            self.fillSpace(postbox: postbox)
        }
        return hasUpdates
    }
    
    private func add(entry: MutableChatListEntry) -> Bool {
        if self.anchorIndex >= entry.entryIndex {
            let insertionIndex = binaryInsertionIndex(self.orderedEntries.lowerOrAtAnchor, extract: { $0.entryIndex }, searchItem: entry.entryIndex)
            
            if insertionIndex < self.orderedEntries.lowerOrAtAnchor.count {
                if self.orderedEntries.lowerOrAtAnchor[insertionIndex].entryIndex == entry.entryIndex {
                    assertionFailure("Inserting an existing index is not allowed")
                    self.orderedEntries.setLowerOrAtAnchorAtArrayIndex(insertionIndex, to: entry)
                    return true
                }
            }
            
            if insertionIndex == 0 && self.orderedEntries.lowerOrAtAnchor.count >= self.halfLimit {
                return false
            }
            self.orderedEntries.insertLowerOrAtAnchorAtArrayIndex(insertionIndex, value: entry)
            if self.orderedEntries.lowerOrAtAnchor.count > self.halfLimit {
                self.orderedEntries.removeLowerOrAtAnchorAtArrayIndex(0)
            }
            return true
        } else {
            let insertionIndex = binaryInsertionIndex(orderedEntries.higherThanAnchor, extract: { $0.entryIndex }, searchItem: entry.entryIndex)
            
            if insertionIndex < self.orderedEntries.higherThanAnchor.count {
                if self.orderedEntries.higherThanAnchor[insertionIndex].entryIndex == entry.entryIndex {
                    assertionFailure("Inserting an existing index is not allowed")
                    self.orderedEntries.setHigherThanAnchorAtArrayIndex(insertionIndex, to: entry)
                    return true
                }
            }
            
            if insertionIndex == self.orderedEntries.higherThanAnchor.count && self.orderedEntries.higherThanAnchor.count >= self.halfLimit {
                return false
            }
            self.orderedEntries.insertHigherThanAnchorAtArrayIndex(insertionIndex, value: entry)
            if self.orderedEntries.higherThanAnchor.count > self.halfLimit {
                self.orderedEntries.removeHigherThanAnchorAtArrayIndex(self.orderedEntries.higherThanAnchor.count - 1)
            }
            return true
        }
    }
}

private struct MutableChatListEntryIndex: Hashable, Comparable {
    var index: ChatListIndex
    var isMessage: Bool
    
    var predecessor: MutableChatListEntryIndex {
        return MutableChatListEntryIndex(index: self.index.predecessor, isMessage: true)
    }
    
    var successor: MutableChatListEntryIndex {
        return MutableChatListEntryIndex(index: self.index.successor, isMessage: true)
    }
    
    static let absoluteLowerBound = MutableChatListEntryIndex(index: .absoluteLowerBound, isMessage: true)
    static let absoluteUpperBound = MutableChatListEntryIndex(index: .absoluteUpperBound, isMessage: true)
    
    static func <(lhs: MutableChatListEntryIndex, rhs: MutableChatListEntryIndex) -> Bool {
        if lhs.index != rhs.index {
            return lhs.index < rhs.index
        } else if lhs.isMessage != rhs.isMessage {
            return lhs.isMessage
        } else {
            return false
        }
    }
}

private extension MutableChatListEntry {
    var messagePeerId: PeerId? {
        switch self {
        case let .IntermediateMessageEntry(intermediateMessageEntry):
            return intermediateMessageEntry.0.messageIndex.id.peerId
        case let .MessageEntry(messageEntry):
            return messageEntry.0.messageIndex.id.peerId
        case .HoleEntry:
            return nil
        }
    }
    
    var entryIndex: MutableChatListEntryIndex {
        switch self {
        case let .IntermediateMessageEntry(intermediateMessageEntry):
            return MutableChatListEntryIndex(index: intermediateMessageEntry.index, isMessage: true)
        case let .MessageEntry(messageEntry):
            return MutableChatListEntryIndex(index: messageEntry.index, isMessage: true)
        case let .HoleEntry(hole):
            return MutableChatListEntryIndex(index: ChatListIndex(pinningIndex: nil, messageIndex: hole.index), isMessage: false)
        }
    }
}

private struct OrderedChatListViewEntries {
    private(set) var lowerOrAtAnchor: [MutableChatListEntry]
    private(set) var higherThanAnchor: [MutableChatListEntry]
    
    private(set) var reverseIndices: [PeerId: [MutableChatListEntryIndex]] = [:]
    
    fileprivate init(lowerOrAtAnchor: [MutableChatListEntry], higherThanAnchor: [MutableChatListEntry]) {
        self.lowerOrAtAnchor = lowerOrAtAnchor
        self.higherThanAnchor = higherThanAnchor
        
        for entry in lowerOrAtAnchor {
            if let peerId = entry.messagePeerId {
                if self.reverseIndices[peerId] == nil {
                    self.reverseIndices[peerId] = [entry.entryIndex]
                } else {
                    self.reverseIndices[peerId]!.append(entry.entryIndex)
                }
            }
        }
        for entry in higherThanAnchor {
            if let peerId = entry.messagePeerId {
                if self.reverseIndices[peerId] == nil {
                    self.reverseIndices[peerId] = [entry.entryIndex]
                } else {
                    self.reverseIndices[peerId]!.append(entry.entryIndex)
                }
            }
        }
    }
    
    mutating func setLowerOrAtAnchorAtArrayIndex(_ index: Int, to value: MutableChatListEntry) {
        let previousIndex = self.lowerOrAtAnchor[index].entryIndex
        let updatedIndex = value.entryIndex
        let previousPeerId = self.lowerOrAtAnchor[index].messagePeerId
        let updatedPeerId = value.messagePeerId
        
        self.lowerOrAtAnchor[index] = value
        
        if previousPeerId != updatedPeerId {
            if let previousPeerId = previousPeerId {
                self.reverseIndices[previousPeerId]?.removeAll(where: { $0 == previousIndex })
                if let isEmpty = self.reverseIndices[previousPeerId]?.isEmpty, isEmpty {
                    self.reverseIndices.removeValue(forKey: previousPeerId)
                }
            }
            if let updatedPeerId = updatedPeerId {
                if self.reverseIndices[updatedPeerId] == nil {
                    self.reverseIndices[updatedPeerId] = [updatedIndex]
                } else {
                    self.reverseIndices[updatedPeerId]!.append(updatedIndex)
                }
            }
        }
    }
    
    mutating func setHigherThanAnchorAtArrayIndex(_ index: Int, to value: MutableChatListEntry) {
        let previousIndex = self.higherThanAnchor[index].entryIndex
        let updatedIndex = value.entryIndex
        let previousPeerId = self.higherThanAnchor[index].messagePeerId
        let updatedPeerId = value.messagePeerId
        
        self.higherThanAnchor[index] = value
        
        if previousPeerId != updatedPeerId {
            if let previousPeerId = previousPeerId {
                self.reverseIndices[previousPeerId]?.removeAll(where: { $0 == previousIndex })
                if let isEmpty = self.reverseIndices[previousPeerId]?.isEmpty, isEmpty {
                    self.reverseIndices.removeValue(forKey: previousPeerId)
                }
            }
            if let updatedPeerId = updatedPeerId {
                if self.reverseIndices[updatedPeerId] == nil {
                    self.reverseIndices[updatedPeerId] = [updatedIndex]
                } else {
                    self.reverseIndices[updatedPeerId]!.append(updatedIndex)
                }
            }
        }
    }
    
    mutating func insertLowerOrAtAnchorAtArrayIndex(_ index: Int, value: MutableChatListEntry) {
        self.lowerOrAtAnchor.insert(value, at: index)
        
        if let peerId = value.messagePeerId {
            if self.reverseIndices[peerId] == nil {
                self.reverseIndices[peerId] = [value.entryIndex]
            } else {
                self.reverseIndices[peerId]!.append(value.entryIndex)
            }
        }
    }
    
    mutating func insertHigherThanAnchorAtArrayIndex(_ index: Int, value: MutableChatListEntry) {
        self.higherThanAnchor.insert(value, at: index)
        
        if let peerId = value.messagePeerId {
            if self.reverseIndices[peerId] == nil {
                self.reverseIndices[peerId] = [value.entryIndex]
            } else {
                self.reverseIndices[peerId]!.append(value.entryIndex)
            }
        }
    }
    
    mutating func removeLowerOrAtAnchorAtArrayIndex(_ index: Int) {
        let previousIndex = self.lowerOrAtAnchor[index].entryIndex
        if let peerId = self.lowerOrAtAnchor[index].messagePeerId {
            self.reverseIndices[peerId]?.removeAll(where: { $0 == previousIndex })
            if let isEmpty = self.reverseIndices[peerId]?.isEmpty, isEmpty {
                self.reverseIndices.removeValue(forKey: peerId)
            }
        }
        
        self.lowerOrAtAnchor.remove(at: index)
    }
    
    mutating func removeHigherThanAnchorAtArrayIndex(_ index: Int) {
        let previousIndex = self.higherThanAnchor[index].entryIndex
        if let peerId = self.higherThanAnchor[index].messagePeerId {
            self.reverseIndices[peerId]?.removeAll(where: { $0 == previousIndex })
            if let isEmpty = self.reverseIndices[peerId]?.isEmpty, isEmpty {
                self.reverseIndices.removeValue(forKey: peerId)
            }
        }
        
        self.higherThanAnchor.remove(at: index)
    }
    
    func find(index: MutableChatListEntryIndex) -> MutableChatListEntry? {
        if let entryIndex = binarySearch(self.lowerOrAtAnchor, extract: { $0.entryIndex }, searchItem: index) {
            return self.lowerOrAtAnchor[entryIndex]
        } else if let entryIndex = binarySearch(self.higherThanAnchor, extract: { $0.entryIndex }, searchItem: index) {
            return self.higherThanAnchor[entryIndex]
        } else {
            return nil
        }
    }
    
    func indicesForPeerId(_ peerId: PeerId) -> [MutableChatListEntryIndex]? {
        return self.reverseIndices[peerId]
    }
    
    var first: MutableChatListEntry? {
        return self.lowerOrAtAnchor.first ?? self.higherThanAnchor.first
    }
    
    mutating func mutableScan(_ f: (MutableChatListEntry) -> MutableChatListEntry?) -> Bool {
        var anyUpdated = false
        for i in 0 ..< self.lowerOrAtAnchor.count {
            if let updated = f(self.lowerOrAtAnchor[i]) {
                self.setLowerOrAtAnchorAtArrayIndex(i, to: updated)
                anyUpdated = true
            }
        }
        for i in 0 ..< self.higherThanAnchor.count {
            if let updated = f(self.higherThanAnchor[i]) {
                self.setHigherThanAnchorAtArrayIndex(i, to: updated)
                anyUpdated = true
            }
        }
        return anyUpdated
    }
    
    mutating func update(index: MutableChatListEntryIndex, _ f: (MutableChatListEntry) -> MutableChatListEntry?) -> Bool {
        if let entryIndex = binarySearch(self.lowerOrAtAnchor, extract: { $0.entryIndex }, searchItem: index) {
            if let updated = f(self.lowerOrAtAnchor[entryIndex]) {
                self.setLowerOrAtAnchorAtArrayIndex(entryIndex, to: updated)
                return true
            }
        } else if let entryIndex = binarySearch(self.higherThanAnchor, extract: { $0.entryIndex }, searchItem: index) {
            if let updated = f(self.higherThanAnchor[entryIndex]) {
                self.setHigherThanAnchorAtArrayIndex(entryIndex, to: updated)
                return true
            }
        }
        return false
    }
    
    mutating func remove(index: MutableChatListEntryIndex) -> Bool {
        if let entryIndex = binarySearch(self.lowerOrAtAnchor, extract: { $0.entryIndex }, searchItem: index) {
            self.removeLowerOrAtAnchorAtArrayIndex(entryIndex)
            return true
        } else if let entryIndex = binarySearch(self.higherThanAnchor, extract: { $0.entryIndex }, searchItem: index) {
            self.removeHigherThanAnchorAtArrayIndex(entryIndex)
            return true
        } else {
            return false
        }
    }
}

final class ChatListViewSample {
    let entries: [MutableChatListEntry]
    let lower: MutableChatListEntry?
    let upper: MutableChatListEntry?
    let anchorIndex: ChatListIndex
    let hole: ChatListHole?
    
    fileprivate init(entries: [MutableChatListEntry], lower: MutableChatListEntry?, upper: MutableChatListEntry?, anchorIndex: ChatListIndex, hole: ChatListHole?) {
        self.entries = entries
        self.lower = lower
        self.upper = upper
        self.anchorIndex = anchorIndex
        self.hole = hole
    }
}

struct ChatListViewState {
    private let anchorIndex: MutableChatListEntryIndex
    private let filterPredicate: ChatListFilterPredicate?
    private let summaryComponents: ChatListEntrySummaryComponents
    private let halfLimit: Int
    private var stateBySpace: [ChatListViewSpace: ChatListViewSpaceState] = [:]
    
    init(postbox: Postbox, spaces: [ChatListViewSpace], anchorIndex: ChatListIndex, filterPredicate: ChatListFilterPredicate?, summaryComponents: ChatListEntrySummaryComponents, halfLimit: Int) {
        self.anchorIndex = MutableChatListEntryIndex(index: anchorIndex, isMessage: true)
        self.filterPredicate = filterPredicate
        self.summaryComponents = summaryComponents
        self.halfLimit = halfLimit
        
        for space in spaces {
            self.stateBySpace[space] = ChatListViewSpaceState(postbox: postbox, space: space, anchorIndex: self.anchorIndex, filterPredicate: self.filterPredicate, summaryComponents: summaryComponents, halfLimit: halfLimit)
        }
    }
    
    func replay(postbox: Postbox, transaction: PostboxTransaction) -> Bool {
        var updated = false
        for (_, state) in self.stateBySpace {
            if state.replay(postbox: postbox, transaction: transaction) {
                updated = true
            }
        }
        return updated
    }
    
    private func sampleIndices() -> (lowerOrAtAnchor: [(ChatListViewSpace, Int)], higherThanAnchor: [(ChatListViewSpace, Int)]) {
        var previousAnchorIndices: [ChatListViewSpace: Int] = [:]
        var nextAnchorIndices: [ChatListViewSpace: Int] = [:]
        for (space, state) in self.stateBySpace {
            previousAnchorIndices[space] = state.orderedEntries.lowerOrAtAnchor.count - 1
            nextAnchorIndices[space] = 0
        }
        
        var backwardsResult: [(ChatListViewSpace, Int)] = []
        var result: [(ChatListViewSpace, Int)] = []
        
        while true {
            var minSpace: ChatListViewSpace?
            for (space, value) in previousAnchorIndices {
                if value != -1 {
                    if let minSpaceValue = minSpace {
                        if self.stateBySpace[space]!.orderedEntries.lowerOrAtAnchor[value].entryIndex > self.stateBySpace[minSpaceValue]!.orderedEntries.lowerOrAtAnchor[previousAnchorIndices[minSpaceValue]!].entryIndex {
                            minSpace = space
                        }
                    } else {
                        minSpace = space
                    }
                }
            }
            if let minSpace = minSpace {
                backwardsResult.append((minSpace, previousAnchorIndices[minSpace]!))
                previousAnchorIndices[minSpace]! -= 1
                if backwardsResult.count == self.halfLimit {
                    break
                }
            }
            
            if minSpace == nil {
                break
            }
        }
        
        while true {
            var maxSpace: ChatListViewSpace?
            for (space, value) in nextAnchorIndices {
                if value != self.stateBySpace[space]!.orderedEntries.higherThanAnchor.count {
                    if let maxSpaceValue = maxSpace {
                        if self.stateBySpace[space]!.orderedEntries.higherThanAnchor[value].entryIndex < self.stateBySpace[maxSpaceValue]!.orderedEntries.higherThanAnchor[nextAnchorIndices[maxSpaceValue]!].entryIndex {
                            maxSpace = space
                        }
                    } else {
                        maxSpace = space
                    }
                }
            }
            if let maxSpace = maxSpace {
                result.append((maxSpace, nextAnchorIndices[maxSpace]!))
                nextAnchorIndices[maxSpace]! += 1
                if result.count == self.halfLimit {
                    break
                }
            }
            
            if maxSpace == nil {
                break
            }
        }
        return (backwardsResult.reversed(), result)
    }
    
    func sample(postbox: Postbox) -> ChatListViewSample {
        let combinedSpacesAndIndicesByDirection = self.sampleIndices()
        
        var result: [MutableChatListEntry] = []
        
        var sampledHoleIndices: [Int] = []
        var sampledAnchorBoundaryIndex: Int?
        
        let directions = [combinedSpacesAndIndicesByDirection.lowerOrAtAnchor, combinedSpacesAndIndicesByDirection.higherThanAnchor]
        for directionIndex in 0 ..< directions.count {
            outer: for i in 0 ..< directions[directionIndex].count {
                let (space, listIndex) = directions[directionIndex][i]
                
                let entry: MutableChatListEntry
                if directionIndex == 0 {
                    entry = self.stateBySpace[space]!.orderedEntries.lowerOrAtAnchor[listIndex]
                } else {
                    entry = self.stateBySpace[space]!.orderedEntries.higherThanAnchor[listIndex]
                }
                
                if entry.entryIndex >= self.anchorIndex {
                    sampledAnchorBoundaryIndex = result.count
                }
                
                switch entry {
                case let .IntermediateMessageEntry(index, messageIndex):
                    var peers = SimpleDictionary<PeerId, Peer>()
                    var notificationsPeerId = index.messageIndex.id.peerId
                    if let peer = postbox.peerTable.get(index.messageIndex.id.peerId) {
                        peers[peer.id] = peer
                        if let notificationSettingsPeerId = peer.notificationSettingsPeerId {
                            notificationsPeerId = notificationSettingsPeerId
                        }
                        if let associatedPeerId = peer.associatedPeerId {
                            if let associatedPeer = postbox.peerTable.get(associatedPeerId) {
                                peers[associatedPeer.id] = associatedPeer
                            }
                        }
                    }
                    let renderedPeer = RenderedPeer(peerId: index.messageIndex.id.peerId, peers: peers)
                    
                    var tagSummaryCount: Int32?
                    var actionsSummaryCount: Int32?
                    
                    if let tagSummary = self.summaryComponents.tagSummary {
                        let key = MessageHistoryTagsSummaryKey(tag: tagSummary.tag, peerId: index.messageIndex.id.peerId, namespace: tagSummary.namespace)
                        if let summary = postbox.messageHistoryTagsSummaryTable.get(key) {
                            tagSummaryCount = summary.count
                        }
                    }
                    
                    if let actionsSummary = self.summaryComponents.actionsSummary {
                        let key = PendingMessageActionsSummaryKey(type: actionsSummary.type, peerId: index.messageIndex.id.peerId, namespace: actionsSummary.namespace)
                        actionsSummaryCount = postbox.pendingMessageActionsMetadataTable.getCount(.peerNamespaceAction(key.peerId, key.namespace, key.type))
                    }
                    
                    let tagSummaryInfo = ChatListMessageTagSummaryInfo(tagSummaryCount: tagSummaryCount, actionsSummaryCount: actionsSummaryCount)
                    
                    let updatedEntry: MutableChatListEntry = .MessageEntry(index: index, message: messageIndex.flatMap(postbox.messageHistoryTable.getMessage).flatMap(postbox.renderIntermediateMessage), readState: postbox.readStateTable.getCombinedState(index.messageIndex.id.peerId), notificationSettings: postbox.peerNotificationSettingsTable.getEffective(notificationsPeerId), embeddedInterfaceState: postbox.peerChatInterfaceStateTable.get(index.messageIndex.id.peerId)?.chatListEmbeddedState, renderedPeer: renderedPeer, presence: postbox.peerPresenceTable.get(index.messageIndex.id.peerId), tagSummaryInfo: tagSummaryInfo, hasFailedMessages: false, isContact: postbox.contactsTable.isContact(peerId: index.messageIndex.id.peerId))
                    if directionIndex == 0 {
                        self.stateBySpace[space]!.orderedEntries.setLowerOrAtAnchorAtArrayIndex(listIndex, to: updatedEntry)
                    } else {
                        self.stateBySpace[space]!.orderedEntries.setHigherThanAnchorAtArrayIndex(listIndex, to: updatedEntry)
                    }
                    result.append(updatedEntry)
                case .MessageEntry:
                    result.append(entry)
                case .HoleEntry:
                    sampledHoleIndices.append(result.count)
                    
                    result.append(entry)
                }
            }
        }
        
        let allIndices = result.map { $0.entryIndex }
        assert(Set(allIndices).count == allIndices.count)
        assert(allIndices.sorted() == allIndices)
        
        var sampledHoleIndex: Int?
        if !sampledHoleIndices.isEmpty {
            if let sampledAnchorBoundaryIndex = sampledAnchorBoundaryIndex {
                var found = false
                for i in 0 ..< sampledHoleIndices.count {
                    if i >= sampledAnchorBoundaryIndex {
                        sampledHoleIndex = sampledHoleIndices[i]
                        found = true
                        break
                    }
                }
                if !found {
                    sampledHoleIndex = sampledHoleIndices.first
                }
            } else if let index = sampledHoleIndices.first {
                sampledHoleIndex = index
            }
        }
        
        var sampledHole: ChatListHole?
        if let index = sampledHoleIndex {
            if case let .HoleEntry(hole) = result[index] {
                sampledHole = hole
            } else {
                assertionFailure()
            }
        }
        
        var lower: MutableChatListEntry?
        if combinedSpacesAndIndicesByDirection.lowerOrAtAnchor.count >= self.halfLimit {
            lower = result[0]
            result.removeFirst()
        }
        
        var upper: MutableChatListEntry?
        if combinedSpacesAndIndicesByDirection.higherThanAnchor.count >= self.halfLimit {
            upper = result.last
            result.removeLast()
        }
        
        return ChatListViewSample(entries: result, lower: lower, upper: upper, anchorIndex: self.anchorIndex.index, hole: sampledHole)
    }
}
