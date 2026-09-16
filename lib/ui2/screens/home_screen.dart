// HOME — decision-oriented. "What matters today?"
//
// Three rings that decide the day — what the night gave back, what the day has
// cost, what the night was made of — three signals worth a glance under them,
// and the small set of things the app can honestly say are worth doing. The
// hard part is not the circles: readiness exists on 71 % of days and needs
// four prior nights before it exists at all, so what a ring does with nothing
// in it is the design. See [RingTrio]. No insight feed and no general
// health-observation card: those are OBSERVATION, and observation lives on
// Health. A home screen that also observes is a dashboard, and a dashboard is
// what this rebuild is replacing.
//
// ONE NAMED EXCEPTION, and it is deliberately not a crack in that rule: the
// illness watch ([_bodyWatch]). It is not a feed and it cannot grow into one —
// exactly one detector may render here, it renders only when its own state is
// amber or red, and it is silent on every ordinary day. The reason it earns
// Home is timing rather than importance: the watch is at its most useful when
// it first goes amber, and amber has no notification, so before this the
// earliest signal the app produces could only be found by opening Health and
// scrolling. A signal that arrives too late to act on is not worth computing.
// If a second observation ever wants this slot, the answer is no — build the
// feed on Health where the others already live.
//
// This file also carries the plumbing every screen in this folder shares —
// navigation, the repo handle, and the three ways a value arrives from the
// data layer. They live here rather than in a fourth file because there are
// only three of them and they are read together.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../data/day_label.dart' show todayLabel;
import '../../data/db.dart' show DbRebuild;
import '../../data/journal_fields.dart' show formatMinuteOfDay;
import '../../data/local_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../models/metric.dart';
import '../../state/app_state.dart';
import '../../state/units_controller.dart';
import '../../theme/theme_switcher.dart' show themedRoute;
import '../activity/day_strain.dart' show DayStrainDetail;
import '../profile/profile.dart';
import '../ui2.dart';
import '../../ai/briefing.dart' show BriefingPeriod;
import 'ai_briefing.dart';
import 'coach.dart';
import 'day_timeline.dart' show DayTimelineScreen;
import 'metric_detail.dart';
import 'readiness_detail.dart';
import 'sleep_detail.dart';

// ═══════════════════ shared plumbing ═══════════════════

/// Page padding. The bottom inset clears the shell's floating nav.
const pad = EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x16 + S.x8);

/// Push a detail screen. Every drill-down in ui2 goes through here.
///
/// This was a raw `PageRouteBuilder` with its own fade+slide, which silently
/// killed the iOS edge-swipe-back on all ~20 screens it pushes — a
/// PageRouteBuilder has no interactive back-gesture machinery. The app's own
/// transition is registered in the theme instead (see page_transitions.dart),
/// so a plain route gets the fade-through on Android and the Cupertino slide
/// WITH swipe-back on iOS. [themedRoute] also keeps the pushed screen
/// re-colouring on an appearance change and names the route for Crashlytics.
void go(BuildContext c, Widget w) => Navigator.of(c)
    .push(themedRoute((_) => w, name: w.runtimeType.toString()));

/// The repo, or null when there is no AppState above us — which is the case in
/// every golden. A screen with no repo renders its absent states, which is
/// exactly what we want a golden to capture.
LocalRepository? repoOf(BuildContext c) {
  try {
    return c.read<AppState>().repo;
  } catch (_) {
    return null;
  }
}

/// The user's unit system, or null in a golden. A screen that cannot reach it
/// renders what the store holds, which is metric.
UnitsController? unitsOf(BuildContext c) {
  try {
    return c.watch<UnitsController>();
  } catch (_) {
    return null;
  }
}

/// "72.4 kg" → `('72.4', 'kg')`. [UnitsController] owns every conversion and
/// hands back one string; this only puts the two halves in the two slots a
/// row has. Never convert in a screen.
(String, String) splitUnit(String s) {
  final i = s.lastIndexOf(' ');
  return i < 0 ? (s, '') : (s.substring(0, i), s.substring(i + 1));
}

/// The band-sync trigger, or null when there is no AppState above us. Every
/// "Sync the band" CTA in this folder goes through here — a call to action
/// with no action behind it is worse than no call to action.
VoidCallback? syncOf(BuildContext c) {
  try {
    final app = c.read<AppState>();
    return app.syncNow;
  } catch (_) {
    return null;
  }
}

/// Whether the database had to be rebuilt to start this launch, or null in a
/// golden. Same shape as [repoOf] and [syncOf].
DbRebuild? dbRebuildOf(BuildContext c) {
  try {
    return c.read<AppState>().dbRebuild;
  } catch (_) {
    return null;
  }
}

/// Whether a live workout is open, or false in a golden. `select`, not
/// `watch`: AppState ticks at ~1 Hz while a session is live, and this screen
/// only cares about the bool flipping. The bare-day card branches on it — see
/// [workoutHoldCard].
bool workoutLiveOf(BuildContext c) {
  try {
    return c.select<AppState, bool>((a) => a.activeWorkout != null);
  } catch (_) {
    return false;
  }
}

/// Whether the band is actively sending data right now, or false in a
/// golden. Same shape and same reasoning as [workoutLiveOf] — `select`
/// because this only cares about the bool flipping, not AppState's ~1 Hz
/// heartbeat.
bool syncingNowOf(BuildContext c) {
  try {
    return c.select<AppState, bool>((a) => a.syncingNow);
  } catch (_) {
    return false;
  }
}

/// Whether a derive job is running or about to (the backlog just landed and
/// today's numbers are being worked out), or false in a golden.
bool derivingOf(BuildContext c) {
  try {
    return c.select<AppState, bool>((a) => a.deriving || a.derivePending);
  } catch (_) {
    return false;
  }
}

/// Read a metric envelope. `_scalarMetric` writes the literal string `'—'` for
/// an absent value, so this must never be replaced by `map['value'] as num`.
Metric metricOf(Object? raw) => Metric.parse(raw);

/// WHICH SENSOR counted the steps, in the two words a card has room for — or
/// null when nothing counted (and on days derived before the ladder existed,
/// whose envelopes name no sensor).
///
/// Read off `inputs_used`, which names the sensor rather than the table the
/// count was stored in. The strap's 100 Hz pedometer and its on-chip counter
/// are BOTH "Strap" here: they are genuinely different measurements, but that
/// difference is a density-3 fact and it is spelled out on Nerd stats. What
/// this must never blur is strap versus phone — a card that lets the phone's
/// count read as the wrist's, or the other way round, defeats the whole point
/// of resolving the day per window.
String? stepSensorLabel(Metric m, [AppLocalizations? l]) {
  final used = m.inputsUsed;
  final strap = used.contains('band_pedometer_100hz') ||
      used.contains('band_step_counter');
  final phone = used.contains('phone_pedometer');
  if (strap && phone) return l?.homeStepSensorStrapPhone ?? 'Strap + phone';
  if (strap) return l?.homeStepSensorStrap ?? 'Strap';
  if (phone) return l?.homeStepSensorPhone ?? 'Phone';
  return null;
}

/// The inner object of an envelope whose `value` is a MAP, not a number —
/// every cross-day metric is one of these (`regularity.value.sri`,
/// `sleep_coach.need.value.need_sec`). `Metric.parse` reads those as absent,
/// because a map is not a num, so the object has to come out by hand.
Map<String, dynamic>? envValue(Object? raw) {
  if (raw is! Map) return null;
  final v = raw['value'];
  return v is Map ? v.cast<String, dynamic>() : null;
}

/// The night the overnight block in a `getToday()` result actually came from,
/// when that is NOT today's — otherwise null.
///
/// `getToday` holds the last scored night over until today's settles, which is
/// every morning before the first sync and the whole of any gap after one.
/// Readiness, sleep, resting HR, HRV and skin temperature then all describe
/// that night while steps and active energy describe today.
///
/// WHAT THIS IS STILL FOR, now that no screen prints its numbers as today's
/// (see [overnightMetric]): naming WHICH NIGHT, and opening it. A screen that
/// is explicitly about a dated night — Sleep, with a day stepper over it —
/// wants this, because the night it should open is the last one that scored,
/// not a calendar day with no sleep in it. Every screen resolves that night
/// HERE so Home, Readiness, Sleep and Health cannot each answer "which night?"
/// differently.
String? heldOverNightOf(Map<String, dynamic> today) {
  final st = today['status'];
  if (st is! Map) return null;
  return st['showing_prior_overnight'] == true
      ? st['overnight_day']?.toString()
      : null;
}

/// Why today has no overnight figures, or null when it has its own.
///
/// Two absences that are not interchangeable, both read straight off
/// `status.overnight_state`:
///
///   * `building` — today's records HAVE reached the app and the night has not
///     finished being worked out. It resolves on its own and there is nothing
///     to ask anyone to do.
///   * anything else — nothing from last night has arrived. Syncing is the
///     thing that changes it.
///
/// Prose, not a `key:arg` token, so `whyFromNote` passes it through as the
/// sentence it already is.
String? staleOvernightNote(Map<String, dynamic> today, [AppLocalizations? l]) {
  if (heldOverNightOf(today) == null) return null;
  final st = today['status'];
  return (st is Map ? st['overnight_state']?.toString() : null) == 'building'
      ? l?.homeOvernightBuilding ?? 'Last night is still being worked out.'
      : l?.homeOvernightNothingYet ??
          'Nothing from last night has reached the app yet.';
}

/// An overnight envelope, REFUSED when the night behind it is not today's.
///
/// This reverses a decision that was made deliberately and was wrong on a
/// phone. `getToday` serves the last scored night whenever today's has not
/// settled, and the old argument for printing it was that the number is real
/// and the most recent one there is, so naming its night is enough. It is not:
/// a figure in the today slot is read as today's before anything under it is,
/// so a morning the strap was never worn showed last week's sleep as this
/// morning's, and the caption saying otherwise sat below three rings nobody
/// reads past. A stale number is a worse answer than an honest gap.
///
/// So the numbers stop here and the reason travels in their place. The night
/// itself is not lost — [heldOverNightOf] still names it, and the screens that
/// are ABOUT a dated night still open it.
Metric overnightMetric(Map<String, dynamic> today, Object? raw,
    [AppLocalizations? l]) {
  final why = staleOvernightNote(today, l);
  return why == null ? metricOf(raw) : Metric(note: why);
}

