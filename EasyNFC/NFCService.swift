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
        tagReaderSession = NFCTagReaderSession(pollingOption: [.iso14443, .iso15693, .iso18092, .pace], delegate: self, queue: nil)
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
    
    // MARK: - Private methods
    
    /// Asynchronously query the NDEF status of a tag
    /// - Parameter tag: The NFC NDEF tag to query
    /// - Returns: A tuple containing the status and capacity of the tag
    /// - Throws: NFCServiceError if an error occurs during the query
    private func queryNDEFStatusAsync(tag: NFCNDEFTag) async throws -> (status: NFCNDEFStatus, capacity: Int) {
        return try await withCheckedThrowingContinuation { continuation in
            tag.queryNDEFStatus { status, capacity, error in
                if let error = error {
                    continuation.resume(throwing: NFCServiceError.readFailed(error))
                    return
                }
                continuation.resume(returning: (status, capacity))
            }
        }
    }
    
    /// Read NFC tag information asynchronously
    /// - Parameters:
    ///   - tag: NFC tag
    ///   - session: NFC session
    /// - Returns: The parsed NFCTag object
    /// - Throws: NFCServiceError if an error occurs during reading
    private func readDEFTagAsync(_ tag: NFCNDEFTag, session: NFCReaderSession) async throws -> NFCTag {
        // Create basic tag data
        var nfcTag = NFCTag()
        if let mifareTag = tag as? NFCMiFareTag {
            nfcTag.id = mifareTag.identifier
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
        } else if let iso15693 = tag as? NFCISO15693Tag {
            nfcTag.id = iso15693.identifier
            nfcTag.isoStandard = "ISO 15693"
        } else if let iso7816Tag = tag as? NFCISO7816Tag {
            nfcTag.id = iso7816Tag.identifier
            nfcTag.isoStandard = "ISO 7816"
            if let historicalBytes = iso7816Tag.historicalBytes, !historicalBytes.isEmpty {
                nfcTag.tagFamily = "EMV/银行卡"
            }
        } else if let felica = tag as? NFCFeliCaTag {
            nfcTag.id = felica.currentIDm
            nfcTag.isoStandard = "ISO 18092"
            nfcTag.tagFamily = "FeliCa"
        }
//        else {
//            print("NFCServiceError.tagNotSupported", tag.isAvailable)
//            session.invalidate(errorMessage: "Tag type not supported")
//            throw NFCServiceError.tagNotSupported
//        }
        
        // Query NDEF status using the async wrapper
        do {
            let (status, capacity) = try await queryNDEFStatusAsync(tag: tag)
            switch status {
            case .notSupported:
                session.invalidate(errorMessage: "Tag doesn't support NDEF format")
                throw NFCServiceError.readFailed(NSError(domain: "NFCService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Tag doesn't support NDEF format"]))
            case .readOnly:
                nfcTag.isWritable = false
            case .readWrite:
                nfcTag.isWritable = true
            @unknown default:
                session.invalidate(errorMessage: "Unknown tag status")
                throw NFCServiceError.readFailed(NSError(domain: "NFCService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unknown tag status"]))
            }
            nfcTag.memorySize = capacity
            return nfcTag
        } catch {
            session.invalidate(errorMessage: "Failed to query tag: \(error.localizedDescription)")
            throw NFCServiceError.readFailed(error)
        }
    }
    
    func readNDEFMessage(tag: NFCNDEFTag, session: NFCReaderSession) async throws -> [NFCRecord] {
        var records: [NFCRecord] = []
        return try await withCheckedThrowingContinuation { continuation in
            // Read NDEF message if available
            tag.readNDEF { [weak self] (message, error) in
                guard let self = self else { return }
                
                if let error = error {
                    // If there's no NDEF data, we can still return the tag with its identifier
                    if let ndefError = error as? NFCReaderError,
                       ndefError.code == .ndefReaderSessionErrorTagNotWritable {
                        session.alertMessage = "Tag read successfully (no NDEF data)"
                        session.invalidate()
                        
                        continuation.resume(returning: records)
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
                        records.append(nfcRecord)
                    }
                }
                
                // Complete the read operation
                session.alertMessage = "Tag read successfully"
                session.invalidate()
                
                // Resume continuation with the tag
                continuation.resume(returning: records)
            }
        }
    }

    /// Process a detected tag from NFCTagReaderSession
    /// - Parameters:
    ///   - tag: The detected tag
    ///   - session: The tag reader session
    private func processTagForReading(_ tag: CoreNFC.NFCTag, session: NFCTagReaderSession) async throws -> NFCTag {
        switch tag {
        case let .miFare(mifare):
            var nfcTag = try await readDEFTagAsync(mifare, session: session)
            nfcTag.records = try await readNDEFMessage(tag: mifare, session: session)
            return nfcTag
        case let .feliCa(felica):
            var nfcTag = try await readDEFTagAsync(felica, session: session)
            nfcTag.records = try await readNDEFMessage(tag: felica, session: session)
            return nfcTag
        case let .iso7816(iso7816):
            var nfcTag = try await readDEFTagAsync(iso7816, session: session)
            nfcTag.records = try await readNDEFMessage(tag: iso7816, session: session)
            return nfcTag
        case let .iso15693(iso15693):
            var nfcTag = try await readDEFTagAsync(iso15693, session: session)
            nfcTag.records = try await readNDEFMessage(tag: iso15693, session: session)
            return nfcTag
        @unknown default:
            throw NFCServiceError.tagNotSupported
        }
    }
    
    /// Process tag for writing operation
    /// - Parameters:
    ///   - tag: NFC tag
    ///   - session: NFC session
    private func processTagForWriting(_ tag: NFCNDEFTag, session: NFCNDEFReaderSession) async throws {
        // Read basic tag information
        let nfcTag = try await readDEFTagAsync(tag, session: session)
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
            
            Task {
                // Process tag for writing (NDEF session is only used for writing in this implementation)
                try await self.processTagForWriting(tag, session: session)
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
            Task {
                do {
                    let nfcTag = try await self.processTagForReading(tag, session: session)
                    session.alertMessage = "Tag read successfully"
                    session.invalidate()
                    
                    if let continuation = self.readContinuation {
                        self.readContinuation = nil
                        continuation.resume(returning: nfcTag)
                    }
                } catch {
                    session.invalidate(errorMessage: "Processing error: \(error.localizedDescription)")
                    self.handleError(error)
                }
            }
        }
    }
}
