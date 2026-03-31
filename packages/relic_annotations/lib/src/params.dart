/// Binds a parameter to a path segment.
///
/// If [name] is null, the Dart parameter name is used.
class Path {
  final String? name;

  const Path([this.name]);
}

/// Binds a parameter to a query string value.
///
/// If [name] is null, the Dart parameter name is used.
class Query {
  final String? name;

  const Query([this.name]);
}

/// Binds a parameter to a request header.
///
/// If [name] is null, the Dart parameter name is used.
class Header {
  final String? name;

  const Header([this.name]);
}

/// Deserializes the request body as JSON via Codable.
class JsonBody {
  const JsonBody();
}

/// Deserializes the request body as form-urlencoded.
class FormBody {
  const FormBody();
}

/// Injects the raw `Request` object.
class Req {
  const Req();
}
