import Foundation
import SwiftUI

// MARK: - App Manager
class AppManager: ObservableObject {
    // MARK: - 单例
    static let shared = AppManager()
    
    @AppStorage("colorScheme") var colorSchemeMode: ColorSchemeMode = .system
    @AppStorage("appTintColor") var appTintColor: AppTintColor = .green
    @AppStorage("appFontDesign") var appFontDesign: AppFontDesign = .standard
    @AppStorage("appFontSize") var appFontSize: AppFontSize = .xlarge
    @AppStorage("appFontWidth") var appFontWidth: AppFontWidth = .expanded
    
    // MARK: - 发布的状态属性
    @Published var savedTags: [NFCTag] = []
    @Published var showingAlert = false
    @Published var alertTitle = ""
    @Published var alertMessage = ""
    
    func showAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showingAlert = true
    }
    
    // UserDefaults keys
    private let savedTagsKey = "nfc-tags"
    
    // MARK: - 初始化
    private init() {
        loadSavedTags()
    }
    
    // MARK: - 公共方法
    
    /// 保存 NFC 标签到 UserDefaults
    /// - Parameter tag: 要保存的 NFC 标签
    func saveTag(_ tag: NFCTag) {
        // 检查是否已存在相同 ID 的标签
        if let index = savedTags.firstIndex(where: { $0.id == tag.id }) {
            savedTags[index] = tag
        } else {
            savedTags.append(tag)
        }
        
        saveTags()
    }
    
    /// 删除保存的 NFC 标签
    /// - Parameter id: 要删除的标签 ID
    func deleteTag(id: UUID) {
        savedTags.removeAll { $0.id == id }
        saveTags()
    }
    
    /// 清除所有保存的标签
    func clearAllTags() {
        savedTags.removeAll()
        saveTags()
    }
    
    // MARK: - 私有方法
    
    /// 将标签数组保存到 UserDefaults
    private func saveTags() {
        do {
            let data = try JSONEncoder().encode(savedTags)
            UserDefaults.standard.set(data, forKey: savedTagsKey)
        } catch {
            print("Error saving tags: \(error)")
        }
    }
    
    /// 从 UserDefaults 加载标签数组
    private func loadSavedTags() {
        guard let data = UserDefaults.standard.data(forKey: savedTagsKey) else { return }
        
        do {
            savedTags = try JSONDecoder().decode([NFCTag].self, from: data)
        } catch {
            print("Error loading tags: \(error)")
        }
    }
} 

extension AppManager {
    var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "EasyNFC"
    }
    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
    }
}
