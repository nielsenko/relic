import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

/// Reports a warning when a method has more than one HTTP method annotation
/// (e.g. both `@Get` and `@Post`).
class MultipleHttpMethodsRule extends AnalysisRule {
  static const LintCode code = LintCode(
    'relic_multiple_http_methods',
    'A method should have at most one HTTP method annotation '
        '(@Get, @Post, @Put, @Delete, @Patch).',
    correctionMessage: 'Remove all but one HTTP method annotation.',
  );

  MultipleHttpMethodsRule()
    : super(
        name: 'relic_multiple_http_methods',
        description:
            'Warns when a method has multiple HTTP method annotations.',
      );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addMethodDeclaration(this, _Visitor(this));
  }
}

const _httpMethodAnnotations = {'Get', 'Post', 'Put', 'Delete', 'Patch'};

class _Visitor extends SimpleAstVisitor<void> {
  final AnalysisRule rule;

  _Visitor(this.rule);

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final httpAnnotations = node.metadata.where((a) {
      final name = a.name.name;
      return _httpMethodAnnotations.contains(name);
    }).toList();

    if (httpAnnotations.length > 1) {
      for (final annotation in httpAnnotations.skip(1)) {
        rule.reportAtNode(annotation);
      }
    }
  }
}