/// A scalar lifted out of an object-valued envelope, wearing that envelope's
/// honesty (tier, confidence, note) so `StatusCard.forMetric` still works on
/// it.
Metric envMetric(Object? raw, num? scalar, {String? unit}) {
  final m = raw is Map ? raw.cast<String, dynamic>() : const <String, dynamic>{};
  final env = Metric.parse({...m, 'value': scalar});
  return scalar == null && env.note == null
      ? Metric(unit: unit, note: m['note']?.toString())
      : Metric(
          value: scalar,
          unit: unit ?? env.unit,
          confidence: env.confidence,
          tier: env.tier,
          inputsUsed: env.inputsUsed,
          note: env.note,
        );
}

/// One stored chart point: `t` is the epoch SECONDS `getChart` stamps on it
/// (local noon of the day the value was derived on), `v` the value.
typedef ChartPoint = ({int t, double v});

/// A `[{t, v}]` point list from `getChart`, timestamps INTACT.
///
/// [seriesOf] drops `t`, and everything downstream then labelled its x axis off
/// the ARRAY INDEX — `'Today'`, `'N days ago'`, weekday letters. `metric_series`
/// stores one row per DERIVED day, not one per calendar day, so after a sync gap
/// the newest stored point is days old and was still being called "Today".
/// Anything that draws a dated axis reads this.
List<ChartPoint> pointsOf(Object? chart) {
  final pts = chart is Map ? chart['points'] : null;
  if (pts is! List) return const [];
  return [
    for (final e in pts)
      if (e is Map && e['v'] is num && e['t'] is num)
        (t: (e['t'] as num).round(), v: (e['v'] as num).toDouble()),
  ];
}

/// The bare values of a point list, for statistics — a mean, a last reading,
/// an [AxisSpec]. NEVER for a painter: a compacted list is the bug, because it
/// lets 22 stored days masquerade as 30 continuous ones.
List<double> valuesOf(List<ChartPoint> pts) => [for (final p in pts) p.v];

/// [pts] laid out DENSE: one slot per calendar day, [days] slots long, ending
/// today. A day `metric_series` has no row for is `null`, which the painter
/// draws as a break rather than joining across.
///
/// This is the shape every chart in this app takes. `metric_series` gets a row
/// only on a day that derives, so the stored list is already compacted: after a
/// four-day sync gap the newest point sat at the right-hand edge under the
/// label "Today", and the line ran straight through the missing week as though
/// it had been measured.
List<double?> denseDays(List<ChartPoint> pts, int days) {
  final out = List<double?>.filled(days, null);
  for (final p in pts) {
    final behind = daysBehind(p.t);
    if (behind == null || behind < 0 || behind >= days) continue;
    out[days - 1 - behind] = p.v;
  }
  return out;
}

/// A `[{t, v}]` point list from `getChart` as a plain series.
///
/// Values only — the caller cannot tell WHEN any of them was recorded. Use
/// [pointsOf] for anything that labels, spans or dates the series; this is for
/// sparklines, which claim nothing about time.
List<double> seriesOf(Object? chart) => valuesOf(pointsOf(chart));

/// An x-axis label for a stored point: [todayWord] when the point really is
/// today's, otherwise "N days ago" counted from the point's OWN date.
///
/// The same vocabulary the axes already spoke. What changed is where N comes
/// from: it used to be the point's position in the array, and `metric_series`
/// holds one row per DERIVED day, so a thirty-point series can span two months
/// and both its edges were labelled as though it spanned thirty days.
String axisDay(int? epochSec,
    {String todayWord = 'Today', String unitWord = 'days'}) {
  final behind = daysBehind(epochSec);
  if (behind == null) return '';
  if (behind <= 0) return todayWord;
  return '$behind $unitWord ago';
}

/// Whole calendar days between a stored point and today, or null when there is
/// no point. Anything above zero means the number drawn is not today's, and a
/// card that presents it as today's has to say so.
int? daysBehind(int? epochSec) {
  if (epochSec == null) return null;
  return calendarDaysBetween(
      DateTime.fromMillisecondsSinceEpoch(epochSec * 1000), DateTime.now());
}

/// Whole calendar days from [from] to [to], reading both as LOCAL wall-clock
/// dates and subtracting them in UTC — the same shape as
/// `LocalRepositoryImpl._dayGap`, which is where this rule already lived.
///
/// Subtracting two local midnights across a DST boundary is 23 or 25 hours and
/// `inDays` truncates the short one, so on 10 March in New York both 9 March
/// and 8 March came back as 1 day behind: [denseDays] wrote them into the same
/// slot, lost the older one, and every dated axis before the spring-forward
/// shifted by a position.
int calendarDaysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day)
        .difference(DateTime.utc(from.year, from.month, from.day))
        .inDays;

/// The withheld-rollup reason inside a `getInsights()` result, or null when the
/// result is real (or simply empty).
Map<String, dynamic>? staleReasonOf(Map<String, dynamic> insights) =>
    insights['stale'] is Map
        ? (insights['stale'] as Map).cast<String, dynamic>()
        : null;

/// The cross-day rollup was WITHHELD: `getInsights` returned the reason it
/// refused instead of the numbers (`LocalRepositoryImpl.crossDayStaleReason`).
///
/// Every screen that reads the rollup renders this rather than quietly showing
/// nothing — "you have no drivers yet" and "we have drivers we will not stand
/// behind" are different states, and the cold-start copy is a wrong answer to
/// the second one.
/// The database could not be opened on this launch and was rebuilt.
///
/// This is the loudest thing this screen can say, and it should be: the old
/// file is parked on disk and only what `salvaged` lists came back. A rebuild
/// the user never hears about is indistinguishable from their data quietly
/// vanishing — which is the one thing a local-first app must never do.
///
/// The counts are stated per table rather than summed. "1,204 rows recovered"
/// reads as reassurance; "nutrition 0" is the sentence that actually tells
/// someone their food log is gone.
StatusCard? dbRebuiltCard(DbRebuild? r, [AppLocalizations? l]) {
  if (r == null) return null;
  final saved = r.salvaged.entries.where((e) => e.value > 0).toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final lost = r.salvaged.entries.where((e) => e.value == 0).toList();
  final savedList = saved.map((e) => '${e.key} ${thousands(e.value)}').join(' · ');
  final lostList = lost.map((e) => e.key).join(' · ');
  return StatusCard(
    l?.homeDbRebuiltTitle ?? 'Your database was rebuilt to start the app',
    '${r.cause}\n\n'
        '${saved.isEmpty ? (l?.homeDbRebuiltNothingRecovered ?? 'Nothing could be read back.') : (l?.homeDbRebuiltRecovered(savedList) ?? 'Recovered: $savedList.')}'
        '${lost.isEmpty ? '' : ' ${l?.homeDbRebuiltEmpty(lostList) ?? 'Empty: $lostList.'}'}'
        '\n\n${l?.homeDbRebuiltKept(r.quarantinePath) ?? 'The original file is kept at ${r.quarantinePath} — nothing was deleted.'}',
    icon: LucideIcons.databaseBackup,
  );
}

/// The bare day during a live workout — missing COMPUTE, not data. A live
/// session holds derivation (`DeriveScheduler.setWorkoutActive`), so nothing
/// lands in `day_result` until it ends: the band keeps recording, the sync
/// keeps landing records, and "Sync the band" is a false answer — the sync
/// completes and changes nothing on this screen. The true remedy is finishing
/// the session, and its bar is pinned right below this card, so the card
/// points there rather than duplicating the door.
StatusCard workoutHoldCard([AppLocalizations? l]) => StatusCard(
      l?.homeWorkoutHoldTitle ?? 'A workout is still running',
      l?.homeWorkoutHoldBody ??
          'Today is on hold while a workout is live: the band keeps recording, '
          'but the numbers are computed once the session ends. Finish the workout '
          'from the bar below and today fills in — syncing will not.',
      icon: LucideIcons.timer,
    );

StatusCard? staleInsightsCard(
    Map<String, dynamic>? reason, VoidCallback? onSync, [AppLocalizations? l]) {
  final s = reason;
  if (s == null) return null;
  final built = s['built_for_day']?.toString();
  return StatusCard(
    l?.homeInsightsRebuildingTitle ?? 'Your cross-day insights are being rebuilt',
    switch (s['kind']) {
      'algo_version' => l?.homeInsightsRebuildingAlgoVersion ??
          'How these are computed changed with the last update.',
      'stale' => built == null || built.isEmpty
          ? (l?.homeInsightsStaleOverWeek ??
              'The last rollup was built over a week ago, which is too old to stand behind.')
          : (l?.homeInsightsStaleOnDay(prettyDay(built, l)) ??
              'The last rollup was built on ${prettyDay(built, l)}, which is too old to stand behind.'),
      _ => l?.homeInsightsNoVersionStamp ?? 'The stored rollup carries no version stamp.',
    },
    fix: onSync == null ? '' : (l?.homeSyncBand ?? 'Sync the band'),
    icon: LucideIcons.refreshCw,
    onFix: onSync,
  );
}

// ── formatting ──

String hm(num? minutes) {
  if (minutes == null) return '';
  final m = minutes.round();
  return m < 60 ? '${m}m' : '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m';
}

/// Minutes → "7:32". The dial form of [hm]: four characters, no letters, so
/// it fits inside an arc at the numeral size.
String hmClock(num? minutes) {
  if (minutes == null) return '';
  final m = minutes.round();
  return '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}';
}

