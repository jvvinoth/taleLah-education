/// Live hands-free microphone — the 1-1 conversation engine (F5 + F6).
///
/// Streams raw PCM16 from the mic, computes a smoothed loudness level that
/// drives voice-reactive UI, and detects end-of-utterance by trailing
/// silence — no stop button, no "tap to send". The collected PCM is wrapped
/// into a WAV for the existing batch endpoints, so the privacy contract
/// (AC-07 — raw audio discarded server-side) is completely unchanged.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';

/// Result of one hands-free listening pass.
class LiveMicResult {
  final Uint8List wavBytes;
  final bool heardSpeech;
  const LiveMicResult(this.wavBytes, {required this.heardSpeech});
}

/// One-utterance voice-activity listener over the `record` PCM stream.
///
/// Lifecycle per turn: [listen] → speaker talks (rings react via [level]) →
/// trailing silence closes the turn automatically → WAV bytes returned.
class LiveMic {
  static const int sampleRate = 16000;

  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _sub;
  StreamSubscription<Amplitude>? _ampSub;
  Completer<LiveMicResult?>? _done;
  final BytesBuilder _pcm = BytesBuilder(copy: false);

  /// Smoothed 0..1 loudness — drives the voice-reactive aura.
  final ValueNotifier<double> level = ValueNotifier(0);

  /// Flips true the first time the speaker is clearly heard this turn.
  final ValueNotifier<bool> heardSpeech = ValueNotifier(false);

  bool get isListening => _done != null && !_done!.isCompleted;

  Future<bool> hasPermission() async {
    try {
      return await _recorder.hasPermission();
    } catch (_) {
      return false;
    }
  }

  /// Listen until [silenceAfter] of quiet follows speech, [maxDuration]
  /// caps the utterance, or nothing is heard for [noSpeechTimeout].
  /// Returns null when cancelled or the mic stream is unavailable.
  Future<LiveMicResult?> listen({
    Duration maxDuration = const Duration(seconds: 6),
    Duration silenceAfter = const Duration(milliseconds: 900),
    Duration noSpeechTimeout = const Duration(seconds: 8),
  }) async {
    await cancel();
    final done = Completer<LiveMicResult?>();
    _done = done;
    _pcm.clear();
    level.value = 0;
    heardSpeech.value = false;

    Stream<Uint8List> stream;
    try {
      stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: sampleRate,
          numChannels: 1,
          echoCancel: true,
          noiseSuppress: true,
        ),
      );
    } catch (_) {
      // Web (and platforms without raw-PCM streaming) — fall back to a
      // file-based recording that yields opus/webm bytes the backend sniffs.
      // This is what makes voice capture work in the browser / PWA.
      return _listenFile(
        done,
        maxDuration: maxDuration,
        silenceAfter: silenceAfter,
        noSpeechTimeout: noSpeechTimeout,
      );
    }

    final startedAt = DateTime.now();
    var lastLoudAt = startedAt;
    var noiseFloor = 0.0;
    var calibrationChunks = 0;
    var loudStreak = 0;
    var speechStarted = false;

    void finish() {
      if (done.isCompleted) return;
      final heard = speechStarted;
      final wav = _wav(_pcm.takeBytes());
      _teardown();
      done.complete(LiveMicResult(wav, heardSpeech: heard));
    }

    _sub = stream.listen((chunk) {
      if (done.isCompleted) return;
      final rms = _rms(chunk);
      _pcm.add(chunk);

      // UI level — normalized + smoothed so the aura feels alive, not jittery.
      final display = (rms * 9).clamp(0.0, 1.0);
      level.value = level.value * 0.6 + display * 0.4;

      // First ~350 ms calibrates the room's noise floor.
      final now = DateTime.now();
      final elapsed = now.difference(startedAt);
      if (elapsed.inMilliseconds < 350) {
        calibrationChunks++;
        noiseFloor += (rms - noiseFloor) / calibrationChunks;
        return;
      }
      final threshold = math.max(noiseFloor * 3.0, 0.012);

      if (rms > threshold) {
        loudStreak++;
        lastLoudAt = now;
        if (!speechStarted && loudStreak >= 2) {
          speechStarted = true;
          heardSpeech.value = true;
        }
      } else {
        loudStreak = 0;
      }

      if (elapsed >= maxDuration) {
        finish();
      } else if (speechStarted &&
          now.difference(lastLoudAt) >= silenceAfter) {
        finish();
      } else if (!speechStarted && elapsed >= noSpeechTimeout) {
        finish();
      }
    }, onDone: finish, onError: (_) => finish());

    return done.future;
  }

  /// Web / no-PCM-stream fallback: record to a file (opus), drive the aura
  /// from amplitude, and end on trailing silence — same UX, browser-safe.
  Future<LiveMicResult?> _listenFile(
    Completer<LiveMicResult?> done, {
    required Duration maxDuration,
    required Duration silenceAfter,
    required Duration noSpeechTimeout,
  }) async {
    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.opus,
          numChannels: 1,
          echoCancel: true,
          noiseSuppress: true,
        ),
        path: '',
      );
    } catch (_) {
      _done = null;
      if (!done.isCompleted) done.complete(null);
      return done.future;
    }

    final startedAt = DateTime.now();
    var lastLoudAt = startedAt;
    var speechStarted = false;

    Future<void> finish() async {
      if (done.isCompleted) return;
      _ampSub?.cancel();
      _ampSub = null;
      String? url;
      try {
        url = await _recorder.stop();
      } catch (_) {
        url = null;
      }
      var bytes = Uint8List(0);
      if (url != null && url.isNotEmpty) {
        try {
          bytes = await http.readBytes(Uri.parse(url));
        } catch (_) {}
      }
      level.value = 0;
      _done = null;
      done.complete(LiveMicResult(bytes, heardSpeech: speechStarted));
    }

    _ampSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 120))
        .listen((amp) {
      if (done.isCompleted) return;
      // dBFS (~ -60..0) → 0..1 for the aura + a simple voice-activity gate.
      final norm = ((amp.current + 45) / 45).clamp(0.0, 1.0);
      level.value = level.value * 0.6 + norm * 0.4;
      final now = DateTime.now();
      final elapsed = now.difference(startedAt);
      if (norm > 0.2) {
        lastLoudAt = now;
        if (!speechStarted) {
          speechStarted = true;
          heardSpeech.value = true;
        }
      }
      if (elapsed >= maxDuration) {
        finish();
      } else if (speechStarted && now.difference(lastLoudAt) >= silenceAfter) {
        finish();
      } else if (!speechStarted && elapsed >= noSpeechTimeout) {
        finish();
      }
    }, onError: (_) => finish());

    return done.future;
  }

  /// Abort the current pass — the pending [listen] resolves to null.
  Future<void> cancel() async {
    final pending = _done;
    _teardown();
    _pcm.clear();
    if (pending != null && !pending.isCompleted) {
      pending.complete(null);
    }
  }

  void _teardown() {
    _sub?.cancel();
    _sub = null;
    _ampSub?.cancel();
    _ampSub = null;
    _done = null;
    _recorder.stop().catchError((_) => null);
    level.value = 0;
  }

  void dispose() {
    cancel();
    _recorder.dispose();
    level.dispose();
    heardSpeech.dispose();
  }

  double _rms(Uint8List chunk) {
    if (chunk.length < 2) return 0;
    final samples = chunk.buffer
        .asInt16List(chunk.offsetInBytes, chunk.length ~/ 2);
    var sum = 0.0;
    for (final s in samples) {
      final v = s / 32768.0;
      sum += v * v;
    }
    return math.sqrt(sum / samples.length);
  }

  /// Minimal 16 kHz mono 16-bit WAV wrapper around the collected PCM.
  Uint8List _wav(Uint8List pcm) {
    final header = ByteData(44);
    void str(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        header.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    header.setUint32(4, 36 + pcm.length, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little); // PCM
    header.setUint16(22, 1, Endian.little); // mono
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * 2, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    str(36, 'data');
    header.setUint32(40, pcm.length, Endian.little);
    return Uint8List.fromList(header.buffer.asUint8List() + pcm);
  }
}

