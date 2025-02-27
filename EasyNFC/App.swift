//
//  NFCApp.swift
//  EasyNFC
//
//  Created by Lsong on 2/28/25.
//

import SwiftUI

@main
struct NFCApp: App {
    @StateObject private var appManager = AppManager.shared
    
    var body: some Scene {
        WindowGroup {
            NFCMainView()
                .environmentObject(appManager)
        }
    }
}
