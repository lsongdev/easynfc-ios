//
//  NFCService.swift
//  EasyNFC
//
//  Created by Lsong on 2/28/25.
//
import CoreNFC
import SwiftUI

// MARK: - NFC Error
enum NFCServiceError: Error, LocalizedError {
    case deviceNotSupported
    case noRecordsToWrite
    case tagNotWritable
    case readFailed(Error)
    case writeFailed(Error)
    case connectionFailed(Error)
    case userCanceled
    case tagNotSupported
    
    var errorDescription: String? {
        switch self {
        case .deviceNotSupported:
            return "NFC is not available on this device. NFC is only supported on iPhone 7 and newer iPhone models."
        case .noRecordsToWrite:
            return "No valid records to write to the tag."
        case .tagNotWritable:
            return "This tag is read-only and cannot be written to."
        case .readFailed(let error):
            return "Failed to read tag: \(error.localizedDescription)"
        case .writeFailed(let error):
            return "Failed to write to tag: \(error.localizedDescription)"
        case .connectionFailed(let error):
            return "Failed to connect to tag: \(error.localizedDescription)"
        case .userCanceled:
            return "Operation canceled by user."
        case .tagNotSupported:
            return "This tag type is not supported."
        }
    }
}

// MARK: - NFC Service
@available(iOS 15.0, *)
class NFCService: NSObject {
    
    // MARK: - Singleton
    static let shared = NFCService()
    
    // MARK: - Private properties
    private var ndefReaderSession: NFCNDEFReaderSession?
    private var tagReaderSession: NFCTagReaderSession?
    private var writeRecords: [NFCRecord] = []
    
    // For async/await support
    private var readContinuation: CheckedContinuation<NFCTag, Error>?
    private var writeContinuation: CheckedContinuation<Void, Error>?
    
    // MARK: - Initialization
    private override init() {
        super.init()
    }
    
    // MARK: - Public methods
    
    /// Check if the device supports NFC
    /// - Returns: Whether NFC is available
    func isNFCAvailable() -> Bool {
        return NFCNDEFReaderSession.readingAvailable
    }
    
    /// Start reading an NFC tag
    /// - Returns: The read NFC tag
    /// - Throws: NFCServiceError if an error occurs during reading
    func read() async throws -> NFCTag {
        guard isNFCAvailable() else {
            throw NFCServiceError.deviceNotSupported
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            self.readContinuation = continuation
            startTagReaderSession(with: "Hold your iPhone near an NFC tag")
        }
    }
    
    /// Write data to an NFC tag
    /// - Parameter records: Array of NFC records to write
    /// - Throws: NFCServiceError if an error occurs during writing
    func write(records: [NFCRecord]) async throws {
        guard isNFCAvailable() else {
            throw NFCServiceError.deviceNotSupported
        }
        
        guard !records.isEmpty else {
            throw NFCServiceError.noRecordsToWrite
        }
        
        writeRecords = records
        
        try await withCheckedThrowingContinuation { continuation in
            self.writeContinuation = continuation
            startNDEFReaderSession(with: "Hold your iPhone near an NFC tag to write")
        }
    }
    
    // MARK: - Private methods
    
