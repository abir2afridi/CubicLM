import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:google_fonts/google_fonts.dart';

/// Faithful Flutter port of the "Thinking orbs" particle engine
/// (orbs.jakubantalik.com). Each state is a 3D dot-cloud rendered on a
/// sphere with orthographic projection — pure grayscale ink that follows
/// the theme (white dots on dark, black dots on light), depth-modulated
/// alpha, and hard phase-continuous cuts between states.
///
/// States: Working, Searching, Solving, Listening, Connecting, Weaving,
/// Composing, Breathing, Shaping. With [autoCycle] the orb picks a random
/// state every few seconds; the label crossfades with a blur while the
/// text shimmers.
class ThinkingOrb extends StatefulWidget {
  const ThinkingOrb({
    super.key,
    this.size = 22,
    this.state,
    this.autoCycle = false,
    this.showLabel = false,
  });

  /// Rendered diameter in logical px. Presets are tuned for ~20 (inline)
  /// and ~64 (hero); other sizes interpolate the 20px preset.
  final double size;
  final OrbState? state;
  final bool autoCycle;
  final bool showLabel;

  @override
  State<ThinkingOrb> createState() => _ThinkingOrbState();
}

class _ThinkingOrbState extends State<ThinkingOrb>
    with SingleTickerProviderStateMixin {
  static const Duration _cyclePeriod = Duration(milliseconds: 2800);

  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;
  double _simTime = 0; // seconds, per-state speed applied
  Timer? _cycleTimer;
  late OrbState _state;

  @override
  void initState() {
    super.initState();
    _state = widget.state ?? OrbState.working;
    _ticker = createTicker(_onTick)..start();
    if (widget.autoCycle && widget.state == null) {
      _cycleTimer = Timer.periodic(_cyclePeriod, (_) {
        if (!mounted) return;
        setState(() => _state = _randomNext(_state));
      });
    }
  }

  // Sim time is never reset on state change — hard cut, continuous phase
  // (matches the reference engine's wall-clock behaviour).
  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    _simTime += dt * _speedFor(_state);
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant ThinkingOrb old) {
    super.didUpdateWidget(old);
    if (widget.state != null && widget.state != _state) {
      _state = widget.state!;
    }
  }

  static OrbState _randomNext(OrbState current) {
    final values = OrbState.values.where((s) => s != current).toList();
    return values[math.Random().nextInt(values.length)];
  }

  @override
  void dispose() {
    _cycleTimer?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final orb = CustomPaint(
      size: Size.square(widget.size),
      painter: _OrbPainter(
        simTime: _simTime,
        state: _state,
        isDark: isDark,
      ),
    );

    if (!widget.showLabel) return orb;

    return Row(mainAxisSize: MainAxisSize.min, children: [
      orb,
      const SizedBox(width: 10),
      _ShimmerLabel(text: _state.label, isDark: isDark, key: ValueKey(_state)),
    ]);
  }
}

// ════════════════════════════════════════════════════════════════════════
// Engine
// ════════════════════════════════════════════════════════════════════════

double _hash(double a, double b) {
  final s = math.sin(a * 12.9898 + b * 78.233) * 43758.5453;
  return s - s.floorToDouble();
}

double _fract(double x) => x - x.floorToDouble();

double _angleDiff(double a, double b) =>
    math.atan2(math.sin(a - b), math.cos(a - b));

/// Fibonacci sphere point for index i of n → (x, y, z) unit vector.
(double, double, double) _fibPoint(int i, int n) {
  final golden = math.pi * (3 - math.sqrt(5));
  final y = 1 - 2 * (i + .5) / n;
  final r = math.sqrt(math.max(0, 1 - y * y));
  final o = i * golden;
  return (r * math.cos(o), y, r * math.sin(o));
}

class _Dot {
  _Dot(this.x, this.y, this.r, this.ink, this.alpha);
  final double x, y, r, ink, alpha;
}

