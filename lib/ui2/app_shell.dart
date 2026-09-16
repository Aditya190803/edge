// The shell: four destinations and one action.
//
// Home · Health · Strain · More in a floating pill, and the coach in a disc
// beside it — the reference app's bottom edge, transcribed. The bar is
// MONOCHROME: white for the tab you are on, grey for the rest. Logging lives
// behind the ⊕ on Home's "My Day" heading, which is where the old Nutrition
// and Wellness tabs went.
//
// There is no fifth tab, and the type system is what says so — [ShellDomain]
// is a closed enum and [AppShell] takes a builder keyed by it, so "just add a
// tab for X" is a change to this file with a reviewer attached, not something
// a screen can do on its own. Anything that feels like another destination is
// a `SubTabs` inside the domain that owns it, or a row on the ⊕ sheet.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'grammar.dart';
import 'theme.dart';

/// The four primary destinations, in bar order.
enum ShellDomain {
  home('Home', LucideIcons.house, C.domHome),
  health('Health', LucideIcons.heartPulse, C.domHealth),
  workout('Strain', LucideIcons.activity, C.domMove),
  more('More', LucideIcons.menu, C.domMind);

  const ShellDomain(this.label, this.icon, this.accent);

  final String label;
  final IconData icon;

  /// The domain's pigment. Use `P.of(context).on(accent)` for text and
  /// `.fill(accent)` for a filled surface — the raw value is not AA-safe. The
  /// bar itself never paints it.
  final Color accent;
}

// There is no `Domain` InheritedWidget. There was one, promising that a screen
// "and anything it pushes" could pick up its accent without threading it — but
// nothing ever read it, and a pushed route could not have: `MaterialApp.home`
// is the gate, so `Navigator.of` pushes above the shell entirely. Screens take
// their accent as a parameter, which is honest about where it comes from.

class AppShell extends StatefulWidget {
  /// Builds the body of one domain. Called lazily — a tab is not built until
  /// it is first selected, then kept alive by the [IndexedStack].
  final Widget Function(BuildContext context, ShellDomain domain) builder;

  final ShellDomain initial;

  /// Notified on every tab change, including a re-tap of the current tab
  /// (which domains conventionally use to scroll to top).
  final void Function(ShellDomain domain)? onSelect;

  /// The coach disc that floats beside the bar. Null hides it.
  final VoidCallback? onCoach;

  /// Pinned between the domain and the tab bar, above every tab. This is not
  /// a general slot — it exists for state that is RUNNING and is not on
  /// screen, which today means a minimised workout. A domain's own content
  /// belongs inside the domain.
  final Widget? banner;

  const AppShell({
    super.key,
    required this.builder,
    this.initial = ShellDomain.home,
    this.onSelect,
    this.onCoach,
    this.banner,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late ShellDomain _current = widget.initial;
  late final Set<ShellDomain> _built = {widget.initial};

  void _select(ShellDomain d) {
    setState(() {
      _current = d;
      _built.add(d);
    });
    widget.onSelect?.call(d);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Scaffold(
      backgroundColor: p.bg,
      // The bar FLOATS over the page, as the reference app's does: the
      // domain scrolls under it, and each domain leaves room at the bottom.
      body: Stack(fit: StackFit.expand, children: [
        SafeArea(
          bottom: false,
          child: Column(children: [
            Expanded(
              child: IndexedStack(
                index: _current.index,
                children: [
                  // An unvisited tab is an empty box, not a built screen —
                  // the old shell built all forty screens' worth of state on
                  // launch.
                  for (final d in ShellDomain.values)
                    if (_built.contains(d))
                      widget.builder(c, d)
                    else
                      const SizedBox.shrink(),
                ],
              ),
            ),
            if (widget.banner != null) widget.banner!,
          ]),
        ),
        Positioned(
          left: S.x4,
          right: S.x4,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.only(bottom: S.x3),
              child: _FloatingBar(
                current: _current,
                onTap: _select,
                onCoach: widget.onCoach,
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// The pill of four tabs, and the coach disc beside it.
class _FloatingBar extends StatelessWidget {
  final ShellDomain current;
  final ValueChanged<ShellDomain> onTap;
  final VoidCallback? onCoach;

  const _FloatingBar(
      {required this.current, required this.onTap, this.onCoach});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Row(children: [
      Expanded(
        child: Container(
          height: 76,
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: R.rXxl,
            border: Border.all(color: p.line),
          ),
          child: Row(
            children: [
              for (final d in ShellDomain.values)
                Expanded(
                  child: _Tab(domain: d, on: d == current, onTap: () => onTap(d)),
                ),
            ],
          ),
        ),
      ),
      if (onCoach != null) ...[
        const SizedBox(width: S.x3),
        Pressable(
          onTap: onCoach,
          semanticLabel: 'Coach',
          child: Container(
            width: 76,
            height: 76,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: p.card,
              shape: BoxShape.circle,
              border: Border.all(color: p.line),
            ),
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(colors: [p.edgeA, p.edgeB, p.edgeA]),
              ),
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: p.card),
                child: Icon(LucideIcons.sparkles, size: 16, color: p.ink),
              ),
            ),
          ),
        ),
      ],
    ]);
  }
}

class _Tab extends StatelessWidget {
  final ShellDomain domain;
  final bool on;
  final VoidCallback onTap;

  const _Tab({required this.domain, required this.on, required this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final ink = on ? p.ink : p.ink3;
    return Semantics(
      selected: on,
      child: Pressable(
        onTap: onTap,
        semanticLabel: domain.label,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(domain.icon, size: 24, color: ink),
            const SizedBox(height: S.x1),
            Text(
              domain.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: F.cap.copyWith(
                  color: ink, fontWeight: on ? FontWeight.w700 : FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
