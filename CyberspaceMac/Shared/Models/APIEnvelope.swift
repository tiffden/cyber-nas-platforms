import Foundation

struct APIRequestEnvelope: Codable {
    let id: String
    let method: String
    let params: [String: String]
}

struct APIErrorPayload: Codable, Error {
    let code: String
    let message: String
    let details: [String: String]?
}

struct APIResponseEnvelope: Codable {
    let id: String
    let ok: Bool
    let result: [String: String]?
    let error: APIErrorPayload?
}
