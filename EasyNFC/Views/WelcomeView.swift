import SwiftUI

struct WelcomeView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var appManager: AppManager = AppManager.shared
    
    var body: some View {
        NavigationStack {
            VStack {
                Spacer()
                
                VStack(spacing: 12) {
                    Image(systemName: "wave.3.left")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                        .foregroundColor(.accentColor)
                        .padding(.bottom, 16)
                    
                    VStack(spacing: 4) {
                        Text("Welcome to \(appManager.appName)")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Smart NFC Reader & Writer")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                
                Spacer()
                                
                VStack(alignment: .leading, spacing: 24) {
                    Label {
                        VStack(alignment: .leading) {
                            Text("Quick Scan")
                                .font(.headline)
                            Text("Read NFC tags instantly")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "wave.3.right")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 8)
                    }
                    
                    Label {
                        VStack(alignment: .leading) {
                            Text("Write & Edit")
                                .font(.headline)
                            Text("Create and modify NFC tags")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "pencil.and.list.clipboard")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 8)
                    }
                    
                    Label {
                        VStack(alignment: .leading) {
                            Text("Multiple Formats")
                                .font(.headline)
                            Text("Support various NFC standards")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "tag.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                
                Spacer()
                
                Button {
                    Task {
                        dismiss()
                    }
                } label: {
                    HStack (alignment: .center) {
                        Text("Get Started")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .foregroundStyle(.background)
                    }
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .padding(.horizontal)
                Spacer()
            }
            .navigationTitle("Welcome")
            .padding()
            .toolbar(.hidden)
        }
    }
}