class _Line {
  _Line(this.x1, this.y1, this.x2, this.y2, this.ink, this.alpha, this.width);
  final double x1, y1, x2, y2, ink, alpha, width;
}

class _Frame {
  final List<_Dot> dots;
  final List<_Line> lines;
  _Frame(this.dots, this.lines);
}

/// Per-state speed multipliers (20px preset from the reference engine).
double _speedFor(OrbState s) => switch (s) {
      OrbState.working => 3.9,
      OrbState.searching => 2.665,
      OrbState.solving => 1.95,
      OrbState.listening => 3.998,
      OrbState.connecting => 6.63,
      OrbState.weaving => 2.75,
      OrbState.composing => 3.12,
      OrbState.breathing => 3.78,
      OrbState.shaping => 2.08,
    };

/// Orthographic camera: yaw → pitch. Returns projector (x,y,z)→(sx, sy, depth).
(double, double, double) Function(double, double, double) _camera(
    double cx, double cy, double scale, double yaw, double pitch) {
  final sy = math.sin(yaw), cyw = math.cos(yaw);
  final sp = math.sin(pitch), cp = math.cos(pitch);
  return (f, v, h) {
    final p = f * cyw + h * sy;
    final yy = -f * sy + h * cyw;
    final g = v * cp - yy * sp;
    final w = v * sp + yy * cp;
    return (cx + p * scale, cy - g * scale, w);
  };
}

_Frame _renderState(OrbState state, double t, double size, bool isDark) {
  switch (state) {
    case OrbState.working:
      return _orbits(t, size);
    case OrbState.searching:
      return _globe(t, size);
    case OrbState.solving:
      return _rubik(t, size);
    case OrbState.listening:
      return _wave(t, size);
    case OrbState.connecting:
      return _web(t, size);
    case OrbState.weaving:
      return _braid(t, size);
    case OrbState.composing:
      return _ribbon(t, size);
    case OrbState.breathing:
      return _ring(t, size);
    case OrbState.shaping:
      return _morph(t, size);
  }
}

// ── Working → "orbits": tilted particle rings with travelling movers ──

_Frame _orbits(double t, double size) {
  final cx = size / 2, cy = size / 2;
  final i = math.pow(size / 300, 0.6).toDouble();
  final R = size / 2 * 0.82;
  final proj = _camera(cx, cy, 1.0, t * 0.12, 0.3);
  final dots = <_Dot>[];
  const rings = 3, ghostsPerRing = 10, moversPerRing = 3;

  for (var p = 0; p < rings; p++) {
    final y = _hash(p.toDouble(), 1.7);
    final g = _hash(p.toDouble(), 5.2);
    final w = _hash(p.toDouble(), 8.9);
    final C = R * (0.45 + 0.52 * y);
    final incl = math.acos(2 * g - 1);
    final phi = w * 2 * math.pi;
    // Ring-plane orthonormal basis.
    final nx = math.sin(incl) * math.cos(phi);
    final ny = math.cos(incl);
    final nz = math.sin(incl) * math.sin(phi);
    var sx = -nz, sy = 0.0, sz = nx;
    final sl = math.sqrt(sx * sx + sz * sz);
    if (sl < 1e-6) {
      sx = 1;
      sz = 0;
    } else {
      sx /= sl;
      sz /= sl;
    }
    // N = normal × S
    final tx = ny * sz - nz * sy;
    final ty = nz * sx - nx * sz;
    final tz = nx * sy - ny * sx;

    // Ghost dots tracing the full ellipse.
    for (var s = 0; s < ghostsPerRing; s++) {
      final Y = s / ghostsPerRing * 2 * math.pi;
      final px = (sx * math.cos(Y) + tx * math.sin(Y)) * C;
      final py = (sy * math.cos(Y) + ty * math.sin(Y)) * C;
      final pz = (sz * math.cos(Y) + tz * math.sin(Y)) * C;
      final (X, py2, depth) = proj(px, py, pz);
      final z = ((pz / C) + 1) / 2;
      dots.add(_Dot(X, py2, 0.9 * i, 0.72, 0.5 * (0.4 + 0.6 * z)));
    }
    // Bright movers travelling along the ring.
    final dirSpeed = (0.25 + 0.55 * w) * (w > 0.5 ? 1.0 : -1.0);
    for (var m = 0; m < moversPerRing; m++) {
      final h2 = _hash(p * 7.0 + m, 3.3);
      final Y = t * dirSpeed + m / moversPerRing * 2 * math.pi + h2 * 6;
      final px = (sx * math.cos(Y) + tx * math.sin(Y)) * C;
      final py = (sy * math.cos(Y) + ty * math.sin(Y)) * C;
      final pz = (sz * math.cos(Y) + tz * math.sin(Y)) * C;
      final (X, py2, depth) = proj(px, py, pz);
      final z = ((pz / C) + 1) / 2;
      dots.add(_Dot(
          X, py2, (1.2 + 1.6 * z) * i, 0.3 - 0.22 * z, 1.0));
    }
  }
  return _Frame(dots, const []);
}

