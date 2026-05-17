import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/live_waveform.dart';

// ═══════════════════════════════════════════════ Root scaffold ════════════════

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _insightRequested = false;

  @override
  Widget build(BuildContext context) {
    // Trigger first summary load after widgets settle.
    if (!_insightRequested) {
      _insightRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(
            ref
                .read(insightControllerProvider.notifier)
                .refreshToday()
                .catchError((_) {}),
          );
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'CUE',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 3),
            ),
            Text(
              'Capture · Understand · Evolve',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_rounded),
            onPressed: () => _showSettings(context),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: const [
            _RecordingHero(),
            SizedBox(height: 18),
            _TranscriptPanel(),
            SizedBox(height: 18),
            _CatchphraseStatsPanel(),
            SizedBox(height: 18),
            _RemindersPanel(),
            SizedBox(height: 18),
            _DailySummaryPanel(),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════ Recording hero ═══════════════

class _RecordingHero extends ConsumerWidget {
  const _RecordingHero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(recordingControllerProvider);
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Header row ─────────────────────────────────────────────────
            Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 280),
                  width: 13,
                  height: 13,
                  decoration: BoxDecoration(
                    color: status.isRecording && !status.isPaused
                        ? CueColors.positive
                        : cs.outline,
                    shape: BoxShape.circle,
                    boxShadow: status.isRecording && !status.isPaused
                        ? [
                            BoxShadow(
                              color: CueColors.positive.withValues(alpha: 0.4),
                              blurRadius: 14,
                              spreadRadius: 3,
                            ),
                          ]
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    status.isPaused
                        ? 'Paused'
                        : status.isRecording
                        ? 'Recording live'
                        : 'Standby',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Icon(
                  status.earphonesConnected
                      ? Icons.headphones_rounded
                      : Icons.headset_off_rounded,
                  color: status.earphonesConnected
                      ? CueColors.primary
                      : cs.outlineVariant,
                ),
              ],
            ),

            const SizedBox(height: 6),
            Text(
              status.statusMessage,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),

            // ─── Waveform ─────────────────────────────────────────────────────
            const SizedBox(height: 18),
            LiveWaveform(
              amplitude: status.amplitude,
              isRecording: status.isRecording && !status.isPaused,
            ),

            // ─── Mic meter ────────────────────────────────────────────────────
            const SizedBox(height: 8),
            _MicMeter(status: status),

            // ─── Catchphrase radar ────────────────────────────────────────────
            if (status.isRecording) ...[
              const SizedBox(height: 10),
              _CatchphraseRadar(status: status),
            ],

            // ─── Live transcript bubble ────────────────────────────────────────
            if (status.isRecording && status.liveTranscript.isNotEmpty) ...[
              const SizedBox(height: 12),
              _LiveBubble(text: status.liveTranscript),
            ],

            // ─── Action buttons ───────────────────────────────────────────────
            const SizedBox(height: 12),
            if (status.isRecording)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    icon: Icon(
                      status.isPaused
                          ? Icons.play_circle_rounded
                          : Icons.pause_circle_rounded,
                    ),
                    label: Text(status.isPaused ? 'Resume' : 'Pause'),
                    onPressed: status.isPaused
                        ? () => ref
                              .read(recordingControllerProvider.notifier)
                              .resumeRecording()
                        : () => ref
                              .read(recordingControllerProvider.notifier)
                              .pauseRecording(),
                  ),
                  const SizedBox(width: 6),
                  TextButton.icon(
                    icon: const Icon(Icons.stop_circle_rounded),
                    label: const Text('Stop'),
                    style: TextButton.styleFrom(
                      foregroundColor: CueColors.negative,
                    ),
                    onPressed: () => ref
                        .read(recordingControllerProvider.notifier)
                        .stopRecording(reason: 'Stopped by user'),
                  ),
                ],
              )
            else
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  icon: const Icon(Icons.mic_rounded),
                  label: const Text('Start session'),
                  onPressed: () => ref
                      .read(recordingControllerProvider.notifier)
                      .startManualRecording(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MicMeter extends StatelessWidget {
  const _MicMeter({required this.status});
  final RecordingStatus status;

  @override
  Widget build(BuildContext context) {
    final active = status.isRecording && !status.isPaused;
    final value = active ? (status.amplitude * 0.55).clamp(0.0, 1.0) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 5,
            value: value,
            backgroundColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest,
            color: CueColors.primary.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          active
              ? 'Mic ${(value * 100).round()}%'
              : status.isPaused
              ? 'Mic paused'
              : 'Mic inactive',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _CatchphraseRadar extends StatelessWidget {
  const _CatchphraseRadar({required this.status});
  final RecordingStatus status;

  @override
  Widget build(BuildContext context) {
    final active = status.catchphraseDetectionActive && !status.isPaused;
    final label = status.lastCatchphraseLabel;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: active
            ? CueColors.positive.withValues(alpha: 0.10)
            : Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            active ? Icons.radar_rounded : Icons.radar_outlined,
            size: 16,
            color: active
                ? CueColors.positive
                : Theme.of(context).colorScheme.outlineVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              active
                  ? label == null
                        ? 'Catchphrase detection active'
                        : '"$label" detected (${status.catchphraseReportCount}×)'
                  : 'Catchphrase detection paused',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: active
                    ? CueColors.positive
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveBubble extends StatelessWidget {
  const _LiveBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CueColors.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CueColors.primary.withValues(alpha: 0.16)),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.35),
      ),
    );
  }
}

