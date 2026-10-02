// The way into a tab. A patch of surveyed ground, and one number.
//
// One widget, two uses: Workout's "start a session" and Wellness's "start a
// sitting". Same card, a different mineral and a different noun, so they are
// the same code — a second copy is how the two drift a corner radius apart
// and nobody notices for a month.
//
// It sits in the list's ordinary padding like every other card. Two earlier
// versions tried to bleed edge to edge — a negative margin (which asserts) and
// an OverflowBox (which takes an unbounded height in a scroll view and blanked
// the tab) — and the height is never fixed, so the copy can grow with the
// user's text size.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/app_localizations.dart';
import '../ui2.dart';

class StartCard extends StatelessWidget {
  const StartCard({
    super.key,
    required this.label,
    required this.count,
    required this.noun,
    required this.accent,
    this.sub,
    this.onTap,
  });

  /// The overline — "START A SESSION".
  final String label;

  /// How many things are behind the tap, and what to call them. A number the
  /// screen can actually stand behind: the count of what the picker offers,
  /// never a total that includes things this tab cannot start.
  final int count;
  final String noun;

  /// The tab's own mineral.
  final Color accent;

  /// The subline under the count, e.g. "Pick one and go". Nullable so the
  /// default copy can be localized in [build] rather than baked into a
  /// const-context default parameter value.
  final String? sub;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final subText = sub ?? (l?.startCardDefaultSub ?? 'Pick one and go');
    final ink = p.on(accent);
    // STRATA: the way into a tab is a patch of surveyed ground in the tab's
    // own mineral — contour texture under the count, and one solid block to
    // press. Decoration only in the lines; the count is the only figure.
    return Pressable(
      onTap: onTap,
      semanticLabel: label.toLowerCase(),
      child: Container(
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Color.alphaBlend(p.wash(accent, strength: .35), p.card),
          borderRadius: R.rXl,
          border: Border.all(color: ink.withValues(alpha: .28)),
        ),
        child: Stack(children: [
          Positioned.fill(
            child: ExcludeSemantics(
              child: CustomPaint(
                painter: ContourField(ink.withValues(alpha: .16),
                    seed: label.length * 7, centre: const Offset(.92, .15)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(S.x5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SurveyLabel(label, color: ink),
                const SizedBox(height: S.x8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.end,
                            spacing: S.x2,
                            children: [
                              Text('$count',
                                  style: F.n48.copyWith(color: p.ink)),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(noun,
                                    style: F.head.copyWith(color: p.ink2)),
                              ),
                            ],
                          ),
                          const SizedBox(height: S.x1),
                          Text(subText,
                              style: F.cap.copyWith(color: p.ink3),
                              maxLines: 2),
                        ],
                      ),
                    ),
                    const SizedBox(width: S.x3),
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                          color: p.fill(accent), borderRadius: R.rLg),
                      child: Icon(LucideIcons.play,
                          size: 22, color: p.inkOnFill),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
