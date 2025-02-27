//
//  NFCTag.swift
//  EasyNFC
//
//  Created by Lsong on 2/28/25.
//

import SwiftUI

// MARK: - Data Models

struct NFCTag: Identifiable, Codable {
    var id = UUID()
    // 存储属性
    var name: String = ""
    var identifier: Data = Data()
    var isWritable: Bool? = nil
    var memorySize: Int = 0
    var timestamp: Date = Date()
    var records: [NFCRecord] = []
    
    // 标签信息属性 - 这些将被存储
    var isoStandard: String = ""  // ISO标准，如 "ISO 14443-A", "ISO 15693"
    var tagFamily: String = ""    // 标签家族，如 "MIFARE Classic", "MIFARE DESFire"
    var serialNumber: String {
        return identifier.map { String(format: "%02X", $0) }.joined()
    }
    var usedSize: Int {
        // TODO: records.reduce()
        return 0
    }
    
    var displayTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
    
    // CodingKeys to exclude computed properties
    enum CodingKeys: String, CodingKey {
        case id, name, identifier, isWritable, memorySize, records, timestamp
        case isoStandard, tagFamily
    }
    
    // 从序列号获取制造商信息
    var manufacturer: String {
        guard identifier.count >= 2 else { return "" }
        let manufacturerByte = identifier[0]
        switch manufacturerByte {
        case 0x04: return "NXP Semiconductors"
        case 0x05: return "Infineon"
        case 0x07: return "Texas Instruments"
        case 0x1D: return "Shanghai Fudan Microelectronics"
        case 0x28, 0x38: return "ST Microelectronics"
        case 0x01, 0x02, 0x03: return "Motorola"
        case 0x20: return "Sony"
        case 0x88: return "Atmel"
        case 0xD0: return "Renesas"
        case 0x08: return identifier.count >= 7 && identifier[1] == 0x04 ? "NXP - MIFARE DESFire" : "NXP - MIFARE Family"
        case 0xFE: return "Sony FeliCa"
        default: return "Unknown (\(String(format: "%02X", manufacturerByte)))"
        }
    }
    var specification:String {
        if !isoStandard.isEmpty {
            return isoStandard
        }
        guard identifier.count >= 2 else { return "Unknown" }
        let manufacturerByte = identifier[0]
        switch manufacturerByte {
        case 0x04, 0x05, 0x07, 0x28, 0x38, 0x01, 0x02, 0x03, 0x20, 0x88, 0xD0:
            return "ISO 14443-A"
        case 0x08:
            if identifier.count >= 7 && identifier[1] == 0x04 {
                return "ISO 14443-4"
            } else {
                return "ISO 14443-3"
            }
        case 0x1D:
            return "ISO 14443-4"
        case 0xFE:
            return "ISO 18092"
        default:
            return "Unknown"
        }
    }
    
    // 从序列号获取标签家族信息
    var family: String {
        if !tagFamily.isEmpty {
            return tagFamily
        }
        guard identifier.count >= 2 else { return "Unknown" }
        let manufacturerByte = identifier[0]
        switch manufacturerByte {
        case 0x08:
            if identifier.count >= 7 && identifier[1] == 0x04 {
                return "MIFARE DESFire"
            } else {
                return "MIFARE Classic"
            }
        case 0xFE:
            return "FeliCa"
        case 0x1D:
            if identifier.count >= 2 && identifier[1] == 0x3C {
                return "Fudan FM11RF08"
            }
            return ""
        default:
            return ""
        }
    }
}


extension NFCTag {
    // MARK: - Text Record
    
    /// 解析文本记录负载
    /// - Parameter payload: 负载数据
    /// - Returns: 元组 (文本内容, 语言代码)
    static func parseTextPayload(_ payload: Data) -> (String, String)? {
        guard !payload.isEmpty else { return nil }
        
        // 第一个字节包含状态位和语言代码长度
        let statusByte = payload[0]
        let languageCodeLength = Int(statusByte & 0x3F)
        
        guard payload.count >= 1 + languageCodeLength else { return nil }
        
        // 提取语言代码
        let languageCodeData = payload.subdata(in: 1..<(1 + languageCodeLength))
        guard let languageCode = String(data: languageCodeData, encoding: .utf8) else { return nil }
        
        // 提取文本内容
        let textData = payload.subdata(in: (1 + languageCodeLength)..<payload.count)
        guard let text = String(data: textData, encoding: .utf8) else { return nil }
        
        return (text, languageCode)
    }
    
