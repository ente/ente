import Foundation

struct AutoFillEntry: Codable {
    let id: String
    let issuer: String
    let account: String
    let secret: String
    let algorithm: String
    let digits: Int
    let period: Int
}

struct AutoFillSnapshot: Codable {
    let version: Int
    let generation: String
    let timeOffsetMilliseconds: Int
    let entries: [AutoFillEntry]
}
