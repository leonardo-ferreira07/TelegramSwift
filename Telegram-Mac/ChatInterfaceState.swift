
//
//  ChatInterfaceState.swift
//  Telegram-Mac
//
//  Created by keepcoder on 01/10/2016.
//  Copyright © 2016 Telegram. All rights reserved.
//

import Cocoa

import PostboxMac
import SwiftSignalKitMac
import TelegramCoreMac


struct ChatInterfaceSelectionState: PostboxCoding, Equatable {
    let selectedIds: Set<MessageId>
    
    static func ==(lhs: ChatInterfaceSelectionState, rhs: ChatInterfaceSelectionState) -> Bool {
        return lhs.selectedIds == rhs.selectedIds
    }
    
    init(selectedIds: Set<MessageId>) {
        self.selectedIds = selectedIds
    }
    
    init(decoder: PostboxDecoder) {
        if let data = decoder.decodeBytesForKeyNoCopy("i") {
            self.selectedIds = Set(MessageId.decodeArrayFromBuffer(data))
        } else {
            self.selectedIds = Set()
        }
    }
    
    func encode(_ encoder: PostboxEncoder) {
        let buffer = WriteBuffer()
        MessageId.encodeArrayToBuffer(Array(selectedIds), buffer: buffer)
        encoder.encodeBytes(buffer, forKey: "i")
    }
}

enum ChatTextInputAttribute : Equatable, PostboxCoding {
    case bold(Range<Int>)
    case italic(Range<Int>)
    case pre(Range<Int>)
    case code(Range<Int>)
    case uid(Range<Int>, Int32)
    
    init(decoder: PostboxDecoder) {
        let range = Range<Int>(Int(decoder.decodeInt32ForKey("start", orElse: 0)) ..< Int(decoder.decodeInt32ForKey("end", orElse: 0)))
        
        let type: Int32 = decoder.decodeInt32ForKey("_rawValue", orElse: 0)
        switch type {
        case 0:
            self = .bold(range)
        case 1:
            self = .italic(range)
        case 2:
            self = .pre(range)
        case 3:
            self = .uid(range, decoder.decodeInt32ForKey("uid", orElse: 0))
        case 4:
            self = .code(range)
        default:
            fatalError("input attribute not supported")
        }
    }
    
    func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(Int32(self.range.lowerBound), forKey: "start")
        encoder.encodeInt32(Int32(self.range.upperBound), forKey: "end")
        switch self {
        case .bold:
            encoder.encodeInt32(0, forKey: "_rawValue")
        case .italic:
            encoder.encodeInt32(1, forKey: "_rawValue")
        case .pre:
            encoder.encodeInt32(2, forKey: "_rawValue")
        case .code:
            encoder.encodeInt32(4, forKey: "_rawValue")
        case let .uid(_, uid):
            encoder.encodeInt32(3, forKey: "_rawValue")
            encoder.encodeInt32(uid, forKey: "uid")
        }
    }
    
}

extension ChatTextInputAttribute {
    var attribute:(String, Any, NSRange) {
        switch self {
        case let .bold(range):
            return (NSAttributedStringKey.font.rawValue, NSFont.bold(.text), NSMakeRange(range.lowerBound, range.upperBound - range.lowerBound))
        case let .italic(range):
            return (NSAttributedStringKey.font.rawValue, NSFontManager.shared.convert(.normal(.text), toHaveTrait: .italicFontMask), NSMakeRange(range.lowerBound, range.upperBound - range.lowerBound))
        case let .pre(range), let .code(range):
            return (NSAttributedStringKey.font.rawValue, NSFont.code(.text), NSMakeRange(range.lowerBound, range.upperBound - range.lowerBound))
        case let .uid(range, uid):
            let tag = TGInputTextTag(uniqueId: Int64(arc4random()), attachment: NSNumber(value: uid), attribute: TGInputTextAttribute(name: NSAttributedStringKey.foregroundColor.rawValue, value: theme.colors.link))
            return (TGMentionUidAttributeName, tag, NSMakeRange(range.lowerBound, range.upperBound - range.lowerBound))
        }
    }
    