String thousands(num? v) {
  if (v == null) return '';
  final s = v.round().abs().toString();
  final b = StringBuffer(v < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

/// A metric value at the precision its unit actually carries.
///
/// ONE rule, so the same reading is not `71.6` on the detail screen and `72`
/// on the card that links to it. A tenth of a bpm on a nocturnal minimum — or
/// of a millisecond on beat timing recovered from 1 Hz records — is precision
/// the measurement does not have, and a number printing more digits than it
/// knows reads as a more careful measurement than it is. Unitless scores keep
/// a decimal only while they are small enough for one to mean something.
String metricValue(String unit, num? value) {
  if (value == null) return '';
  final v = value.toDouble();
  switch (unit) {
    case 'min':
      return hm(v);
    case 'steps':
    case 'kcal':
      return thousands(v);
    case 'bpm':
    case 'ms':
    case '%':
      return v.round().toString();
    case 'br/min':
    case '°':
      return v.toStringAsFixed(1);
  }
  if (v.abs() >= 100) return v.round().toString();
  if (v.abs() >= 10) return v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1);
  return v.toStringAsFixed(1);
}

/// The unit to print BESIDE [metricValue]'s output, which is empty when the
/// format already carries it: `metricValue('min', 443)` is "7h 23m", and a
/// `min` label next to that reads "7h 23m min".
String unitBeside(String unit) => unit == 'min' ? '' : unit;

/// Minute-of-day → "10:40 PM".
///
/// ONE clock format in the app. This used to render 24-hour while Wellness
/// rendered the same field 12-hour, so a target bedtime read `22:40` on Home
/// and `10:40 PM` two screens away. Both now go through the journal layer's
/// [formatMinuteOfDay], which is the format the rest of the app already uses
/// and the one that already has a test.
String clock(num? minOfDay) =>
    minOfDay == null ? '' : formatMinuteOfDay(minOfDay.round());

/// Epoch seconds → "11:08 PM" in the device zone.
String clockOfTs(num? ts) {
  if (ts == null) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ts.round() * 1000);
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
}

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const _weekdays = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday',
  'Friday', 'Saturday', 'Sunday',
];

String monthName(int month, AppLocalizations? l) {
  if (l == null) return _months[month - 1];
  return [
    l.homeMonthJanuary, l.homeMonthFebruary, l.homeMonthMarch,
    l.homeMonthApril, l.homeMonthMay, l.homeMonthJune,
    l.homeMonthJuly, l.homeMonthAugust, l.homeMonthSeptember,
    l.homeMonthOctober, l.homeMonthNovember, l.homeMonthDecember,
  ][month - 1];
}

const _monthsShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Abbreviated month for "Thu 4 Sep" date chips.
String monthShortName(int month, AppLocalizations? l) {
  if (l == null) return _monthsShort[month - 1];
  return [
    l.homeMonthJanuaryShort, l.homeMonthFebruaryShort, l.homeMonthMarchShort,
    l.homeMonthAprilShort, l.homeMonthMayShort, l.homeMonthJuneShort,
    l.homeMonthJulyShort, l.homeMonthAugustShort, l.homeMonthSeptemberShort,
    l.homeMonthOctoberShort, l.homeMonthNovemberShort, l.homeMonthDecemberShort,
  ][month - 1];
}

String _weekdayName(int weekday, AppLocalizations? l) {
  if (l == null) return _weekdays[weekday - 1];
  return [
    l.homeWeekdayMonday, l.homeWeekdayTuesday, l.homeWeekdayWednesday,
    l.homeWeekdayThursday, l.homeWeekdayFriday, l.homeWeekdaySaturday,
    l.homeWeekdaySunday,
  ][weekday - 1];
}

const _weekdaysShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Abbreviated weekday for `DateTime.weekday` (1 = Monday), e.g. "Thu 4 Sep"
/// date chips. Reuses the `wellness*` short-day keys — they're already
/// translated everywhere and mean the same three letters here.
String weekdayShortName(int weekday, AppLocalizations? l) {
  if (l == null) return _weekdaysShort[weekday - 1];
  return [
    l.wellnessMon, l.wellnessTue, l.wellnessWed,
    l.wellnessThu, l.wellnessFri, l.wellnessSat, l.wellnessSun,
  ][weekday - 1];
}

/// 'YYYY-MM-DD' → "Saturday, 20 May".
String prettyDay(String? dayId, [AppLocalizations? l]) {
  final d = dayId == null ? null : DateTime.tryParse(dayId);
  if (d == null) return '';
  return '${_weekdayName(d.weekday, l)}, ${d.day} ${monthName(d.month, l)}';
}

/// The readiness band. `readiness_glassbox` carries no label of its own, so the
/// banding is ours and lives in one place — this one.
///
/// [tier] is that same banding in a form the native surfaces can read.
/// `WidgetService.push` publishes it as `readiness_tier` (and [label] as
/// `readiness_band`) so the widget, the Watch and Siri paint it in their own
/// palettes instead of each keeping a private copy of the cut-offs. They did,
/// and a 65 rendered green on the phone, orange on the widget and yellow on
/// the wrist. -1 = not scored.
///
/// THE CUT-OFFS ARE THE SCORE'S OWN QUANTILES, NOT ROUND NUMBERS (issue #250).
/// `readinessComposite` is `100 / (1 + exp(-z̄))` with no scale parameter, and
/// z̄ is a weight-renormalised mean of per-input robust z's — each ~N(0,1)
/// against that person's OWN baseline. So the score is a percentile of self
/// whose CENTRE IS 50 BY CONSTRUCTION: a night exactly at personal median
/// scores 50, and the old 40/60/80 bands filed that median night under "Take it
/// easy". Roughly a quarter of all nights fell under "Rest today" and 1.7 %
/// could ever reach "Good to go" — it needed every input ~1.4 SD above median
/// at once. A warning that fires on the typical night is not a warning.
///
/// z̄'s own SD is NOT 1: averaging the disclosed weights (.40/.30/.20/.10,
/// renormalised over present inputs) gives σ ≈ 0.55-0.60 if the inputs were
/// independent, ~0.70 at the positive correlation HRV/RHR/RR actually have.
/// σ ≈ 0.65 is the middle of that, and the cut-offs below are its quantiles:
///
///   score = 100 / (1 + exp(-0.65 · Φ⁻¹(p)))
///     p=.05 → 26   p=.20 → 37   p=.75 → 61
///
/// which lands 5 % of nights on "Rest today", 15 % on "Take it easy", 55 % on
/// "Steady" and 25 % on "Good to go". The median night is now the neutral band,
/// which is the whole point. Under the old cut-offs the same distribution read
/// 27 / 47 / 25 / 2.
///
/// σ is the one soft number here — it is a property of how correlated a given
/// person's four inputs are, and it moves with how many of them are present.
/// Re-derive it from a real `metric_series` readiness distribution when there
/// is one long enough to measure; do not nudge the cut-offs by feel.
({String label, Color color, int tier}) readinessBand(num? v,
    [AppLocalizations? l]) {
  if (v == null) {
    return (label: l?.homeReadinessNotScored ?? 'Not scored', color: C.n400, tier: -1);
  }
  if (v >= 61) {
    return (label: l?.homeReadinessGoodToGo ?? 'Good to go', color: C.green, tier: 3);
  }
  if (v >= 37) {
    return (label: l?.homeReadinessSteady ?? 'Steady', color: C.green, tier: 2);
  }
  if (v >= 26) {
    return (label: l?.homeReadinessTakeItEasy ?? 'Take it easy', color: C.yellow, tier: 1);
  }
  return (label: l?.homeReadinessRestToday ?? 'Rest today', color: C.red, tier: 0);
}

/// Glass-box driver keys are the pipeline's own short names.
const driverLabels = {
  'hrv': 'HRV',
  'rhr': 'Resting heart rate',
  'resp': 'Breathing rate',
  'temp': 'Skin temperature',
};

/// A pipeline key the map does not cover is HUMANISED, never printed raw. The
/// glass-box emits whatever inputs the composite used, so a new one used to
/// surface on Home as `resp_rate_slope`.
String driverLabel(Object? key, [AppLocalizations? l]) {
  final k = key?.toString() ?? '';
  final known = switch (k) {
    'hrv' => l?.homeDriverHrv ?? driverLabels['hrv'],
    'rhr' => l?.homeDriverRhr ?? driverLabels['rhr'],
    'resp' => l?.homeDriverResp ?? driverLabels['resp'],
    'temp' => l?.homeDriverTemp ?? driverLabels['temp'],
    _ => null,
  };
  if (known != null) return known;
  if (k.isEmpty) return '';
  final words = k.replaceAll('_', ' ').trim();
  return words.isEmpty
      ? ''
      : '${words[0].toUpperCase()}${words.substring(1)}';
}

/// The three rings, and what each one does when its metric is not there.
///
/// A ring is a shape that always renders, and this data frequently is not
/// there: readiness exists on 71 % of days and needs four prior nights before
/// it exists at all. So the absent states ARE the design here rather than an
/// error branch bolted onto three pretty circles. Each ring has four:
///
///   * MEASURED — an arc, the number, and what the number is out of.
///   * CALIBRATING — a muted arc at nights-banked over nights-needed, with the
///     count under it. Visibly progress towards a real ring; an arc at zero
///     would read as a bad score, which is the lie this exists to avoid. It is
///     drawn only for a `need_baseline` note, the one absence that IS progress.
///   * MEASURED, UNSCALED — sleep with no computed need behind it. The number
///     is real and the fraction is not known, so the track draws empty and the
///     line under it says there is no target yet. Filling it against the
///     hardcoded 480 would be inventing the user's sleep need.
///   * ABSENT — the track alone, the absence in words where the number goes,
///     and the PIPELINE'S OWN reason on a row under the trio which is also the
///     door into the screen that can say more. Three [StatusCard]s is not a
///     home screen; a ring with nothing in it and no reason is worse than one.
///
/// Every ring opens something: recovery → [ReadinessDetail], strain →
/// [DayStrainDetail], sleep → [SleepDetail].
class RingTrio extends StatelessWidget {
  final HomeData d;

  /// Push the ring's own screen. Null in a gallery, where there is no navigator
  /// worth pushing onto.
  final void Function(HomeRingKind)? onOpen;

  /// Draw the dials and nothing under them — no gap rows, no drivers. The
  /// bare day, where one card under the dials says everything.
  final bool quiet;

  const RingTrio({super.key, required this.d, this.onOpen, this.quiet = false});

