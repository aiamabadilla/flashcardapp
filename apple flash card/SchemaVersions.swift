import SwiftData
import Foundation

/// Schema history. Every released shape of the store gets a version here.
///
/// RULES for changing the models (Deck, Card):
///  1. Never edit a released version in place. Freeze the shape you are replacing as nested
///     types inside its version enum, then change the live types for the new version.
///  2. Add the new version to `schemas` and a stage to `stages`.
///  3. Add a test that opens a store written by the old version (see SchemaTests).

// MARK: V1 (first TestFlight shape: ink stored inline in the card row)

enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [SchemaV1.Deck.self, SchemaV1.Card.self] }

    @Model final class Deck {
        var title: String
        var created: Date
        var deletedAt = 0.0
        @Relationship(deleteRule: .cascade) var cards: [Card] = []
        init(title: String = "Untitled Deck") {
            self.title = title
            self.created = .now
        }
    }

    @Model final class Card {
        var order: Int
        var front: Data
        var back: Data
        var frontText: String = ""
        var backText: String = ""
        var frontLined: Bool = true
        var backLined: Bool = true
        var frontBoxX = 0.02
        var frontBoxY = 0.03
        var frontBoxW = 0.96
        var frontBoxSize = 0.03
        var backBoxX = 0.02
        var backBoxY = 0.03
        var backBoxW = 0.96
        var backBoxSize = 0.03
        var isStarred: Bool = false
        var deletedAt = 0.0
        var leitnerBox = 0
        var dueTime = 0.0
        var reviewCount = 0
        var correctCount = 0
        var lastReviewed = 0.0
        var textItemsJSON: String = ""
        var imageItemsJSON: String = ""
        var inkRefWidth: Double = 0
        var frontInkText: String = ""
        var backInkText: String = ""
        var frontInkHash: String = ""
        var backInkHash: String = ""
        init(order: Int) {
            self.order = order
            self.front = Data()
            self.back = Data()
        }
    }
}

// MARK: V2 (ink stored as external files, so listing decks doesn't load every drawing)

enum SchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] { [Deck.self, Card.self] }   // the live models
}

enum IMSTUDYMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)]
    }
}

enum AppStore_ {
    /// The newest schema; this is what the live `Deck` and `Card` types are.
    typealias Latest = SchemaV2

    /// Builds the app's container with the migration plan. `inMemory` is for tests and previews.
    static func makeContainer(inMemory: Bool = false, url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: Latest.self)
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
