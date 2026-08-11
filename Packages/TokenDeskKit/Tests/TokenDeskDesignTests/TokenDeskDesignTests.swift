import Testing
import TokenDeskDesign

@Test
func designModuleNameIsStable() {
    #expect(TokenDeskDesignModule.name == "TokenDeskDesign")
}

@Test
func canvasAndControlMetricsMatchProductBaseline() {
    #expect(TokenDeskDesign.Canvas.width == 1_280)
    #expect(TokenDeskDesign.Canvas.height == 720)
    #expect(TokenDeskDesign.Canvas.headerHeight == 58)
    #expect(TokenDeskDesign.Canvas.providerColumnWidth == 246)
    #expect(TokenDeskDesign.Control.minimumInteractiveDimension >= 40)
}

@Test
func typeScaleProtectsFiveInchReadability() {
    #expect(TokenDeskTextStyle.clock.size >= 64)
    #expect(TokenDeskTextStyle.primaryMetric.size >= 40)
    #expect(TokenDeskTextStyle.pageTitle.size >= 24)
    #expect(TokenDeskTextStyle.cardTitle.size >= 18)
    #expect(TokenDeskTextStyle.body.size >= 14)
    #expect(TokenDeskTextStyle.auxiliary.size >= 11)
}

@Test
func textPairingsMeetWCAGAAContrast() {
    let palette = TokenDeskDesign.Palette.self

    #expect(palette.ink.contrastRatio(against: palette.paper) >= 4.5)
    #expect(palette.ink.contrastRatio(against: palette.surfaceMuted) >= 4.5)
    #expect(palette.inkMuted.contrastRatio(against: palette.paper) >= 4.5)
    #expect(palette.paper.contrastRatio(against: palette.ink) >= 4.5)
}

@Test
func statusComponentsDoNotDependOnColorAlone() {
    let statuses = TokenDeskStatus.allCases
    let labels = Set(statuses.map(\.label))
    let symbols = Set(statuses.map(\.symbol))

    #expect(labels.count == statuses.count)
    #expect(symbols.count == statuses.count)
    #expect(statuses.allSatisfy { !$0.label.isEmpty && !$0.symbol.isEmpty })
}

@Test
func patternsExposeThreeDistinctOneBitTreatments() {
    #expect(Set(TokenDeskPattern.allCases.map(\.rawValue)).count == 3)
}