    /// Start an NFC NDEF reader session (for writing)
    /// - Parameter message: Message to display to the user
    private func startNDEFReaderSession(with message: String) {
        ndefReaderSession = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: false)
        ndefReaderSession?.alertMessage = message
        ndefReaderSession?.begin()
    }
    
    /// Start an NFC tag reader session (for reading)
    /// - Parameter message: Message to display to the user
    private func startTagReaderSession(with message: String) {
        tagReaderSession = NFCTagReaderSession(pollingOption: [.iso14443, .iso15693, .iso18092], delegate: self, queue: nil)
        tagReaderSession?.alertMessage = message
        tagReaderSession?.begin()
    }
    
    /// Handle error
    /// - Parameter error: Error object
    private func handleError(_ error: Error) {
        // If we have a continuation, resume with error
        if let continuation = self.readContinuation {
            self.readContinuation = nil
            continuation.resume(throwing: error)
        } else if let continuation = self.writeContinuation {
            self.writeContinuation = nil
            continuation.resume(throwing: error)
        }
    }
    
    /// Read NFC tag information
    /// - Parameters:
    ///   - tag: NFC tag
    ///   - session: NFC session
    ///   - completion: Completion callback, returns the parsed NFCTag object
    private func readTag(_ tag: NFCNDEFTag, session: NFCNDEFReaderSession, completion: @escaping (NFCTag) -> Void) {
        // Create basic tag data
        var nfcTag = NFCTag(identifier: Data())
        
        // Set identifier (this part is synchronous)
        nfcTag.identifier = extractTagIdentifier(from: tag)
        // 根据具体的标签类型设置 ISO 标准和标签家族
        if let mifareTag = tag as? NFCMiFareTag {
            nfcTag.isoStandard = "ISO 14443-A"
            
            if mifareTag.mifareFamily == .desfire {
                nfcTag.tagFamily = "MIFARE DESFire"
            } else if mifareTag.mifareFamily == .ultralight {
                nfcTag.tagFamily = "MIFARE Ultralight"
            } else if mifareTag.mifareFamily == .plus {
                nfcTag.tagFamily = "MIFARE Plus"
            } else {
                nfcTag.tagFamily = "MIFARE Classic"
            }
        } else if tag is NFCISO15693Tag {
            nfcTag.isoStandard = "ISO 15693"
        } else if let iso7816Tag = tag as? NFCISO7816Tag {
            nfcTag.isoStandard = "ISO 7816"
            
            if let historicalBytes = iso7816Tag.historicalBytes, !historicalBytes.isEmpty {
                nfcTag.tagFamily = "EMV/银行卡"
            }
        } else if tag is NFCFeliCaTag {
            nfcTag.isoStandard = "ISO 18092"
            nfcTag.tagFamily = "FeliCa"
        }
        
        // Query NDEF status (asynchronous operation)
        tag.queryNDEFStatus { [weak self] status, capacity, error in
            guard let self = self else { return }
            
            if let error = error {
                session.invalidate(errorMessage: "Failed to query tag: \(error.localizedDescription)")
                self.handleError(NFCServiceError.readFailed(error))
                return
            }
            
            switch status {
            case .notSupported:
                session.invalidate(errorMessage: "Tag doesn't support NDEF format")
                self.handleError(NFCServiceError.readFailed(NSError(domain: "NFCService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Tag doesn't support NDEF format"])))
                return
            case .readOnly:
                nfcTag.isWritable = false
            case .readWrite:
                nfcTag.isWritable = true
            @unknown default:
                session.invalidate(errorMessage: "Unknown tag status")
                self.handleError(NFCServiceError.readFailed(NSError(domain: "NFCService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unknown tag status"])))
                return
            }
            
            nfcTag.memorySize = capacity
            
            // After asynchronous operation completes, pass the complete tag information to the callback
            completion(nfcTag)
        }
    }
    
    /// Extract identifier from different types of NFC tags
    /// - Parameter tag: NFC tag
    /// - Returns: Tag identifier data
    private func extractTagIdentifier(from tag: NFCNDEFTag) -> Data {
        if let mifare = tag as? NFCMiFareTag {
            return mifare.identifier
        } else if let iso15693 = tag as? NFCISO15693Tag {
            return iso15693.identifier
        } else if let iso7816 = tag as? NFCISO7816Tag {
            return iso7816.identifier
        } else if let felica = tag as? NFCFeliCaTag {
            return felica.currentIDm
        }
        return Data()
    }
    
    /// Process a detected tag from NFCTagReaderSession
    /// - Parameters:
    ///   - tag: The detected tag
    ///   - session: The tag reader session
    private func processDetectedTag(_ tag: CoreNFC.NFCTag, session: NFCTagReaderSession) {
        var nfcTagModel = NFCTag(identifier: Data())
        
        switch tag {
        case let .miFare(mifareTag):
            nfcTagModel.identifier = mifareTag.identifier
            // 设置 ISO 标准和标签家族
            nfcTagModel.isoStandard = "ISO 14443-A"
            if mifareTag.mifareFamily == .desfire {
                nfcTagModel.tagFamily = "MIFARE DESFire"
            } else if mifareTag.mifareFamily == .ultralight {
                nfcTagModel.tagFamily = "MIFARE Ultralight"
            } else if mifareTag.mifareFamily == .plus {
                nfcTagModel.tagFamily = "MIFARE Plus"
            } else {
                nfcTagModel.tagFamily = "MIFARE Classic"
            }
            
            // The correct way to convert a MiFare tag to an NDEF tag
            mifareTag.queryNDEFStatus { (status, capacity, error) in
                if let error = error {
                    session.invalidate(errorMessage: "Failed to query tag: \(error.localizedDescription)")
                    self.handleError(NFCServiceError.readFailed(error))
                    return
                }
                
                // Update tag properties based on NDEF status
                switch status {
                case .notSupported:
                    // Even if NDEF is not supported, we still have the identifier
                    session.alertMessage = "Tag read successfully (no NDEF support)"
                    session.invalidate()
                    
                    if let continuation = self.readContinuation {
                        self.readContinuation = nil
                        continuation.resume(returning: nfcTagModel)
                    }
                    return
                    
                case .readOnly:
                    nfcTagModel.isWritable = false
                case .readWrite:
                    nfcTagModel.isWritable = true
                @unknown default:
                    session.invalidate(errorMessage: "Unknown tag status")
                    self.handleError(NFCServiceError.readFailed(NSError(domain: "NFCService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unknown tag status"])))
                    return
                }
                
                nfcTagModel.memorySize = capacity
                
                // Read NDEF message if available
                mifareTag.readNDEF { [weak self] (message, error) in
                    guard let self = self else { return }
                    
                    if let error = error {
                        // If there's no NDEF data, we can still return the tag with its identifier
                        if let ndefError = error as? NFCReaderError,
                           ndefError.code == .ndefReaderSessionErrorTagNotWritable {
                            session.alertMessage = "Tag read successfully (no NDEF data)"
                            session.invalidate()
                            
                            if let continuation = self.readContinuation {
                                self.readContinuation = nil
                                continuation.resume(returning: nfcTagModel)
                            }
                            return
                        } else {
                            session.invalidate(errorMessage: "Read failed: \(error.localizedDescription)")
                            self.handleError(NFCServiceError.readFailed(error))
                            return
                        }
                    }
                    
                    // Parse NDEF message records
                    if let message = message {
                        for record in message.records {
                            let nfcRecord = NFCRecord(from: record)
                            nfcTagModel.records.append(nfcRecord)
                        }
                    }
                    
                    // Complete the read operation
                    session.alertMessage = "Tag read successfully"
                    session.invalidate()
                    
                    // Resume continuation with the tag
                    if let continuation = self.readContinuation {
                        self.readContinuation = nil
                        continuation.resume(returning: nfcTagModel)
                    }
                }
            }
            
        case let .iso15693(iso15693Tag):
            nfcTagModel.identifier = iso15693Tag.identifier
            nfcTagModel.isoStandard = "ISO 15693"
            
            iso15693Tag.queryNDEFStatus { (status, capacity, error) in
                if let error = error {
                    session.invalidate(errorMessage: "Failed to query tag: \(error.localizedDescription)")
                    self.handleError(NFCServiceError.readFailed(error))
                    return
                }
                
                var updatedTag = nfcTagModel
                
                // Update tag properties
                switch status {
                case .notSupported:
                    // Even if NDEF is not supported, we still have the identifier
                    session.alertMessage = "Tag read successfully (no NDEF support)"
                    session.invalidate()
                    
                    if let continuation = self.readContinuation {
                        self.readContinuation = nil
                        continuation.resume(returning: updatedTag)
                    }
                    return
                    
                case .readOnly:
                    updatedTag.isWritable = false
                case .readWrite:
                    updatedTag.isWritable = true
                @unknown default:
                    session.invalidate(errorMessage: "Unknown tag status")
                    self.handleError(NFCServiceError.readFailed(NSError(domain: "NFCService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unknown tag status"])))
                    return
                }
                
                updatedTag.memorySize = capacity
                
                // Read NDEF message
                iso15693Tag.readNDEF { [weak self] (message, error) in
                    guard let self = self else { return }
                    
                    if let error = error {
                        // If there's no NDEF data, we can still return the tag with its identifier
                        if let ndefError = error as? NFCReaderError,
                           ndefError.code == .ndefReaderSessionErrorTagNotWritable {
                            session.alertMessage = "Tag read successfully (no NDEF data)"
                            session.invalidate()
                            
                            if let continuation = self.readContinuation {
                                self.readContinuation = nil
                                continuation.resume(returning: updatedTag)
                            }
                            return
                        } else {
                            session.invalidate(errorMessage: "Read failed: \(error.localizedDescription)")
                            self.handleError(NFCServiceError.readFailed(error))
                            return
                        }
                    }
                    
                    // Parse NDEF message records
                    if let message = message {
                        for record in message.records {
                            let nfcRecord = NFCRecord(from: record)
                            updatedTag.records.append(nfcRecord)
                        }
                    }
                    
                    // Complete the read operation
                    session.alertMessage = "Tag read successfully"
                    session.invalidate()
                    
                    // Resume continuation with the tag
                    if let continuation = self.readContinuation {
                        self.readContinuation = nil
                        continuation.resume(returning: updatedTag)
                    }
                }
            }
            
        case let .iso7816(iso7816Tag):
            nfcTagModel.identifier = iso7816Tag.identifier
            nfcTagModel.isoStandard = "ISO 7816"
            
            if let historicalBytes = iso7816Tag.historicalBytes, !historicalBytes.isEmpty {
                nfcTagModel.tagFamily = "EMV/银行卡"
            }
            
            iso7816Tag.queryNDEFStatus { (status, capacity, error) in
                if let error = error {
                    session.invalidate(errorMessage: "Failed to query tag: \(error.localizedDescription)")
                    self.handleError(NFCServiceError.readFailed(error))
                    return
                }
                
                var updatedTag = nfcTagModel
                
                // Update tag properties
                switch status {
                case .notSupported:
                    // Even if NDEF is not supported, we still have the identifier
                    session.alertMessage = "Tag read successfully (no NDEF support)"
                    session.invalidate()
                    
                    if let continuation = self.readContinuation {
                        self.readContinuation = nil
                        continuation.resume(returning: updatedTag)
                    }
                    return
                    
                case .readOnly:
                    updatedTag.isWritable = false
                case .readWrite:
                    updatedTag.isWritable = true
                @unknown default:
                    session.invalidate(errorMessage: "Unknown tag status")
                    self.handleError(NFCServiceError.readFailed(NSError(domain: "NFCService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unknown tag status"])))
                    return
                }
                
                updatedTag.memorySize = capacity
                
                // Read NDEF message
                iso7816Tag.readNDEF { [weak self] (message, error) in
                    guard let self = self else { return }
                    
                    if let error = error {
                        // If there's no NDEF data, we can still return the tag with its identifier
                        if let ndefError = error as? NFCReaderError,
                           ndefError.code == .ndefReaderSessionErrorTagNotWritable {
                            session.alertMessage = "Tag read successfully (no NDEF data)"
                            session.invalidate()
                            
                            if let continuation = self.readContinuation {
                                self.readContinuation = nil
                                continuation.resume(returning: updatedTag)
                            }
                            return
                        } else {
                            session.invalidate(errorMessage: "Read failed: \(error.localizedDescription)")
                            self.handleError(NFCServiceError.readFailed(error))
                            return
                        }
                    }
                    
                    // Parse NDEF message records
                    if let message = message {
                        for record in message.records {
                            let nfcRecord = NFCRecord(from: record)
                            updatedTag.records.append(nfcRecord)
                        }
                    }
                    
                    // Complete the read operation
                    session.alertMessage = "Tag read successfully"
                    session.invalidate()
                    
                    // Resume continuation with the tag
                    if let continuation = self.readContinuation {
                        self.readContinuation = nil
                        continuation.resume(returning: updatedTag)
                    }
                }
            }
            
        case let .feliCa(felicaTag):
            nfcTagModel.identifier = felicaTag.currentIDm
            nfcTagModel.isoStandard = "ISO 18092"
            nfcTagModel.tagFamily = "FeliCa"
            
            felicaTag.queryNDEFStatus { (status, capacity, error) in
                if let error = error {
                    session.invalidate(errorMessage: "Failed to query tag: \(error.localizedDescription)")
                    self.handleError(NFCServiceError.readFailed(error))
                    return
                }
                
                var updatedTag = nfcTagModel
                
                // Update tag properties
                switch status {
                case .notSupported:
                    // Even if NDEF is not supported, we still have the identifier
                    session.alertMessage = "Tag read successfully (no NDEF support)"
                    session.invalidate()
                    
                    if let continuation = self.readContinuation {
                        self.readContinuation = nil
                        continuation.resume(returning: updatedTag)
                    }
                    return
                    
                case .readOnly:
                    updatedTag.isWritable = false
                case .readWrite:
                    updatedTag.isWritable = true
                @unknown default:
                    session.invalidate(errorMessage: "Unknown tag status")
                    self.handleError(NFCServiceError.readFailed(NSError(domain: "NFCService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unknown tag status"])))
                    return
                }
                
                updatedTag.memorySize = capacity
                
                // Read NDEF message
                felicaTag.readNDEF { [weak self] (message, error) in
                    guard let self = self else { return }
                    
                    if let error = error {
                        // If there's no NDEF data, we can still return the tag with its identifier
                        if let ndefError = error as? NFCReaderError,
                           ndefError.code == .ndefReaderSessionErrorTagNotWritable {
                            session.alertMessage = "Tag read successfully (no NDEF data)"
                            session.invalidate()
                            
                            if let continuation = self.readContinuation {
                                self.readContinuation = nil
                                continuation.resume(returning: updatedTag)
                            }
                            return
                        } else {
                            session.invalidate(errorMessage: "Read failed: \(error.localizedDescription)")
                            self.handleError(NFCServiceError.readFailed(error))
                            return
                        }
                    }
                    
                    // Parse NDEF message records
                    if let message = message {
                        for record in message.records {
                            let nfcRecord = NFCRecord(from: record)
                            updatedTag.records.append(nfcRecord)
                        }
                    }
                    
                    // Complete the read operation
                    session.alertMessage = "Tag read successfully"
                    session.invalidate()
                    
                    // Resume continuation with the tag
                    if let continuation = self.readContinuation {
                        self.readContinuation = nil
                        continuation.resume(returning: updatedTag)
                    }
                }
            }
            
        @unknown default:
            session.invalidate(errorMessage: "Unsupported tag type")
            self.handleError(NFCServiceError.tagNotSupported)
        }
    }
}