    var range:Range<Int> {
        switch self {
        case let .bold(range), let .italic(range), let .pre(range), let .code(range):
            return range
        case let .uid(range, _):
            return range
        }
    }
}

func ==(lhs: ChatTextInputAttribute, rhs: ChatTextInputAttribute) -> Bool {
    switch lhs {
    case let .bold(range):
        if case .bold(range) = rhs {
            return true
        } else {
            return false
        }
    case let .italic(range):
        if case .italic(range) = rhs {
            return true
        } else {
            return false
        }
    case let .pre(range):
        if case .pre(range) = rhs {
            return true
        } else {
            return false
        }
    case let .code(range):
        if case .code(range) = rhs {
            return true
        } else {
            return false
        }
    case let .uid(range, uid):
        if case .uid(range, uid) = rhs {
            return true
        } else {
            return false
        }
    }
}

func chatTextAttributes(from entities:TextEntitiesMessageAttribute) -> [ChatTextInputAttribute] {
    var inputAttributes:[ChatTextInputAttribute] = []
    for entity in entities.entities {
        switch entity.type {
        case .Bold:
            inputAttributes.append(.bold(entity.range))
        case .Italic:
            inputAttributes.append(.italic(entity.range))
        case .Code:
            inputAttributes.append(.code(entity.range))
        case .Pre:
            inputAttributes.append(.pre(entity.range))
        case let .TextMention(peerId: peerId):
            inputAttributes.append(.uid(entity.range, peerId.id))
        default:
            break
        }
    }
    return inputAttributes
}

func chatTextAttributes(from attributed:NSAttributedString) -> [ChatTextInputAttribute] {
    
    var inputAttributes:[ChatTextInputAttribute] = []
    
    attributed.enumerateAttribute(NSAttributedStringKey.font, in: NSMakeRange(0, attributed.length), options: .init(rawValue: 0)) { font, range, _ in
        if let font = font as? NSFont {
            let descriptor = font.fontDescriptor
            let symTraits = descriptor.symbolicTraits
            let traitSet = NSFontTraitMask(rawValue: UInt(symTraits.rawValue))
            let isBold = traitSet.contains(.boldFontMask)
            let isItalic = traitSet.contains(.italicFontMask)
            let isMonospace = font.fontName == "Menlo-Regular"
            
            if isBold {
                inputAttributes.append(.bold(range.location ..< range.location + range.length))
            } else if isItalic {
                inputAttributes.append(.italic(range.location ..< range.location + range.length))
            } else if isMonospace {
                inputAttributes.append(.code(range.location ..< range.location + range.length))
            }
        }
    }
    
    attributed.enumerateAttribute(NSAttributedStringKey(rawValue: TGMentionUidAttributeName), in: NSMakeRange(0, attributed.length), options: .init(rawValue: 0)) { tag, range, _ in
        if let tag = tag as? TGInputTextTag, let uid = tag.attachment as? NSNumber {
            inputAttributes.append(.uid(range.location ..< range.location + range.length, uid.int32Value))
        }
    }
    return inputAttributes
}

private let markdownRegexFormat = "(^|\\s)(````?)([\\s\\S]+?)(````?)([\\s\\n\\.,:?!;]|$)|(^|\\s)(`)([^\\n]+?)\\7([\\s\\.,:?!;]|$)"
private let markdownRegex = try? NSRegularExpression(pattern: markdownRegexFormat, options: [.caseInsensitive, .anchorsMatchLines])

struct ChatTextInputState: PostboxCoding, Equatable {
    let inputText: String
    let attributes:[ChatTextInputAttribute]
    let selectionRange: Range<Int>
    
    static func ==(lhs: ChatTextInputState, rhs: ChatTextInputState) -> Bool {
        return lhs.inputText == rhs.inputText && lhs.selectionRange == rhs.selectionRange  && lhs.attributes == rhs.attributes
    }
    
    init() {
        self.inputText = ""
        self.selectionRange = 0 ..< 0
        self.attributes = []
    }
    
