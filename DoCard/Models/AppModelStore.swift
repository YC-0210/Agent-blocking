import SwiftData

/// The production open operation, also used by upgrade tests with a copied store.
/// Backup/reset policy belongs to the caller; an opening error is never hidden here.
enum AppModelStore {
  static func open(configuration: ModelConfiguration) throws -> ModelContainer {
    try ModelContainer(
      for: Schema(versionedSchema: AppSchemaV5.self),
      migrationPlan: AppMigrationPlan.self,
      configurations: [configuration])
  }
}
