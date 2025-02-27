//
//  RecordDetailView.swift
//  EasyNFC
//
//  Created by Lsong on 2/28/25.
//
import SwiftUI
import SwiftUIX

// 记录详情视图
struct RecordDetailView: View {
    let record: NFCRecord
    
    var body: some View {
        List {
            Section(header: Text("Basic")) {
                LabeledText(label: "Type", value: record.displayType)
                LabeledText(label: "Format", value: record.displayFormat)
                LabeledText(label: "Payload Size", value: "\(record.payload.count) bytes")
            }
            
            Section(header: Text("Content")) {
                VStack(alignment: .leading, spacing: 4) {
                    if record.type == "U" {
                        if let url = URL(string: record.displayContent) {
                            Link(destination: url) {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(record.displayContent)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.right.square")
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding()
                        }
                    } else {
                        Text(record.displayContent)
                            .font(.body)
                            .padding()
                    }
                }
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = record.displayContent
                    } label: {
                        Label("Copy to clipboard", systemImage: "document.on.clipboard")
                    }
                }
            }
            
            Section("Raw") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(data: record.payload, encoding: .utf8)!)
                        .font(.body)
                        .padding()
                    
                    Divider()
                    
                    Text(NFCTag.dataToHexString(record.payload))
                        .font(.body)
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationTitle("Record Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}