// ── Searching → "globe": lat/lon grid with a gaussian scan belt ──

_Frame _globe(double t, double size) {
  final cx = size / 2, cy = size / 2;
  final i = math.pow(size / 300, 0.6).toDouble();
  final R = size / 2 * 0.82;
  const latRings = 5, lonDensity = 14;
  const scanMul = 4.335, dimBase = 0.45;
  final proj = _camera(cx, cy, 1.0, t * 0.5, 0.4 + 0.06 * math.sin(t * 0.35));
  final dots = <_Dot>[];
  final f = t * (0.5 + (1.7 - 0.5) * scanMul);

  for (var j = 0; j < latRings; j++) {
    final lat = -math.pi / 2 + (j + 1) / (latRings + 1) * math.pi;
    final lonCount = math.max(2, (math.cos(lat).abs() * lonDensity).round());
    for (var k = 0; k < lonCount; k++) {
      final lon = k / lonCount * 2 * math.pi;
      final px = R * math.cos(lat) * math.sin(lon);
      final py = R * math.sin(lat);
      final pz = R * math.cos(lat) * math.cos(lon);
      final (X, Y, depth) = proj(px, py, pz);
      final z = ((pz / R) + 1) / 2;
      final front = math.max(0.0, z * 2 - 1); // front-hemisphere gate
      final N = _angleDiff(lon + t * 0.5, f);
      final D = math.exp(-(N * N) / 0.18) * front;
      dots.add(_Dot(
        X,
        Y,
        (0.6 + 1.7 * z + 1.0 * D) * i,
        0.62 - 0.54 * z,
        dimBase + (1 - dimBase) * math.min(1, D),
      ));
    }
  }
  return _Frame(dots, const []);
}

// ── Solving → "rubik": sphere grid with layer bands scrambling/solving ──

