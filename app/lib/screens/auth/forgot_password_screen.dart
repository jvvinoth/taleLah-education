/// Forgot password — 2 steps: email → code + new password.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';
import '../../services/api_client.dart';
import '../../theme/app_theme.dart';
import 'auth_widgets.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  final String initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final TextEditingController _email =
      TextEditingController(text: widget.initialEmail);
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Enter a valid email');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AppState>().forgotPassword(email);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _codeSent = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = "Can't reach TaleLah right now — please try again";
      });
    }
  }

  Future<void> _reset() async {
    if (_code.text.trim().length != 6) {
      setState(() => _error = 'Enter the 6-digit code from your email');
      return;
    }
    if (_password.text.length < 8) {
      setState(() => _error = 'Use at least 8 characters for the new password');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AppState>().resetPassword(
            email: _email.text.trim(),
            code: _code.text.trim(),
            newPassword: _password.text,
          );
      // Reset auto-logs-in; SplashGate routes home.
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

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Reset password',
      subtitle: _codeSent
          ? 'Enter the code we emailed to\n${_email.text.trim()}'
          : "We'll email you a 6-digit reset code.",
      children: [
        AuthError(message: _error),
        if (!_codeSent) ...[
          AuthField(
            controller: _email,
            label: 'Email',
            icon: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            onSubmitted: (_) => _sendCode(),
          ),
          AuthButton(
              label: 'Send reset code', onPressed: _sendCode, loading: _busy),
        ] else ...[
          CodeField(controller: _code),
          const SizedBox(height: 14),
          AuthField(
            controller: _password,
            label: 'New password',
            hint: 'At least 8 characters',
            icon: Icons.lock_outline_rounded,
            obscure: true,
            autofillHints: const [AutofillHints.newPassword],
            onSubmitted: (_) => _reset(),
          ),
          AuthButton(
              label: 'Set new password', onPressed: _reset, loading: _busy),
          const SizedBox(height: 8),
          AuthLink(
            text: 'Use a different email',
            onTap: () => setState(() {
              _codeSent = false;
              _error = null;
            }),
          ),
        ],
        const SizedBox(height: 4),
        const Text(
          'Reset codes expire after 15 minutes.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: TColors.inkFaint,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
