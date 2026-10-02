// The token boundary. Nothing below this file defines a colour, a size, a
// radius or a duration — everything else in lib/ui2 spends what is declared
// here, and `test/ui2_tokens_test.dart` fails the build if it doesn't.
//
// Three things this file owns that the previous design system did not:
//
//   1. CONTRAST IS SOLVED, NOT ASSERTED. Muted ink and every accent used as
//      text or as a fill are pushed to a WCAG AA (4.5:1) floor by `P.on` /
//      `P.fill`, against the worst surface they can legally land on. The old
//      caption token measured 2.20–2.71:1 across 223 call sites; a token that
//      *can* be misused eventually is. `test/ui2_contrast_test.dart` proves
//      the floor holds in both themes for every accent.
//   2. MOTION IS GATED ONCE. `motion()` and `animate()` are the only way to
//      get a non-zero duration, and they return `Duration.zero` when the
//      platform asks for reduced motion. No call site can opt out, and the
//      tokens test forbids `.repeat(` anywhere in lib/ui2 so an infinite loop
//      can never survive the gate. That gate reaches the NAVIGATOR too:
//      `buildTheme` installs a `pageTransitionsTheme` that returns the page
//      unanimated (22 routes were sliding at full duration under Reduce
//      Motion), and `sheetMotion()` does the same for the four modal sheets,
//      which do not consult a theme at all. Dialogs still use Flutter's own
//      fade-and-scale — small, centred, and the least nauseogenic of the
//      three — so they are deliberately left alone.
//   3. BOTH THEMES ARE DESIGNED. Every colour is defined for light and dark in
//      the same expression. There is no token that exists only inside a
//      dark-mode branch.

import 'dart:math' as math;
import 'package:flutter/material.dart';

/// ── COLOUR ────────────────────────────────────────────────────────────────
///
/// Raw pigment. These are *not* safe to paint text with directly — most of
/// them fail AA on white. Run them through [P.on] (accent as text) or
/// [P.fill] (accent as a filled surface under [P.inkOnFill]) first.
class C {
  // STRATA — every accent is a mineral, and each one means one thing.
  // The names stay generic (green, blue…) because 800 call sites spend them
  // by role; the values are the survey palette.
  static const green = Color(0xFF5CC9A7); // verdigris — recovery, good
  static const greenD = Color(0xFF3FA88A); // weathered verdigris
  static const blue = Color(0xFF6C89EE); // lapis — sleep
  static const purple = Color(0xFFA58BE8); // amethyst — mind

  static const orange = Color(0xFFE0662E); // iron oxide — strain, load
  static const red = Color(0xFFEE6B7E); // rhodochrosite — heart, and warnings
  static const teal = Color(0xFF4FB6C2); // chrysocolla — breath, calm
  static const yellow = Color(0xFFE8CB4F); // sulphur — food, energy
  static const pink = Color(0xFFE48BD0); // kunzite — cycle
  static const indigo = Color(0xFF7A83E8); // azurite

  /// Two light blues the ramps need and nothing else does: the light-sleep
  /// lane sits between REM and deep, and zone 1 sits below `blue`. They live
  /// here rather than inside the painters because a palette that is partly in
  /// theme.dart and partly in charts.dart is two palettes.
  static const sky = Color(0xFF9DB0F5); // celestine — REM / light lanes
  static const blueSoft = Color(0xFF8FA6F0);

  /// The route ramp, and only the route ramp.
  ///
  /// Brighter and more saturated than the UI accents on purpose: this is the
  /// one mark in the app that is drawn over an arbitrary photograph and a
  /// darkened basemap rather than over a known surface, and the UI greens and
  /// reds — tuned to clear 4.5:1 as TEXT on a card — go muddy there.
  ///
  /// Deliberately NOT in [all]. `all` is the set the contrast sweep measures
  /// as ink and as fill, and these are neither: they are a line on a picture.
  /// Putting them in would be asking the wrong question of them.
  static const routeFast = Color(0xFF7CFF6B);
  static const routeMid = Color(0xFFFFC83D);
  static const routeHard = Color(0xFFFF8A30);
  static const routeSlow = Color(0xFFFF4D4D);