  /// Whether ANY of the three has something to draw. When none do, the screen
  /// owes the user one written absence, not three empty circles.
  static bool has(HomeData d) =>
      HomeRingKind.values.any((k) => _ringOf(k, d, null).why == null);

  /// Display order. The enum stays in the order the rest of the app reads.
  static const _order = [
    HomeRingKind.sleep,
    HomeRingKind.recovery,
    HomeRingKind.strain,
  ];

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final rings = [for (final k in _order) _ringOf(k, d, l)];
    final gaps = rings.where((r) => r.why != null).toList();
    // THERE IS NO "THESE TWO ARE FROM SATURDAY" LINE ANY MORE, and there is
    // nothing left for one to explain. Recovery and sleep used to be served
    // from the last scored night whenever today's had not settled, and this
    // card carried one sentence naming that night. Read on a phone, the
    // sentence lost: a number inside a ring is today's, and a caption under
    // three rings does not undo it. The loader refuses the older night now
    // ([overnightMetric]), so a ring with no night behind it is a gap row with
    // the reason in it — same place every other absence on this screen goes.

    // THE DIALS SIT ON THE PAGE, not in a card. Three open arcs across the
    // top of a black screen is the whole signature of the look; boxing them
    // makes them a widget. Order is sleep · recovery · strain — the night,
    // then what it gave back, then what the day has cost.
    return Column(children: [
      if (bigText(c))
        // Past ~1.3× a 100 pt column cannot hold the word "Recovery" on one
        // line and there is nowhere for it to wrap to. The ring keeps its
        // size and the type gets the width instead.
        for (var i = 0; i < rings.length; i++) ...[
          if (i > 0) const SizedBox(height: S.x2),
          _RingRow(rings[i], onTap: _open(rings[i].kind)),
        ]
      else
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < rings.length; i++) ...[
              if (i > 0) const SizedBox(width: S.x3),
              Expanded(
                  child: _RingColumn(rings[i], onTap: _open(rings[i].kind))),
            ],
          ],
        ),
      if (!quiet && (gaps.isNotEmpty || (d.readiness.value != null && d.drivers.isNotEmpty)))
        const SizedBox(height: S.x4),
      if (!quiet)
        for (final r in gaps) ...[
          Divider(color: p.line, height: 1),
          _GapRow(r, onTap: _open(r.kind)),
        ],
      if (!quiet && d.readiness.value != null && d.drivers.isNotEmpty) ...[
          Divider(color: p.line, height: 1),
          const SizedBox(height: S.x3),
          Pressable(
            onTap: _open(HomeRingKind.recovery),
            // Top-aligned: at an accessibility size the driver list is three
            // lines and "Why?" was centred against the middle of them.
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l?.homeWhyLabel ?? 'Why?', style: F.cap.copyWith(color: p.ink3)),
              const SizedBox(width: S.x2),
              Expanded(
                child: Text(
                  d.drivers
                      .take(3)
                      .map((e) => driverLabel(e['label'], l))
                      .join(' · '),
                  style: F.cap.copyWith(color: p.ink2),
                ),
              ),
              Icon(LucideIcons.chevronRight, size: 15, color: p.ink3),
            ]),
          ),
        ],
    ]);
  }

  VoidCallback? _open(HomeRingKind k) {
    final f = onOpen;
    return f == null ? null : () => f(k);
  }
}

/// Which ring. The three the app can stand behind on a home screen: what the
/// night gave back, what the day has cost, and what the night was made of.
enum HomeRingKind { recovery, strain, sleep }

/// One ring's resolved state — the only place a metric becomes a shape.
class _RingState {
  final HomeRingKind kind;
  final String label, value, sub;

  /// Printed small beside [value] inside the dial — `%` on recovery. Empty on
  /// a duration or a scale value that carries its own shape.
  final String unit;
  final IconData icon;
  final Color color;

  /// What to sweep, 0…1 — null when there is nothing honest to sweep.
  final double? frac;

  /// The arc is calibration progress, not the metric, and is drawn muted.
  final bool calibrating;

  /// Nights banked / nights needed, set only while [calibrating] — the
  /// dashed ring divides itself into exactly [need] beads and fills [have]
  /// of them, rather than approximating that count from [frac].
  final int? have, need;

  /// The absence's reason, as the pipeline gave it. Non-null only when the
  /// ring is [absent].
  final String? why;

  const _RingState(
    this.kind,
    this.label,
    this.icon,
    this.color, {
    required this.value,
    this.unit = '',
    this.sub = '',
    this.frac,
    this.calibrating = false,
    this.have,
    this.need,
    this.why,
  });

  /// A number the ring is actually reporting. Calibration is progress, not a
  /// reading, so it is not one.
  bool get measured => why == null && !calibrating;

  Color arc(P p) => calibrating ? p.ink3 : p.on(color);
  Color ink(P p) => measured ? p.on(color) : p.ink3;

  String get spoken => [
        label,
        measured ? '$value$unit' : value.toLowerCase(),
        if (sub.isNotEmpty) sub,
        ?why,
      ].join('. ');
}

_RingState _ringOf(HomeRingKind k, HomeData d, AppLocalizations? l) {
  switch (k) {
    case HomeRingKind.recovery:
      final v = d.readiness.value;
      final band = readinessBand(v, l);
      return v == null
          ? _gap(k, l?.homeRingRecovery ?? 'Recovery', LucideIcons.batteryCharging,
              C.green, d.readiness, l?.homeReadinessNotScored ?? 'Not scored', l)
          : _RingState(k, l?.homeRingRecovery ?? 'Recovery',
              LucideIcons.batteryCharging, band.color,
              value: '${v.round()}', unit: '%', sub: band.label, frac: v / 100);
    case HomeRingKind.strain:
      final v = d.strain.value;
      // 0–21 is the scale's own ceiling, not a target invented here.
      return v == null
          ? _gap(k, l?.homeRingStrain ?? 'Strain', LucideIcons.zap, C.strain,
              d.strain, l?.homeRingNoStrain ?? 'No strain', l, unit: 'days')
          : _RingState(k, l?.homeRingStrain ?? 'Strain', LucideIcons.zap, C.strain,
              value: v.toStringAsFixed(1), sub: l?.homeStrainOf21 ?? 'of 21', frac: v / 21);
    case HomeRingKind.sleep:
      final v = d.sleepMin.value;
      final need = d.sleepNeedMin.value;
      return v == null
          ? _gap(k, l?.homeRingSleep ?? 'Sleep', LucideIcons.moon, C.sleep,
              d.sleepMin, l?.homeRingNoSleep ?? 'No sleep', l,
              fallbackWhy: l?.homeSleepGapFallback ??
                  'No night long enough to score was recorded.')
          : _RingState(k, l?.homeRingSleep ?? 'Sleep', LucideIcons.moon, C.sleep,
              // h:mm, not "7h 32m" — the dial holds four characters well and
              // seven badly, and a clock-shaped duration is how the reference
              // app prints hours slept.
              value: hmClock(v),
              // No computed need means no denominator. The hardcoded 480 in
              // the sleep bundle is not this user's need and must never be
              // shown as one, so the ring stays open and says so.
              sub: need == null
                  ? (l?.homeSleepNoTarget ?? 'No target yet')
                  : (l?.homeOfSpan(hm(need)) ?? 'of ${hm(need)}'),
              frac: need == null || need <= 0 ? null : v / need);
  }
}

/// The absent half: calibrating when the note says the gate is a baseline
/// still filling, otherwise the absence and its reason.
_RingState _gap(HomeRingKind k, String label, IconData icon, Color color,
    Metric m, String word, AppLocalizations? l,
    {String unit = 'nights', String fallbackWhy = ''}) {
  final counts = baselineCountsFromNote(m.note);
  if (counts != null) {
    return _RingState(k, label, icon, color,
        value: l?.homeCalibrating ?? 'Calibrating',
        sub: unit == 'days'
            ? (l?.homeCalibratingDays(counts.have, counts.need) ??
                '${counts.have} of ${counts.need} days')
            : (l?.homeCalibratingNights(counts.have, counts.need) ??
                '${counts.have} of ${counts.need} nights'),
        frac: (counts.have / counts.need).clamp(0.0, 1.0),
        calibrating: true,
        have: counts.have,
        need: counts.need);
  }
  return _RingState(k, label, icon, color,
      value: word,
      // THE PIPELINE'S REASON FIRST. A sentence written here by someone who
      // never saw the day is the fallback, and where there is neither the ring
      // says it does not know rather than guessing a cause.
      why: whyFromNote(m.note, unit: unit) ??
          (fallbackWhy.isNotEmpty
              ? fallbackWhy
              : (l?.homeGapNoReason ?? 'Nothing recorded says why this is missing.')));
}

/// The dial itself: a 270° open arc with the NUMBER inside it, the way the
/// reference app draws all three scores. An empty [frac] draws the track and
/// nothing else. [big] is the number's type step; the row layout at
/// accessibility sizes passes a smaller one.
class _Dial extends StatelessWidget {
  final _RingState r;
  final double stroke;
  final TextStyle big;

  const _Dial(this.r, {required this.stroke, required this.big});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final measured = r.measured;
    return Stack(alignment: Alignment.center, children: [
      CustomPaint(
        size: Size.infinite,
        // Calibrating draws as discrete dashes filling in night by night; a
        // measured value draws the open arc with a soft glow under it. An
        // absent ring is the bare track, and the words go where the number
        // would.
        painter: r.calibrating
            // One dash per night the baseline needs, not a fixed count —
            // "6 of 14" draws as 14 divisions with 6 filled.
            ? DashedRing(r.frac ?? 0, r.arc(p), p.track,
                stroke: stroke, segments: r.need ?? 24)
            : Ring(r.frac ?? 0, r.arc(p), p.track,
                stroke: stroke, t: animate(c, 1), solid: measured),
      ),
      if (measured)
        Padding(
          padding: EdgeInsets.all(stroke + S.x2),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                // White, the way the reference app prints every score —
                // the ring carries the colour.
                Text(r.value, style: big.copyWith(color: p.ink)),
                if (r.unit.isNotEmpty)
                  Text(r.unit, style: F.n17.copyWith(color: p.ink)),
              ],
            ),
          ),
        )
      else
        Text('–', style: big.copyWith(color: p.ink3)),
    ]);
  }
}

