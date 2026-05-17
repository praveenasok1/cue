import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/models.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/live_waveform.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int? _shownPromptId;

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<PendingCatchphrasePrompt?>>(
      pendingCatchphrasePromptProvider,
      (_, next) {
        final prompt = next.value;
        if (prompt != null && prompt.hit.id != _shownPromptId) {
          _shownPromptId = prompt.hit.id;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _showMoodPicker(context, prompt);
          });
        }
      },
    );

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
              'Capture. Understand. Evolve.',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
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
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: const [
            _RecordingHero(),
            SizedBox(height: 18),
            _TranscriptPanel(),
            SizedBox(height: 18),
            _RecentHitsPanel(),
          ],
        ),
      ),
    );
  }

  Future<void> _showMoodPicker(
    BuildContext context,
    PendingCatchphrasePrompt prompt,
  ) async {
    final mood = await showModalBottomSheet<CueMood>(
      context: context,
      showDragHandle: true,
      builder: (context) => _MoodPicker(prompt: prompt),
    );
    if (mood != null && mounted) {
      await ref
          .read(catchphraseControllerProvider.notifier)
          .chooseMood(prompt.hit.id, mood);
    }
  }
}

class _RecordingHero extends ConsumerWidget {
  const _RecordingHero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(recordingControllerProvider);
    final colors = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: status.isRecording
                        ? CueColors.positive
                        : colors.outline,
                    shape: BoxShape.circle,
                    boxShadow: status.isRecording && !status.isPaused
                        ? [
                            BoxShadow(
                              color: CueColors.positive.withValues(alpha: 0.45),
                              blurRadius: 18,
                              spreadRadius: 4,
                            ),
                          ]
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    status.isPaused
                        ? 'Recording paused'
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
                  color: status.earphonesConnected ? CueColors.primary : null,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              status.statusMessage,
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            LiveWaveform(
              amplitude: status.amplitude,
              isRecording: status.isRecording && !status.isPaused,
            ),
            const SizedBox(height: 10),
            _InputLevelMeter(
              amplitude: status.amplitude,
              active: status.isRecording && !status.isPaused,
              paused: status.isPaused,
            ),
            const SizedBox(height: 10),
            _CatchphraseDetectionStatus(status: status),
            if (status.isRecording) ...[
              const SizedBox(height: 14),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _LiveTranscriptPreview(
                  key: ValueKey(status.liveTranscript),
                  text: status.liveTranscript,
                ),
              ),
            ],
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
                    onPressed: () {
                      final controller = ref.read(
                        recordingControllerProvider.notifier,
                      );
                      if (status.isPaused) {
                        controller.resumeRecording();
                      } else {
                        controller.pauseRecording();
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.stop_circle_rounded),
                    label: const Text('Stop'),
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

class _InputLevelMeter extends StatelessWidget {
  const _InputLevelMeter({
    required this.amplitude,
    required this.active,
    required this.paused,
  });

  final double amplitude;
  final bool active;
  final bool paused;

  @override
  Widget build(BuildContext context) {
    final value = active ? amplitude.clamp(0, 1).toDouble() : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 7,
            value: value,
            backgroundColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest,
            color: CueColors.primary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          active
              ? 'Mic input ${(value * 100).round()}%'
              : paused
              ? 'Mic input paused'
              : 'Mic input inactive - start a session to enable waveform',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _CatchphraseDetectionStatus extends StatelessWidget {
  const _CatchphraseDetectionStatus({required this.status});

  final RecordingStatus status;

  @override
  Widget build(BuildContext context) {
    final active = status.catchphraseDetectionActive && !status.isPaused;
    final colors = Theme.of(context).colorScheme;
    final label = status.lastCatchphraseLabel;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: active
            ? CueColors.positive.withValues(alpha: 0.10)
            : colors.surfaceContainerHighest.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            active ? Icons.radar_rounded : Icons.radar_outlined,
            color: active ? CueColors.positive : colors.onSurfaceVariant,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              !status.isRecording
                  ? 'Catchphrase reporting inactive'
                  : active
                  ? label == null
                        ? 'Catchphrase reporting active'
                        : 'Reported "$label" (${status.catchphraseReportCount})'
                  : 'Catchphrase reporting paused',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: active ? CueColors.positive : colors.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TranscriptPanel extends ConsumerStatefulWidget {
  const _TranscriptPanel();

  @override
  ConsumerState<_TranscriptPanel> createState() => _TranscriptPanelState();
}

class _TranscriptPanelState extends ConsumerState<_TranscriptPanel> {
  final _transcriptController = TextEditingController();
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _transcriptController.addListener(() {
      if (_focusNode.hasFocus) {
        _dirty = true;
        setState(() {});
      }
    });
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _transcriptController.dispose();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final transcript = ref.watch(todayTranscriptProvider);
    final recordingStatus = ref.watch(recordingControllerProvider);
    final catchphrases = ref
        .watch(catchphrasesProvider)
        .maybeWhen(data: (items) => items, orElse: () => <Catchphrase>[]);
    final search = _searchController.text.trim();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
              title: 'Today\'s transcript',
              subtitle: DateFormat.yMMMMEEEEd().format(DateTime.now()),
              icon: Icons.subject_rounded,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Search the full day transcript',
              ),
            ),
            const SizedBox(height: 16),
            transcript.when(
              data: (dailyTranscript) {
                final displayText = _withLiveTranscript(
                  dailyTranscript.text,
                  recordingStatus.liveTranscript,
                );
                if (!_focusNode.hasFocus && !_dirty) {
                  _transcriptController.text = displayText;
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _transcriptController,
                      focusNode: _focusNode,
                      minLines: 7,
                      maxLines: 14,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        alignLabelWithHint: true,
                        labelText: 'Edit transcript inline',
                        hintText: 'CUE will append session transcripts here.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Last saved ${DateFormat.jm().format(dailyTranscript.updatedAt)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: () async {
                            final textToSave = _focusNode.hasFocus || _dirty
                                ? _transcriptController.text
                                : dailyTranscript.text;
                            await ref
                                .read(transcriptControllerProvider.notifier)
                                .saveToday(textToSave);
                            _dirty = false;
                            _focusNode.unfocus();
                          },
                          icon: const Icon(Icons.save_rounded),
                          label: const Text('Save'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _HighlightedTranscript(
                      text: _focusNode.hasFocus || _dirty
                          ? _transcriptController.text
                          : displayText,
                      search: search,
                      catchphrases: catchphrases,
                    ),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Text('Could not load transcript: $error'),
            ),
          ],
        ),
      ),
    );
  }

  String _withLiveTranscript(String savedText, String liveTranscript) {
    final live = liveTranscript.trim();
    if (live.isEmpty) return savedText;
    if (savedText.trim().isEmpty) return live;
    return '$savedText\n$live';
  }
}

