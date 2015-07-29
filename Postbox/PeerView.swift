import Foundation

public final class PeerViewEntry {
    public let peerId: PeerId
    public let peer: Peer?
    public let message: RenderedMessage
    
    public init(peer: Peer, message: RenderedMessage) {
        self.peerId = peer.id
        self.peer = peer
        self.message = message
    }
    
    public init(peerId: PeerId, message: RenderedMessage) {
        self.peerId = peerId
        self.peer = nil
        self.message = message
    }
    
    private init(peer: Peer?, peerId: PeerId, message: RenderedMessage) {
        self.peer = peer
        self.peerId = peerId
        self.message = message
    }
}

public struct PeerViewEntryIndex: Equatable, Comparable {
    public let peerId: PeerId
    public let messageIndex: MessageIndex
    
    public init(_ entry: PeerViewEntry) {
        self.peerId = entry.peerId
        self.messageIndex = MessageIndex(entry.message.message)
    }
    
    public init(peerId: PeerId, messageIndex: MessageIndex) {
        self.peerId = peerId
        self.messageIndex = messageIndex
    }
    
    public func earlier() -> PeerViewEntryIndex {
        return PeerViewEntryIndex(peerId: self.peerId, messageIndex: MessageIndex(id: MessageId(peerId: self.messageIndex.id.peerId, namespace: self.messageIndex.id.namespace, id: self.messageIndex.id.id - 1), timestamp: self.messageIndex.timestamp))
    }
    
    public func later() -> PeerViewEntryIndex {
        return PeerViewEntryIndex(peerId: self.peerId, messageIndex: MessageIndex(id: MessageId(peerId: self.messageIndex.id.peerId, namespace: self.messageIndex.id.namespace, id: self.messageIndex.id.id + 1), timestamp: self.messageIndex.timestamp))
    }
}

public func ==(lhs: PeerViewEntryIndex, rhs: PeerViewEntryIndex) -> Bool {
    return lhs.peerId == rhs.peerId && lhs.messageIndex == rhs.messageIndex
}

public func <(lhs: PeerViewEntryIndex, rhs: PeerViewEntryIndex) -> Bool {
    if lhs.messageIndex != rhs.messageIndex {
        return lhs.messageIndex < rhs.messageIndex
    }
    
    return lhs.peerId < rhs.peerId
}

public final class MutablePeerView: CustomStringConvertible {
    public struct RemoveContext {
        var invalidEarlier = false
        var invalidLater = false
        var removedEntries = false
    }
    
    let count: Int
    var earlier: PeerViewEntry?
    var later: PeerViewEntry?
    var entries: [PeerViewEntry]
    
    public init(count: Int, earlier: PeerViewEntry?, entries: [PeerViewEntry], later: PeerViewEntry?) {
        self.count = count
        self.earlier = earlier
        self.entries = entries
        self.later = later
    }
    
    public func removeEntry(context: RemoveContext?, peerId: PeerId) -> RemoveContext {
        var invalidationContext = context ?? RemoveContext()
        
        if let earlier = self.earlier {
            if peerId == earlier.peerId {
                invalidationContext.invalidEarlier = true
            }
        }
        
        if let later = self.later {
            if peerId == later.peerId {
                invalidationContext.invalidLater = true
            }
        }
        
        var i = 0
        while i < self.entries.count {
            if self.entries[i].peerId == peerId {
                self.entries.removeAtIndex(i)
                invalidationContext.removedEntries = true
                break
            }
            i++
        }
        
        return invalidationContext
    }
    