_Frame _rubik(double t, double size) {
  final cx = size / 2, cy = size / 2;
  final i = math.pow(size / 300, 0.6).toDouble();
  final R = size / 2 * 0.82;
  const latRings = 4, lonDensity = 12, moveCount = 14;
  final proj = _camera(cx, cy, 1.0, t * 0.55, 0.35 + 0.1 * math.sin(t * 0.9));
  final dots = <_Dot>[];

  // Move envelope: forward scramble then reverse unwind, then rest.
  const slot = 0.42, pauseAfter = 1.2;
  const cycle = 2 * moveCount * slot + pauseAfter;
  final o = (t % cycle);
  final amounts = List<double>.filled(moveCount, 0.0);
  if (o < 2 * moveCount * slot) {
    final s = (o / slot).floor();
    final f = (o - s * slot) / slot;
    final h = 1 - math.pow(1 - math.min(1, f / 0.7), 3).toDouble();
    if (s < moveCount) {
      for (var p = 0; p < s; p++) {
        amounts[p] = 1;
      }
      amounts[s] = h;
    } else {
      final p = 2 * moveCount - 1 - s;
      for (var y2 = 0; y2 < p; y2++) {
        amounts[y2] = 1;
      }
      if (p < moveCount) amounts[p] = h;
    }
  }

  for (var j = 0; j < latRings; j++) {
    final lat = -math.pi / 2 + (j + 1) / (latRings + 1) * math.pi;
    final lonCount = math.max(2, (math.cos(lat).abs() * lonDensity).round());
    for (var k = 0; k < lonCount; k++) {
      final lon = k / lonCount * 2 * math.pi;
      var px = R * math.cos(lat) * math.sin(lon);
      var py = R * math.sin(lat);
      var pz = R * math.cos(lat) * math.cos(lon);

      // Apply the 14 hash-seeded layer moves (axis, band, ±90°).
      var extraR = 0.0, inkBoost = 0.0;
      for (var m = 0; m < moveCount; m++) {
        final amt = amounts[m];
        if (amt <= 0) continue;
        final axis = (_hash(m.toDouble(), 11.1) * 3).floor();
        final bandSel =
            [-1.0, -0.5, 0.0][(_hash(m.toDouble(), 22.2) * 3).floor()];
        final angle = (math.pi / 2) * amt;
        final coord = axis == 0 ? px : (axis == 1 ? py : pz);
        if ((coord / R - bandSel * 0.66).abs() > 0.34) continue;
        var (a, b) = axis == 0
            ? (py, pz)
            : axis == 1
                ? (px, pz)
                : (px, py);
        final c = math.cos(angle), s2 = math.sin(angle);
        final na = a * c - b * s2;
        final nb = a * s2 + b * c;
        if (axis == 0) {
          py = na;
          pz = nb;
        } else if (axis == 1) {
          px = na;
          pz = nb;
        } else {
          px = na;
          py = nb;
        }
        extraR += 0.3 * amt;
        inkBoost += 0.14 * amt;
      }

      final (X, Y, depth) = proj(px, py, pz);
      final z = ((pz / R) + 1) / 2;
      dots.add(_Dot(X, Y, (0.6 + 1.7 * z + extraR) * i,
          (0.62 - 0.54 * z - inkBoost).clamp(0.0, 1.0), 1.0));
    }
  }
  return _Frame(dots, const []);
}

// ── Listening → "wave": stacked rings with two travelling sine waves ──

_Frame _wave(double t, double size) {
  final cx = size / 2, cy = size / 2;
  final i = math.pow(size / 300, 0.6).toDouble();
  final R = size / 2 * 0.874;
  const rings = 4, lonDensity = 13;
  final proj = _camera(cx, cy, 1.0, t * 0.18, 0.38);
  final dots = <_Dot>[];

  for (var h = 0; h < rings; h++) {
    final w = 0.62 * math.sin(t * 2.1 - h * 0.52) +
        0.38 * math.sin(t * 1.27 + h * 0.83);
    final C = R * (0.88 + 0.105 * w);
    final lat = -math.pi / 2 + (h + 1) / (rings + 1) * math.pi;
    final baseR = math.cos(lat) * C;
    final yOff = math.sin(lat) * C;
    final lonCount = math.max(2, (math.cos(lat).abs() * lonDensity).round());
    for (var k = 0; k < lonCount; k++) {
      final lon = k / lonCount * 2 * math.pi;
      final px = baseR * math.sin(lon);
      final py = yOff;
      final pz = baseR * math.cos(lon);
      final (X, Y, depth) = proj(px, py, pz);
      final z = ((pz / R) + 1) / 2;
      dots.add(_Dot(
        X,
        Y,
        (0.6 + 1.7 * z) * (1 + 0.4 * math.max(0, w)) * i,
        (0.66 - 0.56 * z - 0.1 * math.max(0, w)).clamp(0.0, 1.0),
        1.0,
      ));
    }
  }
  return _Frame(dots, const []);
}

