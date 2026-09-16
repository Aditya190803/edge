// The ⊕ sheet — what the middle button of the tab bar opens.
//
// One list of the things a person can LOG, so the shell needs no tab for
// logging: a workout (live or after the fact), a journal entry, a breathing
// session, food and water, and the wellness set (habits, medication, cycle).
// It returns a choice and pushes nothing itself — `app.dart` owns navigation,
// because two of these rows open screens that used to be tabs and only the
// shell knows how to wrap them.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/app_localizations.dart';
import '../ui2.dart';

enum AddChoice { workout, pastWorkout, journal, breathe, food, wellness }

/// Show the sheet. Resolves to the row tapped, or null when dismissed.
Future<AddChoice?> showAddSheet(BuildContext c) {
  final p = P.of(c);
  return showModalBottomSheet<AddChoice>(
    context: c,
    backgroundColor: p.card,
    barrierColor: p.bg.withValues(alpha: .7),
    sheetAnimationStyle: sheetMotion(c),
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.xl))),
    builder: (_) => const AddSheet(),
  );
}

class AddSheet extends StatelessWidget {
  const AddSheet({super.key});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final rows = <(AddChoice, IconData, String, String)>[
      (AddChoice.workout, LucideIcons.play,
          l?.workoutStartSessionLabel ?? 'Start a workout', 'Live, from the band'),
      (AddChoice.pastWorkout, LucideIcons.clockArrowUp, 'Log a past workout',
          'Times and activity, after the fact'),
      (AddChoice.journal, LucideIcons.notebookPen, 'Journal',
          'Behaviours, notes, how you feel'),
      (AddChoice.breathe, LucideIcons.wind, 'Breathe', 'A paced session, scored'),
      (AddChoice.food, LucideIcons.utensils, 'Food and water', 'Meals, macros, hydration'),
      (AddChoice.wellness, LucideIcons.leaf, 'Wellness',
          'Habits, medication, cycle'),
    ];
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(S.x4, S.x3, S.x4, S.x4),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(color: p.line, borderRadius: R.rPill),
          ),
          const SizedBox(height: S.x4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('LOG', style: F.caps.copyWith(color: p.ink3)),
          ),
          const SizedBox(height: S.x2),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(color: p.line, height: 1),
            _Row(rows[i].$2, rows[i].$3, rows[i].$4,
                onTap: () => Navigator.of(c).pop(rows[i].$1)),
          ],
        ]),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String title, sub;
  final VoidCallback onTap;
  const _Row(this.icon, this.title, this.sub, {required this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      onTap: onTap,
      semanticLabel: '$title. $sub',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x3),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: p.card2, shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: p.ink),
          ),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
              Text(sub, style: F.cap.copyWith(color: p.ink3)),
            ]),
          ),
          Icon(LucideIcons.chevronRight, size: 18, color: p.ink3),
        ]),
      ),
    );
  }
}

/// A screen that used to be a shell tab, shown as a pushed route. It keeps
/// its own title and sub-tabs; this only adds the nav bar with the way back,
/// which a tab never needed.
class PushedTab extends StatelessWidget {
  final String title;
  final Widget child;
  const PushedTab(this.title, this.child, {super.key});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x4),
            child: NavBar(title),
          ),
          Expanded(child: child),
        ]),
      ),
    );
  }
}