  /// The basemap's two ends, which is the whole of the map's styling: every
  /// tile pixel is mapped onto the line between them by `_themeFilter`.
  ///
  /// What makes the map READABLE is the distance between these two, not how
  /// low either one is. Both ends have been wrong once:
  ///
  ///   · ceiling `#4A5568` — OSM's land polygon is near-white and lands on
  ///     the ceiling, so the whole card became a mid-grey slab.
  ///   · ceiling `#232B39` — dark enough that land, water and roads all
  ///     collapsed into each other and the map vanished entirely. On a card
  ///     with no photo the map IS the content, so that is worse.
  ///
  /// This pair keeps the card unmistakably dark while leaving enough range
  /// between water, land and roads to read as a place. It is also the only
  /// lever there is on the labels and street names, which are rendered into
  /// the raster and cannot be asked for separately — they sit near the
  /// ceiling, so a ceiling this far down leaves them as texture, not type.
  static const mapFloor = Color(0xFF0A1018);
  static const mapCeil = Color(0xFF44536D);

  // neutrals
  // basalt → bone, warm-neutral so the minerals sit in rock, not in slate
  static const n900 = Color(0xFF0E1011);
  static const n800 = Color(0xFF1C2022);
  static const n600 = Color(0xFF4A4C4A);
  static const n500 = Color(0xFF6F6D66);
  static const n400 = Color(0xFF8C897F);
  static const n300 = Color(0xFFC9C5BA);
  static const n200 = Color(0xFFE2DED3);
  static const n100 = Color(0xFFEDE9E0);
  static const n50 = Color(0xFFF5F2EB);

  static const white = Color(0xFFFFFFFF);

  /// Each domain owns an accent — the mental map is colour-coded, and the map
  /// is the point. These five are the five tabs, in order, forever.
  static const domHome = green;
  static const domHealth = red;
  static const domFood = yellow;
  static const domMove = orange;
  static const domMind = purple;

  /// Every accent the contrast test sweeps. Adding a colour above without
  /// adding it here means it ships unverified.
  static const all = <Color>[
    green, greenD, blue, purple, orange, red, teal, yellow, pink, indigo,
    sky, blueSoft,
    domHome, domHealth, domFood, domMove, domMind,
  ];
}

/// ── SURFACES + LEGIBLE INK ────────────────────────────────────────────────
///
/// Brightness-resolved. `P.of(context)` in every build method.
class P {
  final bool dark;
  const P(this.dark);

  static P of(BuildContext c) => P(Theme.of(c).brightness == Brightness.dark);

  // Basalt ground; cards are the next layer up, hairlines not shadows.
  Color get bg => dark ? C.n900 : const Color(0xFFF1EEE6);
  Color get card => dark ? const Color(0xFF15181A) : const Color(0xFFFBF9F4);
  Color get card2 => dark ? C.n800 : const Color(0xFFE9E5DB);
  Color get line => dark ? const Color(0xFF262B2D) : const Color(0xFFDAD5C9);
  Color get track => dark ? const Color(0xFF23282A) : const Color(0xFFDAD5C9);

  Color get ink => dark ? const Color(0xFFE7E3D8) : const Color(0xFF17191A);
  Color get ink2 => dark ? const Color(0xFFA6A399) : const Color(0xFF4A4C4A);

  /// The muted caption ink. Hand-solved to clear 4.5:1 on [card2], the darkest
  /// (light theme) / lightest (dark theme) surface it can sit on — so it is
  /// legible on every surface, not just the one it was eyeballed against.
  /// The values it replaces measured 4.34:1 and 3.21:1 respectively.
  Color get ink3 => dark ? C.n400 : const Color(0xFF5E605C);

  /// The ink that goes on top of a [fill]: basalt. Strata fills are the
  /// minerals themselves, bright, with dark type cut into them — [fill]
  /// lightens the accent until basalt clears AA on it.
  Color get inkOnFill => C.n900;

