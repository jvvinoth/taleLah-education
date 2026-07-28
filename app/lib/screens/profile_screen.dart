/// Profile — child profiles, active selection, and language at a glance.
/// F10: north-star progress (family moments / week) + saved memories with
/// a real delete — no scores, no streaks, no proficiency claims.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/story_package.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  void initState() {
    super.initState();
    // F10 — non-fatal; the screen renders fine with zero data.
    context.read<AppState>().refreshProgress();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(gradient: TGradients.page),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, topPad + 12, 20, bottomPad + 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: TShadows.card,
                      ),
                      child: const Icon(Icons.arrow_back_rounded,
                          color: TColors.ink, size: 22),
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Text(
                    'Profile',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: TColors.ink,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Children
              const Text(
                'Your children',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: TColors.inkSoft,
                ),
              ),
              const SizedBox(height: 12),
              if (app.profiles.isEmpty)
                TCard(
                  radius: 26,
                  child: Column(
                    children: const [
                      Text('👶', style: TextStyle(fontSize: 40)),
                      SizedBox(height: 10),
                      Text(
                        'No child profile yet',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: TColors.ink,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Add your child below to get started',
                        style:
                            TextStyle(fontSize: 12, color: TColors.inkFaint),
                      ),
                    ],
                  ),
                )
              else
                ...app.profiles.map((p) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildProfileCard(context, app, p),
                    )),
              const SizedBox(height: 8),

              // Add child
              GestureDetector(
                onTap: () => _showAddChildDialog(context, app),
                child: Container(
                  height: 54,
                  decoration: BoxDecoration(
                    gradient: TGradients.coral,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: TShadows.glowCoral,
                  ),
                  child: const Center(
                    child: Text(
                      '＋  Add a child',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // F10 — the north-star metric, and nothing else (hard rule 6)
              TCard(
                radius: 26,
                gradient: TGradients.night,
                shadows: TShadows.glowTeal,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'THIS WEEK',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.white54,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${app.familyMomentsThisWeek}',
                          style: const TextStyle(
                            fontSize: 44,
                            height: 1.0,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(bottom: 4),
                            child: Text(
                              'family language moments\ncompleted together',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.white70,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // F10 — saved memories (consent-gated) with delete
              if (app.memories.isNotEmpty) ...[
                const Text(
                  'Saved memories',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: TColors.inkSoft,
                  ),
                ),
                const SizedBox(height: 12),
                ...app.memories.map((m) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TCard(
                        radius: 22,
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const Text('📖',
                                style: TextStyle(fontSize: 22)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (m['title'] as String?)
                                                ?.isNotEmpty ==
                                            true
                                        ? m['title'] as String
                                        : 'A story you shared',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: TColors.ink,
                                    ),
                                  ),
                                  if ((m['target_phrase'] as String?)
                                          ?.isNotEmpty ==
                                      true)
                                    Text(
                                      m['target_phrase'] as String,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: TColors.inkFaint,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: () => _confirmDeleteMemory(
                                  context, app, m['id'] as String? ?? ''),
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: TColors.blush,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                    Icons.delete_outline_rounded,
                                    color: TColors.coral,
                                    size: 20),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )),
                const SizedBox(height: 18),
              ],

              // About
              TCard(
                radius: 26,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Row(
                      children: [
                        TMascot(size: 40),
                        SizedBox(width: 12),
                        Text(
                          'TaleLah',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: TColors.ink,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Turns your child\'s real daily moments into 5-minute '
                      'interactive mother-tongue stories — with a parent '
                      'approval gate before every session.',
                      style: TextStyle(
                        fontSize: 13,
                        color: TColors.inkSoft,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDeleteMemory(
      BuildContext context, AppState app, String memoryId) {
    if (memoryId.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24)),
        title: const Text('Delete this memory?',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        content: const Text(
            'The memory and its story audio are removed. This cannot be undone.',
            style: TextStyle(fontSize: 13, color: TColors.inkSoft)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Keep it',
                style: TextStyle(color: TColors.inkFaint)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              app.deleteMemory(memoryId);
            },
            child: const Text('Delete',
                style: TextStyle(
                    color: TColors.coral, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard(
      BuildContext context, AppState app, ChildProfile p) {
    final active = app.activeProfile?.id == p.id;
    return GestureDetector(
      onTap: () => app.selectProfile(p),
      child: TCard(
        radius: 26,
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: active ? TColors.mint : TColors.sky,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Center(
                child: Text('🧒', style: TextStyle(fontSize: 24)),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.alias,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: TColors.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Age ${p.ageBand} · ${_localeName(p.targetLocale)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: TColors.inkFaint,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (active)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: TColors.mint,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'ACTIVE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: TColors.tealDeep,
                  ),
                ),
              )
            else
              const Icon(Icons.radio_button_unchecked_rounded,
                  color: TColors.inkFaint, size: 20),
          ],
        ),
      ),
    );
  }

  String _localeName(String locale) {
    switch (locale) {
      case 'ta-SG':
        return 'Tamil';
      case 'zh-SG':
        return 'Chinese';
      case 'ms-SG':
        return 'Malay';
      default:
        return locale;
    }
  }

  void _showAddChildDialog(BuildContext context, AppState app) {
    final nameCtrl = TextEditingController();
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
              const Text('👶',
                  style: TextStyle(fontSize: 40), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              const Text(
                'Add Your Child',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 20),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F3E9),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: TextField(
                  controller: nameCtrl,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  decoration: const InputDecoration(
                    hintText: "Child's name (e.g. Arun)",
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(16),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () async {
                  if (nameCtrl.text.trim().isEmpty) return;
                  await app.createProfile(
                    alias: nameCtrl.text.trim(),
                    ageBand: '5-6',
                    targetLocale: app.activeProfile?.targetLocale ?? 'ta-SG',
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Container(
                  height: 54,
                  decoration: BoxDecoration(
                    gradient: TGradients.coral,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Center(
                    child: Text(
                      'Add Child',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
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
}
