//
//  SendMessageRequest.swift
//  VerisoulSDK
//
//  Created by Ivan Divljak on 17.1.25..
//

internal struct SendMessageREQUEST: Codable {
    let assertion: String
    let challenge: String
    let projectId: String
    let payload: String
    let keyId: String?
    
    enum CodingKeys: String, CodingKey {
        case assertion
        case challenge
        case payload
        case projectId = "project_id"
        case keyId = "key_id"
    }
}