// MARK: - NFC NDEF Session Delegate
@available(iOS 15.0, *)
extension NFCService: NFCNDEFReaderSessionDelegate {
    func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {
        // Session activated, add code if needed
    }
    
    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        // Implement NDEF message detection (compatibility)
        // Note: Modern implementations typically use the didDetect tags method
    }
    
    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        // Filter user cancel error
        if let readerError = error as? NFCReaderError,
           readerError.code == .readerSessionInvalidationErrorUserCanceled {
            // User canceled
            if let continuation = self.readContinuation {
                self.readContinuation = nil
                continuation.resume(throwing: NFCServiceError.userCanceled)
            } else if let continuation = self.writeContinuation {
                self.writeContinuation = nil
                continuation.resume(throwing: NFCServiceError.userCanceled)
            }
        } else {
            // Other errors
            handleError(error)
        }
    }
    
    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        // Multiple tags detected
        if tags.count > 1 {
            session.alertMessage = "Multiple tags detected. Please present only one tag."
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(500)) {
                session.restartPolling()
            }
            return
        }
        guard let tag = tags.first else { return }
        session.connect(to: tag) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                session.invalidate(errorMessage: "Connection error: \(error.localizedDescription)")
                self.handleError(NFCServiceError.connectionFailed(error))
                return
            }
            
            // Process tag for writing (NDEF session is only used for writing in this implementation)
            self.processTagForWriting(tag, session: session)
        }
    }
    
    /// Process tag for writing operation
    /// - Parameters:
    ///   - tag: NFC tag
    ///   - session: NFC session
    private func processTagForWriting(_ tag: NFCNDEFTag, session: NFCNDEFReaderSession) {
        // Read basic tag information (asynchronous)
        readTag(tag, session: session) { [weak self] nfcTag in
            guard let self = self else { return }
            
            // Check if tag is writable
            guard nfcTag.isWritable ?? false else {
                session.invalidate(errorMessage: "Tag is read-only")
                self.handleError(NFCServiceError.tagNotWritable)
                return
            }
            
            // Create and write NDEF message
            var ndefRecords: [NFCNDEFPayload] = []
            for record in self.writeRecords {
                if let payload = record.createNDEFPayload() {
                    ndefRecords.append(payload)
                }
            }
            let message = NFCNDEFMessage(records: ndefRecords)
            
            // Check if there are valid records
            guard !message.records.isEmpty else {
                session.invalidate(errorMessage: "No valid records to write")
                self.handleError(NFCServiceError.noRecordsToWrite)
                return
            }
            
            // Write NDEF message (asynchronous)
            tag.writeNDEF(message) { [weak self] error in
                guard let self = self else { return }

                if let error = error {
                    session.invalidate(errorMessage: "Write failed: \(error.localizedDescription)")
                    self.handleError(NFCServiceError.writeFailed(error))
                } else {
                    session.alertMessage = "Successfully wrote to tag"
                    session.invalidate()
                    
                    // Resume continuation if available
                    if let continuation = self.writeContinuation {
                        self.writeContinuation = nil
                        continuation.resume(returning: ())
                    }
                }
            }
        }
    }
}

// MARK: - NFC Tag Reader Session Delegate
@available(iOS 15.0, *)
extension NFCService: NFCTagReaderSessionDelegate {
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        // Session became active
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        // Handle session invalidation
        if let readerError = error as? NFCReaderError,
           readerError.code == .readerSessionInvalidationErrorUserCanceled {
            // User canceled
            if let continuation = self.readContinuation {
                self.readContinuation = nil
                continuation.resume(throwing: NFCServiceError.userCanceled)
            }
        } else {
            // Other errors
            handleError(error)
        }
    }
    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [CoreNFC.NFCTag]) {
        // Multiple tags detected
        if tags.count > 1 {
            session.alertMessage = "Multiple tags detected. Please present only one tag."
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(500)) {
                session.restartPolling()
            }
            return
        }
        
        guard let tag = tags.first else { return }
        
        // Connect to the tag
        session.connect(to: tag) { [weak self] error in
            guard let self = self else { return }
            
            if let error = error {
                session.invalidate(errorMessage: "Connection error: \(error.localizedDescription)")
                self.handleError(NFCServiceError.connectionFailed(error))
                return
            }
            
            // Process the detected tag
            self.processDetectedTag(tag, session: session)
        }
    }
}
