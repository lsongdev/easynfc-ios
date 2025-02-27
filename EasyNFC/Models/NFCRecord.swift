//
//  NFCRecord.swift
//  EasyNFC
//
//  Created by Lsong on 2/28/25.
//
import CoreNFC
import SwiftUI

struct NFCRecord: Identifiable, Codable {
    var id = UUID()
    var format: UInt8 = 0
    var type: String = "T"
    var identifier: Data = Data()
    var payload: Data = Data()
    
    var displayType: String {
        switch type {
        case "T": return "Text"
        case "U": return "URL"
        default:
            return "Unknown"
        }
    }
    
    var displayContent: String {
        switch displayType {
        case "Text":
            let (content, _) = NFCTag.parseTextPayload(payload)!
            return content
        case "URL":
            return NFCTag.parseURIPayload(payload)!
        default:
            return "<unknown>"
        }
    }
    
    init() {}
    init(from record: NFCNDEFPayload) {
        self.type = String(data: record.type, encoding: .utf8)!
        self.format = record.typeNameFormat.rawValue
        self.identifier = record.identifier
        self.payload = record.payload
    }
    
    // CodingKeys to exclude computed properties
    enum CodingKeys: String, CodingKey {
        case id, format, type, identifier, payload
    }
    
    mutating func wirteEmpty() {
        self.format = NFCTypeNameFormat.empty.rawValue
    }
    
    mutating func writeText(_ content: String, language: String = "en") {
        self.type = "T"
        self.format = NFCTypeNameFormat.nfcWellKnown.rawValue
        self.payload = NFCTag.createTextPayload(text: content, languageCode: language)
    }
    
    mutating func writeLink(_ link: String) {
        self.type = "U"
        self.format = NFCTypeNameFormat.nfcWellKnown.rawValue
        self.payload = NFCTag.createURIPayload(uri: link)
    }
    
    mutating func writeMedia(_ content: String) {
        self.payload = content.data(using: .utf8)!
        self.format = NFCTypeNameFormat.media.rawValue
    }
    
    var displayFormat: String {
        let typeFormat = NFCTypeNameFormat(rawValue: UInt8(format)) ?? .unknown
        switch typeFormat {
        case .empty: return "Empty"
        case .nfcWellKnown: return "NFC Well Known"
        case .media: return "Media"
        case .absoluteURI: return "Absolute URI"
        case .nfcExternal: return "NFC External"
        case .unknown: return "Unknown"
        case .unchanged: return "Unchanged"
        @unknown default: return "Undefined"
        }
    }
    // 创建 NDEF 负载
    func createNDEFPayload() -> NFCNDEFPayload? {
        guard let typeFormat = NFCTypeNameFormat(rawValue: format) else {
            return nil
        }
        
        return NFCNDEFPayload(
            format: typeFormat,
            type: type.data(using: .utf8)!, // "T"
            identifier: identifier,
            payload: payload
        )
    }
}
