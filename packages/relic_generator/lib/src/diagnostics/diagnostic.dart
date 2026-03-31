/// Severity levels for generator diagnostics.
enum DiagnosticSeverity { error, warning, info }

/// A diagnostic message produced during analysis.
class GeneratorDiagnostic {
  /// The severity of this diagnostic.
  final DiagnosticSeverity severity;

  /// Human-readable message.
  final String message;

  /// The source element that caused this diagnostic (for location reporting).
  final String? elementName;

  /// Optional fix suggestion.
  final String? suggestion;

  const GeneratorDiagnostic({
    required this.severity,
    required this.message,
    this.elementName,
    this.suggestion,
  });

  @override
  String toString() =>
      '[$severity] $message${elementName != null ? ' (at $elementName)' : ''}';
}