    init(inputText: String, selectionRange: Range<Int>, attributes:[ChatTextInputAttribute]) {
        self.inputText = inputText
        self.selectionRange = selectionRange
        self.attributes = attributes
    }
    
    init(inputText: String) {
        self.inputText = inputText
        self.selectionRange = inputText.length ..< inputText.length
        self.attributes = []
    }
    
    init(decoder: PostboxDecoder) {
        self.inputText = decoder.decodeStringForKey("t", orElse: "")
        self.selectionRange = Int(decoder.decodeInt32ForKey("s0", orElse: 0)) ..< Int(decoder.decodeInt32ForKey("s1", orElse: 0))
        self.attributes = decoder.decodeObjectArrayWithDecoderForKey("t.a")
    }
    
    func encode(_ encoder: PostboxEncoder) {
        encoder.encodeString(self.inputText, forKey: "t")
        encoder.encodeInt32(Int32(self.selectionRange.lowerBound), forKey: "s0")
        encoder.encodeInt32(Int32(self.selectionRange.upperBound), forKey: "s1")
        encoder.encodeObjectArray(self.attributes, forKey: "t.a")
    }
    
    var attributedString:NSAttributedString {
        let string = NSMutableAttributedString()
        _ = string.append(string: inputText, color: .text, font: .normal(.text), coreText: false)
        for attribute in attributes {
            let attr = attribute.attribute
            string.addAttribute(NSAttributedStringKey(rawValue: attr.0), value: attr.1, range: attr.2)
        }
        return string.copy() as! NSAttributedString
    }
    
    
    func subInputState(from range: NSRange) -> ChatTextInputState {
        
        var subText = inputText.nsstring.substring(with: range)
        
        var raw:String = subText
        
        var attributes:[ChatTextInputAttribute] = []
        
        
        if let regex = markdownRegex {
            
            var rawOffset:Int = 0
            var newText:[String] = []
            while let match = regex.firstMatch(in: raw, range: NSMakeRange(0, raw.length)) {
                let matchIndex = rawOffset + match.range.location
                
                newText.append(raw.nsstring.substring(with: NSMakeRange(0, match.range.location)))
                
                var pre = match.range(at: 3)
                
                
                if pre.location != NSNotFound {
                    let text = raw.nsstring.substring(with: pre)
                    
                    rawOffset -= match.range(at: 2).length + match.range(at: 4).length
                    newText.append(raw.nsstring.substring(with: match.range(at: 1)) + text + raw.nsstring.substring(with: match.range(at: 5)))
                    attributes.append(.pre(matchIndex + match.range(at: 1).length ..< matchIndex + match.range(at: 1).length + text.length))
                }
                
                pre = match.range(at: 8)
                if pre.location != NSNotFound {
                    let text = raw.nsstring.substring(with: pre)
                    
                    newText.append(raw.nsstring.substring(with: match.range(at: 6)) + text + raw.nsstring.substring(with: match.range(at: 9)))
                    attributes.append(.code(matchIndex + match.range(at: 6).length ..< matchIndex + match.range(at: 6).length + text.length))
                    
                    rawOffset -= match.range(at: 7).length * 2
                }
                
                
                raw = raw.nsstring.substring(from: match.range.location + match.range(at: 0).length)
                rawOffset += match.range.location + match.range(at: 0).length
                
            }
            
            newText.append(raw)
            subText = newText.joined()
        }
        
        
        
        for attr in self.attributes {
            let newRange = Range<Int>(attr.range.lowerBound - range.location ..< attr.range.upperBound - range.location)
            if newRange.lowerBound >= range.location && newRange.upperBound <= range.location + range.length {
                switch attr {
                case .bold:
                    attributes.append(.bold(newRange))
                case .italic:
                    attributes.append(.italic(newRange))
                case .pre:
                    attributes.append(.pre(newRange))
                case .code:
                    attributes.append(.code(newRange))
                case let .uid(_, uid):
                    attributes.append(.uid(newRange, uid))
                }
            }
        }
        
        return ChatTextInputState(inputText: subText, selectionRange: 0 ..< 0, attributes: attributes)
    }
    
    
    var messageTextEntities:[MessageTextEntity] {
        var entities:[MessageTextEntity] = []
        for attribute in attributes {
            switch attribute {
            case let .bold(range):
                entities.append(.init(range: range, type: .Bold))
            case let .italic(range):
                entities.append(.init(range: range, type: .Italic))
            case let .pre(range):
                entities.append(.init(range: range, type: .Pre))
            case let .code(range):
                entities.append(.init(range: range, type: .Code))
            case let .uid(range, uid):
                entities.append(.init(range: range, type: .TextMention(peerId: PeerId(namespace: Namespaces.Peer.CloudUser, id: uid))))
            }
        }
        return entities
    }
    
    
}


