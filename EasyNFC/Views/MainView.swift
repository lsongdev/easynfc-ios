import CoreNFC
import SwiftUI
import SwiftUIX

// MARK: - Main View
struct NFCMainView: View {
    private var nfcService = NFCService.shared
    
    @ObservedObject private var appManager = AppManager.shared
    @State private var showingWelcome = false
    @State private var showCreateSheet = false
    @State private var showingSettings = false
    @State private var searchText = ""
    @State private var scannedTag: NFCTag? = nil
    
    var filteredTags: [NFCTag] {
        if searchText.isEmpty {
            return appManager.savedTags
        }
        return appManager.savedTags.filter { tag in
            tag.serialNumber.lowercased().contains(searchText.lowercased()) ||
            tag.manufacturer.lowercased().contains(searchText.lowercased())
        }
    }
    
    var body: some View {
        NavigationView {
            
            List {
                ForEach(filteredTags) { tag in
                    NavigationLink(destination: NFCTagView(tag: tag)) {
                        tagRow(tag: tag)
                    }
                }
                .onDelete(perform: deleteItems)
                
                if appManager.savedTags.isEmpty {
                    EmptyStateView(
                        title: "No Saved Tags",
                        systemImage: "tag.slash",
                        description: "Press [+] to Scan or create a new tag to get started"
                    )
                }
            }
            .searchable(text: $searchText)
            .listStyle(.insetGrouped)
            .navigationTitle(appManager.appName)
            .navigationBarItems(trailing: HStack {
                addButton
                settingsButton
            })
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .presentationDetents([.medium,.large])
                    .presentationDragIndicator(.hidden)
            }
            .sheet(isPresented: $showingWelcome) {
                WelcomeView()
                    .interactiveDismissDisabled()
            }
            .sheet(isPresented: $showCreateSheet) {
                NavigationView {
                    NFCTagView()
                }
            }
            .sheet(item: $scannedTag) { tag in
                NavigationView {
                    NFCTagView(tag: tag)
                }
            }
            .onAppear {
                showingWelcome = appManager.savedTags.isEmpty
            }
            .alert(appManager.alertTitle, isPresented: $appManager.showingAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(appManager.alertMessage)
            }
            .tint(appManager.appTintColor.getColor())
            .fontDesign(appManager.appFontDesign.getFontDesign())
            .fontWidth(appManager.appFontWidth.getFontWidth())
            .environment(\.dynamicTypeSize, appManager.appFontSize.getFontSize())
            .preferredColorScheme(appManager.colorSchemeMode.getColorScheme())
        }
    }
    
    private var addButton: some View {
        Menu {
            Button(action: handleReadNFC) {
                Label("Scan NFC Tag", systemImage: "wave.3.left")
            }
            
            Button(action: { showCreateSheet = true }) {
                Label("Create New Tag", systemImage: "plus")
            }
        } label: {
            Image(systemName: "plus")
                .fontWeight(.semibold)
        }
    }
    
    private var settingsButton: some View {
        Button {
            showingSettings = true
        } label: {
            Image(systemName: "gear")
        }
    }
    
    // MARK: - Helper Methods
    
    private func handleReadNFC() {
        Task {
            do {
                let tag = try await nfcService.read()
                await MainActor.run {
                    scannedTag = tag
                }
            } catch let error as NFCServiceError {
                // Handle specific NFC errors
                await MainActor.run {
                    appManager.showAlert(
                        title: "NFC Error",
                        message: error.localizedDescription
                    )
                }
            } catch {
                print(error.localizedDescription)
                // Handle other errors
                await MainActor.run {
                    appManager.showAlert(
                        title: "Error",
                        message: "An unexpected error occurred: \(error.localizedDescription)"
                    )
                }
            }
        }
    }
    
    func tagRow(tag: NFCTag) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tag.name)
                .font(.headline)
            
            HStack {
                Text(tag.manufacturer)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(tag.displayTime)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text("\(tag.records.count) records")
                .font(.caption)
                .foregroundColor(.blue)
        }
        .padding(.vertical, 4)
    }
    
    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            appManager.deleteTag(id: filteredTags[index].id)
        }
    }
}
