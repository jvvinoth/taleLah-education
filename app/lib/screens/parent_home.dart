/// Parent Home — moment capture + review generated packages.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import 'child_session.dart';

class ParentHomeScreen extends StatefulWidget {
  const ParentHomeScreen({super.key});

  @override
  State<ParentHomeScreen> createState() => _ParentHomeScreenState();
}

class _ParentHomeScreenState extends State<ParentHomeScreen> {
  final _textController = TextEditingController();
  String _selectedLocale = 'ta-SG';

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('TaleLah'),
        backgroundColor: const Color(0xFFFF6B35),
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Child profile section ────────────────────────────────
            _buildProfileSection(app),
            const SizedBox(height: 24),

            // ── Moment capture ──────────────────────────────────────
            _buildMomentCapture(app),
            const SizedBox(height: 24),

            // ── Progress / latest package ───────────────────────────
            if (app.isGenerating) _buildProgress(app),
            if (app.latestPackage != null && !app.isGenerating)
              _buildPackageCard(app),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileSection(AppState app) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.child_care, color: Color(0xFFFF6B35)),
                const SizedBox(width: 8),
                Text(
                  app.activeProfile?.alias ?? 'No child profile',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (app.activeProfile != null) ...[
              Text('Age: ${app.activeProfile!.ageBand}'),
              Text('Language: ${app.activeProfile!.targetLocale}'),
            ],
            const SizedBox(height: 12),
            if (app.profiles.isEmpty)
              ElevatedButton.icon(
                onPressed: () => _showCreateProfileDialog(app),
                icon: const Icon(Icons.add),
                label: const Text('Add Child Profile'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B35),
                  foregroundColor: Colors.white,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMomentCapture(AppState app) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.auto_stories, color: Color(0xFF2E86AB)),
                SizedBox(width: 8),
                Text(
                  'Capture a Moment',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'What did your child do today?',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _textController,
              maxLines: 3,
              maxLength: 500,
              decoration: InputDecoration(
                hintText: 'e.g. Arun saw a red train at the MRT station',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.grey[50],
              ),
            ),
            const SizedBox(height: 8),
            // Language selector
            Row(
              children: [
                const Text('Language: '),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _selectedLocale,
                  items: const [
                    DropdownMenuItem(
                        value: 'ta-SG', child: Text('🇸🇬 Tamil')),
                    DropdownMenuItem(
                        value: 'zh-SG', child: Text('🇸🇬 Chinese')),
                    DropdownMenuItem(
                        value: 'ms-SG', child: Text('🇸🇬 Malay')),
                  ],
                  onChanged: (v) => setState(() => _selectedLocale = v!),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: app.activeProfile == null || app.isGenerating
                    ? null
                    : () => _startGeneration(app),
                icon: const Icon(Icons.auto_awesome),
                label: Text(app.isGenerating
                    ? 'Generating...'
                    : 'Create Story ✨'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E86AB),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgress(AppState app) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: const Color(0xFFF0F7FF),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            LinearProgressIndicator(
              value: app.progressPct / 100,
              backgroundColor: Colors.grey[200],
              color: const Color(0xFF2E86AB),
              minHeight: 8,
            ),
            const SizedBox(height: 12),
            Text(
              app.generationStatus,
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              '${app.progressPct.toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF2E86AB),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPackageCard(AppState app) {
    final pkg = app.latestPackage!;
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: const Color(0xFFF0FFF0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    pkg.title.isEmpty ? 'Story Ready!' : pkg.title,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('${pkg.sceneCount} scenes • ${pkg.localeLabel}'),
            if (pkg.targetPhrase.isNotEmpty)
              Text('Target phrase: ${pkg.targetPhrase}'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _approveAndStart(app),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Approve & Play'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
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

  // ── Actions ─────────────────────────────────────────────────────────

  void _startGeneration(AppState app) {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please describe the moment')),
      );
      return;
    }
    app.captureAndGenerate(text: text, locale: _selectedLocale);
    _textController.clear();
  }

  Future<void> _approveAndStart(AppState app) async {
    await app.approvePackage();
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ChildSessionScreen()),
    );
  }

  void _showCreateProfileDialog(AppState app) {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Child'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Child\'s name',
                hintText: 'e.g. Arun',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.isNotEmpty) {
                await app.createProfile(
                  alias: nameCtrl.text,
                  ageBand: '5-6',
                  targetLocale: _selectedLocale,
                );
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}
