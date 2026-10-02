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
/// Raw pigment — Apple's system palette, so the app sits beside Health,
/// Fitness and the platform's own controls without looking borrowed. These
/// are *not* safe to paint text with directly — most of them fail AA on
/// white. Run them through [P.on] (accent as text), [P.fill] (accent as a
/// filled surface under [P.inkOnFill]) or [P.tile] (an icon tile) first.
class C {
  // primary
  static const green = Color(0xFF34C759);
  static const greenD = Color(0xFF248A3D);
  static const blue = Color(0xFF007AFF);
  static const purple = Color(0xFFAF52DE);

  // secondary
  static const orange = Color(0xFFFF9500);
  static const red = Color(0xFFFF3B30);
  static const teal = Color(0xFF30B0C7);
  static const yellow = Color(0xFFFFCC00);
  static const pink = Color(0xFFFF2D55);
  static const indigo = Color(0xFF5856D6);

  /// Two light blues the ramps need and nothing else does: the light-sleep
  /// lane sits between REM and deep, and zone 1 sits below `blue`. They live
  /// here rather than inside the painters because a palette that is partly in
  /// theme.dart and partly in charts.dart is two palettes.
  static const sky = Color(0xFF64D2FF);
  static const blueSoft = Color(0xFF5AC8FA);

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

  // neutrals — Apple's grey ladder (systemGray … systemGray6), not a blue-grey
  // slate: a health app reads clinical in neutral greys and moody in tinted
  // ones.
  static const n900 = Color(0xFF1C1C1E);
  static const n800 = Color(0xFF2C2C2E);
  static const n600 = Color(0xFF636366);
  static const n500 = Color(0xFF8E8E93);
  static const n400 = Color(0xFFAEAEB2);
  static const n300 = Color(0xFFC7C7CC);
  static const n200 = Color(0xFFD1D1D6);
  static const n100 = Color(0xFFE5E5EA);
  static const n50 = Color(0xFFF2F2F7);

  static const white = Color(0xFFFFFFFF);

  /// Shadow pigment — only ever drawn at a low alpha, under a mark, never as
  /// ink or fill. Not in [all] for the same reason the route ramp is not.
  static const shade = Color(0xFF000000);

  /// Each domain owns an accent — the mental map is colour-coded, and the map
  /// is the point. These five are the five tabs, in order, forever. They
  /// follow Health's own category colours: the summary in the system tint,
  /// heart in pink, nutrition in green, activity in orange, mind in teal.
  static const domHome = blue;
  static const domHealth = pink;
  static const domFood = green;
  static const domMove = orange;
  static const domMind = teal;

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
///
/// The layout is Health's: a grouped grey page with white cards floating on
/// it in light, and true black with raised charcoal cards in dark — so an
/// OLED panel is genuinely off behind the content.
class P {
  final bool dark;
  const P(this.dark);

  static P of(BuildContext c) => P(Theme.of(c).brightness == Brightness.dark);

  Color get bg => dark ? const Color(0xFF000000) : C.n50;
  Color get card => dark ? C.n900 : C.white;
  Color get card2 => dark ? C.n800 : const Color(0xFFEDEDF2);
  Color get line => dark ? const Color(0xFF38383A) : const Color(0xFFDCDCE0);
  Color get track => dark ? const Color(0xFF3A3A3C) : C.n100;

  Color get ink => dark ? C.white : const Color(0xFF000000);
  Color get ink2 => dark ? const Color(0xFFD1D1D6) : const Color(0xFF3C3C43);

  /// The muted caption ink. Hand-solved to clear 4.5:1 on [card2], the darkest
  /// (light theme) / lightest (dark theme) surface it can sit on — so it is
  /// legible on every surface, not just the one it was eyeballed against.
  Color get ink3 => dark ? const Color(0xFF9D9DA3) : const Color(0xFF66666B);

  /// The ink that goes on top of a [fill]. White by construction — [fill]
  /// darkens the accent until white clears AA on it.
  Color get inkOnFill => C.white;