  /// [accent] rendered as TEXT on one of this brightness' surfaces, nudged
  /// toward the page ink until it clears [_aa] against the worst legal
  /// surface ([card2]). `C.green` on white measures 2.28:1 raw; `on(C.green)`
  /// measures 4.53:1 and still reads unmistakably green.
  ///
  /// Solved TWICE, against the two worst surfaces it can land on. `card2` is
  /// the flat one; the other is `wash(accent)` over it — the Pill and the
  /// active SubTabs chip put this ink on a tinted background nothing was
  /// solving against, and five of six accents measured 4.30–4.49 there. The
  /// solver only ever nudges toward the page ink, so clearing the second
  /// surface cannot un-clear the first.
  Color on(Color accent) {
    final toward = dark ? ink : const Color(0xFF17191A);
    final flat = _solve(accent, toward, card2, dark);
    return _solve(flat, toward, Color.alphaBlend(wash(accent), card2), dark);
  }

  /// [accent] rendered as a FILLED surface under [inkOnFill], darkened until
  /// white text on it clears [_aa]. Buttons, chips, CTA badges.
  Color fill(Color accent) => _solve(accent, C.white, C.n900, false);

  /// A tinted wash of [accent] — the InsightCard / Pill / active-tab
  /// background. Never carries text of its own colour; pair it with [on].
  ///
  /// [strength] is capped at 1: full strength is the tint [on] and [ink3] were
  /// solved against, and a caller asking for 1.6 was pushing muted ink to
  /// 2.99:1 on its own card. A wash darker than a wash is a fill.
  Color wash(Color accent, {double strength = 1}) =>
      accent.withValues(alpha: (dark ? .18 : .11) * strength.clamp(0.0, 1.0));

  List<BoxShadow> el(int level) {
    if (level <= 0) return const [];
    if (dark) {
      // Rock does not float. Elevation is a deep, soft pool under a raised
      // layer — never a glow, never a hard drop.
      return [
        BoxShadow(
          color: const Color(0xFF000000).withValues(alpha: .28 + level * .08),
          blurRadius: 14.0 * level,
          offset: Offset(0, 4.0 * level),
        ),
      ];
    }
    return [
      BoxShadow(
        color: C.n900.withValues(alpha: .04 + level * .015),
        blurRadius: 5.0 * level,
        offset: Offset(0, level * 1.2),
      ),
    ];
  }

  // ── the solver ──────────────────────────────────────────────────────────
  // WCAG 2.1 AA for body text. Non-text UI is allowed 3:1, but a caption that
  // is "technically an indicator" is how the 2.20:1 tokens got shipped, so
  // there is one floor here and it is the strict one.
  static const _aa = 4.5;

  static final _cache = <int, Color>{};

  /// Binary-search the lerp from [c] toward [toward] for the first colour that
  /// clears [_aa] against [against]. 24 steps is well past 8-bit resolution.
  static Color _solve(Color c, Color toward, Color against, bool dark) {
    final key = Object.hash(c.toARGB32(), toward.toARGB32(),
        against.toARGB32(), dark);
    final hit = _cache[key];
    if (hit != null) return hit;
    var out = c;
    if (contrast(c, against) < _aa) {
      var lo = 0.0, hi = 1.0;
      for (var i = 0; i < 24; i++) {
        final mid = (lo + hi) / 2;
        if (contrast(Color.lerp(c, toward, mid)!, against) >= _aa) {
          hi = mid;
        } else {
          lo = mid;
        }
      }
      out = Color.lerp(c, toward, hi)!;
    }
    // Bounded: one entry per (accent, brightness) pair actually used, and the
    // accent set is a compile-time constant.
    _cache[key] = out;
    return out;
  }

  /// WCAG 2.1 contrast ratio, 1.0 … 21.0. Public so the contrast test and any
  /// future palette work measure with exactly the same function the tokens do.
  /// Luminance is `Color.computeLuminance()` — same WCAG formula, no need to
  /// carry our own copy of it.
  static double contrast(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    final hi = math.max(la, lb), lo = math.min(la, lb);
    return (hi + 0.05) / (lo + 0.05);
  }
}

