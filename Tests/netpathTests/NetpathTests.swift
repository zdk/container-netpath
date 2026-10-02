import Testing
@testable import netpath

let ifconfig = """
    en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
    \tinet 192.168.1.140 netmask 0xffffff00 broadcast 192.168.1.255
    bridge100: flags=8a63<UP,BROADCAST,SMART,RUNNING,ALLMULTI,SIMPLEX,MULTICAST> mtu 1500
    \tinet 192.168.64.1 netmask 0xffffff00 broadcast 192.168.64.255
    \tmember: vmenet0 flags=20003<LEARNING,DISCOVER,VIRTIO>
    \tmember: vmenet1 flags=20003<LEARNING,DISCOVER,VIRTIO>
    """

let netA = Network(name: "a", mode: "nat", subnet: "192.168.64.0/24", gateway: "192.168.64.1")
let netB = Network(name: "b", mode: "nat", subnet: "10.77.20.0/24", gateway: "10.77.20.1")

func facts(_ networks: [Network], _ containers: [Container], routes: [String: String]) -> Facts {
    Facts(networks: networks, containers: containers, ifaces: parseIfconfig(ifconfig),
          routes: routes, egress: Egress(iface: "en0", router: "192.168.1.1"))
}

@Test func parsesIfconfig() {
    let i = parseIfconfig(ifconfig)
    #expect(i["en0"]?.ip == "192.168.1.140")
    #expect(i["bridge100"]?.ip == "192.168.64.1")
    #expect(i["bridge100"]?.members == ["vmenet0", "vmenet1"])
}

@Test func parsesRouteGet() {
    let r = parseRouteGet("   route to: default\n    gateway: 192.168.1.1\n  interface: en0\n")
    #expect(r["gateway"] == "192.168.1.1")
    #expect(r["interface"] == "en0")
}

@Test func decodesRunningContainersOnly() throws {
    let json = """
        [{"id":"a1","status":{"state":"running","networks":[{"network":"a","ipv4Address":"192.168.64.2/24"}]}},
         {"id":"a2","status":{"state":"stopped"}}]
        """
    let cs = try decodeContainers(json)
    #expect(cs.map(\.name) == ["a1"])
    #expect(cs.first?.ip == "192.168.64.2")
}

@Test func healthyPathReachesRouter() {
    let r = diagnose(facts([netA], [Container(name: "a1", network: "a", ip: "192.168.64.2")],
                           routes: ["a": "bridge100"]))
    let n = r.networks[0]
    #expect(n.status == "healthy")
    #expect(n.path.map(\.step) == ["vmenet", "bridge", "route", "nat", "egress", "router"])
    #expect(n.path.last?.name == "192.168.1.1")
}

// #2051: b runs but no bridge holds b's gateway.
@Test func missingBridgeIsBroken() {
    let r = diagnose(facts([netA, netB], [Container(name: "b1", network: "b", ip: "10.77.20.2")],
                           routes: ["b": "en0"]))
    let n = r.networks.first { $0.name == "b" }!
    #expect(n.status == "broken")
    #expect(n.problem?.code == "bridge_missing")
    #expect(n.problem?.related == "apple/container#2051")
    #expect(n.path.map(\.status) == ["ok", "missing", "skipped", "skipped", "skipped", "skipped"])
    #expect(r.networks.first { $0.name == "a" }?.status == "idle")
}

@Test func wrongRouteIsBroken() {
    let r = diagnose(facts([netA], [Container(name: "a1", network: "a", ip: "192.168.64.2")],
                           routes: ["a": "en0"]))
    #expect(r.networks[0].problem?.code == "route_missing")
}

@Test func plainTextHasNoEscapes() {
    let r = diagnose(facts([netA], [Container(name: "a1", network: "a", ip: "192.168.64.2")],
                           routes: ["a": "bridge100"]))
    #expect(!render(r, Style(on: false)).contains("\u{1B}"))
}

// Route check must still work when the filter drops the network's other containers.
@Test func filterByContainerKeepsRoute() throws {
    let f = facts([netA], [Container(name: "a1", network: "a", ip: "192.168.64.2"),
                           Container(name: "a2", network: "a", ip: "192.168.64.3")],
                  routes: ["a": "bridge100"])
    let n = diagnose(try f.filtered("a2")).networks[0]
    #expect(n.containers.map(\.name) == ["a2"])
    #expect(n.status == "healthy")
}
