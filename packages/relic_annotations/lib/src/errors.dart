/// Declares which `HttpException` subtypes an endpoint may throw.
class Errors {
  final List<Type> types;

  const Errors(this.types);
}
