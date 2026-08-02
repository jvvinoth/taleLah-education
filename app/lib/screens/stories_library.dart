/// Stories library — every story package, newest first.
/// Tap a card to review (awaiting_parent) or replay (approved/completed).
/// Built-in sample stories appear at the top when the user has fewer than
/// three personal stories, so the screen is never truly empty.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/sample_stories.dart';
import '../models/story_package.dart';
import '../providers/app_state.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';
import 'child_session.dart';
import 'parent_review.dart';

class StoriesLibraryScreen extends StatefulWidget {
  const StoriesLibraryScreen({super.key});

  @override
  State<StoriesLibraryScreen> createState() => _StoriesLibraryScreenState();
}

class _StoriesLibraryScreenState extends State<StoriesLibraryScreen> {
  ApiClient get _api => context.read<AppState>().api;
  List<StoryPackageSummary> _stories = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final stories = await _api.listPackages();
      if (!mounted) return;
      setState(() {
        _stories = stories;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load stories';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    // Show sample stories when the user has fewer than 3 personal stories.
    final showSamples = !_loading && _stories.length < 3;

    return Container(
      decoration: const BoxDecoration(gradient: TGradients.page),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: RefreshIndicator(
          color: TColors.teal,
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(20, topPad + 12, 20, bottomPad + 24),
            children: [
              _buildTopBar(),
              const SizedBox(height: 24),
              if (showSamples) ...[
                _buildSampleStoriesSection(app),
                const SizedBox(height: 28),
              ],
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: Center(
                    child: CircularProgressIndicator(color: TColors.teal),
                  ),
                )
              else if (_error != null)
                _buildEmpty('😕', _error!, 'Pull down to try again')
              else if (_stories.isEmpty)
                _buildEmpty(
                    '🐦',
                    'No stories yet!',
                    'Try a sample story above, or create your own\nfrom the Home screen')
              else
                ..._stories.map((s) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _buildStoryCard(s),
                    )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Row(
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
          'Story Library',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: TColors.ink,
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: _load,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: TShadows.card,
            ),
            child: const Icon(Icons.refresh_rounded,
                color: TColors.teal, size: 22),
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty(String emoji, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 52)),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: TColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: TColors.inkFaint),
          ),
        ],
      ),
    );
  }

  // ── Sample stories section ─────────────────────────────────────────

  Widget _buildSampleStoriesSection(AppState app) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Try a Story Right Now',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: TColors.ink,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'No waiting — tap and read together',
          style: TextStyle(
            fontSize: 12,
            color: TColors.inkFaint,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 156,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: sampleStoryList.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) =>
                _buildSampleCard(app, sampleStoryList[i]),
          ),
        ),
      ],
    );
  }

  Widget _buildSampleCard(AppState app, ApprovedStory story) {
    final (emoji, label, gradient) = _sampleMeta(story.locale);
    return GestureDetector(
      onTap: () => _openSampleStory(app, story),
      child: Container(
        width: 160,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(24),
          boxShadow: TShadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 32)),
            const SizedBox(height: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  story.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$label · 4 scenes',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  (String, String, Gradient) _sampleMeta(String locale) {
    switch (locale) {
      case 'ta-SG':
        return (
          '🕊️',
          'Tamil',
          const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF6C5CE7), Color(0xFF8B7CF6)],
          ),
        );
      case 'zh-SG':
        return (
          '🛝',
          'Chinese',
          const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE17055), Color(0xFFFDCB6E)],
          ),
        );
      case 'ms-SG':
        return (
          '👵',
          'Malay',
          const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF00B894), Color(0xFF55EFC4)],
          ),
        );
      default:
        return (
          '📖',
          'Story',
          const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF636E72), Color(0xFFB2BEC3)],
          ),
        );
    }
  }

  void _openSampleStory(AppState app, ApprovedStory story) {
    app.loadSampleStory(story);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ChildSessionScreen()),
    );
  }

  // ── Story card ──────────────────────────────────────────────────────

  Widget _buildStoryCard(StoryPackageSummary s) {
    final (chipBg, chipFg, chipLabel) = _statusChip(s.status);
    return GestureDetector(
      onTap: () => _openStory(s),
      child: TCard(
        radius: 26,
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: TColors.mist,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Center(
                child: Text(_statusEmoji(s.status),
                    style: const TextStyle(fontSize: 24)),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.title.isEmpty ? 'Story in progress…' : s.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: TColors.ink,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: chipBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          chipLabel,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: chipFg,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${s.localeLabel} · ${s.sceneCount} scenes',
                        style: const TextStyle(
                          fontSize: 11,
                          color: TColors.inkFaint,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: TColors.inkFaint, size: 24),
          ],
        ),
      ),
    );
  }

  String _statusEmoji(String status) {
    switch (status) {
      case 'awaiting_parent':
        return '👀';
      case 'approved':
      case 'in_session':
        return '🎧';
      case 'completed':
        return '⭐';
      case 'needs_clarification':
        return '🤔';
      case 'rejected':
        return '🚫';
      default:
        return '✨';
    }
  }

  (Color, Color, String) _statusChip(String status) {
    switch (status) {
      case 'awaiting_parent':
        return (TColors.lemon, TColors.goldDeep, 'REVIEW');
      case 'approved':
      case 'in_session':
        return (TColors.mint, TColors.tealDeep, 'READY TO PLAY');
      case 'completed':
        return (TColors.mist, TColors.tealDeep, 'COMPLETED');
      case 'needs_clarification':
        return (TColors.peach, TColors.coralDark, 'NEEDS ANSWER');
      case 'rejected':
        return (TColors.blush, TColors.coralDark, 'REJECTED');
      default:
        return (TColors.sky, TColors.inkSoft, 'GENERATING');
    }
  }

  // ── Actions ─────────────────────────────────────────────────────────

  Future<void> _openStory(StoryPackageSummary s) async {
    final app = context.read<AppState>();
    switch (s.status) {
      case 'awaiting_parent':
        final approved = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => ParentReviewScreen(packageId: s.id),
          ),
        );
        if (approved == true && mounted) {
          await app.loadApprovedStory(s.id);
          if (!mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ChildSessionScreen()),
          );
        }
        _load();
        break;
      case 'approved':
      case 'in_session':
      case 'completed':
        final ok = await app.loadApprovedStory(s.id);
        if (!mounted) return;
        if (ok) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ChildSessionScreen()),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not load this story')),
          );
        }
        break;
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('This story is still being created ✨')),
        );
    }
  }
}
