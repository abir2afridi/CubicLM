/// CLI manifest system for the CubicLM terminal CLI manager (pure Dart).
///
/// Installation facts below were verified against official docs:
/// - Claude Code: `npm install -g @anthropic-ai/claude-code`, binary
///   `claude` (code.claude.com/docs). npm install needs Node 22+ and a
///   desktop-class platform (darwin/linux/win) — NO Android build.
/// - OpenCode: `npm i -g opencode-ai`, binary `opencode` (opencode.ai).
/// - Cline CLI: `npm install -g cline`, binary `cline`, Node 20+,
///   `cline auth` to sign in; CLI in preview, macOS/Linux (docs.cline.bot).
/// - Kilo CLI: `npm install -g @kilocode/cli` (kilo.ai/docs).
///
/// Nothing here is assumed Android-compatible: every manifest carries
/// honest platform notes, and install is BLOCKED (never faked) when the
/// Node runtime probe fails.
library;

/// Lifecycle states for a managed CLI (§14 of the terminal spec).
enum CliStatus {
  notInstalled,
  installing,
  installed,
  verifying,
  ready,
  runtimeMissing,
  binaryMissing,
  authRequired,
  updateAvailable,
  broken,
  uninstalling,
  error,
}

/// Short human label for UI badges.
String cliStatusLabel(CliStatus s) {
  switch (s) {
    case CliStatus.notInstalled:
      return 'Not installed';
    case CliStatus.installing:
      return 'Installing…';
    case CliStatus.installed:
      return 'Installed';
    case CliStatus.verifying:
      return 'Verifying…';
    case CliStatus.ready:
      return 'Ready';
    case CliStatus.runtimeMissing:
      return 'Runtime missing';
    case CliStatus.binaryMissing:
      return 'Binary missing';
    case CliStatus.authRequired:
      return 'Auth required';
    case CliStatus.updateAvailable:
      return 'Update available';
    case CliStatus.broken:
      return 'Broken';
    case CliStatus.uninstalling:
      return 'Removing…';
    case CliStatus.error:
      return 'Error';
  }
}

/// True when the CLI can actually be launched.
bool cliIsLaunchable(CliStatus s) =>
    s == CliStatus.ready ||
    s == CliStatus.updateAvailable ||
    s == CliStatus.authRequired;

/// How a CLI gets onto the device.
enum CliProviderKind {
  /// Real `npm install -g <pkg> --prefix <managed>` (verified packages).
  npm,

  /// Pre-existing system binary: detect + show status, never install.
  system,

  /// Not a binary: opens a status/info view (e.g. the Node runtime row).
  runtimeInfo,
}

/// One installable/detectable developer CLI.
class CliManifest {
  /// Stable id, e.g. 'claude-code'.
  final String id;
  final String displayName;
  final String description;
  final String category;
  final CliProviderKind provider;

  /// Binary name, e.g. 'claude'.
  final String command;

  /// Args that print the version, e.g. ['--version'].
  final List<String> versionArgs;

  /// Verified npm package (npm provider only), e.g. '@anthropic-ai/claude-code'.
  final String? npmPackage;

  /// Enforced Node major (0 = any working Node). Only set when verified.
  final int minNodeMajor;

  /// e.g. 'node'. Shown in UI + dependency checks.
  final String runtime;

  /// Honest platform note, e.g. 'Needs Node 22+. No Android build — desktop or managed runtime only.'
  final String platformNote;

  /// Auth guidance (never credentials), e.g. 'Run `claude` and log in when prompted.'
  final String authNote;

  const CliManifest({
    required this.id,
    required this.displayName,
    required this.description,
    required this.category,
    required this.provider,
    required this.command,
    this.versionArgs = const ['--version'],
    this.npmPackage,
    this.minNodeMajor = 0,
    this.runtime = 'node',
    this.platformNote = '',
    this.authNote = '',
  });
}

/// The built-in catalog. Only tools with verified installation facts.
const List<CliManifest> kCliCatalog = [
  CliManifest(
    id: 'claude-code',
    displayName: 'Claude Code',
    description: "Anthropic's AI coding agent for the terminal.",
    category: 'AI Coding',
    provider: CliProviderKind.npm,
    command: 'claude',
    npmPackage: '@anthropic-ai/claude-code',
    minNodeMajor: 22,
    platformNote:
        'npm install needs Node.js 22+ on macOS/Linux/Windows. No Android build exists — on-device install stays blocked until a managed Node runtime is present.',
    authNote: 'Needs an Anthropic account. Launch it and log in when prompted — CubicLM never stores your credentials.',
  ),
  CliManifest(
    id: 'opencode',
    displayName: 'OpenCode',
    description: 'Open-source AI coding agent for the terminal.',
    category: 'AI Coding',
    provider: CliProviderKind.npm,
    command: 'opencode',
    npmPackage: 'opencode-ai',
    platformNote:
        'Needs a working Node.js runtime. No Android build — on-device install stays blocked until a managed Node runtime is present.',
    authNote: 'Configure your model provider on first launch — CubicLM never stores your keys.',
  ),
  CliManifest(
    id: 'cline',
    displayName: 'Cline',
    description: 'AI coding agent (CLI in preview, plus IDE extension).',
    category: 'AI Coding',
    provider: CliProviderKind.npm,
    command: 'cline',
    versionArgs: ['version'],
    npmPackage: 'cline',
    minNodeMajor: 20,
    platformNote:
        'CLI officially supports macOS/Linux (Windows coming). Needs Node.js 20+. No Android build.',
    authNote: 'Run `cline auth` once to sign in — CubicLM never stores your credentials.',
  ),
  CliManifest(
    id: 'kilo',
    displayName: 'Kilo',
    description: 'AI coding agent CLI (OpenCode-compatible config).',
    category: 'AI Coding',
    provider: CliProviderKind.npm,
    command: 'kilo',
    npmPackage: '@kilocode/cli',
    platformNote:
        'Needs a working Node.js runtime. No Android build — on-device install stays blocked until a managed Node runtime is present.',
    authNote: 'Uses Kilo Gateway / your provider keys on first launch — CubicLM never stores them.',
  ),
  CliManifest(
    id: 'git',
    displayName: 'Git',
    description: 'Version control. Detected from the system, never installed by CubicLM.',
    category: 'Development',
    provider: CliProviderKind.system,
    command: 'git',
    runtime: 'system',
    platformNote: 'Uses the device system git when present. Many stock Android builds ship none.',
  ),
  CliManifest(
    id: 'node-runtime',
    displayName: 'Node.js',
    description: 'Managed JS runtime status. Required by Node-based CLIs.',
    category: 'Development',
    provider: CliProviderKind.runtimeInfo,
    command: 'node',
    runtime: 'node',
    platformNote: 'Probed live (managed dir + PATH). Place a compatible Node distribution in the app runtime dir to enable installs.',
  ),
];

