// READINESS — the one composite, taken apart.
//
// Two producers meet on this screen and the copy says so rather than blending
// them: the headline number is the weighted composite, and the breakdown is a
// parallel percentile view of the same four inputs. Presenting the second as
// if it decomposed the first would be a small lie that is very hard to catch.

import 'dart:convert' show jsonDecode;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/db.dart';
import '../../data/local_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../models/metric.dart';
import '../ui2.dart';
import '../../data/day_label.dart' show todayLabel;
import 'driver_breakdown.dart';
import 'home_screen.dart';
import 'investigate.dart';
import 'metric_detail.dart';

class ReadinessData {
  final Metric readiness;
  final List<Map<String, dynamic>> breakdown;
  final int inputsUsed;

  /// `readiness_absent_diag` off the stored bundle — per input `{value,
  /// baseline_n}` plus the composite's own `note`. Produced on
  /// EVERY day readiness comes back absent, and until now its only destination
  /// was a Firebase breadcrumb: the app told its developer why the number was
  /// missing and never told the person looking at the gap.
  ///
  /// Null when readiness scored, which is the same fact as the number existing.
  final Map<String, dynamic>? absentDiag;

  /// The last night that scored, when that is NOT today's.
  ///
  /// It is no longer the source of the number above — [overnightMetric]
  /// refuses an older night, so the headline is today's or it is absent, and
  /// the screen no longer wears a date in its nav bar claiming otherwise. What
  /// is left is coverage: naming the night the data stops at, inside the
  /// absence.
  final String? heldOverNight;

  /// DENSE — one slot per calendar day, `null` where no score was stored. The
  /// chart under it is dated, and `seriesOf` (values only) cannot date
  /// anything: a five-point series from five scattered weeks used to be drawn
  /// as five consecutive days.
  final List<double?> series;

  /// Each input's reading against this user's own usual — the rows under the
  /// ring. Assembled by [driverFacts] from the same breakdown; nothing here
  /// computes.
  final List<DriverFacts> facts;

  const ReadinessData({
    this.readiness = Metric.empty,
    this.breakdown = const [],
    this.inputsUsed = 0,
    this.heldOverNight,
    this.series = const [],
    this.absentDiag,
    this.facts = const [],
  });

  /// The absence diagnostic off a stored day bundle. Read straight from
  /// `day_result` the way `InvestigateData.load` reads `imported` — no
  /// repository accessor exists and this is the only screen that wants it.
  static Future<Map<String, dynamic>?> _absentDiag(String? day) async {
    if (day == null) return null;
    final payload = (await LocalDb.dayResult(day))?['payload_json'];
    if (payload is! String || !payload.contains('"readiness_absent_diag"')) {
      return null;
    }
    final b = jsonDecode(payload);
    final diag = b is Map ? b['readiness_absent_diag'] : null;
    return diag is Map ? diag.cast<String, dynamic>() : null;
  }

  static Future<ReadinessData> load(LocalRepository repo) async {
    final today = await repo.getToday();
    final cd = await repo.getInsights();
    final chart = await repo.getChart('recovery');

    final daily = today['daily'];
    final gb = cd['readiness_glassbox'];
    final v = envValue(gb) ?? const <String, dynamic>{};
    final bd = v['breakdown'];

    final readiness = overnightMetric(today, daily is Map ? daily['readiness'] : null);
    final breakdown = [
      for (final e in (bd is List ? bd : const []))
        if (e is Map) e.cast<String, dynamic>(),
    ];
    // The baselines block, for the reading beside each input. A read that
    // fails costs the rows their comparison and nothing else.
    Map<String, dynamic>? baselines;
    try {
      final heart = await repo.getDayHeart(todayLabel());
      baselines = heart['baselines'] is Map
          ? (heart['baselines'] as Map).cast<String, dynamic>()
          : null;
    } catch (_) {
      baselines = null;
    }

    return ReadinessData(
      readiness: readiness,
      breakdown: breakdown,
      facts: driverFacts(breakdown: breakdown, baselines: baselines),
      inputsUsed: (v['inputs_used'] as num?)?.toInt() ?? 0,
      heldOverNight: heldOverNightOf(today),
      series: denseDays(pointsOf(chart), 90),
      // Only read when there is nothing to explain away — a scored day has no
      // diag in its bundle anyway, and this is one more day_result decode.
      //
      // TODAY'S DAY, never the held-over one. The held-over night usually
      // scored fine, so its diagnostic explains an absence that is not the one
      // on screen: it would list four measured inputs under a card saying the
      // number is missing. A day with no bundle has no diag and this comes back
      // null, which is correct — the note on the metric is the reason then.
      absentDiag: readiness.value != null
          ? null
          : await _absentDiag(
              (today['status'] as Map?)?['today_day']?.toString()),
    );
  }
}