/// The default: three across, the number under the ring rather than inside it.
/// Inside is where a duration overflows its own circle at the first
/// accessibility step, and nothing about "7h 45m" gets shorter.
class _RingColumn extends StatelessWidget {
  final _RingState r;
  final VoidCallback? onTap;

  const _RingColumn(this.r, {this.onTap});

  @override
  Widget build(BuildContext c) => Pressable(
        onTap: onTap,
        semanticLabel: r.spoken,
        child: Column(children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 96),
            child: AspectRatio(
              aspectRatio: 1,
              child: _Dial(r, stroke: 5, big: F.n34),
            ),
          ),
          const SizedBox(height: S.x3),
          _RingText(r, align: TextAlign.center),
        ]),
      );
}

/// The accessibility layout: ring left, type in the width it needs.
class _RingRow extends StatelessWidget {
  final _RingState r;
  final VoidCallback? onTap;

  const _RingRow(this.r, {this.onTap});

  @override
  Widget build(BuildContext c) => Pressable(
        onTap: onTap,
        semanticLabel: r.spoken,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: S.x2),
          child: Row(children: [
            SizedBox(
              width: 64,
              height: 64,
              child: _Dial(r, stroke: 5, big: F.n17),
            ),
            const SizedBox(width: S.x3),
            Expanded(child: _RingText(r, align: TextAlign.start)),
          ]),
        ),
      );
}

class _RingText extends StatelessWidget {
  final _RingState r;
  final TextAlign align;

  const _RingText(this.r, {required this.align});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final cross = align == TextAlign.center
        ? CrossAxisAlignment.center
        : CrossAxisAlignment.start;
    return Column(crossAxisAlignment: cross, children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: align == TextAlign.center
            ? MainAxisAlignment.center
            : MainAxisAlignment.start,
        children: [
          Text(r.label.toUpperCase(),
              style: F.over.copyWith(color: p.ink), textAlign: align),
          const SizedBox(width: 2),
          Icon(LucideIcons.chevronRight, size: 13, color: p.ink3),
        ],
      ),
      // A measured number is INSIDE the dial. What goes under it is the
      // qualifier — the band, the target, the scale. An absent or calibrating
      // ring has no number inside, so its word goes here instead, in the
      // sentence weight rather than the numeral one.
      if (!r.measured) ...[
        const SizedBox(height: 2),
        Text(r.value, style: F.cap.copyWith(color: p.ink2), textAlign: align),
      ],
      // A measured dial carries the label alone, the way the reference app
      // does; the qualifier ("of 21", the band) belongs to the screen the
      // dial opens. An unmeasured one keeps its sub-line: it is the reason.
      if (r.sub.isNotEmpty && !r.measured) ...[
        const SizedBox(height: 2),
        Text(r.sub, style: F.cap.copyWith(color: p.ink3), textAlign: align),
      ],
    ]);
  }
}

/// WHY a ring is empty, on the row that also opens the screen which can say
/// more about it. The three parts of a [StatusCard] — what is missing, why,
/// what to do about it — at the size a home screen can afford to spend on an
/// absence.
class _GapRow extends StatelessWidget {
  final _RingState r;
  final VoidCallback? onTap;

  const _GapRow(this.r, {this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(r.icon, size: 15, color: p.ink3),
          const SizedBox(width: S.x2),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: '${r.label} · ',
                    style: F.cap.copyWith(
                        color: p.ink2, fontWeight: FontWeight.w600)),
                TextSpan(text: r.why, style: F.cap.copyWith(color: p.ink3)),
              ]),
            ),
          ),
          const SizedBox(width: S.x2),
          Icon(LucideIcons.chevronRight, size: 15, color: p.ink3),
        ]),
      ),
    );
  }
}

// ═══════════════════ the screen ═══════════════════

class HomeData {
  final String? name;
  final String? dayId;
  final Metric readiness;
  final List<Map<String, dynamic>> drivers;
  final Metric sleepMin, rhr, steps, calories, caloriesTotal;

  /// The day's 0–21 strain, read from the same `getToday` bundle the Workout
  /// tab reads. Nothing on this screen computes it.
  final Metric strain;

  final int stepGoal;
  final Metric sleepNeedMin;
  final Metric bedtime;
  final Map<String, dynamic>? strainTarget;

  /// Non-null when the cross-day rollup was withheld rather than absent — see
  /// [staleInsightsCard]. Drivers, sleep need and bedtime are all empty in that
  /// case, and the screen owes the user the reason.
  final Map<String, dynamic>? insightsStale;

  /// The last night that scored, when that is NOT today's — so the screen can
  /// say WHERE THE DATA STOPS on a day it has nothing of its own.
  ///
  /// It is no longer where readiness, sleep or resting heart rate come from:
  /// [overnightMetric] refuses those at the loader, and this is what is left
  /// of the held-over night once its numbers are gone. Its one job on this
  /// screen is the sentence in the nothing-today card — "the last night this
  /// app scored was Saturday" is a fact about coverage, not a reading dressed
  /// as one.
  final String? heldOverNight;

  /// The illness watch's own state — 'green' / 'amber' / 'red', or null before
  /// it has the 7 nights of baseline it needs. Home renders it only when it is
  /// amber or red; see the exception noted at the top of this file.
  final String? illnessState;

  /// The night the watch is ABOUT, and how far that night sat from this user's
  /// own baseline. `z` belongs to the latest night alone and can be negative
  /// while the run is still up, so the copy says which direction rather than
  /// implying the run reversed.
  final String? illnessDay;
  final double? illnessZ;

  /// The rest of the dashboard: the three overnight inputs beside resting
  /// heart rate, read straight off the day bundle.
  final Metric hrv, resp, temp;

  /// The stress block — score 0–100 and the pipeline's own word for it.
  final double? stressScore;
  final String? stressLevel;

  /// When last night ran, for the activities row. Epoch seconds.
  final num? sleepOnsetTs, sleepWakeTs;

  /// `baselines` off the heart bundle: per input, value / baseline / delta /
  /// spread. Read for the health-monitor count and the dashboard's
  /// comparison lines; nothing here computes.
  final Map<String, dynamic> baselines;

  const HomeData({
    this.name,
    this.dayId,
    this.readiness = Metric.empty,
    this.drivers = const [],
    this.sleepMin = Metric.empty,
    this.rhr = Metric.empty,
    this.steps = Metric.empty,
    this.calories = Metric.empty,
    this.caloriesTotal = Metric.empty,
    this.strain = Metric.empty,
    this.stepGoal = kDefaultStepGoal,
    this.sleepNeedMin = Metric.empty,
    this.bedtime = Metric.empty,
    this.strainTarget,
    this.heldOverNight,
    this.illnessState,
    this.illnessDay,
    this.illnessZ,
    this.insightsStale,
    this.hrv = Metric.empty,
    this.resp = Metric.empty,
    this.temp = Metric.empty,
    this.stressScore,
    this.stressLevel,
    this.sleepOnsetTs,
    this.sleepWakeTs,
    this.baselines = const {},
  });

  /// The three illness fields, replaced together. Test-facing sugar, and they
  /// travel as a set on purpose — they are read as one envelope, and setting
  /// one without the others describes a state the pipeline cannot produce.
  HomeData copyOrIllness(String? state, String? day, double? z) => HomeData(
        name: name,
        dayId: dayId,
        readiness: readiness,
        drivers: drivers,
        sleepMin: sleepMin,
        rhr: rhr,
        steps: steps,
        calories: calories,
        caloriesTotal: caloriesTotal,
        strain: strain,
        stepGoal: stepGoal,
        sleepNeedMin: sleepNeedMin,
        bedtime: bedtime,
        strainTarget: strainTarget,
        heldOverNight: heldOverNight,
        illnessState: state,
        illnessDay: day,
        illnessZ: z,
        insightsStale: insightsStale,
        hrv: hrv,
        resp: resp,
        temp: temp,
        stressScore: stressScore,
        stressLevel: stressLevel,
        sleepOnsetTs: sleepOnsetTs,
        sleepWakeTs: sleepWakeTs,
        baselines: baselines,
      );

