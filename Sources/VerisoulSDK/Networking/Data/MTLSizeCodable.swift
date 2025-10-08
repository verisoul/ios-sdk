//
//  MTLSizeCodable.swift
//  VerisoulSDK
//
//  Created by Ivan Divljak on 20.1.25..
//

import Metal

public struct MTLSizeCodable: Codable {

    public var width: Int
    public var height: Int
    public var depth: Int

    // Initializer to create from the old MTLSize class
    public init(mtlSize: MTLSize) {
        self.width = mtlSize.width
        self.height = mtlSize.height
        self.depth = mtlSize.depth
    }

    private enum CodingKeys: String, CodingKey {
        case width
        case height
        case depth
    }
}
