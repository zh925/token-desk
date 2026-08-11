import Testing
import TokenDeskData

@Test
func dataModuleLinksGRDB() {
    #expect(TokenDeskDataModule.databaseEngine == "GRDB")
    #expect(TokenDeskDataModule.isDatabaseLibraryLinked)
}
