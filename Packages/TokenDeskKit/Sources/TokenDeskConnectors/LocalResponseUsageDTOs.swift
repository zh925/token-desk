import Foundation

struct GeminiGenerateContentResponseDTO: Decodable {
    let modelVersion: String
    let usageMetadata: GeminiUsageMetadataDTO
}

struct GeminiUsageMetadataDTO: Decodable {
    let promptTokenCount: Int64
    let cachedContentTokenCount: Int64?
    let candidatesTokenCount: Int64
    let thoughtsTokenCount: Int64?
    let totalTokenCount: Int64
}

struct GLMCompletionResponseDTO: Decodable {
    let created: Int64
    let model: String
    let usage: OpenAICompatibleUsageDTO
}

struct MiniMaxCompletionResponseDTO: Decodable {
    let created: Int64
    let model: String
    let usage: OpenAICompatibleUsageDTO
    let baseResponse: MiniMaxBaseResponseDTO?

    enum CodingKeys: String, CodingKey {
        case created
        case model
        case usage
        case baseResponse = "base_resp"
    }
}

struct OpenAICompatibleUsageDTO: Decodable {
    let promptTokens: Int64
    let completionTokens: Int64
    let totalTokens: Int64?
    let promptTokenDetails: PromptTokenDetailsDTO?

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
        case promptTokenDetails = "prompt_tokens_details"
    }
}

struct PromptTokenDetailsDTO: Decodable {
    let cachedTokens: Int64?

    enum CodingKeys: String, CodingKey {
        case cachedTokens = "cached_tokens"
    }
}

struct MiniMaxBaseResponseDTO: Decodable {
    let statusCode: Int

    enum CodingKeys: String, CodingKey {
        case statusCode = "status_code"
    }
}
