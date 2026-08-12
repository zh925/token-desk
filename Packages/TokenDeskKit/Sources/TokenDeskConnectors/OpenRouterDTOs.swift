import Foundation

struct OpenRouterCreditsResponseDTO: Decodable {
    let data: OpenRouterCreditsDTO
}

struct OpenRouterCreditsDTO: Decodable {
    let totalCredits: LosslessDecimalDTO
    let totalUsage: LosslessDecimalDTO

    enum CodingKeys: String, CodingKey {
        case totalCredits = "total_credits"
        case totalUsage = "total_usage"
    }
}