  /// [accent] rendered as TEXT on one of this brightness' surfaces, nudged
  /// toward the page ink until it clears [_aa] against the worst legal
  /// surface ([card2]).
  ///
  /// Solved TWICE, against the two worst surfaces it can land on. `card2` is
  /// the flat one; the other is `wash(accent)` over it — the Pill and the
  /// active chip put this ink on a tinted background. The solver only ever
  /// nudges toward the page ink, so clearing the second surface cannot
  /// un-clear the first.
  Color on(Color accent) {
    final toward = dark ? ink : C.n900;
    final flat = _solve(accent, toward, card2, dark);
    return _solve(flat, toward, Color.alphaBlend(wash(accent), card2), dark);
  }

  /// [accent] rendered as a FILLED surface under [inkOnFill], darkened until
  /// white text on it clears [_aa]. Buttons, chips, CTA badges.
  Color fill(Color accent) => _solve(accent, const Color(0xFF000000), C.white, false);

  /// [accent] as an ICON TILE — the rounded square with a white glyph that
  /// leads a settings row or a summary card, the way the system's own lists
  /// do. A glyph is a graphical object, so WCAG 1.4.11 asks 3:1 of it, not the
  /// 4.5:1 text floor: solving it as text would turn every yellow tile brown.
  /// It never carries words — anything with a label is a [fill].
  Color tile(Color accent) =>
      _solve(accent, const Color(0xFF000000), C.white, false, floor: _ui);

  /// A tinted wash of [accent] — the Pill / active-tab / tinted-button
  /// background. Never carries text of its own colour; pair it with [on].
  ///
  /// [strength] is capped at 1: full strength is the tint [on] and [ink3] were
  /// solved against. A wash darker than a wash is a fill.
  Color wash(Color accent, {double strength = 1}) =>
      accent.withValues(alpha: (dark ? .22 : .12) * strength.clamp(0.0, 1.0));

  /// Elevation. Level 1 — every resting card — is FLAT: a white card on the
  /// grouped grey page is separated by value alone, which is what makes the
  /// screen read calm instead of busy. Only things that genuinely float (the
  /// tab bar, a lifted button, a sheet) cast a shadow, and it is a wide soft
  /// one rather than a tight drop.
  List<BoxShadow> el(int level) {
    if (level <= 1) return const [];
    if (dark) {
      return [
        BoxShadow(
          color: const Color(0xFF000000).withValues(alpha: .5),
          blurRadius: 10.0 * level,
          offset: Offset(0, level * 2.0),
        ),
      ];
    }
    return [
      BoxShadow(
        color: const Color(0xFF000000).withValues(alpha: .05 + level * .01),
        blurRadius: 12.0 * level,
        offset: Offset(0, level * 2.0),
      ),
    ];
  }

  // ── the solver ──────────────────────────────────────────────────────────
  // WCAG 2.1 AA for body text — the floor for anything with words in it.
  static const _aa = 4.5;

  // WCAG 2.1 1.4.11 for non-text UI: icon tiles and nothing else.
  static const _ui = 3.0;

  static final _cache = <int, Color>{};

  /// Binary-search the lerp from [c] toward [toward] for the first colour that
  /// clears [floor] against [against]. 24 steps is well past 8-bit resolution.
  static Color _solve(Color c, Color toward, Color against, bool dark,
      {double floor = _aa}) {
    final key = Object.hash(c.toARGB32(), toward.toARGB32(),
        against.toARGB32(), dark, floor);
    final hit = _cache[key];
    if (hit != null) return hit;
    var out = c;
    if (contrast(c, against) < floor) {
      var lo = 0.0, hi = 1.0;
      for (var i = 0; i < 24; i++) {
        final mid = (lo + hi) / 2;
        if (contrast(Color.lerp(c, toward, mid)!, against) >= floor) {
          hi = mid;
        } else {
          lo = mid;
        }
      }
      out = Color.lerp(c, toward, hi)!;
    }
    // Bounded: one entry per (accent, brightness, floor) actually used, and
    // the accent set is a compile-time constant.
    _cache[key] = out;
    return out;
  }

