import SwiftUI
import SwiftUIX

// Define the URL prefix structure with DisplayName
struct URIPrefix {
    var prefix: String
    var displayName: String
}

extension NFCTag {
    // Additional special URL types that override the standard prefixes
    static let specialURLTypes: [URIPrefix] = [
        URIPrefix(prefix: "wifi:", displayName: "Wi-Fi"),
        URIPrefix(prefix: "mailto:", displayName: "Email"),
        URIPrefix(prefix: "tel:", displayName: "Phone Call"),
        URIPrefix(prefix: "facetime:", displayName: "FaceTime Video")
    ]
}

struct NFCRecordEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var record: NFCRecord = NFCRecord()
    var onSave: (NFCRecord) -> Void
    
    @State private var prefix = ""
    @State private var ssid = ""
    @State private var password = ""
    @State private var encryption = "none"
    
    @State private var email = ""
    @State private var subject = ""
    @State private var content = ""
    @State private var languageCode = "en"
    
    // Map URI prefixes to URIPrefix objects, using specialURLTypes when available
    private var allURLTypes: [URIPrefix] {
        let standardPrefixes = NFCTag.uriPrefixes.map { prefix -> URIPrefix in
            // Check if this prefix has a special type defined
            if let specialType = NFCTag.specialURLTypes.first(where: { $0.prefix == prefix }) {
                return specialType
            }
            // Otherwise use default display name
            return URIPrefix(prefix: prefix, displayName: prefix.isEmpty ? "No Prefix" : prefix)
        }
        
        // Add any special types that aren't in the standard prefixes
        let additionalTypes = NFCTag.specialURLTypes.filter { specialType in
            !NFCTag.uriPrefixes.contains(specialType.prefix)
        }
        
        return standardPrefixes + additionalTypes
    }
    
    var body: some View {
        NavigationView {
            Form {
                Picker("Type", selection: $record.type) {
                    Text("Text").tag("T")
                    Text("URL").tag("U")
                    Text("Media").tag((record.type == "T" || record.type == "U") ? "" : record.type)
                }
                if record.type != "T" && record.type != "U" {
                    InputField("Content Type", text: $record.type, placeholder: "text/html")
                }
                
                Section(header: Text("Content")) {
                    switch record.type {
                    case "T":
                        textSection
                    case "U":
                        urlSection
                    default:
                        textSection
                    }
                }
            }
            .navigationBarTitle("Record", displayMode: .inline)
            .navigationBarItems(leading: cancelButton, trailing: saveButton)

        }
    }
    var textSection: some View {
        Group {
            TextEditor(text: $content)
                .frame(height: 150)
                .textInputAutocapitalization(.never)
            if record.type == "T" {
                InputField("Language", text: $languageCode)
            }
        }
    }
    
    var urlSection: some View {
        Group {
            Picker("Type", selection: $prefix) {
                ForEach(allURLTypes, id: \.prefix) { uriPrefix in
                    Text(uriPrefix.displayName).tag(uriPrefix.prefix)
                }
            }
            switch prefix {
            case "wifi:":
                InputField("SSID", text: $ssid)
                InputField("Password", text: $password)
                Picker("Encryption", selection: $encryption) {
                    Text("None").tag("none")
                    Text("WEP").tag("WEP")
                    Text("WPA").tag("WPA")
                    Text("WPA2").tag("WPA2")
                }
            case "facetime:":
                TextField("Phone number or email", text: $email)
                    .keyboardType(.emailAddress)
            case "mailto:":
                InputField("To", text: $email)
                InputField("Subject", text: $subject)
                TextEditor(text: $content)
                    .frame(height: 100)
            default:
                InputField("URL", text: $content)
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
            switch record.type {
            case "T":
                record.writeText(content, language: languageCode)
            case "U":
                switch prefix {
                case "wifi:":
                    let wifiString = "WIFI:S:\(ssid);P:\(password);T:\(encryption);;"
                    record.writeLink(wifiString)
                case "mailto:":
                    var mailtoUrl = "mailto:\(email)"
                    if !subject.isEmpty {
                        mailtoUrl += "?subject=\(subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
                    }
                    if !content.isEmpty {
                        mailtoUrl += mailtoUrl.contains("?") ? "&" : "?"
                        mailtoUrl += "body=\(content.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
                    }
                    record.writeLink(mailtoUrl)
                default:
                    // For standard URI prefixes
                    if NFCTag.uriPrefixes.contains(prefix) {
                        record.writeLink(prefix + content)
                    } else {
                        record.writeLink(content)
                    }
                }
            default:
                record.writeMedia(content)
            }
            onSave(record)
            dismiss()
        }
    }
}
