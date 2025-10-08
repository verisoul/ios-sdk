//
//  Date+Extension.swift
//  VerisoulSDK
//
//  Created by Ivan Divljak on 23.1.25..
//

import Foundation

extension Date {
    var millisecondsSince1970:Int64 {
        Int64((self.timeIntervalSince1970 * 1000.0).rounded())
    }
    
    init(milliseconds:Int64) {
        self = Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
    }
}

extension TimeInterval {

    var milliseconds: Int {
        return Int(self * 1_000)
    }
    var millisecondsSince1970: Int {
        let now = Date().timeIntervalSince1970
        let realTime = now + (self - ProcessInfo.processInfo.systemUptime)
        let timestamp = Int((realTime * 1000).rounded())
        
        return timestamp
       }
}
