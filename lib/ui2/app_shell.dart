// The five-tab shell.
//
// Home · Health · Nutrition · Workout · Wellness. Stable forever: the contents
// personalise, the mental map does not. Each domain owns an accent, so colour
// tells you where you are before the label does.
//
// There is no sixth tab, and the type system is what says so — [ShellDomain]
// is a closed enum and [AppShell] takes a builder keyed by it, so "just add a
// tab for X" is a change to this file with a reviewer attached, not something
// a screen can do on its own. Anything that feels like a sixth destination is
// a `SubTabs` inside the domain that owns it.

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'grammar.dart';
import 'theme.dart';

/// The five primary destinations, in bar order.
enum ShellDomain {
  home('Home', LucideIcons.house, C.domHome),
  health('Health', LucideIcons.heartPulse, C.domHealth),
  nutrition('Nutrition', LucideIcons.utensils, C.domFood),
  workout('Workout', LucideIcons.dumbbell, C.domMove),
  wellness('Wellness', LucideIcons.leaf, C.domMind);

  const ShellDomain(this.label, this.icon, this.accent);

  final String label;
  final IconData icon;

  /// The domain's pigment. Use `P.of(context).on(accent)` for text and
  /// `.fill(accent)` for a filled surface — the raw value is not AA-safe.
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
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Expanded(
            child: IndexedStack(
              index: _current.index,
              children: [
                // An unvisited tab is an empty box, not a built screen — the
                // old shell built all forty screens' worth of state on launch.
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
      bottomNavigationBar: _TabBar(current: _current, onTap: _select),
    );
  }
}

/// The tab bar — a frosted capsule floating above the page rather than a
/// strip welded to the bottom edge. The page colour shows around it, the
/// selected tab is a tinted lozenge inside it, and the system gesture area
/// stays below it untouched.
class _TabBar extends StatelessWidget {
  final ShellDomain current;
  final ValueChanged<ShellDomain> onTap;

  const _TabBar({required this.current, required this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return ColoredBox(
      color: p.bg,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: S.x2),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(S.x3, S.x1, S.x3, S.x1),
          child: DecoratedBox(
            decoration: ShapeDecoration(
              shape: const StadiumBorder(),
              shadows: p.el(3),
            ),
            child: ClipPath(
              clipper: const ShapeBorderClipper(shape: StadiumBorder()),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  decoration: ShapeDecoration(
                    color: p.card.withValues(alpha: p.dark ? .88 : .92),
                    shape: StadiumBorder(
                      side: BorderSide(color: p.line, width: .5),
                    ),
                  ),
                  padding: const EdgeInsets.all(S.x1),
                  child: Row(
                    children: [
                      for (final d in ShellDomain.values)
                        Expanded(
                          child: _Tab(
                            domain: d,
                            on: d == current,
                            onTap: () => onTap(d),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
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
    final ink = on ? p.on(domain.accent) : p.ink3;
    return Semantics(
      selected: on,
      child: Pressable(
        onTap: onTap,
        semanticLabel: domain.label,
        child: AnimatedContainer(
          duration: motion(c, Motion.base),
          curve: Curves.easeOutCubic,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: ShapeDecoration(
            color: on ? p.wash(domain.accent) : const Color(0x00000000),
            shape: const StadiumBorder(),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(domain.icon, size: 21, color: ink),
              const SizedBox(height: 2),
              Text(
                domain.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: F.over.copyWith(
                  color: ink,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