class _LiveTranscriptPreview extends StatelessWidget {
  const _LiveTranscriptPreview({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final copy = text.trim().isEmpty ? 'Listening for speech...' : text.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CueColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: CueColors.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Live transcript',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: CueColors.primary,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            copy,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: text.trim().isEmpty ? colors.onSurfaceVariant : null,
              fontStyle: text.trim().isEmpty ? FontStyle.italic : null,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
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
    final spans = _buildSpans(context);
    final searchCount = search.isEmpty
        ? 0
        : RegExp(
            RegExp.escape(search),
            caseSensitive: false,
          ).allMatches(text).length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Highlighted view',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              if (search.isNotEmpty)
                Text(
                  '$searchCount match${searchCount == 1 ? '' : 'es'}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SelectableText.rich(
            TextSpan(
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(height: 1.5),
              children: spans.isEmpty
                  ? const [TextSpan(text: 'No transcript yet.')]
                  : spans,
            ),
          ),
        ],
      ),
    );
  }

  List<TextSpan> _buildSpans(BuildContext context) {
    if (text.isEmpty) return const [];
    final matches = <_TextHighlight>[];
    for (final catchphrase in catchphrases) {
      final expression = RegExp(
        RegExp.escape(catchphrase.phrase),
        caseSensitive: false,
      );
      for (final match in expression.allMatches(text)) {
        matches.add(
          _TextHighlight(
            match.start,
            match.end,
            catchphrase.color.withValues(alpha: 0.35),
          ),
        );
      }
    }
    if (search.isNotEmpty) {
      final expression = RegExp(RegExp.escape(search), caseSensitive: false);
      for (final match in expression.allMatches(text)) {
        matches.add(
          _TextHighlight(
            match.start,
            match.end,
            Colors.amber.withValues(alpha: 0.45),
          ),
        );
      }
    }

    matches.sort((a, b) => a.start.compareTo(b.start));
    final spans = <TextSpan>[];
    var index = 0;
    for (final match in matches) {
      if (match.start < index) continue;
      if (match.start > index) {
        spans.add(TextSpan(text: text.substring(index, match.start)));
      }
      spans.add(
        TextSpan(
          text: text.substring(match.start, match.end),
          style: TextStyle(
            backgroundColor: match.color,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
      index = match.end;
    }
    if (index < text.length) spans.add(TextSpan(text: text.substring(index)));
    return spans;
  }
}

class _TextHighlight {
  const _TextHighlight(this.start, this.end, this.color);

  final int start;
  final int end;
  final Color color;
}

class _RecentHitsPanel extends ConsumerWidget {
  const _RecentHitsPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hits = ref.watch(recentHitsProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(
              title: 'Habit log',
              subtitle: 'Catchphrase time, mood, and location captures.',
              icon: Icons.timeline_rounded,
            ),
            const SizedBox(height: 12),
            hits.when(
              data: (items) {
                if (items.isEmpty) {
                  return const Text('No catchphrase events logged yet.');
                }
                return Column(
                  children: [
                    for (final hit in items)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          hit.acknowledged
                              ? Icons.check_circle_rounded
                              : Icons.mood_rounded,
                          color: hit.acknowledged
                              ? CueColors.positive
                              : CueColors.primary,
                        ),
                        title: Text(hit.phrase),
                        subtitle: Text(_hitSubtitle(hit)),
                      ),
                  ],
                );
              },
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => Text('Could not load habit log: $error'),
            ),
          ],
        ),
      ),
    );
  }

  String _hitSubtitle(CatchphraseHit hit) {
    final time = DateFormat.MMMd().add_jm().format(hit.spokenAt);
    final mood = hit.mood == null ? 'Mood pending' : hit.mood!.label;
    final location = hit.latitude == null || hit.longitude == null
        ? 'No location'
        : '${hit.latitude!.toStringAsFixed(4)}, '
              '${hit.longitude!.toStringAsFixed(4)}';
    return '$time - $mood - $location';
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: CueColors.primary.withValues(alpha: 0.11),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: CueColors.primary),
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
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
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

