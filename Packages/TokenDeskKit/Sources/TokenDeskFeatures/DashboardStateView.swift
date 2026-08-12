import SwiftUI
import TokenDeskDesign

/// Consistent loading, empty, error, and stale presentation for dashboard content.
struct DashboardStateView<Value: Equatable & Sendable, Content: View>: View {
    let state: DashboardContentState<Value>
    @ViewBuilder let content: (Value) -> Content

    var body: some View {
        switch state {
        case .loading:
            LoadingSkeleton()
        case .empty(let title, let detail):
            StateMessage(symbol: "□", title: title, detail: detail)
        case .loaded(let value):
            content(value)
        case .stale(let value, let lastUpdated):
            VStack(spacing: TokenDeskDesign.Spacing.small) {
                statusBanner(
                    symbol: "◫",
                    text: "数据已过期 · 最后成功 \(lastUpdated.formatted(date: .omitted, time: .shortened))"
                )
                content(value)
            }
        case .partial(let value, let issues):
            VStack(spacing: TokenDeskDesign.Spacing.small) {
                statusBanner(
                    symbol: "!",
                    text: partialDescription(issues)
                )
                content(value)
            }
        case .failed(let title, let detail, let cached):
            if let cached {
                VStack(spacing: TokenDeskDesign.Spacing.small) {
                    statusBanner(symbol: "×", text: "\(title) · \(detail) · 显示最近数据")
                    content(cached)
                }
            } else {
                StateMessage(symbol: "×", title: title, detail: detail)
            }
        }
    }

    private func partialDescription(_ issues: [DashboardIssue]) -> String {
        guard let first = issues.first else { return "部分数据不可用 · 其余数据保持可读" }
        let suffix = issues.count > 1 ? " · 另有 \(issues.count - 1) 项" : ""
        return "\(first.providerName) · \(first.message)\(suffix)"
    }

    private func statusBanner(symbol: String, text: String) -> some View {
        HStack(spacing: TokenDeskDesign.Spacing.small) {
            Text(symbol)
                .font(TokenDeskTextStyle.control.font)
                .accessibilityHidden(true)
            Text(text)
                .font(TokenDeskTextStyle.auxiliary.font)
                .lineLimit(1)
                .accessibilityLabel(text)
                .accessibilityIdentifier("dashboard-state-banner-text")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, TokenDeskDesign.Spacing.medium)
        .frame(maxWidth: .infinity, minHeight: 30)
        .background(TokenDeskDesign.Palette.surfaceMuted.color)
        .overlay {
            Rectangle().stroke(TokenDeskDesign.Palette.ink.color, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(text)
        .accessibilityIdentifier(statusIdentifier(for: text))
    }

    private func statusIdentifier(for text: String) -> String {
        if text.contains("演示认证失败") { return "app-review-state-authentication" }
        if text.contains("演示离线") { return "app-review-state-offline" }
        return "dashboard-state-banner"
    }
}

private struct LoadingSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: TokenDeskDesign.Spacing.large) {
            Text("正在读取最近数据…")
                .font(TokenDeskTextStyle.body.font)
            ForEach([0.72, 0.94, 0.58], id: \.self) { width in
                TokenDeskPatternFill(.dots)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .scaleEffect(x: width, anchor: .leading)
                    .overlay {
                        Rectangle().stroke(TokenDeskDesign.Palette.ink.color, lineWidth: 1)
                    }
            }
            Spacer()
        }
        .padding(TokenDeskDesign.Spacing.large)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在加载")
        .accessibilityIdentifier("dashboard-state-loading")
    }
}

private struct StateMessage: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: TokenDeskDesign.Spacing.medium) {
            Text(symbol)
                .font(TokenDeskTextStyle.primaryMetric.font)
                .accessibilityHidden(true)
            Text(title)
                .font(TokenDeskTextStyle.cardTitle.font)
                .accessibilityLabel(title)
                .accessibilityIdentifier("dashboard-state-title")
            Text(detail)
                .font(TokenDeskTextStyle.body.font)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
                .accessibilityLabel(detail)
                .accessibilityIdentifier("dashboard-state-detail")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityValue("\(title) · \(detail)")
        .accessibilityIdentifier(stateIdentifier)
    }

    private var stateIdentifier: String {
        if title.contains("演示限流") { return "app-review-state-rate-limited" }
        if title == "官方生产接口暂不可用" { return "app-review-state-unsupported" }
        return "dashboard-state-message"
    }
}

struct PageHeading: View {
    let title: String
    let subtitle: String
    let code: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: TokenDeskDesign.Spacing.extraSmall) {
                Text(title)
                    .font(TokenDeskTextStyle.pageTitle.font)
                Text(subtitle)
                    .font(TokenDeskTextStyle.body.font)
            }
            Spacer()
            Text(code)
                .font(TokenDeskTextStyle.auxiliary.font)
        }
        .frame(height: 52)
    }
}

struct MetricTile: View {
    let label: String
    let value: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: TokenDeskDesign.Spacing.extraSmall) {
            Text(label)
                .font(TokenDeskTextStyle.auxiliary.font)
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let detail {
                Text(detail)
                    .font(TokenDeskTextStyle.auxiliary.font)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(TokenDeskDesign.Spacing.medium)
        .background(TokenDeskDesign.Palette.paper.color)
        .overlay {
            Rectangle().stroke(TokenDeskDesign.Palette.ink.color, lineWidth: 2)
        }
        .accessibilityElement(children: .combine)
    }
}
