//
//  DeviceCheckResponse.swift
//  VerisoulSDK
//
//  Created by Ivan Divljak on 16.1.25..
//

struct DeviceCheckResponse: Codable {
    let bit0: Bool
    let bit1: Bool
    let lastUpdateTime: String

    enum CodingKeys: String, CodingKey {
        case bit0
        case bit1
        case lastUpdateTime = "last_update_time"
    }
}

struct NoReply: Decodable {}
