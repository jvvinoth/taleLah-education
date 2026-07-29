/// Verify email — 6-digit code entry with resend cooldown.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';
import '../../services/api_client.dart';
import '../../theme/app_theme.dart';
import 'auth_widgets.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key, required this.email});

  final String email;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  int _cooldown = 0;
  Timer? _timer;

  @override
  void dispose() {
    _code.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _verify([String? code]) async {
    final value = (code ?? _code.text).trim();
    if (value.length != 6) {
      setState(() => _error = 'Enter the 6-digit code from your email');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context
          .read<AppState>()
          .verifyEmail(email: widget.email, code: value);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.detail;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = "Can't reach TaleLah right now — please try again";
      });
    }
  }

  Future<void> _resend() async {
    if (_cooldown > 0) return;
    setState(() {
      _cooldown = 30;
      _error = null;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldown -= 1);
      if (_cooldown <= 0) t.cancel();
    });
    try {
      await context.read<AppState>().resendVerificationCode(widget.email);
    } catch (_) {
      // Resend is best-effort; the existing code stays valid for 15 min.
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Check your inbox',
      subtitle: 'We sent a 6-digit code to\n${widget.email}',
      children: [
        AuthError(message: _error),
        CodeField(controller: _code, onFilled: _verify),
        const SizedBox(height: 8),
        const Text(
          'The code expires in 15 minutes.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: TColors.inkFaint,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        AuthButton(label: 'Verify', onPressed: _verify, loading: _busy),
        const SizedBox(height: 8),
        AuthLink(
          text: _cooldown > 0
              ? 'Resend code in ${_cooldown}s'
              : "Didn't get it? Resend code",
          onTap: _resend,
        ),
      ],
    );
  }
}
