import 'package:flutter_js/flutter_js.dart';
import 'package:get/get.dart';
import 'app_log_service.dart';

/// A service to execute JavaScript code snippets safely.
class CodeInterpreterService extends GetxService {
  late JavascriptRuntime _jsRuntime;

  @override
  void onInit() {
    super.onInit();
    try {
      _jsRuntime = getJavascriptRuntime();
      // Inject some basic console mock if needed
      _jsRuntime.evaluate("var console = { log: function(msg) { return msg; } };");
    } catch (e) {
      Get.find<AppLogService>().error('Failed to init JS Runtime', details: e);
    }
  }

  /// Executes JS code and returns the result as a string.
  Future<String> executeJs(String code) async {
    try {
      // Basic safety: wrap in a try-catch inside JS
      final wrappedCode = """
        (function() {
          try {
            $code
          } catch (e) {
            return 'Runtime Error: ' + e.toString();
          }
        })()
      """;
      
      final result = await _jsRuntime.evaluateAsync(wrappedCode);
      
      if (result.isError) {
        return 'Error: ${result.stringResult}';
      }
      
      return result.stringResult;
    } catch (e) {
      return 'Execution Error: $e';
    }
  }

  @override
  void onClose() {
    try {
      _jsRuntime.dispose();
    } catch (_) {}
    super.onClose();
  }
}
