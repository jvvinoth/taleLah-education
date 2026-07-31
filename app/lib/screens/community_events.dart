/// Community Events — language-based SG kids programmes curated by the
/// Community Scout agent. Filter by language, register via the organizer.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/community_event.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';

class CommunityEventsScreen extends StatefulWidget {
  const CommunityEventsScreen({super.key});

  @override
  State<CommunityEventsScreen> createState() => _CommunityEventsScreenState();
}

class _CommunityEventsScreenState extends State<CommunityEventsScreen> {
  static const _filters = [
    ('', 'All'),
    ('ta', 'Tamil'),
    ('zh', 'Chinese'),
    ('ms', 'Malay'),
  ];

  String _language = '';

  @override
  void initState() {
    super.initState();
    // Default the filter to the active child's home language so the most
    // relevant events show up first.
    final app = context.read<AppState>();
    final home = app.activeProfile?.homeLanguage ?? '';
    if (_filters.any((f) => f.$1 == home && home.isNotEmpty)) {
      _language = home;
    }
    app.loadEvents(language: _language);
  }

  void _setFilter(String language) {
    setState(() => _language = language);
    context.read<AppState>().loadEvents(language: language);
  }

  Future<void> _register(CommunityEvent event) async {
    final url = Uri.tryParse(event.registrationUrl);
    if (url == null) return;
    final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't open the registration page")),
      );
    }
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
          padding: EdgeInsets.fromLTRB(20, topPad + 12, 20, bottomPad + 120),
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
                        shape: BoxShape.circle,
                        boxShadow: TShadows.card,
                      ),
                      child: const Icon(Icons.arrow_back_rounded,
                          color: TColors.ink, size: 20),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const TMascot(size: 52),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Community Events',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: TColors.ink,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Mother-tongue fun around Singapore',
                          style: TextStyle(
                            fontSize: 13,
                            color: TColors.inkFaint,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Language filter chips
              Row(
                children: _filters.map((f) {
                  final selected = _language == f.$1;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => _setFilter(f.$1),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color:
                              selected ? TColors.ink : const Color(0xFFF0EDE1),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Text(
                          f.$2,
                          style: TextStyle(
                            color: selected ? Colors.white : TColors.inkSoft,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              if (app.eventsLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 60),
                  child: Center(
                    child: CircularProgressIndicator(color: TColors.teal),
                  ),
                )
              else if (app.eventsError != null)
                _buildEmptyState(
                  emoji: '😔',
                  title: "Can't load events right now",
                  subtitle: app.eventsError!,
                  retry: true,
                )
              else if (app.events.isEmpty)
                _buildEmptyState(
                  emoji: '🎈',
                  title: 'No upcoming events here yet',
                  subtitle:
                      'Try another language filter — Mina is always scouting for new ones!',
                )
              else
                ...app.events.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _buildEventCard(e),
                    )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required String emoji,
    required String title,
    required String subtitle,
    bool retry = false,
  }) {
    return TCard(
      radius: 26,
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          const TMascot(size: 72),
          const SizedBox(height: 12),
          Text(emoji, style: const TextStyle(fontSize: 30)),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: TColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              color: TColors.inkFaint,
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
          if (retry) ...[
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => _setFilter(_language),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: TColors.mist,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  'Try again',
                  style: TextStyle(
                    color: TColors.tealDeep,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEventCard(CommunityEvent e) {
    return TCard(
      radius: 26,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _dateBadge(e.date),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: TColors.ink,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      e.organizer,
                      style: const TextStyle(
                        fontSize: 12,
                        color: TColors.inkFaint,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (e.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              e.description,
              style: const TextStyle(
                fontSize: 13,
                color: TColors.inkSoft,
                fontWeight: FontWeight.w500,
                height: 1.5,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _pill('🗣 ${_languageName(e.language)}', TColors.mist,
                  TColors.tealDeep),
              if (e.ageRange.isNotEmpty)
                _pill('👧 Ages ${e.ageRange}', TColors.lemon,
                    TColors.goldDeep),
              if (e.isFree) _pill('FREE', TColors.mint, TColors.tealDeep),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.place_rounded,
                  color: TColors.inkFaint, size: 16),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  e.time.isNotEmpty ? '${e.venue} · ${e.time}' : e.venue,
                  style: const TextStyle(
                    fontSize: 12,
                    color: TColors.inkFaint,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (e.registrationUrl.isNotEmpty) ...[
            const SizedBox(height: 14),
            GestureDetector(
              onTap: () => _register(e),
              child: Container(
                height: 46,
                decoration: BoxDecoration(
                  gradient: TGradients.coral,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: TShadows.glowCoral,
                ),
                child: const Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.open_in_new_rounded,
                          color: Colors.white, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'Register',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _dateBadge(String isoDate) {
    final parsed = DateTime.tryParse(isoDate);
    const months = [
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
    ];
    return Container(
      width: 54,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: TColors.sky,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            parsed != null ? '${parsed.day}' : '?',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: TColors.ink,
              height: 1.1,
            ),
          ),
          Text(
            parsed != null ? months[parsed.month - 1] : '',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: TColors.inkFaint,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: fg),
      ),
    );
  }

  String _languageName(String code) {
    switch (code) {
      case 'ta':
        return 'Tamil';
      case 'zh':
        return 'Chinese';
      case 'ms':
        return 'Malay';
      default:
        return 'English';
    }
  }
}
