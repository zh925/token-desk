import SwiftUI
import TokenDeskDesign

/// Percentage-based plan windows, kept separate from Token usage and cost.
public struct PlansPage: View {
    private let state: DashboardContentState<[PlanWindowSnapshot]>
    private let capabilityStatuses: [ProviderCapabilityStatusSnapshot]

    /// Creates a plan page in any supported dashboard render state.
    public init(
        state: DashboardContentState<[PlanWindowSnapshot]> = .loaded(DashboardFixtures.plans),
        capabilityStatuses: [ProviderCapabilityStatusSnapshot] =
            DashboardFixtures.providerCapabilityStatuses
    ) {
        self.state = state
        self.capabilityStatuses = capabilityStatuses
    }

    /// Fixed plan-window layout with source and confidence markings.
    public var body: some View {
        VStack(spacing: TokenDeskDesign.Spacing.medium) {
            PageHeading(
                title: "套餐页面",
                subtitle: "窗口额度只展示百分比，不换算为 Token",
                code: "PLAN WINDOWS · MOCK"
            )

            DashboardStateView(state: state) { plans in
                VStack(spacing: TokenDeskDesign.Spacing.medium) {
                    HStack(spacing: TokenDeskDesign.Spacing.medium) {
                        ForEach(Array(plans.prefix(2))) { plan in
                            PlanWindowCard(plan: plan)
                        }
                    }
                    HStack(spacing: TokenDeskDesign.Spacing.medium) {
                        ForEach(Array(plans.dropFirst(2).prefix(2))) { plan in
                            PlanWindowCard(plan: plan)
                        }
                        PlanLegendCard(
                            codexStatus: capabilityStatuses.first {
                                $0.id == "codex-plan-unsupported"
                            }
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, TokenDeskDesign.Spacing.extraLarge)
        .padding(.vertical, TokenDeskDesign.Spacing.large)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("套餐页面")
        .accessibilityIdentifier("page-plans")
    }
}

private struct PlanWindowCard: View {
    let plan: PlanWindowSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: TokenDeskDesign.Spacing.medium) {
            HStack {
                Text(String(plan.provider.prefix(1)))
                    .font(TokenDeskTextStyle.control.font)
                    .foregroundStyle(TokenDeskDesign.Palette.paper.color)
                    .frame(width: 30, height: 30)
                    .background(TokenDeskDesign.Palette.ink.color)
                    .accessibilityHidden(true)
                Text("\(plan.provider) · \(plan.name)")
                    .font(TokenDeskTextStyle.cardTitle.font)
                    .lineLimit(1)
                Spacer()
                Text(plan.source.rawValue)
                    .font(TokenDeskTextStyle.auxiliary.font)
            }

            HStack(alignment: .lastTextBaseline) {
                Text("\(plan.usedPercent)%")
                    .font(.system(size: 42, weight: .bold, design: .monospaced))
                Text("已使用")
                    .font(TokenDeskTextStyle.body.font)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    TokenDeskPatternFill(.dots)
                    Rectangle()
                        .fill(TokenDeskDesign.Palette.ink.color)
                        .frame(width: proxy.size.width * CGFloat(plan.usedPercent) / 100)
                }
                .overlay {
                    Rectangle().stroke(TokenDeskDesign.Palette.ink.color, lineWidth: 2)
                }
            }
            .frame(height: 24)
            .accessibilityLabel("已使用 \(plan.usedPercent)%")

            HStack {
                Text(plan.window)
                Spacer()
                Text(plan.resetDescription)
            }
            .font(TokenDeskTextStyle.auxiliary.font)

            if let confidence = plan.confidence {
                Text("估算置信度：\(confidence)")
                    .font(TokenDeskTextStyle.auxiliary.font)
            }
        }
        .padding(TokenDeskDesign.Spacing.large)
        .frame(maxWidth: .infinity, minHeight: 202, alignment: .topLeading)
        .background {
            if plan.source == .estimated {
                TokenDeskPatternFill(
                    .diagonal,
                    foreground: TokenDeskDesign.Palette.surfaceMid.color
                )
            } else {
                TokenDeskDesign.Palette.paper.color
            }
        }
        .overlay {
            Rectangle().stroke(TokenDeskDesign.Palette.ink.color, lineWidth: 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("plan-window-\(plan.id)")
    }
}

private struct PlanLegendCard: View {
    let codexStatus: ProviderCapabilityStatusSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: TokenDeskDesign.Spacing.medium) {
            Text("额度显示规则")
                .font(TokenDeskTextStyle.cardTitle.font)
            if let codexStatus {
                Text("Codex：\(codexStatus.title)")
                    .font(TokenDeskTextStyle.cardTitle.font)
                Text(codexStatus.detail)
                    .font(TokenDeskTextStyle.auxiliary.font)
            }
            Divider()
            Text("● 官方 · ○ 估算 · ◇ 演示（不代表真实额度）")
            Text("未知值显示 —，不会显示为 0。")
        }
        .font(TokenDeskTextStyle.body.font)
        .padding(TokenDeskDesign.Spacing.large)
        .frame(maxWidth: .infinity, minHeight: 202, alignment: .topLeading)
        .background(TokenDeskDesign.Palette.surfaceMuted.color)
        .overlay {
            Rectangle().stroke(TokenDeskDesign.Palette.ink.color, lineWidth: 2)
        }
        .accessibilityElement(children: .combine)
    }
}
