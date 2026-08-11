import Foundation

struct OpenAIUsagePageDTO: Decodable {
    let data: [OpenAIUsageBucketDTO]
    let hasMore: Bool
    let nextPage: String?

    enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
        case nextPage = "next_page"
    }
}

struct OpenAIUsageBucketDTO: Decodable {
    let startTime: Int64
    let endTime: Int64
    let results: [OpenAIUsageResultDTO]

    enum CodingKeys: String, CodingKey {
        case startTime = "start_time"
        case endTime = "end_time"
        case results
    }
}

struct OpenAIUsageResultDTO: Decodable {
    let inputTokens: Int64
    let outputTokens: Int64
    let inputCachedTokens: Int64?
    let inputUncachedTokens: Int64?
    let inputCacheCreationTokens: Int64?
    let projectID: String?
    let model: String?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case inputCachedTokens = "input_cached_tokens"
        case inputUncachedTokens = "input_uncached_tokens"
        case inputCacheCreationTokens = "input_cache_creation_tokens"
        case projectID = "project_id"
        case model
    }
}

struct OpenAICostPageDTO: Decodable {
    let data: [OpenAICostBucketDTO]
    let hasMore: Bool
    let nextPage: String?

    enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
        case nextPage = "next_page"
    }
}

struct OpenAICostBucketDTO: Decodable {
    let startTime: Int64
    let endTime: Int64
    let results: [OpenAICostResultDTO]

    enum CodingKeys: String, CodingKey {
        case startTime = "start_time"
        case endTime = "end_time"
        case results
    }
}

struct OpenAICostResultDTO: Decodable {
    let amount: OpenAIAmountDTO?
    let projectID: String?

    enum CodingKeys: String, CodingKey {
        case amount
        case projectID = "project_id"
    }
}

struct OpenAIAmountDTO: Decodable {
    let value: Decimal
    let currency: String
}
