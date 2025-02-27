
import SwiftUI

struct AboutView: View {
    @StateObject var appManager = AppManager.shared
    
    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    Image(systemName: "wave.3.left")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 60, height: 60)
                        .cornerRadius(12)
                        .foregroundColor(appManager.appTintColor.getColor())
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(appManager.appName)
                            .font(.headline)
                        Text("Version \(appManager.appVersion)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }
            
            // Additional Info Section
            Section(header: Text("About")) {
                Link(destination: URL(string: "https://github.com/lsongdev/easynfc-ios")!) {
                    HStack {
                        Text("GitHub")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundColor(.blue)
                    }
                }
            }
        }
        .navigationTitle("About")
        .listStyle(InsetGroupedListStyle())
    }
}
