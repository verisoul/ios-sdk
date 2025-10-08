//
//  NetworkError.swift
//  VerisoulSDK
//
//  Created by Ivan Divljak on 15.1.25..
//

enum VerisoulNetworkError: Error {
    case invalidURL
    case noData
    case decodingError
    case networkFailure(Error)
}