struct ChatInterfaceMessageActionsState: PostboxCoding, Equatable {
    let closedButtonKeyboardMessageId: MessageId?
    let processedSetupReplyMessageId: MessageId?
    
    var isEmpty: Bool {
        return self.closedButtonKeyboardMessageId == nil && self.processedSetupReplyMessageId == nil
    }
    
    init() {
        self.closedButtonKeyboardMessageId = nil
        self.processedSetupReplyMessageId = nil
    }
    
    init(closedButtonKeyboardMessageId: MessageId?, processedSetupReplyMessageId: MessageId?) {
        self.closedButtonKeyboardMessageId = closedButtonKeyboardMessageId
        self.processedSetupReplyMessageId = processedSetupReplyMessageId
    }
    
    init(decoder: PostboxDecoder) {
        if let closedMessageIdPeerId = (decoder.decodeOptionalInt64ForKey("cb.p") as Int64?), let closedMessageIdNamespace = (decoder.decodeOptionalInt32ForKey("cb.n") as Int32?), let closedMessageIdId = (decoder.decodeOptionalInt32ForKey("cb.i") as Int32?) {
            self.closedButtonKeyboardMessageId = MessageId(peerId: PeerId(closedMessageIdPeerId), namespace: closedMessageIdNamespace, id: closedMessageIdId)
        } else {
            self.closedButtonKeyboardMessageId = nil
        }
        
        if let processedMessageIdPeerId = (decoder.decodeOptionalInt64ForKey("pb.p") as Int64?), let processedMessageIdNamespace = (decoder.decodeOptionalInt32ForKey("pb.n") as Int32?), let processedMessageIdId = (decoder.decodeOptionalInt32ForKey("pb.i") as Int32?) {
            self.processedSetupReplyMessageId = MessageId(peerId: PeerId(processedMessageIdPeerId), namespace: processedMessageIdNamespace, id: processedMessageIdId)
        } else {
            self.processedSetupReplyMessageId = nil
        }
    }
    
    func encode(_ encoder: PostboxEncoder) {
        if let closedButtonKeyboardMessageId = self.closedButtonKeyboardMessageId {
            encoder.encodeInt64(closedButtonKeyboardMessageId.peerId.toInt64(), forKey: "cb.p")
            encoder.encodeInt32(closedButtonKeyboardMessageId.namespace, forKey: "cb.n")
            encoder.encodeInt32(closedButtonKeyboardMessageId.id, forKey: "cb.i")
        } else {
            encoder.encodeNil(forKey: "cb.p")
            encoder.encodeNil(forKey: "cb.n")
            encoder.encodeNil(forKey: "cb.i")
        }
        
        if let processedSetupReplyMessageId = self.processedSetupReplyMessageId {
            encoder.encodeInt64(processedSetupReplyMessageId.peerId.toInt64(), forKey: "pb.p")
            encoder.encodeInt32(processedSetupReplyMessageId.namespace, forKey: "pb.n")
            encoder.encodeInt32(processedSetupReplyMessageId.id, forKey: "pb.i")
        } else {
            encoder.encodeNil(forKey: "pb.p")
            encoder.encodeNil(forKey: "pb.n")
            encoder.encodeNil(forKey: "pb.i")
        }
    }
    
    static func ==(lhs: ChatInterfaceMessageActionsState, rhs: ChatInterfaceMessageActionsState) -> Bool {
        return lhs.closedButtonKeyboardMessageId == rhs.closedButtonKeyboardMessageId && lhs.processedSetupReplyMessageId == rhs.processedSetupReplyMessageId
    }
    
