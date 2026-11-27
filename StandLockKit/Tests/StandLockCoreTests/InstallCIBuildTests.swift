import Foundation
import Testing

@Suite("CI install script", .serialized)
struct InstallCIBuildTests {
    private struct Result {
        let status: Int32
        let output: String
    }

    private struct Fixture {
        let root: URL
        let applications: URL
        let installedApp: URL
        let exportedApp: URL
        let archive: URL
        let backup: URL
        let tools: URL

        init() throws {
            let manager = FileManager.default
            root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            applications = root.appendingPathComponent("Applications")
            installedApp = applications.appendingPathComponent("StandLock.app")
            exportedApp = root.appendingPathComponent("export/StandLock.app")
            archive = root.appendingPathComponent("StandLock.zip")
            backup = root.appendingPathComponent("backup")
            tools = root.appendingPathComponent("tools")
            try manager.createDirectory(at: applications, withIntermediateDirectories: true)
            try manager.createDirectory(at: backup, withIntermediateDirectories: true)
            try manager.createDirectory(at: tools, withIntermediateDirectories: true)
            try Self.makeApp(at: installedApp, version: "1.0", build: "10")
            try Self.makeApp(at: exportedApp, version: "2.0", build: "20")
            try Self.makeTools(in: tools)
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: root)
        }

        func packageWithCICommand() throws -> Result {
            try Self.run("/usr/bin/ditto", arguments: [
                "-c", "-k", "--keepParent", "--rsrc", "--sequesterRsrc", exportedApp.path, archive.path,
            ])
        }

        func install(exitAfterProcessChecks: Int? = nil) throws -> Result {
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = "\(tools.path):/usr/bin:/bin:/usr/sbin:/sbin"
            environment["BACKUP_DIR"] = backup.path
            environment["STANDLOCK_INSTALL_APP"] = installedApp.path
            environment["STANDLOCK_INSTALL_STAGING_ROOT"] = applications.path
            environment["STANDLOCK_TEST_ROOT"] = root.path
            if let exitAfterProcessChecks {
                environment["STANDLOCK_TEST_EXIT_AFTER_CHECKS"] = String(exitAfterProcessChecks)
            }
            return try Self.run("/bin/bash", arguments: [
                Self.script.path, archive.path, "test-host", "2.0", "20",
            ], environment: environment)
        }

        func installedVersion() throws -> String {
            let data = try Data(contentsOf: installedApp.appendingPathComponent("Contents/Info.plist"))
            let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            return try #require(plist?["CFBundleShortVersionString"] as? String)
        }

        private static func makeApp(at app: URL, version: String, build: String) throws {
            let manager = FileManager.default
            let contents = app.appendingPathComponent("Contents")
            let executable = contents.appendingPathComponent("MacOS/StandLock")
            try manager.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
            let plist: [String: Any] = [
                "CFBundleIdentifier": "com.yagizdokumaci.standlock",
                "CFBundleShortVersionString": version,
                "CFBundleVersion": build,
                "CFBundleDisplayName": "StandLock",
                "CFBundleExecutable": "StandLock",
            ]
            let data = try PropertyListSerialization.data(
                fromPropertyList: plist, format: .xml, options: 0
            )
            try data.write(to: contents.appendingPathComponent("Info.plist"))
            try manager.copyItem(at: URL(fileURLWithPath: "/bin/sh"), to: executable)
        }

        private static func makeTools(in directory: URL) throws {
            let scripts = [
                "codesign": """
                #!/bin/bash
                if [ "${1:-}" = "-dvv" ]; then
                  printf 'Identifier=com.yagizdokumaci.standlock\\nTeamIdentifier=F475N5N7V6\\n' >&2
                fi
                """,
                "spctl": "#!/bin/bash\nexit 0\n",
                "ssh": """
                #!/bin/bash
                while [ "$1" != "--" ]; do shift; done
                shift 2
                eval "$1"
                """,
                "scp": """
                #!/bin/bash
                while [ "$1" != "--" ]; do shift; done
                shift
                source_path=${1#test-host:}
                destination_path=${2#test-host:}
                cp "$source_path" "$destination_path"
                """,
                "open": """
                #!/bin/bash
                : > "$STANDLOCK_TEST_ROOT/process.state"
                printf '0\\n' > "$STANDLOCK_TEST_ROOT/process.checks"
                """,
                "pgrep": """
                #!/bin/bash
                [ -f "$STANDLOCK_TEST_ROOT/process.state" ] || exit 1
                checks=$(cat "$STANDLOCK_TEST_ROOT/process.checks")
                checks=$((checks + 1))
                printf '%s\\n' "$checks" > "$STANDLOCK_TEST_ROOT/process.checks"
                if [ -n "${STANDLOCK_TEST_EXIT_AFTER_CHECKS:-}" ] && [ "$checks" -gt "$STANDLOCK_TEST_EXIT_AFTER_CHECKS" ]; then
                  rm -f "$STANDLOCK_TEST_ROOT/process.state"
                  exit 1
                fi
                """,
                "pkill": """
                #!/bin/bash
                rm -f "$STANDLOCK_TEST_ROOT/process.state"
                """,
            ]
            for (name, script) in scripts {
                let url = directory.appendingPathComponent(name)
                try Data(script.utf8).write(to: url)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            }
        }

        private static var script: URL {
            var url = URL(fileURLWithPath: #filePath)
            for _ in 0..<4 { url.deleteLastPathComponent() }
            return url.appendingPathComponent("scripts/install-ci-build.sh")
        }

        fileprivate static func run(
            _ executable: String, arguments: [String], environment: [String: String]? = nil
        ) throws -> Result {
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.environment = environment
            process.standardOutput = output
            process.standardError = output
            try process.run()
            process.waitUntilExit()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            return Result(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
        }
    }

    @Test func acceptsTheCIArchiveAndRejectsUnrelatedRoots() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let package = try fixture.packageWithCICommand()
        #expect(package.status == 0)
        let listing = try Fixture.run("/usr/bin/zipinfo", arguments: ["-1", fixture.archive.path])
        #expect(listing.output.contains("__MACOSX/"))

        let installed = try fixture.install()
        #expect(installed.status == 0, Comment(rawValue: installed.output))
        #expect(try fixture.installedVersion() == "2.0")

        let extra = fixture.root.appendingPathComponent("extra.txt")
        try Data("extra".utf8).write(to: extra)
        let appended = try Fixture.run("/usr/bin/zip", arguments: ["-q", "-j", fixture.archive.path, extra.path])
        #expect(appended.status == 0)
        let rejected = try fixture.install()
        #expect(rejected.status != 0)
        #expect(rejected.output.contains("zip must contain exactly one top-level StandLock.app"))
    }
}
