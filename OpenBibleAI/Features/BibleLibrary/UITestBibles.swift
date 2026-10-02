//
//  UITestBibles.swift
//  OpenBibleAI
//

#if DEBUG
import BibleAI
import BibleDomain
import Foundation

/// UI tests serve the repository's version packages from a local server and
/// describe them in the launch environment, so onboarding and downloads run
/// for real without the internet (Debug builds only):
///
/// - `OPENBIBLE_UITEST_BIBLES_URL`: server base URL (`<base>/<id>/<file>`)
/// - `OPENBIBLE_UITEST_CATALOG`: JSON `[{version, files: [{name, size, sha256}]}]`
/// - `OPENBIBLE_UITEST_RESET_BIBLES=1`: start with nothing installed
/// - `OPENBIBLE_UITEST_PREINSTALL=<id,…>`: install these before the app starts
enum UITestBibles {
    private static var environment: [String: String] { ProcessInfo.processInfo.environment }

    /// The library for a UI-test launch, or nil for a normal launch.
    @MainActor
    static func library() -> BibleLibraryModel? {
        guard let base = environment["OPENBIBLE_UITEST_BIBLES_URL"].flatMap(URL.init(string:)),
              let json = environment["OPENBIBLE_UITEST_CATALOG"],
              let entries = try? JSONDecoder().decode([Entry].self, from: Data(json.utf8))
        else { return nil }

        let directory = URL.applicationSupportDirectory
            .appendingPathComponent("OpenBibleAI/UITestBibles", isDirectory: true)
        // Each UI test starts without a saved comparison.
        UserDefaults.standard.removeObject(forKey: "bible.compareVersions")
        if environment["OPENBIBLE_UITEST_RESET_BIBLES"] == "1" {
            try? FileManager.default.removeItem(at: directory)
            UserDefaults.standard.removeObject(forKey: "bible.activeVersion")
        }

        let catalog = entries.map { entry in
            BibleCatalogEntry(
                version: entry.version,
                manifest: ModelManifest(
                    repository: "",
                    revision: entry.version.id,
                    files: entry.files.map { ModelManifest.File(name: $0.name, size: $0.size, sha256: $0.sha256) },
                    host: .baseURL(base)
                )
            )
        }
        var stores: [String: any LocalModelStoring] = [:]
        for entry in catalog {
            stores[entry.id] = LocalModelStore(
                manifest: entry.manifest,
                directory: directory.appendingPathComponent(entry.id, isDirectory: true)
            )
        }
        return BibleLibraryModel(catalog: catalog, stores: stores, defaults: UserDefaults.standard)
    }

    /// Installs the versions named in `OPENBIBLE_UITEST_PREINSTALL`.
    @MainActor
    static func preinstall(into library: BibleLibraryModel) async {
        guard let ids = environment["OPENBIBLE_UITEST_PREINSTALL"]?.split(separator: ",") else { return }
        await library.refresh()
        for id in ids.map(String.init) where !library.installedIDs.contains(id) {
            await library.install(id).value
        }
    }

    private struct Entry: Decodable {
        struct File: Decodable {
            let name: String
            let size: Int64
            let sha256: String
        }

        let version: BibleVersion
        let files: [File]
    }
}
#endif