/// Voice-reactive aura — concentric rings that breathe on their own and
/// swell with the speaker's live loudness. Wraps any child (Mina, a mic).
/// Respects reduced motion: a single static ring, still level-reactive.
class VoiceAura extends StatefulWidget {
  final ValueListenable<double> level;
  final Widget child;
  final Color color;
  final bool active;
  final double size;

  const VoiceAura({
    super.key,
    required this.level,
    required this.child,
    required this.color,
    this.active = true,
    this.size = 140,
  });

  @override
  State<VoiceAura> createState() => _VoiceAuraState();
}

class _VoiceAuraState extends State<VoiceAura>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.of(context).disableAnimations;
    if (reduced && _breath.isAnimating) _breath.stop();

    final span = widget.size * 2.1;
    return SizedBox(
      width: span,
      height: span,
      child: AnimatedBuilder(
        animation: Listenable.merge([_breath, widget.level]),
        builder: (context, _) {
          final wave = reduced
              ? 0.0
              : math.sin(_breath.value * 2 * math.pi) * 0.5 + 0.5;
          final loud = widget.level.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              if (widget.active)
                for (var i = 2; i >= 0; i--)
                  Container(
                    width: widget.size *
                        (1.12 + i * 0.16 + wave * 0.06 + loud * 0.55),
                    height: widget.size *
                        (1.12 + i * 0.16 + wave * 0.06 + loud * 0.55),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: widget.color.withValues(
                          alpha: ((0.34 - i * 0.09) * (0.5 + loud))
                              .clamp(0.04, 0.5),
                        ),
                        width: 2.5,
                      ),
                    ),
                  ),
              // Soft fill that blooms with the voice.
              if (widget.active)
                Container(
                  width: widget.size * (1.04 + loud * 0.3),
                  height: widget.size * (1.04 + loud * 0.3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color
                        .withValues(alpha: (0.10 + loud * 0.16).clamp(0, 0.3)),
                  ),
                ),
              Transform.scale(
                scale: reduced ? 1.0 : 1.0 + loud * 0.05,
                child: widget.child,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Three gentle bouncing dots — the "thinking" beat between turns.
class ThinkingDots extends StatefulWidget {
  final Color color;
  final double dotSize;
  const ThinkingDots({super.key, required this.color, this.dotSize = 10});

  @override
  State<ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<ThinkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          3,
          (i) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _dot(1),
          ),
        ),
      );
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final t = (_c.value * 2 * math.pi) - i * 0.9;
          final lift = math.max(0.0, math.sin(t));
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Transform.translate(
              offset: Offset(0, -6 * lift),
              child: _dot(0.45 + lift * 0.55),
            ),
          );
        }),
      ),
    );
  }

  Widget _dot(double alpha) => Container(
        width: widget.dotSize,
        height: widget.dotSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withValues(alpha: alpha),
        ),
      );
}