    func withUpdatedClosedButtonKeyboardMessageId(_ closedButtonKeyboardMessageId: MessageId?) -> ChatInterfaceMessageActionsState {
        return ChatInterfaceMessageActionsState(closedButtonKeyboardMessageId: closedButtonKeyboardMessageId, processedSetupReplyMessageId: self.processedSetupReplyMessageId)
    }
    
    func withUpdatedProcessedSetupReplyMessageId(_ processedSetupReplyMessageId: MessageId?) -> ChatInterfaceMessageActionsState {
        return ChatInterfaceMessageActionsState(closedButtonKeyboardMessageId: self.closedButtonKeyboardMessageId, processedSetupReplyMessageId: processedSetupReplyMessageId)
    }
}


final class ChatEmbeddedInterfaceState: PeerChatListEmbeddedInterfaceState {
    let timestamp: Int32
    let text: String
    
    init(timestamp: Int32, text: String) {
        self.timestamp = timestamp
        self.text = text
    }
    
    init(decoder: PostboxDecoder) {
        self.timestamp = decoder.decodeInt32ForKey("d", orElse: 0)
        self.text = decoder.decodeStringForKey("t", orElse: "")
    }
    
    func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.timestamp, forKey: "d")
        encoder.encodeString(self.text, forKey: "t")
    }
    
    public func isEqual(to: PeerChatListEmbeddedInterfaceState) -> Bool {
        if let to = to as? ChatEmbeddedInterfaceState {
            return self.timestamp == to.timestamp && self.text == to.text
        } else {
            return false
        }
    }
}

struct ChatInterfaceHistoryScrollState: PostboxCoding, Equatable {
    let messageIndex: MessageIndex
    let relativeOffset: Double
    
    init(messageIndex: MessageIndex, relativeOffset: Double) {
        self.messageIndex = messageIndex
        self.relativeOffset = relativeOffset
    }
    
    init(decoder: PostboxDecoder) {
        self.messageIndex = MessageIndex(id: MessageId(peerId: PeerId(decoder.decodeInt64ForKey("m.p", orElse: 0)), namespace: decoder.decodeInt32ForKey("m.n", orElse: 0), id: decoder.decodeInt32ForKey("m.i", orElse: 0)), timestamp: decoder.decodeInt32ForKey("m.t", orElse: 0))
        self.relativeOffset = decoder.decodeDoubleForKey("ro", orElse: 0.0)
    }
    
    func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.messageIndex.timestamp, forKey: "m.t")
        encoder.encodeInt64(self.messageIndex.id.peerId.toInt64(), forKey: "m.p")
        encoder.encodeInt32(self.messageIndex.id.namespace, forKey: "m.n")
        encoder.encodeInt32(self.messageIndex.id.id, forKey: "m.i")
        encoder.encodeDouble(self.relativeOffset, forKey: "ro")
    }
    
    static func ==(lhs: ChatInterfaceHistoryScrollState, rhs: ChatInterfaceHistoryScrollState) -> Bool {
        if lhs.messageIndex != rhs.messageIndex {
            return false
        }
        if !lhs.relativeOffset.isEqual(to: rhs.relativeOffset) {
            return false
        }
        return true
    }
}



final class ChatInterfaceState: SynchronizeableChatInterfaceState, Equatable {
    
    var historyScrollMessageIndex: MessageIndex? {
        return self.historyScrollState?.messageIndex
    }
    
    let historyScrollState: ChatInterfaceHistoryScrollState?
    
    let timestamp: Int32
    let inputState: ChatTextInputState
    let replyMessageId: MessageId?
    let forwardMessageIds: [MessageId]
    let dismissedPinnedMessageId:MessageId?
    let composeDisableUrlPreview: String?
    
    
    let messageActionsState: ChatInterfaceMessageActionsState
    var chatListEmbeddedState: PeerChatListEmbeddedInterfaceState? {
        if !self.inputState.inputText.isEmpty && self.timestamp != 0 {
            return ChatEmbeddedInterfaceState(timestamp: self.timestamp, text: self.inputState.inputText)
        } else {
            return nil
        }
    }
    