// ═══════════════════════════════════════════════ Transcript panel ═════════════

class _TranscriptPanel extends ConsumerStatefulWidget {
  const _TranscriptPanel();

  @override
  ConsumerState<_TranscriptPanel> createState() => _TranscriptPanelState();
}

class _TranscriptPanelState extends ConsumerState<_TranscriptPanel> {
  final _controller = TextEditingController();
  final _search = TextEditingController();
  final _focus = FocusNode();
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (_focus.hasFocus) setState(() => _dirty = true);
    });
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final transcript = ref.watch(todayTranscriptProvider);
    final status = ref.watch(recordingControllerProvider);
    final catchphrases = ref
        .watch(catchphrasesProvider)
        .maybeWhen(data: (items) => items, orElse: () => <Catchphrase>[]);
    final searchText = _search.text.trim();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
              icon: Icons.subject_rounded,
              title: "Today's transcript",
              subtitle: DateFormat.yMMMMEEEEd().format(DateTime.now()),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Search transcript',
                isDense: true,
              ),
            ),
            const SizedBox(height: 14),
            transcript.when(
              data: (t) {
                final display = _merge(t.text, status.liveTranscript);
                if (!_focus.hasFocus && !_dirty) _controller.text = display;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _controller,
                      focusNode: _focus,
                      minLines: 6,
                      maxLines: 12,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        labelText: 'Edit inline',
                        hintText: 'CUE appends earphone sessions here.',
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Saved ${DateFormat.jm().format(t.updatedAt)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        FilledButton.icon(
                          icon: const Icon(Icons.save_rounded, size: 16),
                          label: const Text('Save'),
                          onPressed: () async {
                            final text = _focus.hasFocus || _dirty
                                ? _controller.text
                                : t.text;
                            await ref
                                .read(transcriptControllerProvider.notifier)
                                .saveToday(text);
                            setState(() => _dirty = false);
                            _focus.unfocus();
                          },
                        ),
                      ],
                    ),
                    if (searchText.isNotEmpty || catchphrases.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _HighlightedTranscript(
                        text: _focus.hasFocus || _dirty
                            ? _controller.text
                            : display,
                        search: searchText,
                        catchphrases: catchphrases,
                      ),
                    ],
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error: $e'),
            ),
          ],
        ),
      ),
    );
  }

  String _merge(String saved, String live) {
    final l = live.trim();
    if (l.isEmpty) return saved;
    if (saved.trim().isEmpty) return l;
    return '$saved $l';
  }
}

class _HighlightedTranscript extends StatelessWidget {
  const _HighlightedTranscript({
    required this.text,
    required this.search,
    required this.catchphrases,
  });

  final String text;
  final String search;
  final List<Catchphrase> catchphrases;