/// ── TYPE ── the survey hand ───────────────────────────────────────────────
///
/// Four bundled faces, each with one job:
///   · Anybody Wide (150 %) — measured numbers. Extra-wide, like elevation
///     figures on a survey sheet. Only a value the band actually measured
///     gets this face; a label never does.
///   · Anybody Semi (118 %) — screen and card titles.
///   · Albert Sans — everything you read.
///   · Azeret Mono — [over]: the small survey labels (units, axes, eyebrows).
/// All four are static instances under assets/fonts, so nothing is fetched.
class F {
  static const wide = 'Anybody Wide';
  static const semi = 'Anybody Semi';
  static const sans = 'Albert Sans';
  static const mono = 'Azeret Mono';
  static const _fb = [sans];
  static const _tab = [FontFeature.tabularFigures()];

  // The 7 steps.
  static const display = TextStyle(
      fontFamily: semi,
      fontFamilyFallback: _fb,
      fontSize: 32,
      height: 38 / 32,
      fontWeight: FontWeight.w800,
      letterSpacing: -.6);
  static const t1 = TextStyle(
      fontFamily: semi,
      fontFamilyFallback: _fb,
      fontSize: 26,
      height: 32 / 26,
      fontWeight: FontWeight.w800,
      letterSpacing: -.4);
  static const t2 = TextStyle(
      fontFamily: semi,
      fontFamilyFallback: _fb,
      fontSize: 20,
      height: 26 / 20,
      fontWeight: FontWeight.w700,
      letterSpacing: -.3);
  static const head = TextStyle(
      fontFamily: semi,
      fontFamilyFallback: _fb,
      fontSize: 16,
      height: 22 / 16,
      fontWeight: FontWeight.w700,
      letterSpacing: -.1);
  static const body = TextStyle(
      fontFamily: sans,
      fontSize: 15,
      height: 22 / 15,
      fontWeight: FontWeight.w400,
      letterSpacing: 0);
  static const cap = TextStyle(
      fontFamily: sans, fontSize: 13, height: 18 / 13, fontWeight: FontWeight.w400);
  static const over = TextStyle(
      fontFamily: sans,
      fontSize: 12,
      height: 16 / 12,
      fontWeight: FontWeight.w600,
      letterSpacing: .1);

  /// The survey label: units, axis marks, eyebrows, counts. Mono, and never a
  /// sentence — a line someone has to READ belongs in [cap] or [over].
  static const label = TextStyle(
      fontFamily: mono,
      fontFamilyFallback: _fb,
      fontSize: 10.5,
      height: 14 / 10.5,
      fontWeight: FontWeight.w500,
      letterSpacing: .6);

  // Numerals — a parallel display ramp in the wide cut. Tabular, so a live
  // value never jitters its own layout as digits change. Sized a step down
  // from a narrow face: the width is where this face spends its presence.
  static const n48 = TextStyle(
      fontFamily: wide,
      fontFamilyFallback: _fb,
      fontSize: 44,
      height: 1,
      fontWeight: FontWeight.w800,
      letterSpacing: -.8,
      fontFeatures: _tab);
  static const n34 = TextStyle(
      fontFamily: wide,
      fontFamilyFallback: _fb,
      fontSize: 30,
      height: 1,
      fontWeight: FontWeight.w800,
      letterSpacing: -.5,
      fontFeatures: _tab);
  static const n24 = TextStyle(
      fontFamily: wide,
      fontFamilyFallback: _fb,
      fontSize: 21,
      height: 1,
      fontWeight: FontWeight.w700,
      letterSpacing: -.3,
      fontFeatures: _tab);
  static const n17 = TextStyle(
      fontFamily: semi,
      fontFamilyFallback: _fb,
      fontSize: 16,
      height: 1,
      fontWeight: FontWeight.w700,
      letterSpacing: -.1,
      fontFeatures: _tab);

  /// The hero figure — one per screen at most (readiness on Home, total sleep
  /// on Sleep, live heart rate). Not part of the everyday ramp on purpose.
  static const hero = TextStyle(
      fontFamily: wide,
      fontFamilyFallback: _fb,
      fontSize: 84,
      height: .9,
      fontWeight: FontWeight.w800,
      letterSpacing: -2,
      fontFeatures: _tab);
}

/// ── SPACING ── 4pt base ───────────────────────────────────────────────────
class S {
  static const x1 = 4.0;
  static const x2 = 8.0;
  static const x3 = 12.0;
  static const x4 = 16.0;
  static const x5 = 20.0;
  static const x6 = 24.0;
  static const x8 = 32.0;
  static const x10 = 40.0;
  static const x12 = 48.0;
  static const x16 = 64.0;

