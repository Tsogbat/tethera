import Foundation

/// Subcommands and flags for the commands people run most next to agents.
enum CompletionSpecs {
    struct Item: Hashable {
        let name: String
        let detail: String?
    }

    struct Spec {
        var summary: String
        var subcommands: [Item] = []
        var flags: [Item] = []
        var subcommandFlags: [String: [Item]] = [:]
    }

    private static func items(_ pairs: KeyValuePairs<String, String>) -> [Item] {
        pairs.map { Item(name: $0.key, detail: $0.value.isEmpty ? nil : $0.value) }
    }

    static let all: [String: Spec] = {
        var specs: [String: Spec] = [:]
        specs["git"] = Spec(
            summary: "version control",
            subcommands: items(["status": "working tree status", "add": "stage changes", "commit": "record changes", "push": "upload commits",
                                "pull": "fetch and merge", "fetch": "download refs", "checkout": "switch branches or restore files",
                                "switch": "switch branches", "branch": "list, create or delete branches", "merge": "join histories",
                                "rebase": "reapply commits", "log": "commit history", "diff": "show changes", "stash": "set changes aside",
                                "reset": "reset HEAD", "restore": "restore files", "clone": "copy a repository", "init": "new repository",
                                "remote": "manage remotes", "tag": "manage tags", "cherry-pick": "apply a commit", "worktree": "linked checkouts",
                                "show": "show an object", "blame": "who changed each line", "revert": "undo a commit", "clean": "remove untracked files"]),
            flags: items(["--help": "", "--version": "", "-C": "run in a folder"]),
            subcommandFlags: [
                "commit": items(["-m": "message", "-a": "stage tracked changes", "--amend": "change the last commit", "--no-verify": "skip hooks"]),
                "push": items(["-u": "set upstream", "--force-with-lease": "force, safely", "--tags": "push tags", "--force": "overwrite the remote"]),
                "log": items(["--oneline": "one line each", "--graph": "draw branches", "-n": "limit", "--stat": "files changed", "-p": "patches"]),
                "checkout": items(["-b": "new branch", "--": "files follow"]),
                "switch": items(["-c": "new branch", "-": "previous branch"]),
                "branch": items(["-d": "delete merged", "-D": "delete", "-a": "all", "-m": "rename"]),
                "stash": items(["push": "", "pop": "", "list": "", "drop": "", "apply": ""]),
                "add": items(["-A": "everything", "-p": "interactively", "-u": "tracked files"]),
                "diff": items(["--staged": "staged changes", "--stat": "summary", "--name-only": "file names"]),
                "reset": items(["--hard": "discard changes", "--soft": "keep changes staged", "--mixed": "keep changes unstaged"]),
                "pull": items(["--rebase": "rebase instead of merge", "--ff-only": "fast-forward only"]),
            ])
        specs["brew"] = Spec(
            summary: "Homebrew",
            subcommands: items(["install": "install a formula or cask", "uninstall": "remove", "upgrade": "upgrade outdated", "update": "refresh Homebrew",
                                "outdated": "what's old", "list": "installed", "search": "find", "info": "details", "services": "background services",
                                "cleanup": "remove old versions", "doctor": "check setup", "tap": "add a repository", "--prefix": "where it lives"]),
            subcommandFlags: ["install": items(["--cask": "an app"]), "upgrade": items(["--cask": "apps", "--greedy": "include auto-updating apps"])])
        let npmSubcommands = items(["install": "install dependencies", "run": "run a script", "test": "run tests", "start": "start",
                                    "build": "", "ci": "clean install", "add": "add a dependency", "remove": "remove a dependency",
                                    "update": "update", "outdated": "what's old", "publish": "publish the package", "exec": "run a package binary",
                                    "init": "new package", "audit": "security audit", "dlx": "run without installing"])
        specs["npm"] = Spec(summary: "Node packages", subcommands: npmSubcommands, flags: items(["--save-dev": "", "-D": "dev dependency", "-g": "global"]))
        specs["pnpm"] = Spec(summary: "Node packages", subcommands: npmSubcommands, flags: items(["-D": "dev dependency", "-w": "workspace root", "--filter": ""]))
        specs["yarn"] = Spec(summary: "Node packages", subcommands: npmSubcommands, flags: items(["-D": "dev dependency"]))
        specs["bun"] = Spec(summary: "JavaScript runtime", subcommands: npmSubcommands + items(["x": "run a package"]))
        specs["docker"] = Spec(
            summary: "containers",
            subcommands: items(["ps": "running containers", "run": "start a container", "build": "build an image", "compose": "multi-container apps",
                                "exec": "run in a container", "logs": "container logs", "images": "images", "pull": "download an image",
                                "push": "upload an image", "stop": "stop", "rm": "remove containers", "rmi": "remove images", "system": "disk use and prune"]),
            subcommandFlags: ["run": items(["-it": "interactive", "-d": "detached", "--rm": "remove on exit", "-p": "publish a port", "-v": "mount", "-e": "env"]),
                              "ps": items(["-a": "all"]), "build": items(["-t": "tag", "-f": "Dockerfile"])])
        specs["kubectl"] = Spec(
            summary: "Kubernetes",
            subcommands: items(["get": "list resources", "describe": "details", "apply": "apply config", "delete": "delete resources",
                                "logs": "pod logs", "exec": "run in a pod", "port-forward": "forward a port", "rollout": "manage rollouts",
                                "config": "contexts", "scale": "", "top": "resource use"]),
            flags: items(["-n": "namespace", "-A": "all namespaces", "-o": "output format", "--context": ""]))
        specs["gh"] = Spec(
            summary: "GitHub",
            subcommands: items(["pr": "pull requests", "issue": "issues", "repo": "repositories", "run": "workflow runs", "release": "releases",
                                "auth": "sign in", "api": "call the API", "browse": "open in the browser", "workflow": "workflows", "secret": "secrets"]),
            subcommandFlags: ["pr": items(["create": "", "list": "", "view": "", "checkout": "", "merge": "", "status": ""]),
                              "run": items(["list": "", "watch": "", "view": ""])])
        specs["cargo"] = Spec(
            summary: "Rust",
            subcommands: items(["build": "compile", "run": "build and run", "test": "run tests", "check": "type-check", "clippy": "lint",
                                "fmt": "format", "add": "add a dependency", "update": "update dependencies", "doc": "documentation", "publish": "publish the crate"]),
            flags: items(["--release": "optimized", "--all-features": "", "-p": "package"]))
        specs["swift"] = Spec(
            summary: "Swift",
            subcommands: items(["build": "compile", "run": "build and run", "test": "run tests", "package": "package commands"]),
            flags: items(["-c": "configuration", "--filter": "tests to run", "--product": ""]))
        specs["claude"] = Spec(
            summary: "Claude Code",
            subcommands: items(["mcp": "MCP servers", "config": "settings", "update": "update Claude Code", "doctor": "check setup"]),
            flags: items(["-p": "print and exit", "--continue": "resume the last conversation", "-c": "continue", "--resume": "pick a conversation",
                          "--model": "model", "--permission-mode": "", "--dangerously-skip-permissions": "no prompts"]))
        specs["codex"] = Spec(
            summary: "Codex",
            subcommands: items(["exec": "run non-interactively", "login": "sign in", "resume": "continue a session", "mcp": "MCP servers"]),
            flags: items(["--model": "", "-m": "model", "--full-auto": "work without asking"]))
        specs["opencode"] = Spec(summary: "OpenCode", subcommands: items(["run": "one prompt", "auth": "providers", "models": "list models", "serve": "headless server"]))
        specs["ollama"] = Spec(
            summary: "local models",
            subcommands: items(["run": "chat with a model", "pull": "download a model", "list": "installed models", "ps": "loaded models",
                                "launch": "start an agent on a local model", "rm": "remove a model", "serve": "start the server"]))
        specs["tethera"] = Spec(
            summary: "Tethera sessions",
            subcommands: items(["list": "sessions", "new": "a new session", "attach": "attach here", "rename": "", "close": "end a session",
                                "open": "open beside this session", "changes": "this session's diff", "mcp": "browser tools for agents",
                                "bridge": "for another Mac over ssh", "handover": "move the daemon to this version", "version": ""]))
        return specs
    }()
}
