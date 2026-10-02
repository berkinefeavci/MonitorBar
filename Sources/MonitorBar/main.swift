import Foundation

if CommandLine.arguments.contains("--probe") {
    let displays = DisplayDiscovery.externalDisplays()
    print("External displays: \(displays.count)")
    DDCClient.shared.probe(displays: displays) { results in
        for probe in results {
            let level = probe.brightness.map { "\($0.current)/\($0.maximum)" } ?? "unavailable"
            print("\(probe.display.name) [\(probe.display.id)]: brightness \(level)")
            if let issue = probe.issue { print("  \(issue)") }
        }
        exit(0)
    }
    RunLoop.main.run()
}