  @override
  Widget build(BuildContext context) {
    final matchCount = search.isEmpty
        ? 0
        : RegExp(
            RegExp.escape(search),
            caseSensitive: false,
          ).allMatches(text).length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Highlighted',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              if (search.isNotEmpty)
                Text(
                  '$matchCount match${matchCount == 1 ? '' : 'es'}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SelectableText.rich(
            TextSpan(
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(height: 1.5),
              children: text.isEmpty
                  ? const [TextSpan(text: 'No transcript yet.')]
                  : _spans(context),
            ),
          ),
        ],
      ),
    );
  }

  List<TextSpan> _spans(BuildContext context) {
    final highlights = <_HL>[];
    for (final cp in catchphrases) {
      for (final m in RegExp(
        RegExp.escape(cp.phrase),
        caseSensitive: false,
      ).allMatches(text)) {
        highlights.add(_HL(m.start, m.end, cp.color.withValues(alpha: 0.32)));
      }
    }
    if (search.isNotEmpty) {
      for (final m in RegExp(
        RegExp.escape(search),
        caseSensitive: false,
      ).allMatches(text)) {
        highlights.add(
          _HL(m.start, m.end, Colors.amber.withValues(alpha: 0.42)),
        );
      }
    }
    highlights.sort((a, b) => a.start.compareTo(b.start));
    final spans = <TextSpan>[];
    var idx = 0;
    for (final h in highlights) {
      if (h.start < idx) continue;
      if (h.start > idx) {
        spans.add(TextSpan(text: text.substring(idx, h.start)));
      }
      spans.add(
        TextSpan(
          text: text.substring(h.start, h.end),
          style: TextStyle(
            backgroundColor: h.color,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      idx = h.end;
    }
    if (idx < text.length) spans.add(TextSpan(text: text.substring(idx)));
    return spans;
  }
}

class _HL {
  const _HL(this.start, this.end, this.color);
  final int start;
  final int end;
  final Color color;
}

// ═══════════════════════════════════════════════ Catchphrase stats ════════════

class _CatchphraseStatsPanel extends ConsumerWidget {
  const _CatchphraseStatsPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(todayCatchphraseStatsProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(
              icon: Icons.bar_chart_rounded,
              title: 'Catchphrase log',
              subtitle: "Today's occurrences — tap count for details",
            ),
            const SizedBox(height: 12),
            stats.when(
              data: (items) => items.isEmpty
                  ? const Text('No catchphrases heard yet today.')
                  : Column(
                      children: items
                          .map((stat) => _StatRow(stat: stat))
                          .toList(),
                    ),
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Error: $e'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.stat});
  final CatchphraseStat stat;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: stat.catchphrase.color,
        radius: 18,
        child: Text(
          stat.count.toString(),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 13,
          ),
        ),
      ),
      title: Text(
        stat.catchphrase.phrase,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        stat.catchphrase.tag.label,
        style: const TextStyle(fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _CatchphraseDetailSheet(stat: stat),
      ),
    );
  }
}

class _CatchphraseDetailSheet extends StatelessWidget {
  const _CatchphraseDetailSheet({required this.stat});
  final CatchphraseStat stat;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      maxChildSize: 0.92,
      builder: (_, sc) => ListView(
        controller: sc,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          _SectionHeader(
            icon: Icons.bar_chart_rounded,
            title: '"${stat.catchphrase.phrase}"',
            subtitle:
                '${stat.count} occurrence${stat.count == 1 ? '' : 's'} today',
          ),
          const SizedBox(height: 16),
          for (final hit in stat.hits)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 48,
                      decoration: BoxDecoration(
                        color: stat.catchphrase.color,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat.jms().format(hit.spokenAt),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          if (hit.latitude != null && hit.longitude != null)
                            Row(
                              children: [
                                const Icon(
                                  Icons.location_on_rounded,
                                  size: 13,
                                  color: CueColors.primary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${hit.latitude!.toStringAsFixed(5)}, ${hit.longitude!.toStringAsFixed(5)}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            )
                          else
                            const Text(
                              'No GPS data',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          const SizedBox(height: 4),
                          Text(
                            hit.context.length > 80
                                ? '${hit.context.substring(0, 80)}…'
                                : hit.context,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════ Reminders ════════════════════

class _RemindersPanel extends ConsumerWidget {
  const _RemindersPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reminders = ref.watch(openRemindersProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(
              icon: Icons.notifications_active_rounded,
              title: 'Reminders',
              subtitle: 'Auto-extracted from transcript · synced to MS To-Do',
            ),
            const SizedBox(height: 12),
            reminders.when(
              data: (items) => items.isEmpty
                  ? const Text(
                      'No open reminders. Say "remind me to…" while recording.',
                    )
                  : Column(
                      children: items
                          .map(
                            (r) => CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: r.completed,
                              onChanged: (_) => ref
                                  .read(insightControllerProvider.notifier)
                                  .completeReminder(r.id),
                              title: Text(r.text),
                              subtitle: Text(
                                _subtitle(r),
                                style: const TextStyle(fontSize: 11),
                              ),
                              controlAffinity: ListTileControlAffinity.leading,
                            ),
                          )
                          .toList(),
                    ),
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Error: $e'),
            ),
          ],
        ),
      ),
    );
  }

  String _subtitle(CueReminder r) {
    final created = DateFormat.MMMd().add_jm().format(r.createdAt);
    final due = r.dueAt == null
        ? ''
        : ' · due ${DateFormat.MMMd().format(r.dueAt!)}';
    final ms = r.microsoftToDoId != null ? ' · ✓ To-Do' : '';
    return '$created$due$ms';
  }
}

// ═══════════════════════════════════════════════ Daily summary ════════════════

class _DailySummaryPanel extends ConsumerWidget {
  const _DailySummaryPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(todaySummaryProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: _SectionHeader(
                    icon: Icons.auto_stories_rounded,
                    title: 'Daily summary',
                    subtitle: 'Generated from today\'s transcript',
                  ),
                ),
                IconButton(
                  tooltip: 'Regenerate',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: () => ref
                      .read(insightControllerProvider.notifier)
                      .refreshToday(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            summary.when(
              data: (s) => s == null
                  ? const Text(
                      'No summary yet. Record some audio or tap regenerate.',
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.summary, style: const TextStyle(height: 1.45)),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _Chip(Icons.notes_rounded, '${s.wordCount} words'),
                            _Chip(
                              Icons.radar_rounded,
                              '${s.catchphraseCount} catchphrases',
                            ),
                            _Chip(
                              Icons.notifications_rounded,
                              '${s.reminderCount} reminders',
                            ),
                            for (final kw in s.keywords)
                              _Chip(Icons.tag_rounded, kw),
                          ],
                        ),
                      ],
                    ),
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Error: $e'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 14, color: CueColors.primary),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      padding: const EdgeInsets.symmetric(horizontal: 2),
    );
  }
}

