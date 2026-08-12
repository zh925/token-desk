import Foundation

struct AnthropicUsagePageDTO: Decodable {
    let data: [AnthropicUsageBucketDTO]
    let hasMore: Bool
    let nextPage: String?

    enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
        case nextPage = "next_page"
    }
}

struct AnthropicUsageBucketDTO: Decodable {
    let startingAt: String
    let endingAt: String
    let results: [AnthropicUsageResultDTO]

    enum CodingKeys: String, CodingKey {
        case startingAt = "starting_at"
        case endingAt = "ending_at"
        case results
    }
}

struct AnthropicUsageResultDTO: Decodable {
    let uncachedInputTokens: Int64
    let cacheReadInputTokens: Int64
    let cacheCreation: AnthropicCacheCreationDTO
    let outputTokens: Int64
    let model: String?
    let workspaceID: String?

    enum CodingKeys: String, CodingKey {
        case uncachedInputTokens = "uncached_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case cacheCreation = "cache_creation"
        case outputTokens = "output_tokens"
        case model
        case workspaceID = "workspace_id"
    }
}

struct AnthropicCacheCreationDTO: Decodable {
    let ephemeralFiveMinuteInputTokens: Int64
    let ephemeralOneHourInputTokens: Int64

    enum CodingKeys: String, CodingKey {
        case ephemeralFiveMinuteInputTokens = "ephemeral_5m_input_tokens"
        case ephemeralOneHourInputTokens = "ephemeral_1h_input_tokens"
    }
}

struct AnthropicCostPageDTO: Decodable {
    let data: [AnthropicCostBucketDTO]
    let hasMore: Bool
    let nextPage: String?

    enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
        case nextPage = "next_page"
    }
}

struct AnthropicCostBucketDTO: Decodable {
    let startingAt: String
    let endingAt: String
    let results: [AnthropicCostResultDTO]

    enum CodingKeys: String, CodingKey {
        case startingAt = "starting_at"
        case endingAt = "ending_at"
        case results
    }
}

struct AnthropicCostResultDTO: Decodable {
    let amount: String
    let currency: String
    let workspaceID: String?

    enum CodingKeys: String, CodingKey {
        case amount
        case currency
        case workspaceID = "workspace_id"
    }
}
