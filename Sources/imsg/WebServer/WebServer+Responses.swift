import Foundation
import HTTPTypes
import Hummingbird

extension WebServer {
  // MARK: - Helpers

  static func queryString(request: Request, name: String) -> String? {
    guard let components = URLComponents(string: request.uri.description) else { return nil }
    return components.queryItems?.first { $0.name == name }?.value
  }

  static func queryInt(request: Request, name: String) -> Int? {
    guard let components = URLComponents(string: request.uri.description) else { return nil }
    return components.queryItems?.first { $0.name == name }.flatMap { Int($0.value ?? "") }
  }

  static func queryInt64(request: Request, name: String) -> Int64? {
    guard let components = URLComponents(string: request.uri.description) else { return nil }
    return components.queryItems?.first { $0.name == name }.flatMap { Int64($0.value ?? "") }
  }

  static func queryBool(request: Request, name: String) -> Bool? {
    guard let components = URLComponents(string: request.uri.description) else { return nil }
    guard let value = components.queryItems?.first(where: { $0.name == name })?.value
    else { return nil }
    return value == "true" || value == "1"
  }

  static func jsonResponse<T: Encodable>(_ value: T) -> Response {
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.withoutEscapingSlashes]
      let data = try encoder.encode(value)
      let json = String(data: data, encoding: .utf8) ?? "{}"
      return Response(
        status: .ok,
        headers: HTTPFields([
          HTTPField(name: .contentType, value: "application/json"),
          HTTPField(name: .cacheControl, value: "no-store"),
        ]),
        body: .init(byteBuffer: ByteBuffer(string: json))
      )
    } catch {
      return errorResponse(status: .internalServerError, message: "encoding error")
    }
  }

  static func errorResponse(status: HTTPResponse.Status, message: String) -> Response {
    let json: String
    if let data = try? JSONEncoder().encode(["error": message]),
      let str = String(data: data, encoding: .utf8)
    {
      json = str
    } else {
      json = "{\"error\":\"internal error\"}"
    }
    return Response(
      status: status,
      headers: HTTPFields([
        HTTPField(name: .contentType, value: "application/json"),
        HTTPField(name: .cacheControl, value: "no-store"),
      ]),
      body: .init(byteBuffer: ByteBuffer(string: json))
    )
  }
}
