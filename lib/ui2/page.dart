// THE PAGE.
//
// Every screen in lib/ui2 is one of these: a large title that sits in the
// content and collapses, as it scrolls away, into a small centred title on a
// frosted bar pinned to the top. Round controls ride that bar — back on the
// left, the page's own actions on the right — so they never scroll away.
//
// It replaces two frames that each owned half of this: `NavBar` above a
// `ListView` on pushed screens, and a bare `ListView` with a `ScreenTitle` in
// it on the tabs. Those drew a fixed header and a separate scroll; the system
// draws one surface where the title IS the top of the content.
//
// What it promises every screen:
//
//   • The back control is in the same place, the same size, on every pushed
//     page — the bar is pinned, so it is reachable from anywhere in a scroll.
//   • The title is said ONCE. The inline copy only exists once the large one
//     has scrolled away, and is excluded from semantics, so neither a screen
//     reader nor a finder meets the page's name twice.
//   • Reduced motion is honoured: the bar's fade is driven by scroll position,
//     not by a timer, so there is nothing to animate when nothing moves.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'grammar.dart';
import 'theme.dart';

/// A round control for the page bar: a glyph in a filled circle, the system's
/// floating navigation button. Pass these as [HealthPage.actions].
class BarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  /// Draw the circle in this accent instead of the card colour — for the one
  /// action a page is built around (add, start).
  final Color? accent;

  const BarButton(this.icon, this.label, {super.key, this.onTap, this.accent});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final a = accent;
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: ShapeDecoration(
          color: a == null ? p.card : p.fill(a),
          shape: const CircleBorder(),
          shadows: p.el(2),
        ),
        child: Icon(icon, size: 19, color: a == null ? p.ink : p.inkOnFill),
      ),
    );
  }
}

class HealthPage extends StatefulWidget {
  /// The page's name. Set large at the top of the content, then small in the
  /// bar once it has scrolled away.
  final String title;

  /// A short line ABOVE the large title, in small caps — the date on a summary,
  /// the category on a metric.
  final String eyebrow;

  /// A line UNDER the large title — what `NavBar.sub` used to carry.
  final String sub;

  /// Show the back control. Tab roots have none; everything pushed does.
  final bool back;
  final VoidCallback? onBack;

  /// Round controls at the right of the bar. [BarButton]s, normally — any
  /// widget is accepted so a page with a non-icon action (a "Done") can say
  /// so in words.
  final List<Widget> actions;

  /// Sits directly under the large title, before the body: a segmented
  /// control, a day switcher, a search field.
  final Widget? accessory;

  /// The body, top to bottom. Built lazily, like a `ListView`'s children.
  final List<Widget> children;

  /// Pull to refresh. Null means the page cannot be pulled.
  final Future<void> Function()? onRefresh;

  final ScrollController? controller;

  /// Horizontal gutter for [children]. Zero for a page that draws edge to edge.
  final double gutter;

  const HealthPage({
    super.key,
    required this.title,
    required this.children,
    this.eyebrow = '',
    this.sub = '',
    this.back = true,
    this.onBack,
    this.actions = const [],
    this.accessory,
    this.onRefresh,
    this.controller,
    this.gutter = S.x4,
  });

  @override
  State<HealthPage> createState() => _HealthPageState();
}

class _HealthPageState extends State<HealthPage> {
  /// 0 with the large title fully on screen, 1 once it has scrolled under the
  /// bar. Everything the bar does is a function of this one number.
  double _t = 0;

  /// How far the content scrolls before the large title is gone — its own
  /// height, near enough, at 1× text.
  static const _collapse = 44.0;

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    final t = (n.metrics.pixels / _collapse).clamp(0.0, 1.0);
    if ((t - _t).abs() > .01 || (t == 0 || t == 1) && t != _t) {
      setState(() => _t = t);
    }
    return false;
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final w = widget;
    Widget scroll = CustomScrollView(
      controller: w.controller,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _LargeTitle(w)),
        if (w.accessory != null)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x3),
            sliver: SliverToBoxAdapter(child: w.accessory),
          ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(w.gutter, 0, w.gutter, S.x12),
          sliver: SliverList(delegate: SliverChildListDelegate(w.children)),
        ),
      ],
    );
    if (w.onRefresh != null) {
      scroll = RefreshIndicator(onRefresh: w.onRefresh!, child: scroll);
    }
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Bar(page: w, t: _t),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: _onScroll,
                child: scroll,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The large title block at the top of the content.
class _LargeTitle extends StatelessWidget {
  final HealthPage page;
  const _LargeTitle(this.page);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.x4 + S.x1, 0, S.x4, S.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (page.eyebrow.isNotEmpty) ...[
            Text(
              page.eyebrow.toUpperCase(),
              style: F.over.copyWith(
                color: p.ink3,
                fontWeight: FontWeight.w700,
                letterSpacing: .6,
              ),
            ),
            const SizedBox(height: 2),
          ],
          Semantics(
            header: true,
            child: Text(page.title, style: F.display.copyWith(color: p.ink)),
          ),
          if (page.sub.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(page.sub, style: F.cap.copyWith(color: p.ink3)),
          ],
        ],
      ),
    );
  }
}

/// The pinned bar. The page colour over the large title; lifted toward the
/// card colour, hairlined, and carrying the inline title once the large one
/// has gone.
class _Bar extends StatelessWidget {
  final HealthPage page;
  final double t;
  const _Bar({required this.page, required this.t});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final collapsed = t >= .98;
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: S.x4),
      decoration: BoxDecoration(
        color: Color.lerp(p.bg, p.card, t * .6)!.withValues(alpha: 1),
        border: Border(
          bottom: BorderSide(color: p.line.withValues(alpha: t), width: .5),
        ),
      ),
      child: Row(
        children: [
          if (page.back)
            BarButton(
              LucideIcons.chevronLeft,
              'Back',
              onTap: page.onBack ?? () => Navigator.maybePop(c),
            ),
          Expanded(
            child: collapsed
                ? ExcludeSemantics(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: S.x2),
                      child: Text(
                        page.title,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: F.head.copyWith(color: p.ink),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          for (var i = 0; i < page.actions.length; i++) ...[
            if (i > 0) const SizedBox(width: S.x2),
            page.actions[i],
          ],
          // A pushed page with no actions keeps the title centred by
          // mirroring the back button's width on the right.
          if (page.back && page.actions.isEmpty) const SizedBox(width: S.tap),
        ],
      ),
    );
  }
}