    /// 创建文本记录负载
    /// - Parameters:
    ///   - text: 文本内容
    ///   - languageCode: 语言代码 (默认为 "en")
    /// - Returns: 负载数据
    static func createTextPayload(text: String, languageCode: String = "en") -> Data {
        var payload = Data()
        
        // 语言代码数据
        guard let languageCodeData = languageCode.data(using: .utf8) else { return Data() }
        
        // 状态字节 (UTF-8 编码 + 语言代码长度)
        let statusByte: UInt8 = UInt8(languageCodeData.count)
        payload.append(statusByte)
        
        // 添加语言代码
        payload.append(languageCodeData)
        
        // 添加文本内容
        if let textData = text.data(using: .utf8) {
            payload.append(textData)
        }
        
        return payload
    }
    
    // MARK: - URI Record
    
    /// URI 前缀代码
    static let uriPrefixes = [
        "", // 0x00
        "http://www.", // 0x01
        "https://www.", // 0x02
        "http://", // 0x03
        "https://", // 0x04
        "tel:", // 0x05
        "mailto:", // 0x06
        "ftp://anonymous:anonymous@", // 0x07
        "ftp://ftp.", // 0x08
        "ftps://", // 0x09
        "sftp://", // 0x0A
        "smb://", // 0x0B
        "nfs://", // 0x0C
        "ftp://", // 0x0D
        "dav://", // 0x0E
        "news:", // 0x0F
        "telnet://", // 0x10
        "imap:", // 0x11
        "rtsp://", // 0x12
        "urn:", // 0x13
        "pop:", // 0x14
        "sip:", // 0x15
        "sips:", // 0x16
        "tftp:", // 0x17
        "btspp://", // 0x18
        "btl2cap://", // 0x19
        "btgoep://", // 0x1A
        "tcpobex://", // 0x1B
        "irdaobex://", // 0x1C
        "file://", // 0x1D
        "urn:epc:id:", // 0x1E
        "urn:epc:tag:", // 0x1F
        "urn:epc:pat:", // 0x20
        "urn:epc:raw:", // 0x21
        "urn:epc:", // 0x22
        "urn:nfc:" // 0x23
    ]
    
    /// 解析 URI 记录负载
    /// - Parameter payload: 负载数据
    /// - Returns: URI 字符串
    static func parseURIPayload(_ payload: Data) -> String? {
        guard payload.count > 0 else { return nil }
        
        // 第一个字节是 URI 标识符代码
        let identifierCode = Int(payload[0])
        
        // 获取 URI 前缀
        let prefix = identifierCode < uriPrefixes.count ? uriPrefixes[identifierCode] : ""
        
        // 获取 URI 内容
        let uriData = payload.subdata(in: 1..<payload.count)
        guard let uri = String(data: uriData, encoding: .utf8) else { return nil }
        
        return prefix + uri
    }
    
    /// 创建 URI 记录负载
    /// - Parameter uri: URI 字符串
    /// - Returns: 负载数据
    static func createURIPayload(uri: String) -> Data {
        var payload = Data()
        
        // 查找匹配的前缀
        var identifierCode: UInt8 = 0
        var uriWithoutPrefix = uri
        
        for (index, prefix) in uriPrefixes.enumerated() where !prefix.isEmpty {
            if uri.hasPrefix(prefix) {
                identifierCode = UInt8(index)
                uriWithoutPrefix = String(uri.dropFirst(prefix.count))
                break
            }
        }
        
        // 添加标识符代码
        payload.append(identifierCode)
        
        // 添加 URI 内容
        if let uriData = uriWithoutPrefix.data(using: .utf8) {
            payload.append(uriData)
        }
        
        return payload
    }
    
    static func createDataPayload() {
        // TODO:
    }
    
    // MARK: - Utilities
    
    /// 将数据转换为十六进制字符串
    /// - Parameter data: 数据
    /// - Returns: 十六进制字符串
    static func dataToHexString(_ data: Data) -> String {
        return data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