  /// WCAG 2.1 contrast ratio, 1.0 … 21.0. Public so the contrast test and any
  /// future palette work measure with exactly the same function the tokens do.
  static double contrast(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    final hi = math.max(la, lb), lo = math.min(la, lb);
    return (hi + 0.05) / (lo + 0.05);
  }
}

/// ── TYPE ── 7 steps, 3 weights, tabular figures on anything that changes ──
///
/// The platform's own face where it exists — SF Pro on iOS — and Inter
/// everywhere else. Inter was drawn for the same job SF was (dense UI text
/// on screens) and shares its proportions, so Android renders the same
/// hierarchy instead of landing on Roboto. Numerals take the DISPLAY cut of
/// each: tighter, heavier digits that read as a measurement at a glance —
/// Health's big numbers are what make its cards scannable.
class F {
  static const _f = '.SF Pro Text';
  static const _fb = ['Inter'];
  static const _n = '.SF Pro Display';
  static const _nb = ['Inter Display', 'Inter'];
  static const _tab = [FontFeature.tabularFigures()];

  // The 7 steps. Large title → caption, on Apple's own ramp.
  static const display = TextStyle(
      fontFamily: _n,
      fontFamilyFallback: _nb,
      fontSize: 34,
      height: 41 / 34,
      fontWeight: FontWeight.w700,
      letterSpacing: -.9);
  static const t1 = TextStyle(
      fontFamily: _n,
      fontFamilyFallback: _nb,
      fontSize: 28,
      height: 34 / 28,
      fontWeight: FontWeight.w700,
      letterSpacing: -.6);
  static const t2 = TextStyle(
      fontFamily: _n,
      fontFamilyFallback: _nb,
      fontSize: 22,
      height: 28 / 22,
      fontWeight: FontWeight.w700,
      letterSpacing: -.45);
  static const head = TextStyle(
      fontFamily: _f,
      fontFamilyFallback: _fb,
      fontSize: 17,
      height: 22 / 17,
      fontWeight: FontWeight.w600,
      letterSpacing: -.35);
  static const body = TextStyle(
      fontFamily: _f,
      fontFamilyFallback: _fb,
      fontSize: 15,
      height: 21 / 15,
      letterSpacing: -.2);
  static const cap = TextStyle(
      fontFamily: _f,
      fontFamilyFallback: _fb,
      fontSize: 13,
      height: 18 / 13,
      letterSpacing: -.08);
  static const over = TextStyle(
      fontFamily: _f,
      fontFamilyFallback: _fb,
      fontSize: 11,
      height: 14 / 11,
      fontWeight: FontWeight.w500,
      letterSpacing: .1);