class ReadinessDetail extends StatefulWidget {
  final ReadinessData? data;
  const ReadinessDetail({super.key, this.data});

  @override
  State<ReadinessDetail> createState() => _ReadinessDetailState();
}

class _ReadinessDetailState extends State<ReadinessDetail> {
  ReadinessData? _d;
  bool _loading = true;

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

  Future<void> _load() async {
    final repo = repoOf(context);
    if (repo == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final d = await ReadinessData.load(repo);
      if (mounted) setState(() => (_d = d, _loading = false));
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final d = _d ?? const ReadinessData();
    final v = d.readiness.value;
    final band = readinessBand(v, l);

    // No date in the nav bar. It named the held-over night, and the headline
    // can no longer BE that night — a date up here now would be labelling
    // today's number with somebody else's day.
    return detailScaffold(c, l?.readinessDetailTitle ?? 'Readiness', [
      if (_loading && _d == null) ...[
        const SizedBox(height: S.x8),
        const Center(child: CircularProgressIndicator()),
      ] else ...[
        if (v == null) ...[
          // No `why:`. The pipeline records why readiness abstained on every
          // day it does, and the "What was missing" section directly below is
          // built from that record — a sentence written here was competing
          // with the real answer one line down and winning.
          StatusCard.forMetric(
                  l?.readinessDetailNotScoredTitle ??
                      'Readiness is not scored',
                  d.readiness,
                  // Where the data stops, appended to whatever the pipeline
                  // said. Not a substitute for the reason and not a reading —
                  // "the last one was Saturday" is a fact about coverage.
                  gap: d.heldOverNight == null
                      ? null
                      : (l?.readinessDetailLastNightScored(
                              prettyDay(d.heldOverNight, l)) ??
                          'The last night scored was '
                              '${prettyDay(d.heldOverNight, l)}.')) ??
              const SizedBox.shrink(),
          if (d.absentDiag != null)
            Section(l?.readinessDetailWhatWasMissing ?? 'What was missing',
                _absence(c, p, d.absentDiag!)),
        ] else
          // THE HERO IS ON THE PAGE, not in a card: the ring, the number in
          // white, the label inside — then the readings card pointing up at
          // it, and one sentence.
          Padding(
            padding: const EdgeInsets.only(top: S.x4, bottom: S.x2),
            child: Center(
              child: ScoreRing(
                value: '${v.round()}',
                unit: '%',
                label: l?.readinessDetailTitle ?? 'Recovery',
                sub: band.label,
                frac: d.readiness.normalized(100),
                color: p.on(band.color),
              ),
            ),
          ),
          if (d.facts.isNotEmpty) ...[
            // The reading beside each input when the baselines block gave
            // one; otherwise the signed contribution the score itself
            // carried, so the card is never empty on a scored day.
            MetricListCard([
              for (final f in d.facts)
                MetricLine(
                  f.spec.icon,
                  f.spec.title,
                  f.value != null
                      ? metricValue(f.spec.unit, f.value)
                      : f.contribution != null
                          ? '${f.contribution! >= 0 ? '+' : ''}'
                              '${f.contribution!.toStringAsFixed(1)}'
                          : (l?.readinessDetailNotAvailable ?? 'not available'),
                  baseline: f.usual == null
                      ? ''
                      : metricValue(f.spec.unit, f.usual),
                  move: (f.delta ?? f.contribution) == null
                      ? null
                      : (f.delta ?? f.contribution)! > 0
                          ? Move.up
                          : (f.delta ?? f.contribution)! < 0
                              ? Move.down
                              : Move.flat,
                  // Judged only past the smallest change worth calling one;
                  // inside the usual spread the arrow stays grey. A bare
                  // contribution is already signed good/bad by the score.
                  good: f.delta != null
                      ? (!f.beyondUsualSpread
                          ? null
                          : (f.delta! > 0) == f.spec.higherBetter)
                      : f.contribution == null
                          ? null
                          : f.contribution! >= 0,
                  onTap: () => go(c, MetricDetail(f.spec.chartKey)),
                ),
            ], legend: 'Today vs. your usual'),
            const SizedBox(height: S.x3),
            InsightBox(_sentence(d, band.label)),
          ],
          if (d.series.any((v) => v != null)) ...[
            const HeadingRow('Weekly Trends'),
            _weekCard(c, p, d),
          ],

        // The old weight-and-contribution card is one tap down, on the
        // Investigate screen; the readings card above is what this screen
        // says about the inputs now.
        if (d.breakdown.isEmpty && v != null)
          Section(
            l?.readinessDetailWhatWentIntoIt ?? 'What went into it',
            StatusCard(
              l?.readinessDetailNoBreakdownTitle ?? 'No breakdown yet',
              l?.readinessDetailNoBreakdownBody ??
                  'Ranking each input against your own history takes about two '
                      'weeks of nights.',
              icon: LucideIcons.listTree,
            ),
          ),

        // The header used to say "Last 90 days" over a chart of five points.
        // It says what is drawn.
        Section(
          _historyTitle(c, d),
          !d.series.any((v) => v != null)
              ? StatusCard(
                  l?.readinessDetailNoHistoryTitle ?? 'No readiness history',
                  l?.readinessDetailNoHistoryBody ?? '0 days scored.',
                  fix: l?.readinessDetailWearOvernight ?? 'Wear the band overnight',
                  icon: LucideIcons.chartLine,
                )
              : Surface(child: _history(c, d)),
        ),
        const SizedBox(height: S.x5),
        investigateRow(c, () => go(c, const Investigate('readiness'))),
      ],
    ]);
  }

  /// The last seven days as bars in their own band colour, today on a lit
  /// column — the reference app's "RECOVERY" weekly card.
  Widget _weekCard(BuildContext c, P p, ReadinessData d) {
    final l = AppLocalizations.of(c);
    final n = d.series.length;
    final week = [for (var i = n - 7; i < n; i++) i < 0 ? null : d.series[i]];
    final today = DateTime.now();
    return Container(
      padding: const EdgeInsets.all(S.x4),
      decoration: BoxDecoration(color: p.card, borderRadius: R.rLg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text((l?.readinessDetailTitle ?? 'Recovery').toUpperCase(),
                style: F.over.copyWith(color: p.ink)),
          ),
          Icon(LucideIcons.chevronRight, size: 18, color: p.ink3),
        ]),
        const SizedBox(height: S.x4),
        SizedBox(
          height: bigText(c) ? 300 : 200,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < 7; i++) ...[
              if (i > 0) const SizedBox(width: S.x2),
              Expanded(
                child: _WeekColumn(
                  value: week[i],
                  day: DateTime(today.year, today.month, today.day - (6 - i)),
                  today: i == 6,
                  l: l,
                ),
              ),
            ],
          ]),
        ),
      ]),
    );
  }

  /// One sentence, from the inputs that actually moved: which ones sat
  /// outside their usual, which way, and the band that came out of it.
  String _sentence(ReadinessData d, String band) {
    final up = <String>[], down = <String>[], flat = <String>[];
    for (final f in d.facts) {
      if (!f.used || f.delta == null) continue;
      final name = f.spec.title;
      if (!f.beyondUsualSpread) {
        flat.add(name);
      } else if (f.delta! > 0) {
        up.add(name);
      } else {
        down.add(name);
      }
    }
    String list(List<String> a) => a.length == 1
        ? a[0]
        : '${a.sublist(0, a.length - 1).join(', ')} and ${a.last}';
    final parts = <String>[
      if (up.isNotEmpty) '${list(up)} ${up.length == 1 ? 'is' : 'are'} above your usual',
      if (down.isNotEmpty) '${list(down)} ${down.length == 1 ? 'is' : 'are'} below your usual',
    ];
    if (parts.isEmpty && flat.isNotEmpty) {
      return 'Every input sat inside its usual range, which lands recovery at '
          '"${band.toLowerCase()}" today.';
    }
    final typical = flat.isEmpty ? '' : ', while ${list(flat)} ${flat.length == 1 ? 'is' : 'are'} typical';
    return '${parts.join(' and ')}$typical, which lands recovery at '
        '"${band.toLowerCase()}" today.';
  }

  /// The last 90 CALENDAR days, trimmed to start at the first day that
  /// actually has a score — so the x labels span real dates and the empty run
  /// before the first sync is not drawn as ninety missing days.
  List<double?> _window(ReadinessData d) {
    final first = d.series.indexWhere((v) => v != null);
    return first <= 0 ? d.series : d.series.sublist(first);
  }

  String _historyTitle(BuildContext c, ReadinessData d) {
    final l = AppLocalizations.of(c);
    final n = d.series.any((v) => v != null) ? _window(d).length : 0;
    return n == 0
        ? (l?.readinessDetailHistoryTitle ?? 'History')
        : (l?.readinessDetailLastNDays(n) ??
            'Last $n day${n == 1 ? '' : 's'}');
  }

  Widget _history(BuildContext c, ReadinessData d) {
    final win = _window(d);
    // Readiness is a 0–100 score and the axis says so — auto-scaling turned a
    // 71-to-76 week into a chart that looked like a collapse and a recovery.
    const axis = AxisSpec(min: 0, max: 100, ticks: 3, format: axisInt);
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    return ChartFrame(
      title: l?.readinessDetailTitle ?? 'Readiness',
      unit: l?.readinessDetailUnit ?? '/100',
      height: 120,
      yAxis: axis,
      // Slot 0 is `length - 1` days behind today, not `length` — the last slot
      // IS today. MetricDetail draws the same `recovery` series and already
      // counts it this way; the two screens dated one chart differently.
      xLabels: [
        l?.readinessDetailDaysAgo(win.length - 1) ??
            '${win.length - 1} day${win.length == 2 ? '' : 's'} ago',
        l?.readinessDetailToday ?? 'Today',
      ],
      series: win,
      child: CustomPaint(
        size: Size.infinite,
        painter: LineChart(win, p.on(C.green), dots: false, t: animate(c, 1),
            axis: axis),
      ),
    );
  }

  /// The pipeline's own absence diagnostic, one row per input. Two facts per
  /// row and neither is inferred here: did last night produce this input, and
  /// how many of your own nights are behind it. The line underneath QUOTES the
  /// composite's note rather than guessing a reason from the rows above it —
  /// and it never turns a night count into a date, because nothing in the
  /// pipeline knows when you will next wear the band.
  Widget _absence(BuildContext c, P p, Map<String, dynamic> diag) {
    final l = AppLocalizations.of(c);
    final rows = <(String, String)>[];
    for (final k in const ['hrv', 'rhr', 'resp', 'temp']) {
      final e = diag[k];
      if (e is! Map) continue;
      final n = (e['baseline_n'] as num?)?.toInt() ?? 0;
      rows.add((
        driverLabel(k, l),
        '${e['value'] == true ? (l?.readinessDetailMeasured ?? 'Measured') : (l?.readinessDetailNotMeasured ?? 'Not measured')} · '
            '${l?.readinessDetailNightsOfHistory(n) ?? '$n night${n == 1 ? '' : 's'} of your own history'}',
      ));
    }
    final note = diag['note']?.toString();
    final need = needMessageFromNote(note);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (rows.isNotEmpty)
        Surface(
          pad: const EdgeInsets.symmetric(horizontal: S.x4),
          child: Column(children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(color: p.line, height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: S.x3),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(rows[i].$1, style: F.body.copyWith(color: p.ink)),
                      Text(rows[i].$2,
                          style: F.over.copyWith(color: p.ink3)),
                    ]),
              ),
            ],
          ]),
        ),
      const SizedBox(height: S.x3),
      Text(
        need != null
            ? (l?.readinessDetailNeedSuffix(need) ??
                '$need. Each input is ranked against your own nights, so the '
                    'score cannot start before there are enough of them.')
            : (note != null && note.isNotEmpty
                ? note
                : (l?.readinessDetailNoNoteFallback ??
                    'Everything above was present, and the comparison against '
                        'your own history still could not be made.')),
        style: F.cap.copyWith(color: p.ink3, height: 1.5),
      ),
    ]);
  }

}

