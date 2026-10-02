import Foundation

// `netpath enable` / `disable`: link this plugin folder into the folder `container` scans.

struct EnableError: Error, CustomStringConvertible {
    let description: String
}

func enable() throws {
    let source = try pluginDir()
    let target = try pluginTarget()
    let fm = FileManager.default

    if let dest = try? fm.destinationOfSymbolicLink(atPath: target.path) {
        if dest == source.path {
            print("Already enabled: \(target.path) → \(source.path)")
            return
        }
    } else if fm.fileExists(atPath: target.path) {
        throw EnableError(description: "\(target.path) already exists and is not a link. Remove it, then run again.")
    }

    try runAsNeeded([
        ["/bin/mkdir", "-p", target.deletingLastPathComponent().path],
        ["/bin/ln", "-sfn", source.path, target.path],
    ])
    print("Enabled: \(target.path) → \(source.path)")
    print("Run: container netpath")
}

func disable() throws {
    let target = try pluginTarget()
    let fm = FileManager.default

    guard (try? fm.destinationOfSymbolicLink(atPath: target.path)) != nil else {
        if fm.fileExists(atPath: target.path) {
            // A real folder came from `make install`. Leave it to `make uninstall`.
            throw EnableError(description: "\(target.path) is not a link. Remove it with `sudo make uninstall`.")
        }
        print("Already disabled")
        return
    }
    try runAsNeeded([["/bin/rm", target.path]])
    print("Disabled: removed \(target.path)")
}

/// Where `container` expects this plugin, e.g. /usr/local/libexec/container-plugins/netpath.
private func pluginTarget() throws -> URL {
    struct Status: Decodable {
        struct Paths: Decodable { let installRoot: String }
        let paths: Paths
    }
    let json = try sh("container", "system", "status", "--format", "json")
    let root = try JSONDecoder().decode(Status.self, from: Data(json.utf8)).paths.installRoot
    return URL(fileURLWithPath: root).appending(path: "libexec/container-plugins/netpath")
}

/// The folder holding bin/netpath and config.toml.
private func pluginDir() throws -> URL {
    guard let exe = Bundle.main.executableURL?.resolvingSymlinksInPath() else {
        throw EnableError(description: "cannot find the netpath binary")
    }
    let dir = exe.deletingLastPathComponent().deletingLastPathComponent()
    guard FileManager.default.fileExists(atPath: dir.appending(path: "config.toml").path) else {
        throw EnableError(description: "\(exe.path) is not inside a plugin folder. Install with brew or `make install` first.")
    }
    let stable = URL(fileURLWithPath: stablePath(dir.path))
    return FileManager.default.fileExists(atPath: stable.path) ? stable : dir
}

/// Brew's versioned Cellar path → its `opt` path, so the link survives `brew upgrade`.
func stablePath(_ path: String) -> String {
    // ponytail: assumes Homebrew's standard layout. Other paths pass through unchanged.
    path.replacingOccurrences(of: #"/Cellar/container-netpath/[^/]+/"#, with: "/opt/container-netpath/",
                              options: .regularExpression)
}

/// Runs each command. If one fails (e.g. /usr/local is not writable), retries it with sudo,
/// but only when someone can type a password.
private func runAsNeeded(_ cmds: [[String]]) throws {
    for cmd in cmds where !run(cmd) {
        guard isatty(STDIN_FILENO) == 1 else {
            let lines = cmds.map { "  sudo " + $0.joined(separator: " ") }.joined(separator: "\n")
            throw EnableError(description: "this needs root. Run:\n\(lines)")
        }
        guard run(["/usr/bin/sudo"] + cmd) else {
            throw EnableError(description: "`\(cmd.joined(separator: " "))` failed")
        }
    }
}

private func run(_ cmd: [String]) -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: cmd[0])
    p.arguments = Array(cmd.dropFirst())
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return false }
    p.waitUntilExit()
    return p.terminationStatus == 0
}
