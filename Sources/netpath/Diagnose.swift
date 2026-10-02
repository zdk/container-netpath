// Turns Facts into a Report: walk each network's path and stop at the first break.

struct Report: Encodable {
    let networks: [NetworkReport]
}

struct NetworkReport: Encodable {
    let name: String
    let subnet: String?
    let mode: String
    let status: String  // healthy | broken | idle
    let containers: [ContainerRef]
    let path: [Step]
    let problem: Problem?
}

struct ContainerRef: Encodable {
    let name: String
    let ip: String
}

struct Step: Encodable {
    let step: String    // vmenet | bridge | route | nat | egress | router
    let name: String?   // bridge100, en0, ...
    let status: String  // ok | missing | skipped | assumed
    let detail: String?
}

struct Problem: Encodable {
    let code: String
    let detail: String
    let fix: String
    let related: String?
}

private let restart = "container system stop && container system start"

func diagnose(_ f: Facts) -> Report {
    let multi = f.networks.count > 1
    return Report(networks: f.networks.map { diagnose($0, f, multi: multi) })
}

private func diagnose(_ n: Network, _ f: Facts, multi: Bool) -> NetworkReport {
    let cs = f.containers.filter { $0.network == n.name }
    let refs = cs.map { ContainerRef(name: $0.name, ip: $0.ip) }
    func report(_ path: [Step], _ problem: Problem?) -> NetworkReport {
        NetworkReport(name: n.name, subnet: n.subnet, mode: n.mode,
                      status: cs.isEmpty ? "idle" : problem == nil ? "healthy" : "broken",
                      containers: refs, path: path, problem: problem)
    }
    // vmnet only creates the bridge while a container is attached.
    guard !cs.isEmpty else { return report([], nil) }

    let nat = n.mode == "nat"
    var path: [Step] = []
    // Mark the remaining steps as never reached, keeping path order.
    func stop(_ s: Step, _ p: Problem) -> NetworkReport {
        path.append(s)
        let order = nat ? ["vmenet", "bridge", "route", "nat", "egress", "router"] : ["vmenet", "bridge", "route"]
        for k in order where !path.contains(where: { $0.step == k }) {
            path.append(Step(step: k, name: nil, status: "skipped", detail: nil))
        }
        path.sort { order.firstIndex(of: $0.step)! < order.firstIndex(of: $1.step)! }
        return report(path, p)
    }

    guard let (bname, bridge) = f.bridge(withIP: n.gateway) else {
        path.append(Step(step: "vmenet", name: nil, status: "ok", detail: nil))
        return stop(
            Step(step: "bridge", name: nil, status: "missing", detail: "no bridge has gw \(n.gateway ?? "?")"),
            Problem(code: "bridge_missing",
                    detail: "\(cs.count) running container(s) but the host has no bridge for \(n.subnet ?? n.name)",
                    fix: restart, related: multi ? "apple/container#2051" : nil))
    }
    let members = bridge.members.isEmpty ? nil : bridge.members.joined(separator: ", ")
    path.append(Step(step: "vmenet", name: members, status: "ok", detail: nil))

    guard !bridge.members.isEmpty else {
        return stop(
            Step(step: "bridge", name: bname, status: "missing", detail: "no containers attached"),
            Problem(code: "bridge_detached", detail: "\(bname) exists but has no members",
                    fix: restart, related: multi ? "apple/container#2051" : nil))
    }
    path.append(Step(step: "bridge", name: bname, status: "ok", detail: "gw \(n.gateway ?? "?")"))

    let via = f.routes[n.name]
    let subnet = n.subnet ?? n.name
    guard via == bname else {
        return stop(
            Step(step: "route", name: nil, status: "missing", detail: "\(subnet) → \(via ?? "none"), not \(bname)"),
            Problem(code: "route_missing", detail: "host routes \(subnet) to \(via ?? "nowhere")",
                    fix: restart, related: nil))
    }
    path.append(Step(step: "route", name: nil, status: "ok", detail: "\(subnet) → \(bname)"))
    guard nat else { return report(path, nil) }

    guard let e = f.egress else {
        return stop(
            Step(step: "egress", name: nil, status: "missing", detail: "no default route"),
            Problem(code: "no_egress", detail: "the host has no default route",
                    fix: "Check the host's own network connection.", related: nil))
    }
    let hostIP = f.ifaces[e.iface]?.ip
    // NAT rules need root to read, so this step is inferred, not checked.
    path.append(Step(step: "nat", name: nil, status: "assumed", detail: "→ \(hostIP ?? e.iface)"))
    path.append(Step(step: "egress", name: e.iface, status: "ok", detail: hostIP))
    path.append(Step(step: "router", name: e.router, status: "ok", detail: "internet"))
    return report(path, nil)
}