  /// The minimum comfortable target, enforced inside `Pressable`. Apple HIG
  /// and WCAG 2.5.5 both land here.
  static const tap = 44.0;
}

/// ── RADII ─────────────────────────────────────────────────────────────────
class R {
  // Strata corners: small and firm — cut stone, not pebbles.
  static const sm = 6.0;
  static const md = 10.0;
  static const lg = 14.0;
  static const xl = 20.0;
  static const xxl = 28.0;
  static const pill = 999.0;

  static const rSm = BorderRadius.all(Radius.circular(sm));
  static const rMd = BorderRadius.all(Radius.circular(md));
  static const rLg = BorderRadius.all(Radius.circular(lg));
  static const rXl = BorderRadius.all(Radius.circular(xl));
  static const rXxl = BorderRadius.all(Radius.circular(xxl));
  static const rPill = BorderRadius.all(Radius.circular(pill));
}

/// ── MOTION ── one gate, no exceptions ─────────────────────────────────────
///
/// The audit found zero reduced-motion support and 13 infinite `.repeat()`
/// loops. Both are structural problems, so both get structural answers: these
/// are the only durations in the system, and `test/ui2_tokens_test.dart`
/// forbids `.repeat(` in lib/ui2 outright. Ambient motion that genuinely needs
/// to loop takes its phase from a caller-owned value (see `BreathRing.t`), so
/// the screen owns the ticker and the same gate stops it.
class Motion {
  /// True when the platform is NOT asking for reduced motion.
  static bool enabled(BuildContext c) =>
      MediaQuery.maybeDisableAnimationsOf(c) != true;

  static const fast = Duration(milliseconds: 120);
  static const base = Duration(milliseconds: 180);
  static const slow = Duration(milliseconds: 280);

  /// The one orchestrated moment: contours lighting from the coast to the
  /// summit when Home first shows a score. Passes through [motion] like any
  /// other duration, so reduced motion lands on the finished map.
  static const reveal = Duration(milliseconds: 900);

  /// The session clock. A live workout counts REAL seconds, so this is the one
  /// duration that must NOT pass through [motion] — reduced motion silences
  /// animation, it does not stop time. It lives here because theme.dart is the
  /// only file allowed to write a `Duration(…)`, and a screen inventing its own
  /// tick is how thirteen ungated tickers happened last time.
  static const tick = Duration(seconds: 1);

  /// One full breath cycle for the paced-breathing ring — 5 s in, 5 s out is
  /// the pace the breathing session already uses. The PHASE is still owned by
  /// the screen (see `BreathRing.t`); this is only how long a cycle lasts, and
  /// the screen must not start it at all when [enabled] is false.
  static const breath = Duration(seconds: 5);

  /// One pulse of the ECG capture screen's contact rings. Phase is owned by
  /// the screen (like [breath]); nothing runs when [enabled] is false.
  static const ecgPulse = Duration(seconds: 2);

  /// The ECG live-preview repaint cadence: incoming packets only mark the
  /// ring dirty, and the screen's clock repaints at most this often.
  static const ecgPreviewTick = Duration(milliseconds: 100);
}

/// Collapse [d] to zero when the user has asked for reduced motion. Every
/// `AnimatedFoo`, `AnimationController` and implicit transition in lib/ui2
/// takes its duration from here.
Duration motion(BuildContext c, Duration d) =>
    Motion.enabled(c) ? d : Duration.zero;

/// The animated-progress form: returns `1` (finished) instead of `t` when
/// motion is off, so a chart that draws itself in still ends up fully drawn.
double animate(BuildContext c, double t) => Motion.enabled(c) ? t : 1;

/// The motion gate for `showModalBottomSheet`, which takes an [AnimationStyle]
/// rather than reading [ThemeData.pageTransitionsTheme] like a route does.
/// Null keeps the platform default; [AnimationStyle.noAnimation] cuts straight
/// to the open sheet.
AnimationStyle? sheetMotion(BuildContext c) =>
    Motion.enabled(c) ? null : AnimationStyle.noAnimation;

