import Foundation

struct DeepSeekBalanceResponseDTO: Decodable {
    let isAvailable: Bool
    let balanceInfos: [DeepSeekBalanceInfoDTO]

    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balanceInfos = "balance_infos"
    }
}

struct DeepSeekBalanceInfoDTO: Decodable {
    let currency: String
    let totalBalance: LosslessDecimalDTO

    enum CodingKeys: String, CodingKey {
        case currency
        case totalBalance = "total_balance"
    }
}

struct DeepSeekCompletionResponseDTO: Decodable {
    let created: Int64
    let model: String
    let usage: DeepSeekResponseUsageDTO
}

struct DeepSeekResponseUsageDTO: Decodable {
    let promptTokens: Int64
    let completionTokens: Int64
    let promptCacheHitTokens: Int64?
    let promptCacheMissTokens: Int64?
    let totalTokens: Int64?

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case promptCacheHitTokens = "prompt_cache_hit_tokens"
        case promptCacheMissTokens = "prompt_cache_miss_tokens"
        case totalTokens = "total_tokens"
    }
}