  static Future<HomeData> load(LocalRepository repo, [AppLocalizations? l]) async {
    final today = await repo.getToday();
    final cd = await repo.getInsights();
    final profile = await repo.getProfile();

    final daily = today['daily'];
    final sleep = today['sleep'];
    Object? d(String k) => daily is Map ? daily[k] : null;
    Object? s(String k) => sleep is Map ? sleep[k] : null;

    final gb = cd['readiness_glassbox'];
    final gbDrivers = gb is Map ? gb['drivers'] : null;

    final coach = cd['sleep_coach'];
    final needEnv = coach is Map ? coach['need'] : null;
    final bedEnv = coach is Map ? coach['bedtime'] : null;
    final needSec = (envValue(needEnv)?['need_sec'] as num?);

    final strain = today['coach'];

    final heldOver = heldOverNightOf(today);
    final dayId = (today['status'] as Map?)?['today_day']?.toString();

    // The stress block, the night's window and the baselines. Each is its
    // own read and each may fail on its own; a miss costs its row only.
    final stress = today['stress'];
    num? onset, wake;
    Map<String, dynamic> baselines = const {};
    if (dayId != null) {
      try {
        final night = await repo.getDaySleepV2(dayId);
        onset = night['onset_ts'] as num?;
        wake = night['wake_ts'] as num?;
      } catch (_) {}
      try {
        final heart = await repo.getDayHeart(dayId);
        if (heart['baselines'] is Map) {
          baselines = (heart['baselines'] as Map).cast<String, dynamic>();
        }
      } catch (_) {}
    }

    // Same envelope Health reads. The watch runs on NOCTURNAL RESTING HEART
    // RATE ALONE — it has never been given a temperature series — so nothing
    // here may imply a second signal.
    final illness = today['illness'];

    return HomeData(
      name: profile['name']?.toString(),
      dayId: dayId,
      hrv: overnightMetric(today, d('hrv'), l),
      resp: overnightMetric(today, d('resp'), l),
      temp: overnightMetric(today, d('skin_temp'), l),
      stressScore:
          stress is Map ? (stress['score'] as num?)?.toDouble() : null,
      stressLevel: stress is Map ? stress['level']?.toString() : null,
      sleepOnsetTs: onset,
      sleepWakeTs: wake,
      baselines: baselines,
      heldOverNight: heldOver,
      illnessState: illness is Map ? illness['state']?.toString() : null,
      illnessDay: illness is Map ? illness['date']?.toString() : null,
      illnessZ: illness is Map ? (illness['z'] as num?)?.toDouble() : null,
      // The three that come off the OVERNIGHT block. Gated, so a night that
      // is not today's cannot arrive wearing today's clothes — see
      // [overnightMetric]. Steps, active energy and strain are today's own and
      // are read straight.
      readiness: overnightMetric(today, d('readiness'), l),
      drivers: [
        for (final e in (gbDrivers is List ? gbDrivers : const []))
          if (e is Map) e.cast<String, dynamic>(),
      ],
      strain: metricOf(d('strain')),
      sleepMin: overnightMetric(today, s('duration_min'), l),
      rhr: overnightMetric(today, d('resting_hr'), l),
      steps: metricOf(d('steps')),
      calories: metricOf(d('calories')),
      caloriesTotal: metricOf(d('calories_total')),
      stepGoal: (today['step_goal'] as num?)?.toInt() ?? kDefaultStepGoal,
      // sleep_coach.need is the COMPUTED need. `sleep.need_min` is a hardcoded
      // 480 and must never be shown as "your sleep need".
      sleepNeedMin: envMetric(needEnv, needSec == null ? null : needSec / 60,
          unit: 'min'),
      bedtime: envMetric(
          bedEnv, envValue(bedEnv)?['bedtime_min_of_day'] as num?),
      strainTarget: strain is Map && strain['strain_target'] is Map
          ? (strain['strain_target'] as Map).cast<String, dynamic>()
          : null,
      insightsStale: staleReasonOf(cd),
    );
  }
}

class HomeScreen extends StatefulWidget {
  /// Injected only by goldens; production always loads.
  final HomeData? data;

  /// Hour of day, injected only by goldens. The greeting reads the clock, so a
  /// golden baked in the evening fails the next morning on nothing but the
  /// word "evening" — a test that breaks by being run at a different time is
  /// noise that trains you to regenerate without looking.
  final int? hour;

  /// Whether a workout is live, injected only by tests/goldens — production
  /// reads it off AppState via [workoutLiveOf].
  final bool? workoutLive;

  /// The ⊕ on the "My Day" heading. Null in a golden.
  final VoidCallback? onAdd;