class _MoodPicker extends StatelessWidget {
  const _MoodPicker({required this.prompt});

  final PendingCatchphrasePrompt prompt;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How did you feel?',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            'CUE heard "${prompt.catchphrase.phrase}" and logged this moment.',
          ),
          const SizedBox(height: 18),
          GridView.count(
            shrinkWrap: true,
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 3.4,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final mood in CueMood.values)
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(mood),
                  child: Text('${mood.emoji} ${mood.label}'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> _showSettings(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final themeMode = ref.watch(themeModeControllerProvider);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          builder: (context, scrollController) {
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
              children: [
                const _SectionHeader(
                  title: 'Settings',
                  subtitle: 'CUE starts in light mode by default.',
                  icon: Icons.settings_rounded,
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
                  onSelectionChanged: (selection) {
                    ref
                        .read(themeModeControllerProvider.notifier)
                        .setThemeMode(selection.single);
                  },
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Audio catchphrases',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () => _showCatchphraseSheet(context, ref),
                      icon: const Icon(Icons.mic_rounded),
                      label: const Text('Record'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Each catchphrase has a short audio sample, a text label used for transcript matching, and a highlight color.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                const _CatchphraseList(compact: true),
              ],
            );
          },
        );
      },
    ),
  );
}

class _CatchphraseList extends ConsumerWidget {
  const _CatchphraseList({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catchphrases = ref.watch(catchphrasesProvider);
    return catchphrases.when(
      data: (items) {
        if (items.isEmpty) {
          return Text(
            'No audio catchphrases yet. Tap Record to add one.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          );
        }
        return Column(
          children: [
            for (final item in items)
              ListTile(
                dense: compact,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: item.color,
                  child: const Icon(
                    Icons.graphic_eq_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                title: Text(item.phrase),
                subtitle: Text(
                  item.audioPath == null
                      ? 'Legacy text-only catchphrase'
                      : 'Voice sample saved',
                ),
                trailing: IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () => ref
                      .read(catchphraseControllerProvider.notifier)
                      .delete(item.id),
                ),
              ),
          ],
        );
      },
      loading: () => const LinearProgressIndicator(),
      error: (error, _) => Text('Could not load catchphrases: $error'),
    );
  }
}

Future<void> _showCatchphraseSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _CatchphraseForm(ref: ref),
  );
}

