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

    private func statusBanner(symbol: String, text: String) -> some View {
        HStack(spacing: TokenDeskDesign.Spacing.small) {
            Text(symbol)
                .font(TokenDeskTextStyle.control.font)
            Text(text)
                .font(TokenDeskTextStyle.auxiliary.font)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, TokenDeskDesign.Spacing.medium)
        .frame(maxWidth: .infinity, minHeight: 30)
        .background(TokenDeskDesign.Palette.surfaceMuted.color)
        .overlay {
            Rectangle().stroke(TokenDeskDesign.Palette.ink.color, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
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
            Text(title)
                .font(TokenDeskTextStyle.cardTitle.font)
            Text(detail)
                .font(TokenDeskTextStyle.body.font)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("dashboard-state-message")
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
