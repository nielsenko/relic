import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'src/rules/multiple_body_params_rule.dart';
import 'src/rules/multiple_http_methods_rule.dart';

/// Entry point for the Relic analyzer plugin.
///
/// The analysis server discovers this via the top-level `plugin` variable.
final plugin = RelicPlugin();

class RelicPlugin extends Plugin {
  @override
  String get name => 'relic';

  @override
  void register(PluginRegistry registry) {
    registry.registerWarningRule(MultipleHttpMethodsRule());
    registry.registerWarningRule(MultipleBodyParamsRule());
  }
}