    public func addEntry(entry: PeerViewEntry) {
        if self.entries.count == 0 {
            self.entries.append(entry)
        } else {
            let first = PeerViewEntryIndex(self.entries[self.entries.count - 1])
            let last = PeerViewEntryIndex(self.entries[0])
            
            let index = PeerViewEntryIndex(entry)
            
            var next: PeerViewEntryIndex?
            if let later = self.later {
                next = PeerViewEntryIndex(later)
            }
            
            if index < last {
                let earlierEntry = self.earlier
                if earlierEntry == nil || PeerViewEntryIndex(earlierEntry!) < index {
                    if self.entries.count < self.count {
                        self.entries.insert(entry, atIndex: 0)
                    } else {
                        self.earlier = entry
                    }
                }
            } else if index > first {
                if next != nil && index > next! {
                    let laterEntry = self.later
                    if laterEntry == nil || PeerViewEntryIndex(laterEntry!) > index {
                        if self.entries.count < self.count {
                            self.entries.append(entry)
                        } else {
                            self.later = entry
                        }
                    }
                } else {
                    self.entries.append(entry)
                    if self.entries.count > self.count {
                        let earliest = self.entries[0]
                        self.earlier = earliest
                        self.entries.removeAtIndex(0)
                    }
                }
            } else if index != last && index != first {
                var i = self.entries.count
                while i >= 1 {
                    if PeerViewEntryIndex(self.entries[i - 1]) < index {
                        break
                    }
                    i--
                }
                self.entries.insert(entry, atIndex: i)
                if self.entries.count > self.count {
                    let earliest = self.entries[0]
                    self.earlier = earliest
                    self.entries.removeAtIndex(0)
                }
            }
        }
    }
    
    public func complete(context: RemoveContext, fetchEarlier: (PeerViewEntryIndex?, Int) -> [PeerViewEntry], fetchLater: (PeerViewEntryIndex?, Int) -> [PeerViewEntry]) {
        if context.removedEntries && self.entries.count != self.count {
            var addedEntries: [PeerViewEntry] = []
            
            var latestAnchor: PeerViewEntryIndex?
            
            if self.entries.count != 0 {
                latestAnchor = PeerViewEntryIndex(self.entries[self.entries.count - 1])
            } else if let later = self.later {
                latestAnchor = PeerViewEntryIndex(later)
            }

            if let later = self.later {
                addedEntries += fetchLater(PeerViewEntryIndex(later).earlier(), self.count)
            }
            if let earlier = self.earlier {
                addedEntries += fetchEarlier(PeerViewEntryIndex(earlier).later(), self.count)
            }
            
            addedEntries += self.entries
            addedEntries.sortInPlace({ PeerViewEntryIndex($0) < PeerViewEntryIndex($1) })
            
            var i = addedEntries.count - 1
            while i >= 1 {
                if PeerViewEntryIndex(addedEntries[i]) == PeerViewEntryIndex(addedEntries[i - 1]) {
                    addedEntries.removeAtIndex(i)
                }
                i--
            }
            self.entries = []
            
            var anchorIndex = addedEntries.count - 1
            if let latestAnchor = latestAnchor {
                var i = addedEntries.count - 1
                while i >= 0 {
                    if PeerViewEntryIndex(addedEntries[i]) <= latestAnchor {
                        anchorIndex = i
                        break
                    }
                    i--
                }
            }
            
            self.later = nil
            if anchorIndex + 1 < addedEntries.count {
                let i = anchorIndex + 1
                while i < addedEntries.count {
                    self.later = addedEntries[i]
                    break
                }
            }
            
            i = anchorIndex
            while i >= 0 && i > anchorIndex - self.count {
                self.entries.insert(addedEntries[i], atIndex: 0)
                i--
            }
            
            self.earlier = nil
            if anchorIndex - self.count >= 0 {
                i = anchorIndex - self.count
                while i >= 0 {
                    self.earlier = addedEntries[i]
                    break
                }
            }
        } else {
            var earlyIndex: PeerViewEntryIndex?
            if self.entries.count != 0 {
                earlyIndex = PeerViewEntryIndex(self.entries[0])
            }
            
            let earlierEntries = fetchEarlier(earlyIndex, 1)
            if earlierEntries.count == 0 {
                self.earlier = nil
            } else {
                self.earlier = earlierEntries[0]
            }
            
            var lateIndex: PeerViewEntryIndex?
            if self.entries.count != 0 {
                lateIndex = PeerViewEntryIndex(self.entries[self.entries.count - 1])
            }
            
            let laterEntries = fetchLater(lateIndex, 1)
            if laterEntries.count == 0 {
                self.later = nil
            } else {
                self.later = laterEntries[0]
            }
        }
    }
    