    var synchronizeableInputState: SynchronizeableChatInputState? {
        if self.inputState.inputText.isEmpty {
            return nil
        } else {
            return SynchronizeableChatInputState(replyToMessageId: self.replyMessageId, text: self.inputState.inputText, timestamp: self.timestamp)
        }
    }
    
    func withUpdatedSynchronizeableInputState(_ state: SynchronizeableChatInputState?) -> SynchronizeableChatInterfaceState {
        return self.withUpdatedInputState(ChatTextInputState(inputText: state?.text ?? "")).withUpdatedReplyMessageId(state?.replyToMessageId)
    }
    
    
    init() {
        self.timestamp = 0
        self.inputState = ChatTextInputState()
        self.replyMessageId = nil
        self.forwardMessageIds = []
        self.messageActionsState = ChatInterfaceMessageActionsState()
        self.dismissedPinnedMessageId = nil
        self.composeDisableUrlPreview = nil
        self.historyScrollState = nil
    }
    
    init(timestamp: Int32, inputState: ChatTextInputState, replyMessageId: MessageId?, forwardMessageIds: [MessageId], messageActionsState:ChatInterfaceMessageActionsState, dismissedPinnedMessageId: MessageId?, composeDisableUrlPreview: String?, historyScrollState: ChatInterfaceHistoryScrollState?) {
        self.timestamp = timestamp
        self.inputState = inputState
        self.replyMessageId = replyMessageId
        self.forwardMessageIds = forwardMessageIds
        self.messageActionsState = messageActionsState
        self.dismissedPinnedMessageId = dismissedPinnedMessageId
        self.composeDisableUrlPreview = composeDisableUrlPreview
        self.historyScrollState = historyScrollState
    }
    
    init(decoder: PostboxDecoder) {
        self.timestamp = decoder.decodeInt32ForKey("ts", orElse: 0)
        if let inputState = decoder.decodeObjectForKey("is", decoder: { return ChatTextInputState(decoder: $0) }) as? ChatTextInputState {
            self.inputState = inputState
        } else {
            self.inputState = ChatTextInputState()
        }
        let replyMessageIdPeerId: Int64? = decoder.decodeOptionalInt64ForKey("r.p")
        let replyMessageIdNamespace: Int32? = decoder.decodeOptionalInt32ForKey("r.n")
        let replyMessageIdId: Int32? = decoder.decodeOptionalInt32ForKey("r.i")
        if let replyMessageIdPeerId = replyMessageIdPeerId, let replyMessageIdNamespace = replyMessageIdNamespace, let replyMessageIdId = replyMessageIdId {
            self.replyMessageId = MessageId(peerId: PeerId(replyMessageIdPeerId), namespace: replyMessageIdNamespace, id: replyMessageIdId)
        } else {
            self.replyMessageId = nil
        }
        if let forwardMessageIdsData = decoder.decodeBytesForKeyNoCopy("fm") {
            self.forwardMessageIds = MessageId.decodeArrayFromBuffer(forwardMessageIdsData)
        } else {
            self.forwardMessageIds = []
        }
        
        
        if let messageActionsState = decoder.decodeObjectForKey("as", decoder: { ChatInterfaceMessageActionsState(decoder: $0) }) as? ChatInterfaceMessageActionsState {
            self.messageActionsState = messageActionsState
        } else {
            self.messageActionsState = ChatInterfaceMessageActionsState()
        }
        
        let dismissedPinnedIdPeerId: Int64? = decoder.decodeOptionalInt64ForKey("d.p.p")
        let dismissedPinnedIdNamespace: Int32? = decoder.decodeOptionalInt32ForKey("d.p.n")
        let dismissedPinnedIdId: Int32? = decoder.decodeOptionalInt32ForKey("d.p.i")
        if let dismissedPinnedIdPeerId = dismissedPinnedIdPeerId, let dismissedPinnedIdNamespace = dismissedPinnedIdNamespace, let dismissedPinnedIdId = dismissedPinnedIdId {
            self.dismissedPinnedMessageId = MessageId(peerId: PeerId(dismissedPinnedIdPeerId), namespace: dismissedPinnedIdNamespace, id: dismissedPinnedIdId)
        } else {
            self.dismissedPinnedMessageId = nil
        }
        
        if let composeDisableUrlPreview = decoder.decodeOptionalStringForKey("dup") as String? {
            self.composeDisableUrlPreview = composeDisableUrlPreview
        } else {
            self.composeDisableUrlPreview = nil
        }
        
        self.historyScrollState = decoder.decodeObjectForKey("hss", decoder: { ChatInterfaceHistoryScrollState(decoder: $0) }) as? ChatInterfaceHistoryScrollState
        
        
    }
    
