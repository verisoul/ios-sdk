//
//  ExampleApp.swift
//  Example
//
//  Created by Ivan Divljak on 23.1.25..
//

import SwiftUI

@main
struct ExampleApp: App {
    
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