  // Numerals — a parallel display ramp. Tabular, so a live value never jitters
  // its own layout as digits change.
  static const n48 = TextStyle(
      fontFamily: _n,
      fontFamilyFallback: _nb,
      fontSize: 48,
      height: 1,
      fontWeight: FontWeight.w700,
      letterSpacing: -1.6,
      fontFeatures: _tab);
  static const n34 = TextStyle(
      fontFamily: _n,
      fontFamilyFallback: _nb,
      fontSize: 34,
      height: 1,
      fontWeight: FontWeight.w700,
      letterSpacing: -1.0,
      fontFeatures: _tab);
  static const n24 = TextStyle(
      fontFamily: _n,
      fontFamilyFallback: _nb,
      fontSize: 26,
      height: 1,
      fontWeight: FontWeight.w700,
      letterSpacing: -.7,
      fontFeatures: _tab);
  static const n17 = TextStyle(
      fontFamily: _n,
      fontFamilyFallback: _nb,
      fontSize: 17,
      height: 1,
      fontWeight: FontWeight.w600,
      letterSpacing: -.3,
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
///
/// Larger than a Material card's, and meant to be drawn CONTINUOUS — the
/// squircle corner the system uses — through [R.shape]. A circular arc of the
/// same radius kinks where it meets the straight edge; a superellipse eases
/// into it, which is most of why a native card looks expensive and a web
/// card does not.
class R {
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 20.0;
  static const xl = 26.0;
  static const xxl = 34.0;
  static const pill = 999.0;

  static const rSm = BorderRadius.all(Radius.circular(sm));
  static const rMd = BorderRadius.all(Radius.circular(md));
  static const rLg = BorderRadius.all(Radius.circular(lg));
  static const rXl = BorderRadius.all(Radius.circular(xl));
  static const rXxl = BorderRadius.all(Radius.circular(xxl));
  static const rPill = BorderRadius.all(Radius.circular(pill));

  /// The continuous-corner card shape at [r]. Every card surface in the
  /// grammar is drawn with this, not with a `BoxDecoration` radius.
  static RoundedSuperellipseBorder shape(BorderRadius r, {BorderSide side = BorderSide.none}) =>
      RoundedSuperellipseBorder(borderRadius: r, side: side);
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
  final tint = p.on(C.blue);
  final base = ThemeData(brightness: b, useMaterial3: true);
  return ThemeData(
    brightness: b,
    useMaterial3: true,
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: C.blue,
      brightness: b,
      surface: p.card,
    ).copyWith(
      primary: tint,
      onPrimary: p.inkOnFill,
      secondary: p.on(C.pink),
      surface: p.card,
      onSurface: p.ink,
      onSurfaceVariant: p.ink3,
      outline: p.line,
      outlineVariant: p.line,
      surfaceContainerHighest: p.card2,
    ),
    fontFamily: '.SF Pro Text',
    fontFamilyFallback: const ['Inter'],
    textTheme: base.textTheme.apply(
      fontFamily: '.SF Pro Text',
      fontFamilyFallback: const ['Inter'],
      bodyColor: p.ink,
      displayColor: p.ink,
    ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: const Color(0x00000000),
    dividerTheme: DividerThemeData(color: p.line, thickness: .5, space: 1),
    iconTheme: IconThemeData(color: p.ink2),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: tint,
      selectionColor: tint.withValues(alpha: .25),
      selectionHandleColor: tint,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: tint,
      linearTrackColor: p.track,
      circularTrackColor: const Color(0x00000000),
    ),
    // The system's own switch is green-on, grey-off; Material's default is a
    // violet thumb inside a tonal track. Same widget, platform's colours.
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.all(C.white),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? C.green : p.track),
      trackOutlineColor:
          WidgetStateProperty.all(const Color(0x00000000)),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? tint : const Color(0x00000000)),
      shape: const CircleBorder(),
      side: BorderSide(color: p.ink3, width: 1.5),
    ),
    radioTheme: RadioThemeData(fillColor: WidgetStateProperty.all(tint)),
    sliderTheme: SliderThemeData(
      activeTrackColor: tint,
      inactiveTrackColor: p.track,
      thumbColor: C.white,
      overlayColor: const Color(0x00000000),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.dark ? C.n800 : C.n900,
      contentTextStyle: F.cap.copyWith(color: C.white),
      actionTextColor: P(true).on(C.blue),
      elevation: 0,
      shape: R.shape(R.rMd),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.card,
      modalBackgroundColor: p.card,
      surfaceTintColor: const Color(0x00000000),
      showDragHandle: false,
      shape: const RoundedSuperellipseBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.xxl)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.card,
      surfaceTintColor: const Color(0x00000000),
      shape: R.shape(R.rXl),
      titleTextStyle: F.head.copyWith(color: p.ink),
      contentTextStyle: F.cap.copyWith(color: p.ink2),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: tint,
        textStyle: F.body.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: p.bg,
      surfaceTintColor: const Color(0x00000000),
      foregroundColor: p.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: F.head.copyWith(color: p.ink),
    ),
    // NO inputDecorationTheme. Most fields in lib/ui2 are collapsed
    // decorations inside their own styled containers; a theme-level fill or
    // focus border reaches into every one of them, and drew a blue outline
    // inside the search capsule.
    pageTransitionsTheme: PageTransitionsTheme(builders: {
      for (final e in const PageTransitionsTheme().builders.entries)
        e.key: _Gated(e.value),
    }),
  );
}
