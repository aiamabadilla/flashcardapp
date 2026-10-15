import SwiftData
import Foundation

/// Schema history. Every released shape of the store gets a version here.
///
/// RULES for changing the models (Deck, Card):
///  1. Never edit a released version in place. Copy the previous models into the old
///     version's enum as nested types, then change the live types for the new version.
///  2. Add the new version to `schemas` and a stage to `stages`.
///  3. Add a test that opens a store written by the old version (see SchemaTests).
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    // V1 is the shape shipped to testers: the current Deck and Card models.
    static var models: [any PersistentModel.Type] { [Deck.self, Card.self] }
}

enum IMSTUDYMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

enum AppStore_ {
    /// Builds the app's container with the migration plan. `inMemory` is for tests and previews.
    static func makeContainer(inMemory: Bool = false, url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config: ModelConfiguration
        if let url {
            config = ModelConfiguration(schema: schema, url: url)
        } else {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        }
        return try ModelContainer(for: schema, migrationPlan: IMSTUDYMigrationPlan.self,
                                  configurations: config)
    }
}
