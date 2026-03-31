import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

/// Reports a warning when a method has more than one body parameter
/// (`@JsonBody` or `@FormBody`).
class MultipleBodyParamsRule extends AnalysisRule {
  static const LintCode code = LintCode(
    'relic_multiple_body_params',
    'A method should have at most one body parameter '
        '(@JsonBody or @FormBody).',
    correctionMessage: 'Remove all but one body annotation.',
  );

  MultipleBodyParamsRule()
    : super(
        name: 'relic_multiple_body_params',
        description:
            'Warns when a method has multiple body parameter annotations.',
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

const _bodyAnnotations = {'JsonBody', 'FormBody'};

class _Visitor extends SimpleAstVisitor<void> {
  final AnalysisRule rule;

  _Visitor(this.rule);

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final parameters = node.parameters?.parameters;
    if (parameters == null) return;

    final bodyParams = <FormalParameter>[];
    for (final param in parameters) {
      final hasBody = param.metadata.any((a) {
        return _bodyAnnotations.contains(a.name.name);
      });
      if (hasBody) bodyParams.add(param);
    }

    if (bodyParams.length > 1) {
      for (final param in bodyParams.skip(1)) {
        rule.reportAtNode(param);
      }
    }
  }
}
