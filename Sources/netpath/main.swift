import Foundation

let usage = """
    USAGE: container netpath [<network | container | ip>] [--json]

    Shows how traffic leaves each container network and where it breaks.

    OPTIONS:
      --json      Print JSON (for scripts and agents)
      -h, --help  Show this help

    EXIT CODES:
      0  all networks healthy or idle
      1  at least one network is broken
      2  could not inspect the host
    """

var args = Array(CommandLine.arguments.dropFirst())
if args.contains("-h") || args.contains("--help") {
    print(usage)
    exit(0)
}
let json = args.contains("--json")
args.removeAll { $0 == "--json" }

func fail(_ msg: String) -> Never {
    if json {
        let data = (try? JSONEncoder().encode(["error": msg])) ?? Data()
        print(String(decoding: data, as: UTF8.self))
    } else {
        FileHandle.standardError.write(Data("Error: \(msg)\n".utf8))
    }
    exit(2)
}

if let bad = args.first(where: { $0.hasPrefix("-") }) { fail("unknown option '\(bad)'\n\n\(usage)") }
if args.count > 1 { fail("expected at most one target\n\n\(usage)") }

do {
    var facts = try collect()
    if let target = args.first { facts = try facts.filtered(target) }
    let report = diagnose(facts)

    if json {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        print(String(decoding: try enc.encode(report), as: UTF8.self))
    } else {
        let color = isatty(STDOUT_FILENO) == 1 && ProcessInfo.processInfo.environment["NO_COLOR"] == nil
        print(render(report, Style(on: color)))
    }
    exit(report.networks.contains { $0.status == "broken" } ? 1 : 0)
} catch {
    fail("\(error)")
}
