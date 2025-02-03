//
//  AppDelegate.swift
//  DemoVerisoulSDK
//
//  Created by Ivan Divljak on 15.1.25..
//
import UIKit
import VerisoulSDK

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        Verisoul.shared.configure(env: VerisoulEnvironment.prod, projectId: "00000000-0000-0000-0000-000000000001")
        return true
    }
}
