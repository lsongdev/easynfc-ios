//
//  NFCTagDetailView.swift
//  EasyNFC
//
//  Created by Lsong on 2/28/25.
//
import SwiftUI
import SwiftUIX

// MARK: - Tag Detail View

struct NFCTagView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appManager: AppManager
    @State private var showingAddRecord: Bool = false
    @State private var tag: NFCTag
    @State private var showingExport: Bool = false
    
    private var nfcService = NFCService.shared
    
    // Initialize with a tag
    init(tag: NFCTag = NFCTag()) {
        _tag = State(initialValue: tag)
    }
    
    var body: some View {
        List {
            Section("Information") {
                InputField("Name", text: $tag.name)
                if !tag.serialNumber.isEmpty {
                    LabeledText(label: "Identifier", value: tag.serialNumber)
                }
                if !tag.isoStandard.isEmpty {
                    LabeledText(label: "Specification", value: tag.specification)
                }
                if !tag.tagFamily.isEmpty {
                    LabeledText(label: "Family", value: tag.family)
                }
                if !tag.manufacturer.isEmpty {
                    LabeledText(label: "Manufacturer", value: tag.manufacturer)
                }
                if tag.memorySize > 0 {
                    LabeledText(label: "Memory Size", value: "\(tag.memorySize) bytes")
                }
                LabeledText(label: "Used Space", value: "\(tag.usedSize) bytes")
                if let isWritable = tag.isWritable {
                    LabeledText(label: "Writable", value:  isWritable ? "Yes" : "No", valueColor: isWritable ? .green : .red)
                }
                
            }
            
            Section(header: HStack {
                Text("Records (\(tag.records.count))")
                Spacer()
                Button {
                    showingAddRecord = true
                } label: {
                    Image(systemName: "plus")
                }
            }) {
                ForEach(tag.records) { record in
                    NavigationLink(destination: RecordDetailView(record: record)) {
                        recordRow(record: record)
                    }
                }
                .onDelete { index in
                    tag.records.remove(atOffsets: index)
                }
                
                if tag.records.isEmpty {
                    Text("No records found")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                }
            }
            
            Section {
                Button {
                    writeToTag()
                } label: {
                    Label("Write to Tag", systemImage: "pencil")
                }
                .disabled(tag.records.isEmpty)
                Button {
                    showingExport = true
                } label: {
                    Label("Export to file", systemImage: "arrowshape.turn.up.right")
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationTitle(tag.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarItems(leading: cancelButton, trailing: saveButton)
        .sheet(isPresented: $showingAddRecord) {
            NFCRecordEditorView(
                onSave: { record in
                    tag.records.append(record)
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden)
        }
        .shareFile(
            isPresented: $showingExport,
            document: try! JSONEncoder().encode(tag),
            filename: "\(appManager.appName)-\(tag.name).json"
        )
        .onAppear {
            if tag.name.isEmpty {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyMMdd-HHmmss"
                tag.name = "Tag-\(dateFormatter.string(from: Date()))"
            }
        }
    }
    
    func recordRow(record: NFCRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.displayType)
                .font(.headline)
            Text(record.displayContent.isEmpty ? "<empty>" : record.displayContent)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }
    
    private func saveTag() {
        tag.timestamp = Date()
        appManager.saveTag(tag)
    }
    
    private func writeToTag() {
        Task {
            do {
                try await nfcService.write(records: tag.records)
            } catch let error as NFCServiceError {
                // Handle specific NFC errors
                await MainActor.run {
                    AppManager.shared.showAlert(
                        title: "NFC Error",
                        message: error.localizedDescription
                    )
                }
            } catch {
                // Handle other errors
                await MainActor.run {
                    AppManager.shared.showAlert(
                        title: "Error",
                        message: "An unexpected error occurred: \(error.localizedDescription)"
                    )
                }
            }
        }
    }
    
    var cancelButton: some View {
        Button("Cancel") {
            dismiss()
        }
    }
    var saveButton: some View {
        Button("Save") {
            saveTag()
            dismiss()
        }
        .disabled(tag.name.isEmpty)
    }

}