// ── Connecting → "web": fibonacci nodes, proximity lines, signal hops ──

_Frame _web(double t, double size) {
  final cx = size / 2, cy = size / 2;
  final i = math.pow(size / 300, 0.6).toDouble();
  final R = size / 2 * 0.8;
  const nodeCount = 8, thr = 0.72, signals = 1;
  final proj = _camera(cx, cy, 1.0, t * 0.12, 0.32);
  final dots = <_Dot>[];
  final lines = <_Line>[];

  // Node positions with gentle value-noise wobble.
  final nodes = <List<double>>[];
  for (var s = 0; s < nodeCount; s++) {
    final (bx, by, bz) = _fibPoint(s, nodeCount);
    double wob(double seed, double rate) =>
        0.3 * (math.sin(t * rate + seed * 9.0) * 0.5 +
                math.sin(t * rate * 1.7 + seed * 31.0) * 0.5);
    var a = bx + wob(9.0 + s, 0.24);
    var d = by + wob(27.0 + s, 0.21);
    var m = bz + wob(55.0 + s, 0.27);
    final len = math.sqrt(a * a + d * d + m * m);
    a /= len;
    d /= len;
    m /= len;
    nodes.add([a, d, m]);
  }

  // Proximity edges.
  for (var a = 0; a < nodeCount; a++) {
    for (var b = a + 1; b < nodeCount; b++) {
      final dx = nodes[a][0] - nodes[b][0];
      final dy = nodes[a][1] - nodes[b][1];
      final dz = nodes[a][2] - nodes[b][2];
      final dist =
          math.sqrt(dx * dx + dy * dy + dz * dz);
      if (dist >= thr) continue;
      final mid = (nodes[a][2] + nodes[b][2]) / 2;
      final z = ((mid) + 1) / 2;
      final (x1, y1, _) = proj(nodes[a][0] * R, nodes[a][1] * R, nodes[a][2] * R);
      final (x2, y2, _) = proj(nodes[b][0] * R, nodes[b][1] * R, nodes[b][2] * R);
      lines.add(_Line(x1, y1, x2, y2, 0.42,
          (1 - dist / thr) * (0.3 + 0.55 * z), math.max(0.6, 0.8 * i)));
    }
  }

  // Node pulses.
  for (var s = 0; s < nodeCount; s++) {
    final n = nodes[s];
    final k = 1 + 0.25 * math.sin(t * 1.4 + s * 2.7);
    final m = (n[2] + 1) / 2;
    final (X, Y, _) = proj(n[0] * R, n[1] * R, n[2] * R);
    dots.add(_Dot(X, Y, (1.4 + 1.8 * m) * k * i, 0.55 - 0.45 * m, 1.0));
  }

  // Signal pulses hopping between random nodes.
  for (var s = 0; s < signals; s++) {
    final seed = 7.31 + s * 13.7;
    final hop = (t * 0.55 + seed).floorToDouble();
    final prog = _fract(t * 0.55 + seed);
    final a = nodes[(hop * _hash(hop, 3.1) * 97).floor() % nodeCount];
    final b = nodes[(hop * _hash(hop, 8.7) * 57).floor() % nodeCount];
    var x = a[0] + (b[0] - a[0]) * prog;
    var y = a[1] + (b[1] - a[1]) * prog;
    var zc = a[2] + (b[2] - a[2]) * prog;
    final len = math.sqrt(x * x + y * y + zc * zc);
    x /= len;
    y /= len;
    zc /= len;
    final I = ((zc + 1) / 2);
    final (X, Y, _) = proj(x * R, y * R, zc * R);
    dots.add(_Dot(X, Y, (1.4 * 1.5 + 1.8 * I) * i, 0.05, 0.5 + 0.5 * I));
  }

  return _Frame(dots, lines);
}

