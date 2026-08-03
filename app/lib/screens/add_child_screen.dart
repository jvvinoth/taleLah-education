/// Add / edit a child profile — name, age, home language and photo.
/// Replaces the old name-only dialogs; the photo uploads after create.
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../models/story_package.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';

class AddChildScreen extends StatefulWidget {
  const AddChildScreen({super.key, this.existing});

  /// When set, the screen edits this profile instead of creating one.
  final ChildProfile? existing;

  @override
  State<AddChildScreen> createState() => _AddChildScreenState();
}

class _AddChildScreenState extends State<AddChildScreen> {
  static const _ages = ['4', '5', '6', '7', '8'];
  static const _languages = [
    ('ta', 'தமிழ்', 'Tamil', 'ta-SG'),
    ('zh', '中文', 'Chinese', 'zh-SG'),
    ('ms', 'Melayu', 'Malay', 'ms-SG'),
    ('en', 'ABC', 'English', 'ta-SG'),
  ];

  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.alias ?? '');
  late String? _age = _ages.contains(widget.existing?.ageBand)
      ? widget.existing!.ageBand
      : null;
  late String _language = widget.existing?.homeLanguage ?? 'ta';
  Uint8List? _photoBytes;
  String _photoType = 'image/jpeg';
  bool _busy = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        imageQuality: 85,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) {
        setState(() => _error = 'Photo too large — max 5 MB');
        return;
      }
      setState(() {
        _photoBytes = bytes;
        _photoType = picked.mimeType ?? 'image/jpeg';
        _error = null;
      });
    } catch (_) {
      setState(() => _error = "Couldn't read that photo — try another one");
    }
  }

  Future<void> _save(AppState app) async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = "What's your child's name?");
      return;
    }
    if (!_isEdit && _age == null) {
      setState(() => _error = 'Pick your child\'s age');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final lang = _languages.firstWhere((l) => l.$1 == _language);
    try {
      String profileId;
      if (_isEdit) {
        profileId = widget.existing!.id;
        await app.updateProfile(
          profileId,
          alias: name,
          ageBand: _age ?? widget.existing!.ageBand,
          homeLanguage: _language,
          // Must travel with homeLanguage: this is what the story is actually
          // written in. Leaving it behind meant switching a child from Tamil
          // to Chinese kept generating Tamil books forever.
          targetLocale: lang.$4,
        );
      } else {
        final profile = await app.createProfile(
          alias: name,
          ageBand: _age!,
          targetLocale: lang.$4,
          homeLanguage: _language,
        );
        profileId = profile.id;
      }
      if (_photoBytes != null) {
        await app.uploadProfilePhoto(
          profileId: profileId,
          imageBytes: _photoBytes!,
          contentType: _photoType,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = "Couldn't save right now — please try again";
      });
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
                  Text(
                    _isEdit ? 'Edit profile' : 'Add your child',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: TColors.ink,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              TCard(
                radius: 26,
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Photo picker with circular preview
                    Center(child: _buildPhotoPicker(app)),
                    const SizedBox(height: 6),
                    const Center(
                      child: Text(
                        'Tap to add a photo (optional)',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: TColors.inkFaint,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: TColors.blush,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: TColors.coralDark,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    _label('NAME'),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F3E9),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: TextField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        decoration: const InputDecoration(
                          hintText: "Child's name (e.g. Arun)",
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.all(16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _label('AGE'),
                    const SizedBox(height: 8),
                    Row(
                      children: _ages.map((a) {
                        final selected = _age == a;
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                                right: a == _ages.last ? 0 : 8),
                            child: GestureDetector(
                              onTap: () => setState(() => _age = a),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                height: 46,
                                decoration: BoxDecoration(
                                  color: selected
                                      ? TColors.ink
                                      : const Color(0xFFF0EDE1),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Center(
                                  child: Text(
                                    a,
                                    style: TextStyle(
                                      color: selected
                                          ? Colors.white
                                          : TColors.inkSoft,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),
                    _label('HOME LANGUAGE'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _languages.map((l) {
                        final selected = _language == l.$1;
                        return GestureDetector(
                          onTap: () => setState(() => _language = l.$1),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: selected
                                  ? TColors.ink
                                  : const Color(0xFFF0EDE1),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  l.$2,
                                  style: TextStyle(
                                    color: selected
                                        ? Colors.white
                                        : TColors.inkSoft,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  l.$3,
                                  style: TextStyle(
                                    color: selected
                                        ? Colors.white.withValues(alpha: 0.6)
                                        : TColors.inkFaint,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                    GestureDetector(
                      onTap: _busy ? null : () => _save(app),
                      child: Container(
                        height: 54,
                        decoration: BoxDecoration(
                          gradient: TGradients.coral,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: TShadows.glowCoral,
                        ),
                        child: Center(
                          child: _busy
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : Text(
                                  _isEdit ? 'Save changes' : 'Add child',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        ),
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

  Widget _buildPhotoPicker(AppState app) {
    final existingUrl = widget.existing?.photoUrl;
    ImageProvider? image;
    if (_photoBytes != null) {
      image = MemoryImage(_photoBytes!);
    } else if (existingUrl != null && existingUrl.isNotEmpty) {
      image = NetworkImage(app.api.photoUrl(existingUrl));
    }
    return GestureDetector(
      onTap: _pickPhoto,
      child: Stack(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: TColors.sky,
              shape: BoxShape.circle,
              image: image != null
                  ? DecorationImage(image: image, fit: BoxFit.cover)
                  : null,
            ),
            child: image == null
                ? const Center(
                    child: Text('🧒', style: TextStyle(fontSize: 40)))
                : null,
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: TGradients.coral,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(Icons.camera_alt_rounded,
                  color: Colors.white, size: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        color: TColors.inkFaint,
        letterSpacing: 1.2,
      ),
    );
  }
}
