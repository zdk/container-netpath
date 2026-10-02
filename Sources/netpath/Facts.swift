import Foundation

// Raw state read from the host. No judgement here; see Diagnose.swift.

struct Network {
    let name: String
    let mode: String
    let subnet: String?
    let gateway: String?
}

struct Container {
    let name: String
    let network: String
    let ip: String
}

struct Iface {
    var ip: String?
    var members: [String] = []
}

struct Egress {
    let iface: String
    let router: String
}

struct Facts {
    var networks: [Network]
    var containers: [Container]
    var ifaces: [String: Iface]
    /// Network name → interface the host routes its subnet to.
    var routes: [String: String]
    var egress: Egress?

    func bridge(withIP ip: String?) -> (name: String, iface: Iface)? {
        guard let ip else { return nil }
        return ifaces.first { $0.key.hasPrefix("bridge") && $0.value.ip == ip }
            .map { ($0.key, $0.value) }
    }
}

enum Failure: Error, CustomStringConvertible {
    case command(String)
    case notFound(String)

    var description: String {
        switch self {
        case .command(let c): "`\(c)` failed. Is the container system running? Try: container system start"
        case .notFound(let t): "no network, container, or IP named '\(t)'"
        }
    }
}

// MARK: - Collect

func collect() throws -> Facts {
    let containers = try decodeContainers(sh("container", "ls", "--format", "json"))
    let networks = try decodeNetworks(sh("container", "network", "list", "--format", "json"))
    let ifaces = parseIfconfig(try sh("/sbin/ifconfig", "-a"))

    // One probe per network is enough: all its containers share a subnet.
    var routes: [String: String] = [:]
    for n in networks {
        guard let c = containers.first(where: { $0.network == n.name }),
              let out = try? sh("/sbin/route", "-n", "get", c.ip),
              let iface = parseRouteGet(out)["interface"]
        else { continue }
        routes[n.name] = iface
    }

    var egress: Egress?
    if let out = try? sh("/sbin/route", "-n", "get", "default") {
        let r = parseRouteGet(out)
        if let i = r["interface"], let g = r["gateway"] { egress = Egress(iface: i, router: g) }
    }

    return Facts(networks: networks, containers: containers, ifaces: ifaces, routes: routes, egress: egress)
}

func sh(_ args: String...) throws -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = args
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    try p.run()
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    guard p.terminationStatus == 0 else { throw Failure.command(args.joined(separator: " ")) }
    return String(decoding: data, as: UTF8.self)
}

// MARK: - Parse

private struct LsEntry: Decodable {
    struct Attachment: Decodable {
        let network: String
        let ipv4Address: String?
    }
    struct Status: Decodable {
        let state: String
        let networks: [Attachment]?
    }
    let id: String
    let status: Status
}

func decodeContainers(_ json: String) throws -> [Container] {
    try JSONDecoder().decode([LsEntry].self, from: Data(json.utf8))
        .filter { $0.status.state == "running" }
        .flatMap { e in
            (e.status.networks ?? []).compactMap { a in
                // "192.168.64.2/24" → "192.168.64.2"
                a.ipv4Address.map { Container(name: e.id, network: a.network, ip: String($0.split(separator: "/")[0])) }
            }
        }
}

private struct NetEntry: Decodable {
    struct Config: Decodable {
        let name: String
        let mode: String?
    }
    struct Status: Decodable {
        let ipv4Gateway: String?
        let ipv4Subnet: String?
    }
    let configuration: Config
    let status: Status?
}

func decodeNetworks(_ json: String) throws -> [Network] {
    try JSONDecoder().decode([NetEntry].self, from: Data(json.utf8)).map {
        Network(name: $0.configuration.name, mode: $0.configuration.mode ?? "nat",
                subnet: $0.status?.ipv4Subnet, gateway: $0.status?.ipv4Gateway)
    }
}

/// Interface name → first IPv4 address and bridge members.
func parseIfconfig(_ text: String) -> [String: Iface] {
    var out: [String: Iface] = [:]
    var cur: String?
    for line in text.split(separator: "\n") {
        if let first = line.first, !first.isWhitespace, let colon = line.firstIndex(of: ":") {
            cur = String(line[..<colon])
            out[cur!] = Iface()
            continue
        }
        guard let cur else { continue }
        let f = line.split(whereSeparator: \.isWhitespace)
        guard f.count >= 2 else { continue }
        if f[0] == "inet", out[cur]?.ip == nil { out[cur]?.ip = String(f[1]) }
        if f[0] == "member:" { out[cur]?.members.append(String(f[1])) }
    }
    return out
}

/// `route -n get` output as key → value ("interface" → "en0").
func parseRouteGet(_ text: String) -> [String: String] {
    var out: [String: String] = [:]
    for line in text.split(separator: "\n") {
        let kv = line.split(separator: ":", maxSplits: 1)
        guard kv.count == 2 else { continue }
        out[kv[0].trimmingCharacters(in: .whitespaces)] = kv[1].trimmingCharacters(in: .whitespaces)
    }
    return out
}

// MARK: - Filter

extension Facts {
    /// Keep one network, or one container and its network. Matches name or IP.
    func filtered(_ target: String) throws -> Facts {
        var f = self
        if networks.contains(where: { $0.name == target }) {
            f.networks = networks.filter { $0.name == target }
            f.containers = containers.filter { $0.network == target }
            return f
        }
        let hits = containers.filter { $0.name == target || $0.ip == target }
        guard !hits.isEmpty else { throw Failure.notFound(target) }
        f.containers = hits
        f.networks = networks.filter { n in hits.contains { $0.network == n.name } }
        return f
    }
}