// ── Weaving → "braid": ghost sphere + three pole-to-pole strands ──

_Frame _braid(double t, double size) {
  final cx = size / 2, cy = size / 2;
  final i = math.pow(size / 300, 0.6).toDouble();
  final R = size / 2 * 0.76;
  const strands = 3, ptsPerStrand = 6, ghostCount = 17, turns = 3;
  final proj = _camera(cx, cy, 1.0, t * 0.4, 0.3);
  final dots = <_Dot>[];

  for (var g = 0; g < ghostCount; g++) {
    final (bx, by, bz) = _fibPoint(g, ghostCount);
    final (X, Y, depth) = proj(bx * R, by * R, bz * R);
    final z = ((by) + 1) / 2;
    dots.add(_Dot(X, Y, 0.8 * i, 0.78, 0.1 + 0.22 * z));
  }

  for (var p = 0; p < strands; p++) {
    final offset = p / strands * 2 * math.pi;
    for (var g = 0; g < ptsPerStrand; g++) {
      final w = (_fract(g / ptsPerStrand + t * 0.045) * 2 - 1) * 0.96;
      final C = math.sqrt(math.max(0, 1 - w * w));
      final poleFade = math.min(1, (1 - w.abs()) / 0.1);
      final az = w * math.pi * turns + offset;
      final d = 1 + 0.075 * math.sin(w * math.pi * turns * 2 + offset * 2 + t * 0.8);
      final px = math.cos(az) * C * d * R;
      final py = w * R * d;
      final pz = math.sin(az) * C * d * R;
      final (X, Y, depth) = proj(px, py, pz);
      final E = ((py / R) + 1) / 2;
      dots.add(_Dot(X, Y, (1.2 + 1.8 * E) * i, 0.55 - 0.45 * E,
          poleFade * (0.45 + 0.55 * E)));
    }
  }
  return _Frame(dots, const []);
}

// ── Composing → "ribbon": frozen camera, wobbling band lanes on sphere ──

_Frame _ribbon(double t, double size) {
  return _band(t, size,
      lanes: 2, segs: 20, ghosts: 8, faceOn: false, wobMul: 1.0);
}

// ── Breathing → "ring": face-on disc with gentle concentric ripples ──

_Frame _ring(double t, double size) {
  return _band(t, size,
      lanes: 2, segs: 15, ghosts: 0, faceOn: true, wobMul: 0.368);
}

_Frame _band(double t, double size,
    {required int lanes,
    required int segs,
    required int ghosts,
    required bool faceOn,
    required double wobMul}) {
  final cx = size / 2, cy = size / 2;
  final i = math.pow(size / 300, 0.6).toDouble();
  final R = size / 2 * 0.78;
  final proj = _camera(cx, cy, 1.0, faceOn ? 0.0 : t * 0.1, 0.3);
  final dots = <_Dot>[];
  final tilt = faceOn ? 0.0 : 0.55;

  for (var g = 0; g < ghosts; g++) {
    final (bx, by, bz) = _fibPoint(g, ghosts);
    final (X, Y, depth) = proj(bx * R, by * R, bz * R);
    final z = ((by) + 1) / 2;
    dots.add(_Dot(X, Y, 0.8 * i, 0.78, 0.1 + 0.22 * z));
  }

  for (var lane = 0; lane < lanes; lane++) {
    final pe = (lane - (lanes - 1) / 2) * 0.075;
    final edgeFall = ((lane - (lanes - 1) / 2).abs()) / (lanes / 2);
    for (var s = 0; s < segs; s++) {
      final Z = s / segs * 2 * math.pi;
      final ce = (0.16 * math.sin(Z * 3 - t * 1.7 + lane * 0.22) +
              0.07 * math.sin(Z * 5 + t * 1.1)) *
          wobMul;
      // Band point: ring on the tilted plane + radial (pe) and normal
      // (ce) offsets, renormalized onto the sphere.
      final cz = math.cos(Z), sz = math.sin(Z);
      final bx = cz + pe * cz + ce * -sz;
      final by = tilt + ce * 1.0;
      final bz = sz + pe * sz + ce * cz;
      final len = math.sqrt(bx * bx + by * by + bz * bz);
      final rx = bx / len * R;
      final ry = by / len * R;
      final rz = bz / len * R;
      final (X, Y, _) = proj(rx, ry, rz);
      final M = ((ry / R) + 1) / 2;
      dots.add(_Dot(
        X,
        Y,
        (1.1 + 1.7 * M) * (1 - 0.25 * edgeFall) * i,
        (0.52 - 0.44 * M + 0.18 * edgeFall).clamp(0.0, 1.0),
        0.4 + 0.6 * M,
      ));
    }
  }
  return _Frame(dots, const []);
}