/// One day of the weekly card: the score over the bar in the band's colour,
/// the weekday and date under it; today's column sits on a lit ground.
class _WeekColumn extends StatelessWidget {
  final double? value;
  final DateTime day;
  final bool today;
  final AppLocalizations? l;
  const _WeekColumn(
      {required this.value, required this.day, required this.today, this.l});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final v = value;
    final band = readinessBand(v, l);
    final col = p.on(band.color);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: S.x1),
      decoration: BoxDecoration(
          color: today ? p.card2 : const Color(0x00000000),
          borderRadius: R.rSm),
      child: Column(children: [
        // The label rides the bar: laid out bottom-up so the bar's height is
        // a fraction of what is left under the label, never of nothing.
        Expanded(
          child: Column(children: [
            Text(v == null ? '' : '${v.round()}%',
                style: F.cap.copyWith(
                    color: col, fontWeight: FontWeight.w700)),
            const SizedBox(height: S.x1),
            Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: v == null ? 0 : (v / 100).clamp(.04, 1.0),
                  child: Container(
                    width: 14,
                    decoration:
                        BoxDecoration(color: col, borderRadius: R.rSm),
                  ),
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: S.x2),
        Text(weekdayShortName(day.weekday, l),
            style: F.cap.copyWith(
                color: today ? p.ink : p.ink3,
                fontWeight: today ? FontWeight.w700 : FontWeight.w500)),
        Text('${day.day}',
            style: F.cap.copyWith(color: today ? p.ink : p.ink3)),
      ]),
    );
  }
}
