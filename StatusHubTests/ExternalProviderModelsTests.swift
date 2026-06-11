import XCTest
@testable import StatusHub

final class ExternalProviderModelsTests: XCTestCase {
    func testPluginManifestDecoding() throws {
        let json = """
        {
          "id": "mac-system",
          "title": "Mac System",
          "version": "0.1.0",
          "providers": [
            {
              "id": "main",
              "title": "Mac System Provider",
              "icon": "cpu",
              "statusFile": "runtime/status.json",
              "command": "bin/provider",
              "arguments": ["--once"],
              "workingDirectory": "."
            }
          ]
        }
        """.data(using: .utf8)!

        let manifest = try JSONDecoder().decode(StatusHubPluginManifest.self, from: json)

        XCTAssertEqual(manifest.id, "mac-system")
        XCTAssertEqual(manifest.title, "Mac System")
        XCTAssertEqual(manifest.version, "0.1.0")
        XCTAssertEqual(manifest.providers.count, 1)
        XCTAssertEqual(manifest.providers[0].statusFile, "runtime/status.json")
        XCTAssertEqual(manifest.providers[0].command, "bin/provider")
    }

    func testSnapshotDecoding() throws {
        let json = """
        {
          "status": "attention",
          "summary": "1 item needs attention",
          "updatedAt": "2026-06-11T12:30:00+08:00",
          "items": [
            {
              "id": "temperature",
              "title": "Temperature",
              "subtitle": "CPU 91 C",
              "status": "attention",
              "url": "https://example.com/temperature",
              "value": "91 C",
              "detail": {
                "source": "powermetrics"
              },
              "actions": [
                {
                  "id": "run",
                  "title": "Run",
                  "command": "bin/provider",
                  "arguments": ["run"],
                  "workingDirectory": "."
                }
              ],
              "links": [
                {
                  "id": "latest",
                  "title": "Latest report",
                  "url": "https://example.com/report"
                }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(ExternalProviderSnapshot.self, from: json)

        XCTAssertEqual(snapshot.status, .attention)
        XCTAssertEqual(snapshot.summary, "1 item needs attention")
        XCTAssertEqual(snapshot.items.first?.id, "temperature")
        XCTAssertEqual(snapshot.items.first?.status, .attention)
        XCTAssertEqual(snapshot.items.first?.value, "91 C")
        XCTAssertEqual(snapshot.items.first?.detail?["source"], "powermetrics")
        XCTAssertEqual(snapshot.items.first?.actions?.first?.command, "bin/provider")
        XCTAssertEqual(snapshot.items.first?.links?.first?.title, "Latest report")
    }

    func testHubStatusSeverityOrdering() {
        XCTAssertTrue(HubStatus.failed > .attention)
        XCTAssertTrue(HubStatus.attention > .running)
        XCTAssertTrue(HubStatus.running > .unknown)
        XCTAssertTrue(HubStatus.success > .idle)
    }

    func testInstalledPluginBuiltinSource() {
        let manifest = StatusHubPluginManifest(
            id: "mac-system",
            title: "Mac System",
            version: "0.1.3",
            providers: []
        )
        let plugin = InstalledPlugin(
            manifest: manifest,
            sourceURL: "builtin:mac-system",
            directory: URL(fileURLWithPath: "/tmp/mac-system"),
            gitTag: nil
        )

        XCTAssertTrue(plugin.isBuiltin)
        XCTAssertEqual(plugin.builtinId, "mac-system")
    }
}
