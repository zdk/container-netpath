// Text view: containers on top, then each hop on the host, then the router.

struct Style {
    let on: Bool

    private func c(_ code: String, _ s: String) -> String { on ? "\u{1B}[\(code)m\(s)\u{1B}[0m" : s }
    func bold(_ s: String) -> String { c("1", s) }
    func dim(_ s: String) -> String { c("2", s) }
    func red(_ s: String) -> String { c("31", s) }
    func green(_ s: String) -> String { c("32", s) }
    func yellow(_ s: String) -> String { c("33", s) }
}

func render(_ r: Report, _ st: Style) -> String {
    var out = r.networks.map { render($0, st) }
    let broken = r.networks.filter { $0.status == "broken" }
    var footer = st.dim("\(r.networks.count) network(s) · \(broken.count) broken")
    if broken.contains(where: { $0.problem?.related != nil }) {
        footer += "\n" + st.yellow("⚠ A network lost its bridge while others exist. Likely apple/container#2051.")
    }
    out.append(footer)
    return out.joined(separator: "\n\n")
}

private let labels = ["vmenet": "vmenet", "bridge": "bridge", "route": "route", "nat": "NAT", "egress": "egress"]

private func render(_ n: NetworkReport, _ st: Style) -> String {
    let status = switch n.status {
    case "healthy": st.green("✓ healthy")
    case "broken": st.red("✗ broken")
    default: st.dim("· idle")
    }
    let head = "\(n.name)  \(n.subnet ?? "")"
    var lines = [st.bold(n.name) + "  " + (n.subnet ?? "") + pad(head, 56) + status]
    guard n.status != "idle" else {
        lines.append("  " + st.dim("no running containers"))
        return lines.joined(separator: "\n")
    }

    // Left column label for each step.
    func label(_ s: Step) -> String {
        if s.step == "router" { return "router \(s.name ?? "")" }
        return s.name ?? labels[s.step] ?? s.step
    }
    let col = (n.containers.map { "\($0.name) \($0.ip)".count } + n.path.map { label($0).count }).max() ?? 0
    let bar = String(repeating: "═", count: col + 4) + "╪"

    lines.append("")
    for (i, c) in n.containers.enumerated() {
        let len = c.name.count + 1 + c.ip.count
        lines.append("  " + st.bold(c.name) + " " + c.ip + " " + String(repeating: "─", count: col - len + 1) + (i == 0 ? "┐" : "┤"))
    }
    lines.append(st.dim(bar + "═══ host ══════"))

    for s in n.path {
        if s.step == "router" { lines.append(st.dim(bar + String(repeating: "═", count: 15))) }
        let l = label(s)
        let left = "  " + l + String(repeating: " ", count: col - l.count + 2)
        switch s.status {
        case "missing":
            lines.append(st.red(left + "✗  " + (s.detail ?? "missing")))
        case "skipped":
            lines.append(st.dim(left + "·  not reached"))
        default:
            let detail = s.step == "router" ? "→ internet " + st.green("✓") : s.detail ?? ""
            lines.append(left + "▼" + (detail.isEmpty ? "" : "  " + detail))
        }
    }
    if let p = n.problem {
        lines.append("")
        lines.append("  " + p.detail)
        lines.append("  fix: " + p.fix)
    }
    return lines.joined(separator: "\n")
}

private func pad(_ s: String, _ width: Int) -> String {
    String(repeating: " ", count: max(2, width - s.count))
}
