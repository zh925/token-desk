import Foundation

struct KimiBalanceResponseDTO: Decodable {
    let status: Bool
    let data: KimiBalanceDataDTO
}

struct KimiBalanceDataDTO: Decodable {
    let availableBalance: LosslessDecimalDTO

    enum CodingKeys: String, CodingKey {
        case availableBalance = "available_balance"
    }
}

struct KimiCompletionResponseDTO: Decodable {
    let created: Int64
    let model: String
    let usage: KimiResponseUsageDTO
}

struct KimiResponseUsageDTO: Decodable {
    let promptTokens: Int64
    let completionTokens: Int64
    let totalTokens: Int64?
    let cachedTokens: Int64?

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
        case cachedTokens = "cached_tokens"
    }
}
