import SwiftData
import Testing
@testable import CanIV2

@Suite("App settings")
struct AppSettingsTests {
    @MainActor
    @Test("Fetch-or-create returns one persistent settings record")
    func fetchOrCreateSingleton() throws {
        let container = try TestFixtures.container()
        let context = ModelContext(container)
        let first = try ModelMutationService.fetchOrCreateSettings(in: context, defaultCurrencyCode: "MYR", now: TestFixtures.date)
        try ModelMutationService.saveValidated(context)
        let second = try ModelMutationService.fetchOrCreateSettings(in: context, defaultCurrencyCode: "PHP", now: TestFixtures.date)

        #expect(first.id == second.id)
        #expect(second.currencyCode == "MYR")
        #expect(try context.fetchCount(FetchDescriptor<AppSettings>()) == 1)
    }

    @MainActor
    @Test("Currency validation accepts supported ISO codes and rejects invalid codes")
    func currencyValidation() throws {
        try AppSettings(currencyCode: "MYR").validate()
        try AppSettings(currencyCode: "PHP").validate()
        #expect(throws: DomainValidationError.invalidCurrencyCode) {
            try AppSettings(currencyCode: "myr").validate()
        }
        #expect(throws: DomainValidationError.unsupportedCurrencyCode("ZZZ")) {
            try AppSettings(currencyCode: "ZZZ").validate()
        }
    }

    @MainActor
    @Test("Validated save rejects more than one settings record")
    func duplicateSettings() throws {
        let container = try TestFixtures.container()
        let context = ModelContext(container)
        context.insert(AppSettings(currencyCode: "MYR"))
        context.insert(AppSettings(currencyCode: "PHP"))

        #expect(throws: DomainValidationError.multipleSettingsRecords) {
            try ModelMutationService.saveValidated(context)
        }
    }
}
