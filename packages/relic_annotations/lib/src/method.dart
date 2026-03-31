/// Marks a method as handling HTTP GET requests.
class Get {
  final String path;

  const Get([this.path = '/']);
}

/// Marks a method as handling HTTP POST requests.
class Post {
  final String path;

  const Post([this.path = '/']);
}

/// Marks a method as handling HTTP PUT requests.
class Put {
  final String path;

  const Put([this.path = '/']);
}

/// Marks a method as handling HTTP DELETE requests.
class Delete {
  final String path;

  const Delete([this.path = '/']);
}

/// Marks a method as handling HTTP PATCH requests.
class Patch {
  final String path;

  const Patch([this.path = '/']);
}