    func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.timestamp, forKey: "ts")
        encoder.encodeObject(self.inputState, forKey: "is")
        if let replyMessageId = self.replyMessageId {
            encoder.encodeInt64(replyMessageId.peerId.toInt64(), forKey: "r.p")
            encoder.encodeInt32(replyMessageId.namespace, forKey: "r.n")
            encoder.encodeInt32(replyMessageId.id, forKey: "r.i")
        } else {
            encoder.encodeNil(forKey: "r.p")
            encoder.encodeNil(forKey: "r.n")
            encoder.encodeNil(forKey: "r.i")
        }
        
        let buffer = WriteBuffer()
        MessageId.encodeArrayToBuffer(forwardMessageIds, buffer: buffer)
        encoder.encodeBytes(buffer, forKey: "fm")
        
        
        
        if self.messageActionsState.isEmpty {
            encoder.encodeNil(forKey: "as")
        } else {
            encoder.encodeObject(self.messageActionsState, forKey: "as")
        }
        
        if let dismissedPinnedMessageId = self.dismissedPinnedMessageId {
            encoder.encodeInt64(dismissedPinnedMessageId.peerId.toInt64(), forKey: "d.p.p")
            encoder.encodeInt32(dismissedPinnedMessageId.namespace, forKey: "d.p.n")
            encoder.encodeInt32(dismissedPinnedMessageId.id, forKey: "d.p.i")
        } else {
            encoder.encodeNil(forKey: "d.p.p")
            encoder.encodeNil(forKey: "d.p.n")
            encoder.encodeNil(forKey: "d.p.i")
        }
        
        if let composeDisableUrlPreview = self.composeDisableUrlPreview {
            encoder.encodeString(composeDisableUrlPreview, forKey: "dup")
        } else {
            encoder.encodeNil(forKey: "dup")
        }
        
        if let historyScrollState = self.historyScrollState {
            encoder.encodeObject(historyScrollState, forKey: "hss")
        } else {
            encoder.encodeNil(forKey: "hss")
        }
        
    }
    
    func isEqual(to: PeerChatInterfaceState) -> Bool {
        if let to = to as? ChatInterfaceState, self == to {
            return true
        } else {
            return false
        }
    }
    
    static func ==(lhs: ChatInterfaceState, rhs: ChatInterfaceState) -> Bool {
        return lhs.inputState == rhs.inputState && lhs.replyMessageId == rhs.replyMessageId && lhs.forwardMessageIds == rhs.forwardMessageIds && lhs.messageActionsState == rhs.messageActionsState && lhs.timestamp == rhs.timestamp && lhs.dismissedPinnedMessageId == rhs.dismissedPinnedMessageId && lhs.composeDisableUrlPreview == rhs.composeDisableUrlPreview && lhs.historyScrollState == rhs.historyScrollState
    }
    
    func withUpdatedInputState(_ inputState: ChatTextInputState) -> ChatInterfaceState {
        return ChatInterfaceState(timestamp: self.timestamp, inputState: inputState, replyMessageId: self.replyMessageId, forwardMessageIds: self.forwardMessageIds, messageActionsState:self.messageActionsState, dismissedPinnedMessageId: self.dismissedPinnedMessageId, composeDisableUrlPreview: self.composeDisableUrlPreview, historyScrollState: self.historyScrollState)
    }
    
    func withUpdatedDismissedPinnedId(_ dismissedPinnedId: MessageId?) -> ChatInterfaceState {
        return ChatInterfaceState(timestamp: self.timestamp, inputState: self.inputState, replyMessageId: self.replyMessageId, forwardMessageIds: self.forwardMessageIds, messageActionsState:self.messageActionsState, dismissedPinnedMessageId: dismissedPinnedId, composeDisableUrlPreview: self.composeDisableUrlPreview, historyScrollState: self.historyScrollState)
    }
    
    func withUpdatedReplyMessageId(_ replyMessageId: MessageId?) -> ChatInterfaceState {
        return ChatInterfaceState(timestamp: self.timestamp, inputState: self.inputState, replyMessageId: replyMessageId, forwardMessageIds: self.forwardMessageIds, messageActionsState:self.messageActionsState, dismissedPinnedMessageId: self.dismissedPinnedMessageId, composeDisableUrlPreview: self.composeDisableUrlPreview, historyScrollState: self.historyScrollState)
    }
    
    func withUpdatedForwardMessageIds(_ forwardMessageIds: [MessageId]) -> ChatInterfaceState {
        return ChatInterfaceState(timestamp: self.timestamp, inputState: self.inputState, replyMessageId: self.replyMessageId, forwardMessageIds: forwardMessageIds, messageActionsState:self.messageActionsState, dismissedPinnedMessageId: self.dismissedPinnedMessageId, composeDisableUrlPreview: self.composeDisableUrlPreview, historyScrollState: self.historyScrollState)
    }
    
    func withoutForwardMessages() -> ChatInterfaceState {
        return ChatInterfaceState(timestamp: self.timestamp, inputState: self.inputState, replyMessageId: self.replyMessageId, forwardMessageIds: [], messageActionsState:self.messageActionsState, dismissedPinnedMessageId: self.dismissedPinnedMessageId, composeDisableUrlPreview: self.composeDisableUrlPreview, historyScrollState: self.historyScrollState)
    }
    
    func withUpdatedTimestamp(_ timestamp: Int32) -> ChatInterfaceState {
        return ChatInterfaceState(timestamp: timestamp, inputState: self.inputState, replyMessageId: self.replyMessageId, forwardMessageIds: self.forwardMessageIds, messageActionsState:self.messageActionsState, dismissedPinnedMessageId: self.dismissedPinnedMessageId, composeDisableUrlPreview: self.composeDisableUrlPreview, historyScrollState: self.historyScrollState)
    }
    
    
    func withUpdatedMessageActionsState(_ f: (ChatInterfaceMessageActionsState) -> ChatInterfaceMessageActionsState) -> ChatInterfaceState {
        return ChatInterfaceState(timestamp: self.timestamp, inputState: self.inputState, replyMessageId: self.replyMessageId, forwardMessageIds: self.forwardMessageIds, messageActionsState:f(self.messageActionsState), dismissedPinnedMessageId: self.dismissedPinnedMessageId, composeDisableUrlPreview: self.composeDisableUrlPreview, historyScrollState: self.historyScrollState)
    }
    
    func withUpdatedComposeDisableUrlPreview(_ disableUrlPreview: String?) -> ChatInterfaceState {
        return ChatInterfaceState(timestamp: self.timestamp, inputState: self.inputState, replyMessageId: self.replyMessageId, forwardMessageIds: self.forwardMessageIds, messageActionsState: self.messageActionsState, dismissedPinnedMessageId: self.dismissedPinnedMessageId, composeDisableUrlPreview: disableUrlPreview, historyScrollState: self.historyScrollState)
    }
    
    func withUpdatedHistoryScrollState(_ historyScrollState: ChatInterfaceHistoryScrollState?) -> ChatInterfaceState {
        return ChatInterfaceState(timestamp: self.timestamp, inputState: self.inputState, replyMessageId: self.replyMessageId, forwardMessageIds: self.forwardMessageIds, messageActionsState: self.messageActionsState, dismissedPinnedMessageId: self.dismissedPinnedMessageId, composeDisableUrlPreview: self.composeDisableUrlPreview, historyScrollState: historyScrollState)
    }
    
    
}
