import Commander
import Foundation
import IMsgCore

enum ServeCommand {
  static let spec = CommandSpec(
    name: "serve",
    abstract: "Launch a web UI for iMessage",
    discussion: nil,
    signature: CommandSignatures.withRuntimeFlags(
      CommandSignature(
        options: CommandSignatures.baseOptions() + [
          .make(
            label: "host",
            names: [.long("host")],
            help: "Bind address (default: 127.0.0.1)"
          ),
          .make(
            label: "port",
            names: [.long("port")],
            help: "Listen port (default: 8080)"
          ),
        ])
    ),
    usageExamples: [
      "imsg serve",
      "imsg serve --host 0.0.0.0 --port 3000",
    ]
  ) { values, _ in
    let dbPath = values.option("db") ?? MessageStore.defaultPath
    let host = values.option("host") ?? "127.0.0.1"
    let port = values.option("port").flatMap { Int($0) } ?? 8080
    let store = try MessageStore(path: dbPath)
    let server = WebServer(store: store, host: host, port: port)
    try await server.run()
  }
}
