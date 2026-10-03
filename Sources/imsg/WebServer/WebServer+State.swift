import Foundation
import HTTPTypes
import Hummingbird

extension WebServer {
  func registerStateRoutes(api: RouterGroup<BasicRequestContext>) {
    let themes = themeStore
    let contacts = contactResolver

    api.get("theme") { _, _ -> Response in
      Self.jsonResponse(ThemeResponse(theme: await themes.current()))
    }

    api.post("theme") { request, _ -> Response in
      guard
        request.headers[.contentType]?.split(separator: ";").first?
          .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "application/json"
      else {
        return Self.errorResponse(
          status: .unsupportedMediaType, message: "expected application/json")
      }
      let body = try await request.body.collect(upTo: 16_384)
      guard let theme = try? JSONDecoder().decode(OmarchyTheme.self, from: Data(buffer: body)),
        OmarchyThemeStore.isValid(theme)
      else {
        return Self.errorResponse(status: .badRequest, message: "invalid theme palette")
      }
      try await themes.update(theme)
      return Self.jsonResponse(ThemeResponse(theme: await themes.current()))
    }

    api.post("contacts/refresh") { _, _ -> Response in
      await contacts.refresh()
      return Self.jsonResponse(OkResponse(ok: true))
    }

    // This stream observes cheap in-memory state. Contact notifications invalidate
    // the resolver; a one-minute expiry also recovers missed notifications/permissions.
    api.get("state/events") { _, _ -> Response in
      let body = ResponseBody { writer in
        var previousTheme: OmarchyTheme?
        var previousRevision: String?
        var heartbeat = 0
        try await writer.write(ByteBuffer(string: ": connected\nretry: 3000\n\n"))
        while !Task.isCancelled {
          await contacts.loadIfNeeded()
          let revision = await contacts.revision
          if previousRevision != revision {
            previousRevision = revision
            try await writer.write(ByteBuffer(string: "event: contacts\ndata: {}\n\n"))
          }
          let theme = await themes.current()
          if theme != previousTheme {
            previousTheme = theme
            let json = try JSONEncoder().encode(ThemeResponse(theme: theme))
            let text = String(decoding: json, as: UTF8.self)
            try await writer.write(ByteBuffer(string: "event: theme\ndata: \(text)\n\n"))
          }
          if heartbeat % 15 == 0 {
            try await writer.write(ByteBuffer(string: ": heartbeat\n\n"))
          }
          heartbeat += 1
          try await Task.sleep(for: .seconds(1))
        }
        try await writer.finish(nil)
      }
      return Response(
        status: .ok,
        headers: HTTPFields([
          HTTPField(name: .contentType, value: "text/event-stream; charset=utf-8"),
          HTTPField(name: .cacheControl, value: "no-cache, no-transform"),
          HTTPField(name: .init("X-Accel-Buffering")!, value: "no"),
        ]), body: body
      )
    }
  }
}

private struct ThemeResponse: Codable {
  let theme: OmarchyTheme?
}
