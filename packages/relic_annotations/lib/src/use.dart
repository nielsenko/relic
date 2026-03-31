/// Applies middleware to a class or method.
///
/// Accepts either a `Middleware` function reference or a `MiddlewareObject`
/// instance. Both must be const.
class Use {
  final Object middleware;

  const Use(this.middleware);
}