  const HomeScreen(
      {super.key, this.data, this.hour, this.workoutLive, this.onAdd});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with RevisionReload {
  HomeData? _d;
  bool _loading = true;

  /// The load THREW. Distinct from "there is nothing yet": a decode or a locked
  /// database is a read problem, and telling a user with three months of
  /// history that their band has never produced data is the wrong answer to it.
  bool _failed = false;

  /// Set the moment "Sync the band" is tapped, cleared once real progress has
  /// a signal of its own (`syncingNow`) or after [_tapGrace] with nothing —
  /// the bridge over the gap between the tap and the first record landing,
  /// where neither `busy` (skipped entirely on the common fast-reclaim path)
  /// nor `syncingNow` has moved yet and the button would otherwise look inert.
  bool _syncTapped = false;
  Timer? _syncTapTimer;
  static const _tapGrace = Duration(seconds: 20);

  void _tapSync(VoidCallback sync) {
    sync();
    setState(() => _syncTapped = true);
    _syncTapTimer?.cancel();
    _syncTapTimer = Timer(_tapGrace, () {
      if (mounted) setState(() => _syncTapped = false);
    });
  }

  @override
  void dispose() {
    _syncTapTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.data != null) {
      _d = widget.data;
      _loading = false;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// Handed its data (golden, gallery) — the screen just renders what it has.
  @override
  bool get revisionReloads => widget.data == null;

  /// Home used to load once post-frame and never listen, so the "Sync the
  /// band" button it renders could not change what the screen showed: the
  /// offload landed, the derive ran, and Home kept saying "Nothing derived
  /// yet" until the app was relaunched.
  @override
  void reload() => _load();

  Future<void> _load() async {
    final repo = repoOf(context);
    if (repo == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final t = beginRead(#home);
    try {
      final d = await HomeData.load(repo, AppLocalizations.of(context));
      if (stillNewest(#home, t)) {
        setState(() => (_d = d, _loading = false, _failed = false));
      }
    } catch (_) {
      if (stillNewest(#home, t)) setState(() => (_loading = false, _failed = true));
    }
  }

  /// The "nothing derived yet" card, upgraded with the one thing it used to
  /// withhold: whether anything is actually happening right now. Tapping Sync
  /// used to leave this card looking identical whether the band was mid-drain
  /// or the tap had silently gone nowhere — "I am not sure if it is actually
  /// syncing or not, no progress, no cue" was exactly that gap. `syncingNow` is
  /// the one signal that is honest across BOTH session paths (a fresh connect
  /// sets `busy`; the common fast-reclaim-from-background path never does), so
  /// it is what ends "connecting", not `busy`. `deriving`/`derivePending` catch
  /// the LAST mile — the backlog landed, `syncingNow` has gone quiet again, but
  /// this screen is still bare because the heavy derive it depends on hasn't
  /// finished. Without that phase the card would flash back to a bare "Nothing
  /// derived yet" for the minute or so a full sleep-stage + spectra pass takes.
  /// The syncing / analyzing / connecting phase card — valid whether or not
  /// [HomeData] itself has loaded yet, which is why it does not take one.
  /// Shared by the fully-bare first-run path (`d == null`) and the
  /// derived-but-empty bare-day path, so a first-run tap of "Sync the band"
  /// gets the same connecting/syncing feedback as every other one. Returns
  /// null when none of the three phases apply, so the caller falls through
  /// to its own "nothing yet" copy.
  Widget? _phaseStatusCard(BuildContext c, AppLocalizations? l) {
    final syncing = syncingNowOf(c);
    final deriving = derivingOf(c);
    // The tap latch is otherwise cleared only by its 20s grace timer — if
    // real progress lands before that timer fires, clear it here too so the
    // UI does not bounce back to "Connecting" once syncing/deriving goes
    // quiet again.
    if ((syncing || deriving) && _syncTapped) {
      _syncTapped = false;
      _syncTapTimer?.cancel();
    }
    final spinner = SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(strokeWidth: 2, color: P.of(c).ink3),
    );

    if (syncing) {
      return StatusCard(
        l?.homeSyncingTitle ?? 'Syncing with your band',
        l?.homeSyncingBody ?? 'Pulling data now — this can take a few minutes '
            'on a full backlog.',
        leading: spinner,
      );
    }
    if (deriving) {
      return StatusCard(
        l?.homeAnalyzingTitle ?? 'Crunching last night\'s numbers',
        l?.homeAnalyzingBody ?? 'The data is in — sleep, recovery and strain '
            'are next.',
        leading: spinner,
      );
    }
    if (_syncTapped) {
      return StatusCard(
        l?.homeConnectingTitle ?? 'Connecting to your band',
        l?.homeConnectingBody ?? 'Hang on — this usually takes a few seconds.',
        leading: spinner,
      );
    }
    return null;
  }

  Widget _bareStatusCard(BuildContext c, HomeData d, AppLocalizations? l) {
    final phase = _phaseStatusCard(c, l);
    if (phase != null) return phase;

    final sync = syncOf(c);
    return StatusCard(
      d.heldOverNight == null
          ? (l?.homeNothingDerivedTitle ?? 'Nothing derived yet')
          : (l?.homeNothingTodayTitle ?? 'Nothing recorded for today'),
      d.heldOverNight == null
          ? (l?.homeNothingDerivedBody ?? 'No band recordings processed yet.')
          : (l?.homeNothingTodayBody(prettyDay(d.heldOverNight, l)) ??
              'The last night this app scored was '
                  '${prettyDay(d.heldOverNight, l)}. Nothing has reached it since.'),
      fix: sync == null ? '' : (l?.homeSyncBand ?? 'Sync the band'),
      icon: LucideIcons.watch,
      onFix: sync == null ? null : () => _tapSync(sync),
    );
  }

  /// Morning / afternoon / evening / night. One split at 18:00 greeted 00:30
  /// and 15:40 alike with "Good morning" beside a sun.
  ({String word, IconData icon, Color color}) _greeting(int h, AppLocalizations? l) {
    if (h < 5) {
      return (word: l?.homeGreetingStillUp ?? 'Still up', icon: LucideIcons.moon, color: C.indigo);
    }
    if (h < 12) {
      return (word: l?.homeGreetingMorning ?? 'Good morning', icon: LucideIcons.sun, color: C.yellow);
    }
    if (h < 18) {
      return (word: l?.homeGreetingAfternoon ?? 'Good afternoon', icon: LucideIcons.sun, color: C.orange);
    }
    return (word: l?.homeGreetingEvening ?? 'Good evening', icon: LucideIcons.moon, color: C.indigo);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final d = _d;
    final g = _greeting(widget.hour ?? DateTime.now().hour, l);

    if (d == null) {
      return _refreshable(ListView(padding: pad, children: [
        const SizedBox(height: S.x8),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (_failed)
          StatusCard(
            l?.homeLoadFailedTitle ?? 'Today could not be read',
            l?.homeLoadFailedBody ??
                'The stored day failed to load. Nothing was deleted — this is a '
                'read that went wrong, not missing data.',
            fix: l?.homeTryAgain ?? 'Try again',
            icon: LucideIcons.databaseZap,
            onFix: () {
              setState(() => (_loading = true, _failed = false));
              _load();
            },
          )
        else
          Builder(builder: (c) {
            final phase = _phaseStatusCard(c, l);
            if (phase != null) return phase;
            final sync = syncOf(c);
            return StatusCard(
              l?.homeNothingDerivedTitle ?? 'Nothing derived yet',
              l?.homeNothingDerivedBody ?? 'No band recordings processed yet.',
              fix: sync == null ? '' : (l?.homeSyncBand ?? 'Sync the band'),
              icon: LucideIcons.watch,
              onFix: sync == null ? null : () => _tapSync(sync),
            );
          }),
      ]));
    }

    // Nothing measured at all: a first run, or a day of no wear. The copy
    // splits them on whether this install has ever scored a night.
    final bare = d.readiness.isEmpty &&
        d.sleepMin.isEmpty &&
        d.strain.isEmpty &&
        d.rhr.isEmpty &&
        d.steps.value == null &&
        d.calories.isEmpty;

    final stale = staleInsightsCard(d.insightsStale, syncOf(c), l);
    // Above everything else: if the app had to rebuild the database to
    // start, that outranks anything else this screen has to say today.
    final rebuilt = dbRebuiltCard(dbRebuildOf(c), l);

    return _refreshable(ListView(padding: pad, children: [
      if (rebuilt != null) ...[const SizedBox(height: S.x3), rebuilt],

      // ── the one observation Home is allowed to make ──
      ...?_bodyWatch(c, d),

      // ── header: avatar · ‹ TODAY › · band ──
      _header(c, p, d, g, l),

      // ── the wordmark ──
      Padding(
        padding: const EdgeInsets.only(top: S.x2, bottom: S.x6),
        child: Center(
          child: Text('REBOUND',
              style: F.caps.copyWith(color: p.ink3, letterSpacing: 4)),
        ),
      ),
      if (bare) ...[
        // The dials are the page even on a day with nothing in them — the
        // reference app never takes them away. Quiet: the one card under
        // them says why.
        RingTrio(d: d, quiet: true),
        const SizedBox(height: S.x8),
        // A live workout holds derivation, so a bare day with a session open
        // is the hold at work, not a sync problem — see [workoutHoldCard].
        (widget.workoutLive ?? workoutLiveOf(c))
            ? workoutHoldCard(l)
            : _bareStatusCard(c, d, l),
      ] else ...[
        // ── the three rings ──
        //
        // Recovery, strain and sleep, each a door into its own screen. They
        // render as long as ONE of them has something to draw — a trio of
        // empty circles says less than the one written absence below, and the
        // empty state is a DOOR, not a dead end.
        if (RingTrio.has(d))
          RingTrio(
            d: d,
            onOpen: (k) => go(
                c,
                switch (k) {
                  HomeRingKind.recovery => const ReadinessDetail(),
                  HomeRingKind.strain => const DayStrainDetail(),
                  HomeRingKind.sleep => const SleepDetail(),
                }),
          )
        else
          Builder(builder: (c) {
            final need = needMessageFromNote(d.readiness.note);
            return StatusCard(
              l?.homeReadinessNotScoredTitle ?? 'Readiness is not scored today',
              need != null
                  ? (l?.homeReadinessNeedBody(need) ??
                      '$need to know what normal looks like for you.')
                  : whyFromNote(d.readiness.note) ??
                      (l?.homeReadinessNoReason ?? 'Nothing recorded says why.'),
              fix: l?.homeSeeWhatWasMissing ?? 'See what was missing',
              icon: LucideIcons.batteryCharging,
              onFix: () => go(c, const ReadinessDetail()),
            );
          }),

        // ── the rollup was withheld, not absent ──
        if (stale != null) ...[const SizedBox(height: S.x3), stale],

        // ── the two monitors ──
        const SizedBox(height: S.x10),
        _monitors(c, p, d),

        // ── my day ──
        HeadingRow(l?.homeTodaysPlan ?? 'My Day',
            trailing: PlusDisc(onTap: widget.onAdd)),
        if (coachReady(c)) ...[
          _outlookRow(c, p, d),
          const SizedBox(height: S.x3),
        ],
        _activities(c, p, d),
        if (d.bedtime.value != null || d.sleepNeedMin.value != null) ...[
          const SizedBox(height: S.x3),
          _tonight(c, p, d),
        ],

        // ── my dashboard ──
        const HeadingRow('My Dashboard'),
        ..._dashboard(c, p, d),

        // ── the way into the whole day ──
        const SizedBox(height: S.x3),
        detailLinkRow(c, LucideIcons.chartGantt,
            l?.homeBreakdownTitle ?? 'Breakdown of your day',
            l?.homeBreakdownSubtitle ?? 'Hour by hour',
            () => go(c, const DayTimelineScreen())),
        const SizedBox(height: S.x6),
      ],
    ]));
  }

  // ── header ───────────────────────────────────────────────────────────────
  Widget _header(BuildContext c, P p, HomeData d,
      ({String word, IconData icon, Color color}) g, AppLocalizations? l) {
    final battery = _batteryOf(c);
    return Padding(
      padding: const EdgeInsets.only(top: S.x2, bottom: S.x4),
      child: Row(children: [
        Pressable(
          semanticLabel: l?.homeProfileSettings ?? 'Profile and settings',
          onTap: () => go(c, const ProfileHome()),
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [p.edgeA, p.edgeB]),
            ),
            child: d.name == null || d.name!.isEmpty
                ? Icon(LucideIcons.user, size: 18, color: p.ink)
                : Text(d.name!.substring(0, 1).toUpperCase(),
                    style: F.head.copyWith(
                        color: p.ink, fontWeight: FontWeight.w700)),
          ),
        ),
        Expanded(
          child: Center(
            child: Semantics(
              label: '${g.word}. ${prettyDay(d.dayId, l)}',
              child: ExcludeSemantics(
                child: DayPill(
                  (d.dayId == null || d.dayId == todayLabel())
                      ? (l?.dayStrainToday ?? 'Today')
                      : _shortDay(d.dayId!, l),
                ),
              ),
            ),
          ),
        ),
        // The band: its charge and one tap to sync it. The reference app
        // puts exactly this in the corner.
        Builder(builder: (c) {
          final sync = syncOf(c);
          final busy = syncingNowOf(c) || derivingOf(c);
          return Pressable(
            semanticLabel: l?.homeSyncBand ?? 'Sync the band',
            onTap: sync == null ? null : () => _tapSync(sync),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (battery != null)
                Text('${battery.round()}%',
                    style: F.cap.copyWith(
                        color: p.ink, fontWeight: FontWeight.w600)),
              const SizedBox(width: S.x2),
              busy
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: p.ink))
                  : Icon(LucideIcons.watch, size: 22, color: p.ink),
            ]),
          );
        }),
      ]),
    );
  }

  /// "Wed 20 May" — what fits the pill.
  static String _shortDay(String dayId, AppLocalizations? l) {
    final t = DateTime.tryParse(dayId);
    if (t == null) return dayId;
    return '${weekdayShortName(t.weekday, l)} ${t.day} ${monthShortName(t.month, l)}';
  }

  static double? _batteryOf(BuildContext c) {
    try {
      return c.select<AppState, double?>((a) => a.device.batteryPct);
    } catch (_) {
      return null;
    }
  }

  // ── the two monitors ──────────────────────────────────────────────────────
  Widget _monitors(BuildContext c, P p, HomeData d) {
    final l = AppLocalizations.of(c);
    // Within range: an input whose delta sits inside its own spread. Counted
    // over the inputs the baselines block actually carries.
    var have = 0, inRange = 0;
    for (final k in const ['hrv', 'resting_hr', 'resp', 'skin_temp']) {
      final b = d.baselines[k];
      if (b is! Map) continue;
      final delta = (b['delta'] as num?)?.toDouble();
      final spread = (b['spread'] as num?)?.toDouble();
      if (delta == null || spread == null) continue;
      have++;
      if (delta.abs() <= spread) inRange++;
    }
    final allIn = have > 0 && inRange == have;
    final stress = d.stressScore;
    Widget reading(Widget badge, Color col, String top, String sub) =>
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          badge,
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(top.toUpperCase(),
                      style: F.over.copyWith(color: p.on(col)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(sub,
                      style: F.cap.copyWith(color: p.ink2),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ]),
          ),
        ]);
    Widget square(Widget child, Color col) => Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration:
              BoxDecoration(color: p.wash(col), borderRadius: R.rSm),
          child: child,
        );
    final tiles = <Widget>[
      TileCard(
        'Health monitor',
        onTap: () => go(c, const MetricDetail('resting_hr')),
        child: have == 0
            ? reading(
                square(Icon(LucideIcons.minus, size: 16, color: p.ink3),
                    C.n400),
                C.n400,
                'No baseline',
                'Needs nights')
            : reading(
                square(
                    Icon(allIn ? LucideIcons.check : LucideIcons.triangleAlert,
                        size: 16,
                        color: p.on(allIn ? C.teal : C.yellow)),
                    allIn ? C.teal : C.yellow),
                allIn ? C.teal : C.yellow,
                allIn ? 'Within range' : 'Outside range',
                '$inRange/$have Metrics'),
      ),
      TileCard(
        'Stress monitor',
        onTap: () => go(c, const MetricDetail('stress')),
        child: stress == null
            ? reading(
                square(Icon(LucideIcons.minus, size: 16, color: p.ink3),
                    C.n400),
                C.n400,
                'No reading',
                'Needs a night')
            : reading(
                square(
                    Text(stress.round().toString(),
                        style: F.n17.copyWith(color: p.on(C.teal))),
                    C.teal),
                C.teal,
                d.stressLevel ?? 'Stress',
                l?.homeRestingSub ?? 'Overnight'),
      ),
    ];
    if (bigText(c)) {
      return Column(children: [
        tiles[0],
        const SizedBox(height: S.x3),
        tiles[1],
      ]);
    }
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: tiles[0]),
        const SizedBox(width: S.x3),
        Expanded(child: tiles[1]),
      ]),
    );
  }

  // ── my day ────────────────────────────────────────────────────────────────
  Widget _outlookRow(BuildContext c, P p, HomeData d) {
    final who = d.name == null || d.name!.isEmpty ? 'Your' : "${d.name}'s";
    return Pressable(
      onTap: () =>
          go(c, const AiBriefingScreen(period: BriefingPeriod.morning)),
      semanticLabel: '$who daily outlook',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x4),
        decoration: BoxDecoration(color: p.card, borderRadius: R.rLg),
        child: Row(children: [
          Icon(LucideIcons.sun, size: 22, color: p.ink2),
          const SizedBox(width: S.x3),
          Expanded(
            child: Text('$who Daily Outlook',
                style: F.head.copyWith(color: p.ink),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          Icon(LucideIcons.chevronRight, size: 20, color: p.ink3),
        ]),
      ),
    );
  }

  /// "TODAY'S ACTIVITIES": last night as a lozenge, then the two ways to add
  /// to the day.
  Widget _activities(BuildContext c, P p, HomeData d) {
    final l = AppLocalizations.of(c);
    final tst = d.sleepMin.value;
    return Container(
      padding: const EdgeInsets.all(S.x4),
      decoration: BoxDecoration(color: p.card, borderRadius: R.rLg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text("TODAY'S ACTIVITIES",
                style: F.over.copyWith(color: p.ink)),
          ),
          Pressable(
            onTap: () => go(c, const DayTimelineScreen()),
            semanticLabel: l?.homeBreakdownTitle ?? 'Breakdown of your day',
            child: Icon(LucideIcons.expand, size: 18, color: p.ink2),
          ),
        ]),
        const SizedBox(height: S.x3),
        if (tst != null)
          Pressable(
            onTap: () => go(c, const SleepDetail()),
            semanticLabel: 'Sleep, ${hm(tst)}',
            child: Container(
              padding: const EdgeInsets.all(S.x2),
              decoration:
                  BoxDecoration(color: p.card2, borderRadius: R.rMd),
              child: Row(children: [
                Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: S.x4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: C.sleep.withValues(alpha: .55),
                      borderRadius: R.rSm),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(LucideIcons.moon, size: 18, color: p.ink),
                    const SizedBox(width: S.x2),
                    Text(hmClock(tst),
                        style: F.n24.copyWith(color: p.ink)),
                  ]),
                ),
                const SizedBox(width: S.x4),
                Expanded(
                  child: Text('SLEEP', style: F.over.copyWith(color: p.ink)),
                ),
                if (d.sleepOnsetTs != null && d.sleepWakeTs != null)
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(clockOfTs(d.sleepOnsetTs),
                            style: F.cap.copyWith(color: p.ink3)),
                        Text(clockOfTs(d.sleepWakeTs),
                            style: F.cap.copyWith(color: p.ink3)),
                      ]),
                const SizedBox(width: S.x2),
                Container(width: 2, height: 28, color: p.on(C.sleep)),
              ]),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: S.x2),
            child: Text(l?.homeRingNoSleep ?? 'No sleep recorded yet',
                style: F.cap.copyWith(color: p.ink3)),
          ),
        const SizedBox(height: S.x3),
        Row(children: [
          Expanded(
            child: PillButton('Add activity',
                icon: LucideIcons.plus, onTap: widget.onAdd),
          ),
          const SizedBox(width: S.x3),
          Expanded(
            child: PillButton('Start activity',
                icon: LucideIcons.timer, onTap: widget.onAdd),
          ),
        ]),
      ]),
    );
  }

  /// "TONIGHT'S SLEEP": the bedtime the coach recommends and the need it
  /// computed. Two figures, caps under each, as on the phone.
  Widget _tonight(BuildContext c, P p, HomeData d) {
    final l = AppLocalizations.of(c);
    Widget figure(IconData i, String value, String caption) => Expanded(
          child: Column(children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(i, size: 18, color: p.ink2),
                const SizedBox(width: S.x2),
                Text(value, style: F.n24.copyWith(color: p.ink)),
              ]),
            ),
            const SizedBox(height: S.x1),
            Text(caption.toUpperCase(),
                textAlign: TextAlign.center,
                style: F.over.copyWith(color: p.ink3)),
          ]),
        );
    return Pressable(
      onTap: () => go(c, const SleepDetail()),
      semanticLabel: "Tonight's sleep",
      child: Container(
        padding: const EdgeInsets.all(S.x4),
        decoration: BoxDecoration(color: p.card, borderRadius: R.rLg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text("TONIGHT'S SLEEP",
                  style: F.over.copyWith(color: p.ink)),
            ),
            Icon(LucideIcons.chevronRight, size: 18, color: p.ink3),
          ]),
          const SizedBox(height: S.x5),
          Row(children: [
            if (d.bedtime.value != null)
              figure(LucideIcons.bedDouble, clock(d.bedtime.value),
                  'Recommended bedtime'),
            if (d.sleepNeedMin.value != null)
              figure(LucideIcons.moon, hmClock(d.sleepNeedMin.value),
                  l?.homeNeed ?? 'Sleep need'),
          ]),
        ]),
      ),
    );
  }

  // ── my dashboard ──────────────────────────────────────────────────────────
  List<Widget> _dashboard(BuildContext c, P p, HomeData d) {
    final l = AppLocalizations.of(c);
    MetricLine? line(IconData icon, String label, Metric m, String key,
        String unit, String chart, {bool higherBetter = true, bool judge = true}) {
      if (m.isEmpty) return null;
      final b = d.baselines[key];
      final usual = b is Map ? (b['baseline'] as num?) : null;
      final delta = b is Map ? (b['delta'] as num?)?.toDouble() : null;
      final spread = b is Map ? (b['spread'] as num?)?.toDouble() : null;
      final past = delta != null && spread != null && delta.abs() > spread;
      return MetricLine(
        icon,
        label,
        metricValue(unit, m.value),
        baseline: usual == null ? '' : metricValue(unit, usual),
        move: delta == null
            ? null
            : delta > 0
                ? Move.up
                : delta < 0
                    ? Move.down
                    : Move.flat,
        good: !judge || delta == null || !past
            ? null
            : (delta > 0) == higherBetter,
        onTap: () => go(c, MetricDetail(chart)),
      );
    }

    final lines = <MetricLine?>[
      line(LucideIcons.activity, 'Heart rate variability', d.hrv, 'hrv', 'ms',
          'hrv'),
      line(LucideIcons.heartPulse, l?.homeRestingSub ?? 'Resting heart rate',
          d.rhr, 'resting_hr', 'bpm', 'resting_hr',
          higherBetter: false),
      line(LucideIcons.wind, 'Respiratory rate', d.resp, 'resp', 'br/min',
          'resp_rate',
          judge: false),
      line(LucideIcons.thermometer, 'Skin temperature', d.temp, 'skin_temp',
          '°', 'skin_temp',
          judge: false),
      d.steps.value == null
          ? null
          : MetricLine(LucideIcons.footprints, l?.homeSteps ?? 'Steps',
              thousands(d.steps.value),
              baseline: d.stepGoal > 0 ? thousands(d.stepGoal) : '',
              onTap: () => go(c, const MetricDetail('steps'))),
      line(LucideIcons.flame, l?.homeActiveEnergy ?? 'Calories', d.calories,
          'calories', 'kcal', 'calories',
          judge: false),
    ].whereType<MetricLine>().toList();
    if (lines.isEmpty) {
      return [
        StatusCard(
          'No readings yet',
          'The dashboard fills in from the first scored night.',
          icon: LucideIcons.layoutDashboard,
        ),
      ];
    }
    return [
      for (var i = 0; i < lines.length; i++) ...[
        if (i > 0) const SizedBox(height: S.x3),
        MetricListCard([lines[i]], notch: false),
      ],
    ];
  }

  /// The illness watch, on Home, at amber as well as red.
  ///
  /// Returns null on every ordinary day — green, or no state at all because the
  /// CUSUM has not got its 7 nights yet. Absence here is silence, not a card
  /// explaining that nothing is wrong: "you are not getting sick" is not an
  /// observation worth a slot, and a watch that renders daily stops being read.
  ///
  /// The tap goes to the resting-heart-rate chart rather than Health's copy of
  /// this card, because the chart is the EVIDENCE — the watch reads that one
  /// series, so the honest answer to "why are you telling me this" is to show
  /// it. Health keeps its own fuller card; this is not a duplicate route to the
  /// same words, it is a shorter road to the number underneath them.
  static List<Widget>? _bodyWatch(BuildContext c, HomeData d) {
    final state = d.illnessState;
    if (state == null || state == 'green') return null;
    final l = AppLocalizations.of(c);

    final sameNight = d.illnessDay == null || d.illnessDay == d.dayId;
    final z = d.illnessZ;
    final zAbs = z == null ? '' : z.abs().toStringAsFixed(1);

    return [
      Observation(
        state == 'red'
            ? (l?.homeIllnessRedTitle ?? 'Several nights in a row are away from your normal')
            : sameNight
                ? (l?.homeIllnessAmberSameNight ?? 'Last night sat outside your normal range')
                : (l?.homeIllnessAmberOtherNight(prettyDay(d.illnessDay, l)) ??
                    '${prettyDay(d.illnessDay, l)} sat outside your normal range'),
        z == null
            ? (l?.homeIllnessBodyNoZ ??
                'Your nocturnal resting heart rate has been running above your own '
                'baseline. This reads one signal. It names a pattern, and it does '
                'not name a cause.')
            : (z >= 0
                ? (l?.homeIllnessBodyAbove(zAbs) ??
                    'Your nocturnal resting heart rate has been running above your own '
                    'baseline; that night sat $zAbs standardised deviations above it. '
                    'This reads one signal. It names a pattern, and it does not name '
                    'a cause.')
                : (l?.homeIllnessBodyBelow(zAbs) ??
                    'Your nocturnal resting heart rate has been running above your own '
                    'baseline; that night sat $zAbs standardised deviations below it. '
                    'This reads one signal. It names a pattern, and it does not name '
                    'a cause.')),
        advice: l?.homeIllnessAdvice ?? 'Worth noting if it continues past a couple of days.',
        onTap: () => go(c, const MetricDetail('resting_hr')),
      ),
      const SizedBox(height: S.x3),
    ];
  }

  /// Pull to reload. The screen also reloads itself on `insightsRevision`, but
  /// a derive that fails silently, an import, or anything that lands without
  /// bumping it still leaves the user a way to ask.
  Widget _refreshable(Widget list) =>
      RefreshIndicator(onRefresh: _load, child: list);
}