/// A registry entry: what CubicLM installed (or adopted) + where.
class InstalledCli {
  final String manifestId;
  final String version;
  final String installDir;
  final String binaryPath;
  final String provider;
  final int installedAtMs;
  final int lastVerifiedMs;

  const InstalledCli({
    required this.manifestId,
    required this.version,
    required this.installDir,
    required this.binaryPath,
    required this.provider,
    required this.installedAtMs,
    required this.lastVerifiedMs,
  });

  Map<String, dynamic> toMap() => {
        'manifestId': manifestId,
        'version': version,
        'installDir': installDir,
        'binaryPath': binaryPath,
        'provider': provider,
        'installedAtMs': installedAtMs,
        'lastVerifiedMs': lastVerifiedMs,
      };

  factory InstalledCli.fromMap(Map m) => InstalledCli(
        manifestId: (m['manifestId'] ?? '').toString(),
        version: (m['version'] ?? '').toString(),
        installDir: (m['installDir'] ?? '').toString(),
        binaryPath: (m['binaryPath'] ?? '').toString(),
        provider: (m['provider'] ?? '').toString(),
        installedAtMs: (m['installedAtMs'] is int)
            ? m['installedAtMs'] as int
            : int.tryParse('${m['installedAtMs']}') ?? 0,
        lastVerifiedMs: (m['lastVerifiedMs'] is int)
            ? m['lastVerifiedMs'] as int
            : int.tryParse('${m['lastVerifiedMs']}') ?? 0,
      );
}

/// Match a typed `npm install -g <pkg>[...]` command to known packages.
/// Returns the matched npm package names (may be several).
List<String> matchNpmGlobalInstall(String command) {
  final parts = _splitShell(command);
  if (parts.length < 3) return [];
  if (parts[0] != 'npm') return [];
  var i = 1;
  // npm <install|i|add> [-g|--global] <pkgs...>
  if (!{'install', 'i', 'add', 'in'}.contains(parts[i])) return [];
  i++;
  final pkgs = <String>[];
  var global = false;
  for (; i < parts.length; i++) {
    final p = parts[i];
    if (p == '-g' || p == '--global') {
      global = true;
      continue;
    }
    if (p.startsWith('-')) continue; // other flags
    if (p.startsWith('.') || p.startsWith('/') || p.startsWith('http')) {
      continue; // paths/urls are not registry packages
    }
    pkgs.add(p); // version suffix stripped below (scope-aware)
  }
  if (!global || pkgs.isEmpty) return [];
  // Strip version suffixes but keep scopes: @scope/pkg@1.2 → @scope/pkg
  return pkgs.map((p) {
    if (p.startsWith('@')) {
      final rest = p.substring(1);
      final at = rest.indexOf('@');
      return at < 0 ? p : '@${rest.substring(0, at)}';
    }
    final at = p.indexOf('@');
    return at < 0 ? p : p.substring(0, at);
  }).toList();
}

List<String> _splitShell(String cmd) {
  final out = <String>[];
  final buf = StringBuffer();
  String? quote;
  for (var i = 0; i < cmd.length; i++) {
    final ch = cmd[i];
    if (quote != null) {
      if (ch == quote) {
        quote = null;
      } else {
        buf.write(ch);
      }
    } else if (ch == '"' || ch == "'") {
      quote = ch;
    } else if (ch == ' ' || ch == '\t') {
      if (buf.isNotEmpty) {
        out.add(buf.toString());
        buf.clear();
      }
    } else {
      buf.write(ch);
    }
  }
  if (buf.isNotEmpty) out.add(buf.toString());
  return out;
}

final _secretArg = RegExp(
    r'(--?(token|key|password|passwd|secret|api[-_]?key)\b\s*[= ]\s*\S+|password\s*=\s*\S+|Bearer\s+\S+)',
    caseSensitive: false);

/// Mask secret-looking fragments before echoing/logging a command.
String redactCommand(String command) =>
    command.replaceAllMapped(_secretArg, (_) => '[redacted]');

/// True when a command line looks secret-bearing (never persist these).
bool isSensitiveCommand(String command) =>
    _secretArg.hasMatch(command) ||
    RegExp(r'\b(auth|login|passwd)\b', caseSensitive: false)
        .hasMatch(command);
