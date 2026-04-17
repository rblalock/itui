import Foundation
import HTTPTypes
import Hummingbird

extension WebServer {
  func registerStaticRoutes(router: Router<BasicRequestContext>) {
    router.get("/") { request, _ -> Response in
      Self.serveResource(
        name: "index", ext: "html", contentType: "text/html; charset=utf-8",
        requestHeaders: request.headers)
    }
    router.get("styles.css") { request, _ -> Response in
      Self.serveResource(
        name: "styles", ext: "css", contentType: "text/css; charset=utf-8",
        requestHeaders: request.headers)
    }
    router.get("app.js") { request, _ -> Response in
      Self.serveResource(
        name: "app", ext: "js", contentType: "application/javascript; charset=utf-8",
        requestHeaders: request.headers)
    }
    // Standalone verification page that exercises the contact/avatar API surface.
    // Serves at both `/debug` and `/debug.html` so it's easy to remember.
    router.get("debug") { request, _ -> Response in
      Self.serveResource(
        name: "debug", ext: "html", contentType: "text/html; charset=utf-8",
        requestHeaders: request.headers)
    }
    router.get("debug.html") { request, _ -> Response in
      Self.serveResource(
        name: "debug", ext: "html", contentType: "text/html; charset=utf-8",
        requestHeaders: request.headers)
    }
  }

  private static func serveResource(
    name: String, ext: String, contentType: String, requestHeaders: HTTPFields
  ) -> Response {
    guard let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "web"),
      let data = try? Data(contentsOf: url),
      let content = String(data: data, encoding: .utf8)
    else {
      return Response(status: .notFound, body: .init(byteBuffer: ByteBuffer(string: "Not Found")))
    }

    // Compute ETag from content hash
    let etag = "\"\(Self.djb2Hash(content))\""

    // Return 304 if client already has this version
    if let ifNoneMatch = requestHeaders[.ifNoneMatch], ifNoneMatch == etag {
      return Response(
        status: .notModified,
        headers: HTTPFields([
          HTTPField(name: .eTag, value: etag),
          HTTPField(name: .cacheControl, value: "public, max-age=3600, must-revalidate"),
        ])
      )
    }

    return Response(
      status: .ok,
      headers: HTTPFields([
        HTTPField(name: .contentType, value: contentType),
        HTTPField(name: .cacheControl, value: "public, max-age=3600, must-revalidate"),
        HTTPField(name: .eTag, value: etag),
      ]),
      body: .init(byteBuffer: ByteBuffer(string: content))
    )
  }

  /// Simple DJB2 hash for ETag generation — fast and sufficient for cache validation.
  private static func djb2Hash(_ string: String) -> String {
    var hash: UInt64 = 5381
    for byte in string.utf8 {
      hash = ((hash &<< 5) &+ hash) &+ UInt64(byte)
    }
    return String(hash, radix: 16)
  }
}