// ── Shaping → "morph": dots morph circle → triangle → square ──

_Frame _morph(double t, double size) {
  final cx = size / 2, cy = size / 2;
  const dotCount = 18, spread = 1.45;
  final scale = size * 0.5; // shape coords are in unit space (±0.26)
  final dotR = math.max(0.35, 0.021 * 1.35 * spread * size);
  final dots = <_Dot>[];

  List<Offset> shape(int id) {
    if (id == 0) {
      // Circle radius 0.24
      return List.generate(dotCount, (k) {
        final a = -math.pi / 2 + k / dotCount * 2 * math.pi;
        return Offset(math.cos(a) * 0.24, math.sin(a) * 0.24);
      });
    }
    final verts = id == 1
        ? [const Offset(0, -0.26), const Offset(0.24, 0.16), const Offset(-0.24, 0.16)]
        : [
            const Offset(0, -0.2),
            const Offset(0.2, -0.2),
            const Offset(0.2, 0.2),
            const Offset(-0.2, 0.2),
          ];
    // Arc-length-uniform sampling around the closed polyline.
    final pts = <Offset>[];
    final lens = <double>[];
    var total = 0.0;
    for (var k = 0; k < verts.length; k++) {
      final a = verts[k], b = verts[(k + 1) % verts.length];
      final l = (b - a).distance;
      lens.add(l);
      total += l;
    }
    for (var k = 0; k < dotCount; k++) {
      var target = k / dotCount * total;
      for (var seg = 0; seg < verts.length; seg++) {
        if (target <= lens[seg]) {
          final f = lens[seg] == 0 ? 0.0 : target / lens[seg];
          pts.add(Offset(verts[seg].dx +
                  (verts[(seg + 1) % verts.length].dx - verts[seg].dx) * f,
              verts[seg].dy +
                  (verts[(seg + 1) % verts.length].dy - verts[seg].dy) * f));
          break;
        }
        target -= lens[seg];
      }
    }
    return pts;
  }

  const hold = 1.4, morphDur = 0.9, slot = 2.3, cycle = 6.9;
  final u = t % cycle;
  final slotIdx = (u / slot).floor() % 3;
  final slotT = u % slot;
  final from = shape(slotIdx);
  final to = shape((slotIdx + 1) % 3);
  final morphT = slotT < hold
      ? 0.0
      : math
          .min(1, (slotT - hold) / morphDur)
          .clamp(0.0, 1.0)
          .toDouble();
  final eased = morphT * morphT * (3 - 2 * morphT); // smoothstep
  final pulse = 1 + 0.02 * math.sin(u * 3.1);

  for (var k = 0; k < dotCount; k++) {
    final a = from[k % from.length], b = to[k % to.length];
    final x = cx + (a.dx + (b.dx - a.dx) * eased) * spread * scale;
    final y = cy + (a.dy + (b.dy - a.dy) * eased) * spread * scale;
    dots.add(_Dot(x, y, dotR * pulse, 0.0, 1.0)); // ink 0 → pure theme ink
  }
  return _Frame(dots, const []);
}

