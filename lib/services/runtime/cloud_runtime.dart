/// Cloud runtime provider abstraction.
///
/// Heavy/unsupported projects can run remotely — but CubicLM ships NO
/// cloud execution backend today, so the default provider reports
/// `isConfigured == false` and the UI says so honestly instead of
/// pretending to deploy anywhere.
library;

/// A remote environment that can install deps + serve a preview URL.
abstract class CloudRuntimeProvider {
  /// Display name, e.g. 'CubicLM Cloud'.
  String get label;

  /// True only when backend URL + credentials are actually configured.
  bool get isConfigured;

  /// Why unavailable (shown in UI when ![isConfigured]).
  String get unavailableReason;
}

/// Default: no backend bundled — honest placeholder, never faked.
class UnconfiguredCloudRuntime implements CloudRuntimeProvider {
  @override
  String get label => 'Cloud runtime';

  @override
  bool get isConfigured => false;

  @override
  String get unavailableReason =>
      'No cloud runtime is configured in this build. '
      'Export the ZIP (project menu) and run `npm run dev` where Node exists, '
      'or place a compatible Node distribution in the app runtime dir and Recheck.';
}