    public func updatePeers(peers: [PeerId : Peer]) -> Bool {
        var updated = false
        
        if let earlier = self.earlier {
            if let peer = peers[earlier.peerId] {
                self.earlier = PeerViewEntry(peer: peer, message: earlier.message)
                updated = true
            }
        }
        
        if let later = self.later {
            if let peer = peers[later.peerId] {
                self.later = PeerViewEntry(peer: peer, message: later.message)
                updated = true
            }
        }
        
        var i = 0
        while i < self.entries.count {
            if let peer = peers[self.entries[i].peerId] {
                self.entries[i] = PeerViewEntry(peer: peer, message: self.entries[i].message)
                updated = true
            }
            i++
        }
        
        return updated
    }
    
    public func incompleteMessages() -> [Message] {
        var result: [Message] = []
        
        if let earlier = self.earlier {
            if earlier.message.incomplete {
                result.append(earlier.message.message)
            }
        }
        if let later = self.later {
            if later.message.incomplete {
                result.append(later.message.message)
            }
        }
        
        for entry in self.entries {
            if entry.message.incomplete {
                result.append(entry.message.message)
            }
        }
        
        return result
    }
    
    public func completeMessages(messages: [MessageId : RenderedMessage]) {
        if let earlier = self.earlier {
            if let message = messages[earlier.message.message.id] {
                self.earlier = PeerViewEntry(peer: earlier.peer, peerId: earlier.peerId, message: message)
            }
        }
        if let later = self.later {
            if let message = messages[later.message.message.id] {
                self.later = PeerViewEntry(peer: later.peer, peerId: later.peerId, message: message)
            }
        }
        
        var i = 0
        while i < self.entries.count {
            if let message = messages[self.entries[i].message.message.id] {
                self.entries[i] = PeerViewEntry(peer: self.entries[i].peer, peerId: self.entries[i].peerId, message: message)
            }
            i++
        }
    }
    
    public var description: String {
        var string = ""
        
        if let earlier = self.earlier {
            string += "more("
            string += "(p \(earlier.peerId.namespace):\(earlier.peerId.id), m \(earlier.message.message.id.namespace):\(earlier.message.message.id.id)—\(earlier.message.message.timestamp)"
            string += ") "
        }
        
        string += "["
        var first = true
        for entry in self.entries {
            if first {
                first = false
            } else {
                string += ", "
            }
            string += "(p \(entry.peerId.namespace):\(entry.peerId.id), m \(entry.message.message.id.namespace):\(entry.message.message.id.id)—\(entry.message.message.timestamp))"
        }
        string += "]"
        
        if let later = self.later {
            string += " more("
            string += "(p \(later.peerId.namespace):\(later.peerId), m \(later.message.message.id.namespace):\(later.message.message.id.id)—\(later.message.message.timestamp)"
            string += ")"
        }
        
        return string
    }
}

public final class PeerView: CustomStringConvertible {
    let earlier: PeerViewEntryIndex?
    let later: PeerViewEntryIndex?
    public let entries: [PeerViewEntry]
    
    init(_ mutableView: MutablePeerView) {
        if let earlier = mutableView.earlier {
            self.earlier = PeerViewEntryIndex(earlier)
        } else {
            self.earlier = nil
        }
        
        if let later = mutableView.later {
            self.later = PeerViewEntryIndex(later)
        } else {
            self.later = nil
        }
        
        self.entries = mutableView.entries
    }
    
    public var description: String {
        var string = ""
        
        if let earlier = self.earlier {
            string += "more("
            string += "(p \(earlier.peerId.namespace):\(earlier.peerId.id), m \(earlier.messageIndex.id.namespace):\(earlier.messageIndex.id.id)—\(earlier.messageIndex.timestamp)"
            string += ") "
        }
        
        string += "["
        var first = true
        for entry in self.entries {
            if first {
                first = false
            } else {
                string += ", "
            }
            string += "(p \(entry.peerId.namespace):\(entry.peerId.id), m \(entry.message.message.id.namespace):\(entry.message.message.id.id)—\(entry.message.message.timestamp))"
        }
        string += "]"
        
        if let later = self.later {
            string += " more("
            string += "(p \(later.peerId.namespace):\(later.peerId), m \(later.messageIndex.id.namespace):\(later.messageIndex.id.id)—\(later.messageIndex.timestamp)"
            string += ")"
        }
        
        return string
    }
}