class _CatchphraseForm extends StatefulWidget {
  const _CatchphraseForm({required this.ref});

  final WidgetRef ref;

  @override
  State<_CatchphraseForm> createState() => _CatchphraseFormState();
}

class _CatchphraseFormState extends State<_CatchphraseForm> {
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
  bool _isRecording = false;
  String? _audioPath;
  String? _error;

  @override
  void dispose() {
    _phraseController.dispose();
    if (_isRecording) {
      widget.ref
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
        22,
        0,
        22,
        MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(
              title: 'Record catchphrase',
              subtitle:
                  'Say the phrase once, then add its text label and highlight color.',
              icon: Icons.add_reaction_rounded,
            ),
            const SizedBox(height: 16),
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
                      ? 'Stop recording sample'
                      : _audioPath == null
                      ? 'Record audio sample'
                      : 'Re-record audio sample',
                ),
                onPressed: _toggleRecording,
              ),
            ),
            if (_audioPath != null && !_isRecording) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: CueColors.positive,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Audio sample saved',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _phraseController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Text label',
                hintText: 'for example: drink water',
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              children: [
                for (final color in _colors)
                  ChoiceChip(
                    selected: _color == color,
                    label: const SizedBox(width: 24, height: 24),
                    avatar: CircleAvatar(backgroundColor: color),
                    onSelected: (_) => setState(() => _color = color),
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: CueColors.negative)),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.check_rounded),
                label: const Text('Save audio catchphrase'),
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
      final service = widget.ref.read(catchphraseAudioServiceProvider);
      if (_isRecording) {
        final path = await service.stopSampleRecording();
        setState(() {
          _isRecording = false;
          _audioPath = path ?? _audioPath;
        });
      } else {
        final path = await service.startSampleRecording();
        setState(() {
          _isRecording = true;
          _audioPath = path;
        });
      }
    } catch (error) {
      setState(() {
        _isRecording = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _save() async {
    try {
      final audioPath = _audioPath;
      if (audioPath == null) {
        throw ArgumentError('Record an audio sample first.');
      }
      await widget.ref
          .read(catchphraseControllerProvider.notifier)
          .add(
            phrase: _phraseController.text,
            color: _color,
            audioPath: audioPath,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }
}