/// True once the user's text scale has passed the point where a card's header
/// can no longer be one line. The number is not a device class — it is where
/// `label · value · unit` stops fitting a phone's width — and it is shared so
/// that every card that has to restack does it at the same moment.
bool bigText(BuildContext c) => MediaQuery.textScalerOf(c).scale(1) > 1.3;

/// Reduced motion has to reach the NAVIGATOR, not only the widgets inside it.
/// `TransitionRoute` builds its controller straight from `transitionDuration`
/// and never asks whether animations are disabled, so before this every push
/// slid at full duration for exactly the people who turned the setting on —
/// and a full-screen slide is the most nauseogenic thing the app does.
///
/// Sheets and dialogs do not consult a theme at all; those pass
/// `AnimationStyle.noAnimation` at their call sites.
class _Gated extends PageTransitionsBuilder {
  /// Whatever the SDK ships for this platform — taken from the default theme
  /// rather than named here, so the app keeps the native transition and this
  /// gate does not quietly become a second opinion about what it should be.
  final PageTransitionsBuilder inner;
  const _Gated(this.inner);

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext c,
      Animation<double> animation, Animation<double> secondary, Widget child) {
    if (!Motion.enabled(c)) return child;
    return inner.buildTransitions(route, c, animation, secondary, child);
  }
}

ThemeData buildTheme(Brightness b) {
  final p = P(b == Brightness.dark);
  return ThemeData(
    brightness: b,
    scaffoldBackgroundColor: p.bg,
    colorScheme: ColorScheme.fromSeed(
            seedColor: C.green, brightness: b, surface: p.card)
        .copyWith(
      primary: p.on(C.green),
      onPrimary: p.inkOnFill,
      surface: p.card,
      onSurface: p.ink,
      outline: p.line,
      outlineVariant: p.line,
    ),
    fontFamily: F.sans,
    canvasColor: p.bg,
    // The few screens that still use a Material AppBar read as the NavBar:
    // centred Anybody title, basalt ground, no tint when content scrolls under.
    appBarTheme: AppBarTheme(
      backgroundColor: p.bg,
      surfaceTintColor: const Color(0x00000000),
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      foregroundColor: p.ink,
      iconTheme: IconThemeData(color: p.ink),
      titleTextStyle: F.head.copyWith(color: p.ink),
    ),
    dividerColor: p.line,
    dialogTheme: DialogThemeData(
      backgroundColor: p.card,
      shape: RoundedRectangleBorder(
          borderRadius: R.rXl, side: BorderSide(color: p.line)),
      titleTextStyle: F.t2.copyWith(color: p.ink),
      contentTextStyle: F.body.copyWith(color: p.ink2),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.card,
      modalBackgroundColor: p.card,
      showDragHandle: true,
      dragHandleColor: p.line,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(R.xxl))),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.card2,
      contentTextStyle: F.body.copyWith(color: p.ink),
      actionTextColor: p.on(C.green),
      shape: RoundedRectangleBorder(
          borderRadius: R.rLg, side: BorderSide(color: p.line)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: p.on(C.green),
      linearTrackColor: p.track,
      circularTrackColor: p.track,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? p.inkOnFill : p.ink3),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? p.fill(C.green) : p.card2),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? p.fill(C.green) : p.line),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: p.on(C.green),
      inactiveTrackColor: p.track,
      thumbColor: p.ink,
      overlayColor: p.wash(C.green),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.card2,
      hintStyle: F.body.copyWith(color: p.ink3),
      labelStyle: F.body.copyWith(color: p.ink2),
      border: OutlineInputBorder(
          borderRadius: R.rMd, borderSide: BorderSide(color: p.line)),
      enabledBorder: OutlineInputBorder(
          borderRadius: R.rMd, borderSide: BorderSide(color: p.line)),
      focusedBorder: OutlineInputBorder(
          borderRadius: R.rMd,
          borderSide: BorderSide(color: p.on(C.green), width: 1.5)),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: p.on(C.green),
      selectionColor: p.wash(C.green),
      selectionHandleColor: p.on(C.green),
    ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: const Color(0x00000000),
    pageTransitionsTheme: PageTransitionsTheme(builders: {
      for (final e in const PageTransitionsTheme().builders.entries)
        e.key: _Gated(e.value),
    }),
  );
}