// ── Painter ──

class _OrbPainter extends CustomPainter {
  _OrbPainter({
    required this.simTime,
    required this.state,
    required this.isDark,
  });

  final double simTime;
  final OrbState state;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = _renderState(state, simTime, size.width, isDark);

    for (final l in frame.lines) {
      final gray = isDark ? (1 - l.ink) * 255 : l.ink * 255;
      final paint = Paint()
        ..color = Color.fromRGBO(
            gray.round(), gray.round(), gray.round(), l.alpha.clamp(0.0, 1.0))
        ..strokeWidth = l.width
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(l.x1, l.y1), Offset(l.x2, l.y2), paint);
    }

    // Back-to-front for correct translucent overlap.
    final sorted = [...frame.dots]..sort((a, b) => a.y.compareTo(b.y));
    for (final d in sorted) {
      final gray = isDark ? (1 - d.ink) * 255 : d.ink * 255;
      final paint = Paint()
        ..color = Color.fromRGBO(
            gray.round(), gray.round(), gray.round(), d.alpha.clamp(0.0, 1.0))
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(d.x, d.y), math.max(0.3, d.r), paint);
    }
  }

  @override
  bool shouldRepaint(_OrbPainter old) =>
      old.simTime != simTime || old.state != state || old.isDark != isDark;
}

// ════════════════════════════════════════════════════════════════════════
// Shimmer label (CSS .t-shimmer port)
// ════════════════════════════════════════════════════════════════════════

class _ShimmerLabel extends StatefulWidget {
  const _ShimmerLabel({super.key, required this.text, required this.isDark});

  final String text;
  final bool isDark;

  @override
  State<_ShimmerLabel> createState() => _ShimmerLabelState();
}

class _ShimmerLabelState extends State<_ShimmerLabel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: AnimatedBuilder(
          animation: anim,
          builder: (context, _) {
            final t = anim.value;
            final incoming = child.key == ValueKey(widget.text);
            final scale = incoming ? 0.25 + 0.75 * t : 1.0 - 0.75 * (1 - t);
            final blur = incoming ? (1 - t) * 4 : t * 4;
            return Transform.scale(
              scale: scale,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                child: child,
              ),
            );
          },
        ),
      ),
      child: _shimmerText(),
    );
  }

  Widget _shimmerText() {
    final base = widget.isDark
        ? Colors.white.withValues(alpha: 0.5)
        : Colors.black.withValues(alpha: 0.45);
    final highlight =
        widget.isDark ? Colors.white : const Color(0xFF0D0D0D);

    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = _c.value;
        return ShaderMask(
          shaderCallback: (bounds) {
            final dx = 1.4 - 2.8 * t;
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Colors.transparent,
                Colors.transparent,
                highlight,
                Colors.transparent,
                Colors.transparent,
              ],
              stops: [
                (dx - 0.35).clamp(0.0, 1.0),
                (dx - 0.12).clamp(0.0, 1.0),
                dx.clamp(0.0, 1.0),
                (dx + 0.12).clamp(0.0, 1.0),
                (dx + 0.35).clamp(0.0, 1.0),
              ],
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcATop,
          child: child,
        );
      },
      child: Text(widget.text,
          key: ValueKey(widget.text),
          style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
              color: base)),
    );
  }
}

// ── States ──

enum OrbState {
  working,
  searching,
  solving,
  listening,
  connecting,
  weaving,
  composing,
  breathing,
  shaping,
}

extension OrbStateLabel on OrbState {
  String get label => switch (this) {
        OrbState.working => 'Working',
        OrbState.searching => 'Searching',
        OrbState.solving => 'Solving',
        OrbState.listening => 'Listening',
        OrbState.connecting => 'Connecting',
        OrbState.weaving => 'Weaving',
        OrbState.composing => 'Composing',
        OrbState.breathing => 'Breathing',
        OrbState.shaping => 'Shaping',
      };
}