// ═══════════════════════════════════════════════ Shared widgets ═══════════════

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: CueColors.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: CueColors.primary, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════ Settings sheet ═══════════════

Future<void> _showSettings(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Consumer(
      builder: (ctx, ref, _) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          builder: (_, sc) => _SettingsContent(scrollController: sc),
        );
      },
    ),
  );
}

class _SettingsContent extends ConsumerStatefulWidget {
  const _SettingsContent({required this.scrollController});
  final ScrollController scrollController;

  @override
  ConsumerState<_SettingsContent> createState() => _SettingsContentState();
}

class _SettingsContentState extends ConsumerState<_SettingsContent> {
  final _clientIdController = TextEditingController();
  String? _deviceUserCode;
  bool _polling = false;
  bool _msEnabled = false;

  @override
  void initState() {
    super.initState();
    _initMsStatus();
  }

  Future<void> _initMsStatus() async {
    final svc = ref.read(microsoftToDoServiceProvider);
    final enabled = await svc.isEnabled;
    final id = await svc.clientId;
    if (mounted) {
      setState(() {
        _msEnabled = enabled;
        _clientIdController.text = id ?? '';
      });
    }
  }

  @override
  void dispose() {
    _clientIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeControllerProvider);
    final catchphrases = ref.watch(catchphrasesProvider);

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 36),
      children: [
        // ── Appearance ─────────────────────────────────────────────────────
        const _SectionHeader(
          icon: Icons.settings_rounded,
          title: 'Settings',
          subtitle: 'App preferences',
        ),
        const SizedBox(height: 16),
        SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(
              value: ThemeMode.light,
              label: Text('Light'),
              icon: Icon(Icons.light_mode_rounded),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              label: Text('Dark'),
              icon: Icon(Icons.dark_mode_rounded),
            ),
          ],
          selected: {themeMode},
          onSelectionChanged: (s) => ref
              .read(themeModeControllerProvider.notifier)
              .setThemeMode(s.single),
        ),

        // ── Audio catchphrases ─────────────────────────────────────────────
        const SizedBox(height: 28),
        Row(
          children: [
            const Expanded(
              child: _SectionHeader(
                icon: Icons.graphic_eq_rounded,
                title: 'Audio catchphrases',
                subtitle: 'Record voice samples · assign tags',
              ),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.mic_rounded, size: 16),
              label: const Text('Record'),
              onPressed: () => _showAddCatchphrase(context),
            ),
          ],
        ),
        const SizedBox(height: 12),
        catchphrases.when(
          data: (items) => items.isEmpty
              ? Text(
                  'No catchphrases yet. Tap Record to add one.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                )
              : Column(
                  children: items
                      .map((cp) => _CatchphraseSettingsRow(catchphrase: cp))
                      .toList(),
                ),
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('Error: $e'),
        ),

        // ── Microsoft To-Do ────────────────────────────────────────────────
        const SizedBox(height: 28),
        const _SectionHeader(
          icon: Icons.task_alt_rounded,
          title: 'Microsoft To-Do',
          subtitle: 'Auto-add reminders to your To-Do list',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _clientIdController,
          decoration: const InputDecoration(
            labelText: 'Azure App Client ID',
            hintText: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
          ),
          onSubmitted: (v) async {
            await ref.read(microsoftToDoServiceProvider).saveClientId(v);
            if (mounted) setState(() {});
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                _msEnabled ? 'Connected to Microsoft To-Do' : 'Not connected',
                style: TextStyle(
                  color: _msEnabled
                      ? CueColors.positive
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (_msEnabled)
              TextButton(
                onPressed: () async {
                  await ref.read(microsoftToDoServiceProvider).signOut();
                  if (mounted) setState(() => _msEnabled = false);
                },
                child: const Text('Sign out'),
              )
            else
              FilledButton(
                onPressed: _polling ? null : _startMsSignIn,
                child: Text(_polling ? 'Waiting…' : 'Connect'),
              ),
          ],
        ),
        if (_deviceUserCode != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: CueColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Visit microsoft.com/devicelogin and enter:',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      _deviceUserCode!,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 4,
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded),
                      onPressed: () => Clipboard.setData(
                        ClipboardData(text: _deviceUserCode!),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.open_in_browser_rounded),
                      onPressed: () => launchUrl(
                        Uri.parse('https://microsoft.com/devicelogin'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _startMsSignIn() async {
    final id = _clientIdController.text.trim();
    if (id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your Azure Client ID first.')),
      );
      return;
    }
    try {
      await ref.read(microsoftToDoServiceProvider).saveClientId(id);
      final svc = ref.read(microsoftToDoServiceProvider);
      final pending = await svc.requestDeviceCode();
      setState(() {
        _polling = true;
        _deviceUserCode = pending.userCode;
      });
      final ok = await svc.pollForToken(pending);
      if (mounted) {
        setState(() {
          _msEnabled = ok;
          _polling = false;
          _deviceUserCode = null;
        });
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _polling = false;
          _deviceUserCode = null;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  void _showAddCatchphrase(BuildContext ctx) {
    showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AddCatchphraseForm(parentRef: ref),
    );
  }
}

// ── Catchphrase row in settings ─────────────────────────────────────────────

class _CatchphraseSettingsRow extends ConsumerWidget {
  const _CatchphraseSettingsRow({required this.catchphrase});
  final Catchphrase catchphrase;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: catchphrase.color,
        radius: 18,
        child: const Icon(
          Icons.graphic_eq_rounded,
          color: Colors.white,
          size: 16,
        ),
      ),
      title: Text(
        catchphrase.phrase,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: DropdownButton<CatchphraseTag>(
        value: catchphrase.tag,
        isDense: true,
        underline: const SizedBox(),
        items: CatchphraseTag.values
            .map(
              (t) => DropdownMenuItem(
                value: t,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(t.icon, size: 14, color: CueColors.primary),
                    const SizedBox(width: 6),
                    Text(t.label, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            )
            .toList(),
        onChanged: (t) {
          if (t != null) {
            ref
                .read(catchphraseControllerProvider.notifier)
                .updateTag(catchphrase.id, t);
          }
        },
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline_rounded),
        onPressed: () => ref
            .read(catchphraseControllerProvider.notifier)
            .delete(catchphrase.id),
      ),
    );
  }
}

// ── Add catchphrase form ─────────────────────────────────────────────────────

class _AddCatchphraseForm extends StatefulWidget {
  const _AddCatchphraseForm({required this.parentRef});
  final WidgetRef parentRef;

  @override
  State<_AddCatchphraseForm> createState() => _AddCatchphraseFormState();
}

class _AddCatchphraseFormState extends State<_AddCatchphraseForm> {
  static const _colors = [
    Color(0xFFFFC857),
    Color(0xFF7BDFF2),
    Color(0xFFB2F7EF),
    Color(0xFFFF8FAB),
    Color(0xFFCDB4DB),
    Color(0xFF90BE6D),
  ];

  final _phraseController = TextEditingController();
  Color _color = _colors.first;
  CatchphraseTag _tag = CatchphraseTag.countOnly;
  bool _isRecording = false;
  String? _audioPath;
  String? _error;

  @override
  void dispose() {
    _phraseController.dispose();
    if (_isRecording) {
      widget.parentRef
          .read(catchphraseAudioServiceProvider)
          .stopSampleRecording()
          .ignore();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(
              icon: Icons.add_reaction_rounded,
              title: 'New catchphrase',
              subtitle: 'Record voice · label · pick tag',
            ),
            const SizedBox(height: 16),
            // Record button.
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _isRecording
                      ? CueColors.negative
                      : CueColors.primary,
                ),
                icon: Icon(
                  _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                ),
                label: Text(
                  _isRecording
                      ? 'Stop recording'
                      : _audioPath == null
                      ? 'Record voice sample'
                      : 'Re-record',
                ),
                onPressed: _toggleRecording,
              ),
            ),
            if (_audioPath != null && !_isRecording) ...[
              const SizedBox(height: 8),
              const Row(
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    color: CueColors.positive,
                    size: 18,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Audio sample ready',
                    style: TextStyle(color: CueColors.positive),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _phraseController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Text label',
                hintText: 'e.g. drink water',
              ),
            ),
            const SizedBox(height: 12),
            // Color picker.
            Wrap(
              spacing: 10,
              children: _colors
                  .map(
                    (c) => GestureDetector(
                      onTap: () => setState(() => _color = c),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _color == c
                                ? Colors.black87
                                : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            // Tag picker.
            DropdownButtonFormField<CatchphraseTag>(
              initialValue: _tag,
              decoration: const InputDecoration(labelText: 'Tag'),
              items: CatchphraseTag.values
                  .map(
                    (t) => DropdownMenuItem(
                      value: t,
                      child: Row(
                        children: [
                          Icon(t.icon, size: 16, color: CueColors.primary),
                          const SizedBox(width: 8),
                          Text(t.label),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (t) {
                if (t != null) setState(() => _tag = t);
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: CueColors.negative)),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.check_rounded),
                label: const Text('Save catchphrase'),
                onPressed: _isRecording ? null : _save,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleRecording() async {
    setState(() => _error = null);
    try {
      final svc = widget.parentRef.read(catchphraseAudioServiceProvider);
      if (_isRecording) {
        final path = await svc.stopSampleRecording();
        setState(() {
          _isRecording = false;
          _audioPath = path ?? _audioPath;
        });
      } else {
        final path = await svc.startSampleRecording();
        setState(() {
          _isRecording = true;
          _audioPath = path;
        });
      }
    } catch (e) {
      setState(() {
        _isRecording = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _save() async {
    final path = _audioPath;
    if (path == null) {
      setState(() => _error = 'Record a voice sample first.');
      return;
    }
    try {
      await widget.parentRef
          .read(catchphraseControllerProvider.notifier)
          .add(
            phrase: _phraseController.text,
            color: _color,
            audioPath: path,
            tag: _tag,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }
}
