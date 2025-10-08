//
//  VerifyAttestationREQUEST.swift
//  VerisoulSDK
//
//  Created by Ivan Divljak on 17.1.25..
//

struct VerifyAttestationRequest: Codable {
    let attestation: String
    let challenge: String
    let projectId: String
    let keyId: String
    
    enum CodingKeys: String, CodingKey {
        case attestation
        case challenge
        case keyId = "key_id"
        case projectId = "project_id"
    }
}
