/// Login — email + password, with forgot-password and one-tap demo entry.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';
import '../../services/api_client.dart';
import '../../theme/app_theme.dart';
import 'auth_widgets.dart';
import 'forgot_password_screen.dart';
import 'signup_screen.dart';
import 'verify_email_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _demoBusy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AppState>().login(
            email: _email.text.trim(),
            password: _password.text,
          );
      // SplashGate routes to home via AppState.isLoggedIn.
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 403) {
        // Unverified — send them straight to the code screen.
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => VerifyEmailScreen(email: _email.text.trim()),
        ));
        setState(() => _busy = false);
        return;
      }
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

  Future<void> _tryDemo() async {
    setState(() {
      _demoBusy = true;
      _error = null;
    });
    try {
      await context.read<AppState>().tryDemo();
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _demoBusy = false;
        _error = "Can't reach TaleLah right now — please try again";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Welcome back!',
      subtitle: 'Everyday moments. Mother-tongue magic.',
      showBack: false,
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AuthError(message: _error),
              AuthField(
                controller: _email,
                label: 'Email',
                icon: Icons.mail_outline_rounded,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                validator: (v) => v == null || !v.contains('@')
                    ? 'Enter a valid email'
                    : null,
              ),
              AuthField(
                controller: _password,
                label: 'Password',
                icon: Icons.lock_outline_rounded,
                obscure: true,
                autofillHints: const [AutofillHints.password],
                validator: (v) =>
                    v == null || v.isEmpty ? 'Enter your password' : null,
                onSubmitted: (_) => _login(),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: AuthLink(
                  text: 'Forgot password?',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ForgotPasswordScreen(
                        initialEmail: _email.text.trim()),
                  )),
                ),
              ),
              const SizedBox(height: 6),
              AuthButton(label: 'Log in', onPressed: _login, loading: _busy),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'New to TaleLah?',
                    style: TextStyle(
                      color: TColors.inkSoft,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  AuthLink(
                    text: 'Sign up',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const SignupScreen())),
                  ),
                ],
              ),
              const Divider(height: 24, color: TColors.mist),
              AuthButton(
                label: _demoBusy ? 'Opening demo…' : '✨ Try the demo',
                onPressed: _tryDemo,
                loading: _demoBusy,
                gradient: TGradients.mint,
                glow: TShadows.glowTeal,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
