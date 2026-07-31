/// A playful "pick your adventure" swipe deck for child mode.
///
/// One big picture-card at a time: drag left/right to browse, swipe up (or tap
/// the card / the Pick button) to choose. Tapping ALWAYS works, so the story
/// flow never depends on gesture physics — swiping is a delight, not a gate.
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// One choosable card.
class AdventureOption {
  final String emoji;
  final String label;
  final Color accent;
  const AdventureOption({
    required this.emoji,
    required this.label,
    required this.accent,
  });
}

/// Parse the story's choice strings (e.g. "🔴 Red (சிவப்பு)") into cards.
List<AdventureOption> adventureOptionsFrom(List<String> choices) {
  const accents = [Color(0xFF1C857D), Color(0xFFDE6544), Color(0xFFE39A0C)];
  final out = <AdventureOption>[];
  for (var i = 0; i < choices.length; i++) {
    final raw = choices[i].trim();
    var emoji = '📖';
    var label = raw;
    final sp = raw.indexOf(' ');
    if (sp > 0) {
      final head = raw.substring(0, sp);
      // A leading pictograph (above the Latin/symbol range) is the emoji.
      if (head.isNotEmpty && head.runes.first > 0x2100) {
        emoji = head;
        label = raw.substring(sp + 1).trim();
      }
    }
    out.add(AdventureOption(
      emoji: emoji,
      label: label.isEmpty ? raw : label,
      accent: accents[i % accents.length],
    ));
  }
  return out;
}

class AdventureDeck extends StatefulWidget {
  final List<AdventureOption> options;
  final ValueChanged<int> onPick;
  final double cardHeight;

  const AdventureDeck({
    super.key,
    required this.options,
    required this.onPick,
    this.cardHeight = 300,
  });

  @override
  State<AdventureDeck> createState() => _AdventureDeckState();
}

class _AdventureDeckState extends State<AdventureDeck>
    with SingleTickerProviderStateMixin {
  late List<int> _order;
  Offset _drag = Offset.zero;
  late final AnimationController _c;
  Offset _from = Offset.zero;
  Offset _to = Offset.zero;
  String _mode = ''; // browse · pick · snap

  @override
  void initState() {
    super.initState();
    _order = List<int>.generate(widget.options.length, (i) => i);
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    )
      ..addListener(() {
        setState(() {
          _drag = Offset.lerp(_from, _to, Curves.easeOut.transform(_c.value))!;
        });
      })
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _settle();
      });
  }

  @override
  void didUpdateWidget(covariant AdventureDeck old) {
    super.didUpdateWidget(old);
    // New scene, new deck — never let a stale order index an options list
    // of a different length.
    if (old.options.length != widget.options.length) {
      _order = List<int>.generate(widget.options.length, (i) => i);
      _drag = Offset.zero;
      _mode = '';
      _c.reset();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _settle() {
    if (_mode == 'browse') {
      _order.add(_order.removeAt(0)); // front → back
    } else if (_mode == 'pick') {
      final chosen = _order.first;
      _drag = Offset.zero;
      _mode = '';
      _c.reset();
      widget.onPick(chosen);
      return;
    }
    setState(() => _drag = Offset.zero);
    _mode = '';
    _c.reset();
  }

  void _fling(String mode, Offset to) {
    _mode = mode;
    _from = _drag;
    _to = to;
    _c.forward(from: 0);
  }

  void _release(Size size) {
    final dx = _drag.dx, dy = _drag.dy;
    if (dy < -80 && dy.abs() >= dx.abs()) {
      _fling('pick', Offset(dx, -size.height));
    } else if (dx.abs() > 80) {
      _fling('browse', Offset(dx.sign * size.width * 1.4, dy));
    } else {
      _fling('snap', Offset.zero);
    }
  }

  void _pickFront() => widget.onPick(_order.first);

  @override
  Widget build(BuildContext context) {
    final opts = widget.options;
    return Column(
      children: [
        SizedBox(
          height: widget.cardHeight,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              // Paint back-to-front so the front card is on top.
              final stack = <Widget>[];
              for (final i in _order.reversed) {
                final slot = _order.indexOf(i);
                stack.add(_card(opts[i], slot, size));
              }
              return Stack(alignment: Alignment.center, children: stack);
            },
          ),
        ),
        const SizedBox(height: 14),
        _controls(),
        const SizedBox(height: 10),
        _dots(),
      ],
    );
  }

  Widget _card(AdventureOption o, int slot, Size size) {
    final isFront = slot == 0;
    final rot = isFront ? _drag.dx / 900 : 0.0;
    final offset = isFront ? _drag : Offset(0, -14.0 * slot);
    final scale = isFront ? 1.0 : (slot == 1 ? 0.93 : 0.86);
    final opacity = isFront ? 1.0 : (slot == 1 ? 0.6 : 0.32);

    final card = Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: offset,
        child: Transform.rotate(
          angle: rot,
          child: Transform.scale(
            scale: scale,
            child: _cardFace(o, isFront),
          ),
        ),
      ),
    );

    if (!isFront) return IgnorePointer(child: card);

    return GestureDetector(
      onTap: _pickFront,
      onPanStart: (_) {
        if (_c.isAnimating) _c.stop();
      },
      onPanUpdate: (d) => setState(() => _drag += d.delta),
      onPanEnd: (_) => _release(size),
      child: card,
    );
  }

  Widget _cardFace(AdventureOption o, bool isFront) {
    final showPick = isFront && _drag.dy < -30 && _drag.dy.abs() >= _drag.dx.abs();
    final showBrowse = isFront && _drag.dx.abs() > 30 && !showPick;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: TShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(
            flex: 6,
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          o.accent.withValues(alpha: 0.20),
                          o.accent.withValues(alpha: 0.05),
                        ],
                      ),
                    ),
                    child: Center(
                      child: Text(o.emoji, style: const TextStyle(fontSize: 78)),
                    ),
                  ),
                ),
                if (showPick)
                  _stamp('PICK ⬆', o.accent, Alignment.center, -0.08),
                if (showBrowse)
                  _stamp(_drag.dx > 0 ? 'NEXT ›' : '‹ BACK', TColors.teal,
                      Alignment.topRight, 0.18),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Center(
                child: Text(
                  o.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    height: 1.25,
                    fontWeight: FontWeight.w800,
                    color: TColors.ink,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stamp(String text, Color color, Alignment align, double angle) {
    return Align(
      alignment: align,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Transform.rotate(
          angle: angle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color, width: 3),
            ),
            child: Text(
              text,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _controls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _round(Icons.chevron_left_rounded, () {
          if (_c.isAnimating) return;
          final s = context.size ?? const Size(300, 300);
          _fling('browse', Offset(-s.width, 0));
        }),
        const SizedBox(width: 12),
        Flexible(
          child: GestureDetector(
            onTap: _pickFront,
            child: Container(
              height: 58,
              padding: const EdgeInsets.symmetric(horizontal: 22),
              decoration: BoxDecoration(
                color: TColors.coral,
                borderRadius: BorderRadius.circular(30),
                boxShadow: TShadows.glowCoral,
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text('Pick this!',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800)),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        _round(Icons.chevron_right_rounded, () {
          if (_c.isAnimating) return;
          final s = context.size ?? const Size(300, 300);
          _fling('browse', Offset(s.width, 0));
        }),
      ],
    );
  }

  Widget _round(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: TShadows.card,
        ),
        child: Icon(icon, color: TColors.inkSoft, size: 26),
      ),
    );
  }

  Widget _dots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < widget.options.length; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: _order.first == i ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: _order.first == i
                  ? TColors.coral
                  : TColors.inkFaint.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}
