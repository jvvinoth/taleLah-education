/// Parent Review & Edit (F2) — review facts, swap words, tune difficulty,
/// regenerate single components (cap 5), then approve. Immutable after approval.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';

class ParentReviewScreen extends StatefulWidget {
  final String packageId;
  const ParentReviewScreen({super.key, required this.packageId});

  @override
  State<ParentReviewScreen> createState() => _ParentReviewScreenState();
}

class _ParentReviewScreenState extends State<ParentReviewScreen> {
  Map<String, dynamic>? _pkg;
  bool _loading = true;
  bool _busy = false;

  static const _maxRegens = 5;
  static const _levels = [
    ('beginning', '🌱 Beginning'),
    ('emerging', '🌿 Emerging'),
    ('growing', '🌳 Growing'),
    ('conversational', '💬 Conversational'),
  ];

  ApiClient get _api => context.read<AppState>().api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final detail = await _api.getPackageDetail(widget.packageId);
      setState(() {
        _pkg = detail['package'] as Map<String, dynamic>?;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      _showError('Failed to load story: $e');
    }
  }

  bool get _editable => _pkg?['status'] == 'awaiting_parent';
  int get _regenCount => (_pkg?['regeneration_count'] as int?) ?? 0;
  int get _regensLeft => _maxRegens - _regenCount;

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: TColors.coral),
    );
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _guarded(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on ApiException catch (e) {
      _showError(e.detail);
    } catch (e) {
      _showError('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Actions ─────────────────────────────────────────────────────────

  Future<void> _regenerate(String component, {int sceneIndex = 0}) =>
      _guarded(() async {
        final r = await _api.regenerateComponent(widget.packageId, component,
            sceneIndex: sceneIndex);
        setState(() => _pkg = r['package'] as Map<String, dynamic>?);
        _showSuccess(
            'Regenerated $component — ${r['regenerations_remaining']} left');
      });

  Future<void> _saveFacts(List<String> facts) => _guarded(() async {
        await _api.editFacts(widget.packageId, facts);
        await _load();
        _showSuccess('Facts updated');
      });

  Future<void> _swapWord(String oldWord, String newWord) => _guarded(() async {
        await _api.swapTargetWord(widget.packageId, oldWord, newWord);
        await _load();
        _showSuccess('Swapped "$oldWord" → "$newWord"');
      });

  Future<void> _setLevel(String level) => _guarded(() async {
        await _api.setDifficulty(widget.packageId, level);
        await _load();
      });

  Future<void> _approve() => _guarded(() async {
        await _api.approvePackage(widget.packageId);
        if (!mounted) return;
        Navigator.pop(context, true);
      });

  // ── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Container(
      decoration: const BoxDecoration(gradient: TGradients.page),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _pkg == null
                ? const Center(child: Text('Story not found'))
                : Stack(
                    children: [
                      SingleChildScrollView(
                        padding:
                            EdgeInsets.fromLTRB(20, topPad + 12, 20, 130),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildTopBar(),
                            const SizedBox(height: 18),
                            _buildTitleCard(),
                            const SizedBox(height: 16),
                            _buildFactsCard(),
                            const SizedBox(height: 16),
                            _buildLearningPlanCard(),
                            const SizedBox(height: 16),
                            _buildScenes(),
                            const SizedBox(height: 16),
                            _buildMissionCard(),
                            const SizedBox(height: 16),
                            _buildHandoffCard(),
                          ],
                        ),
                      ),
                      if (_editable)
                        Positioned(
                          left: 20,
                          right: 20,
                          bottom:
                              MediaQuery.of(context).padding.bottom + 16,
                          child: _buildApproveButton(),
                        ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Row(
      children: [
        GestureDetector(
          onTap: () => Navigator.pop(context, false),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: TShadows.card,
            ),
            child: const Icon(Icons.arrow_back_rounded,
                color: TColors.ink, size: 22),
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'Review Story',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _regensLeft > 0 ? TColors.mint : TColors.peach,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '🔄 $_regensLeft left',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: _regensLeft > 0
                  ? const Color(0xFF1F7B75)
                  : TColors.coral,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTitleCard() {
    final story = _pkg!['story'] as Map<String, dynamic>? ?? {};
    return TCard(
      gradient: TGradients.hero,
      radius: 24,
      shadows: TShadows.glowTeal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            story['title'] as String? ?? '',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          if ((story['title_target_lang'] as String? ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              story['title_target_lang'] as String,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              _pill(_editable ? '⏳ Awaiting your review' : '✅ Approved'),
              const SizedBox(width: 8),
              _pill((_pkg!['language'] as Map?)?['locale'] as String? ?? ''),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // ── Facts ───────────────────────────────────────────────────────────

  Widget _buildFactsCard() {
    final facts = (_pkg!['moment_facts'] as List? ?? [])
        .map((f) => (f as Map)['text'] as String? ?? '')
        .where((t) => t.isNotEmpty)
        .toList();
    return TCard(
      radius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('📝 Moment Facts', 'What really happened',
              onEdit: _editable ? () => _showFactsDialog(facts) : null),
          const SizedBox(height: 10),
          ...facts.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  ',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: TColors.teal)),
                    Expanded(
                      child: Text(t,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  void _showFactsDialog(List<String> facts) {
    final controllers =
        facts.map((t) => TextEditingController(text: t)).toList();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Edit Facts',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 16),
                ...List.generate(controllers.length, (i) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F3E9),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: TextField(
                        controller: controllers[i],
                        maxLines: 2,
                        minLines: 1,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.all(12),
                          suffixIcon: controllers.length > 1
                              ? IconButton(
                                  icon: const Icon(Icons.close_rounded,
                                      size: 18, color: TColors.inkFaint),
                                  onPressed: () => setDialogState(
                                      () => controllers.removeAt(i)),
                                )
                              : null,
                        ),
                      ),
                    ),
                  );
                }),
                if (controllers.length < 5)
                  TextButton.icon(
                    onPressed: () => setDialogState(
                        () => controllers.add(TextEditingController())),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add fact'),
                  ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () {
                    final updated = controllers
                        .map((c) => c.text.trim())
                        .where((t) => t.isNotEmpty)
                        .toList();
                    if (updated.isEmpty) return;
                    Navigator.pop(ctx);
                    _saveFacts(updated);
                  },
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: TGradients.coral,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Center(
                      child: Text('Save Facts',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Learning plan ───────────────────────────────────────────────────

  Widget _buildLearningPlanCard() {
    final plan = _pkg!['learning_plan'] as Map<String, dynamic>?;
    if (plan == null) return const SizedBox.shrink();
    final words =
        (plan['target_words'] as List? ?? []).map((w) => '$w').toList();
    final level = plan['level'] as String? ?? 'emerging';

    return TCard(
      radius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('🎯 Learning Plan', 'Tap a word to swap it'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: words
                .map((w) => GestureDetector(
                      onTap: _editable ? () => _showSwapDialog(w) : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: TColors.mist,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(w,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: TColors.tealDeep)),
                            if (_editable) ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.swap_horiz_rounded,
                                  size: 15, color: TColors.tealDeep),
                            ],
                          ],
                        ),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: TColors.lemon,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              '💬 ${plan['target_phrase'] ?? ''}',
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 14),
          const Text('Difficulty',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: TColors.inkSoft)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _levels.map((l) {
              final selected = level == l.$1;
              return GestureDetector(
                onTap: _editable && !selected ? () => _setLevel(l.$1) : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color:
                        selected ? TColors.ink : const Color(0xFFF0EDE1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    l.$2,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : TColors.inkSoft,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Future<void> _showSwapDialog(String oldWord) async {
    final locale =
        (_pkg!['language'] as Map?)?['locale'] as String? ?? 'ta-SG';
    List<Map<String, dynamic>> bank = [];
    try {
      bank = await _api.getWordBank(locale);
    } catch (e) {
      _showError('Could not load word bank: $e');
      return;
    }
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Swap "$oldWord" for…',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: bank.map((e) {
                      final english = e['english'] as String? ?? '';
                      return GestureDetector(
                        onTap: () {
                          Navigator.pop(ctx);
                          _swapWord(oldWord, english);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: TColors.mist,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('${e['word'] ?? ''}',
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: TColors.tealDeep)),
                              Text('${e['romanised'] ?? ''} · $english',
                                  style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: TColors.inkSoft)),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel',
                    style: TextStyle(color: TColors.inkFaint)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Scenes / mission / handoff ──────────────────────────────────────

  Widget _buildScenes() {
    final scenes = (_pkg!['story'] as Map?)?['scenes'] as List? ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader('📖 Scenes', '${scenes.length} scenes'),
        const SizedBox(height: 10),
        ...scenes.map((s) {
          final scene = s as Map<String, dynamic>;
          final idx = scene['index'] as int? ?? 0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TCard(
              radius: 20,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: TColors.peach,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('Scene ${idx + 1}',
                            style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: TColors.coral)),
                      ),
                      const Spacer(),
                      if (_editable) _regenButton('scene', sceneIndex: idx),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(scene['narration'] as String? ?? '',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.4)),
                  if ((scene['narration_target_lang'] as String? ?? '')
                      .isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(scene['narration_target_lang'] as String,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: TColors.tealDeep,
                            height: 1.4)),
                  ],
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildMissionCard() {
    final mission = (_pkg!['story'] as Map?)?['room_mission'] as Map? ?? {};
    return TCard(
      radius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child:
                      _sectionHeader('🏠 Room Mission', 'Off-screen play')),
              if (_editable) _regenButton('mission'),
            ],
          ),
          const SizedBox(height: 8),
          Text(mission['instruction'] as String? ?? '',
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, height: 1.4)),
          if ((mission['instruction_target_lang'] as String? ?? '')
              .isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(mission['instruction_target_lang'] as String,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: TColors.tealDeep,
                    height: 1.4)),
          ],
        ],
      ),
    );
  }

  Widget _buildHandoffCard() {
    final handoff = (_pkg!['story'] as Map?)?['family_handoff'] as Map? ?? {};
    return TCard(
      radius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: _sectionHeader(
                      '👪 Family Handoff', 'Keep the talk going')),
              if (_editable) _regenButton('handoff'),
            ],
          ),
          const SizedBox(height: 8),
          Text(handoff['prompt'] as String? ?? '',
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, height: 1.4)),
          if ((handoff['response_suggestion'] as String? ?? '')
              .isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F3E9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('💡 ${handoff['response_suggestion']}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: TColors.inkSoft)),
            ),
          ],
        ],
      ),
    );
  }

  // ── Shared bits ─────────────────────────────────────────────────────

  Widget _sectionHeader(String title, String subtitle,
      {VoidCallback? onEdit}) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800)),
              Text(subtitle,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: TColors.inkFaint)),
            ],
          ),
        ),
        if (onEdit != null)
          GestureDetector(
            onTap: onEdit,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: TColors.mist,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.edit_rounded,
                      size: 14, color: TColors.tealDeep),
                  SizedBox(width: 4),
                  Text('Edit',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: TColors.tealDeep)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _regenButton(String component, {int sceneIndex = 0}) {
    final enabled = _regensLeft > 0 && !_busy;
    return GestureDetector(
      onTap: enabled
          ? () => _regenerate(component, sceneIndex: sceneIndex)
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: enabled ? TColors.mint : const Color(0xFFF0EDE1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _busy
                ? const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.refresh_rounded,
                    size: 14,
                    color: enabled
                        ? const Color(0xFF1F7B75)
                        : TColors.inkFaint),
            const SizedBox(width: 4),
            Text('Redo',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: enabled
                        ? const Color(0xFF1F7B75)
                        : TColors.inkFaint)),
          ],
        ),
      ),
    );
  }

  Widget _buildApproveButton() {
    return GestureDetector(
      onTap: _busy ? null : _approve,
      child: Container(
        height: 58,
        decoration: BoxDecoration(
          gradient: _busy ? null : TGradients.hero,
          color: _busy ? const Color(0xFFE8E4D8) : null,
          borderRadius: BorderRadius.circular(20),
          boxShadow: _busy ? null : TShadows.glowTeal,
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_rounded,
                  color: _busy ? TColors.inkFaint : Colors.white, size: 22),
              const SizedBox(width: 8),
              Text(
                'Approve Story',
                style: TextStyle(
                  color: _busy ? TColors.inkFaint : Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
