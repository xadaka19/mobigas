import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:mobigas/core/theme/app_theme.dart';
import 'package:mobigas/core/providers/auth_provider.dart';
import 'package:mobigas/core/widgets/google_sign_in_button.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isGoogleLoading = false;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _identifierController.text.trim();
    if (email.isEmpty) {
      _showError('Enter your email address');
      return;
    }
    if (!email.contains('@') || !email.contains('.')) {
      _showError('Enter a valid email address');
      return;
    }
    if (_passwordController.text.length < 6) {
      _showError('Enter your password');
      return;
    }

    final auth = context.read<AuthProvider>();
    // Accounts are created with the customer's real email during
    // registration, so login authenticates against that email
    // directly.
    await auth.login(email.toLowerCase(), _passwordController.text);

    if (!mounted) return;
    if (auth.error != null) {
      _showError(auth.error!);
    } else {
      context.go('/home');
    }
  }

  /// Same entry point as signup — an existing Google customer signs
  /// in, a new one gets a profile created on the spot.
  Future<void> _continueWithGoogle() async {
    setState(() => _isGoogleLoading = true);
    final auth = context.read<AuthProvider>();
    final ok = await auth.signInWithGoogle();

    if (!mounted) return;
    setState(() => _isGoogleLoading = false);

    if (!ok) {
      _showError(auth.error ?? 'Google sign-in did not complete.');
      return;
    }
    context.go('/home');
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isLoading = auth.state == AuthState.loading && !_isGoogleLoading;
    final busy = isLoading || _isGoogleLoading;

    return Scaffold(
      backgroundColor: AppColors.orangeWarm,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              _buildHeader(),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GoogleSignInButton(
                      isLoading: _isGoogleLoading,
                      onPressed: busy ? null : _continueWithGoogle,
                    ),
                    const SizedBox(height: 20),
                    const OrDivider(label: 'or sign in with email'),
                    const SizedBox(height: 24),
                    _label('Email address'),
                    TextFormField(
                      controller: _identifierController,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      onChanged: (_) => setState(() {}),
                      style: _fieldStyle(context),
                      decoration: const InputDecoration(
                        hintText: 'jane@gmail.com',
                        prefixIcon: Icon(
                          Icons.email_outlined,
                          color: AppColors.gray400,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _label('Password'),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      keyboardType: TextInputType.text,
                      autocorrect: false,
                      enableSuggestions: false,
                      autofillHints: const [AutofillHints.password],
                      style: _fieldStyle(context),
                      decoration: InputDecoration(
                        hintText: 'Enter your password',
                        prefixIcon: const Icon(Icons.lock_outline_rounded,
                            color: AppColors.gray400, size: 20),
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: AppColors.gray400,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () async {
                          final email = _identifierController.text.trim();
                          if (!email.contains('@') || !email.contains('.')) {
                            _showError(
                                'Enter your email address to reset password');
                            return;
                          }
                          final authProvider = context.read<AuthProvider>();
                          final messenger = ScaffoldMessenger.of(context);
                          await authProvider.resetPassword(email);
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('Reset link sent to $email'),
                                backgroundColor: AppColors.success,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                        child: const Text(
                          'Forgot password?',
                          style: TextStyle(color: AppColors.orange),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: busy ? null : _login,
                      child: isLoading
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: AppColors.white,
                              ),
                            )
                          : const Text('Sign in'),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Don't have an account? ",
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        GestureDetector(
                          onTap: () => context.go('/register'),
                          child: Text(
                            'Create account',
                            style:
                                Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: AppColors.orange,
                                      fontWeight: FontWeight.w600,
                                    ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: () => context.push('/terms'),
                          child: Text('Terms of Service',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: AppColors.orange,
                                    decoration: TextDecoration.underline,
                                  )),
                        ),
                        Text('  ·  ',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppColors.gray400,
                                    )),
                        GestureDetector(
                          onTap: () => context.push('/privacy'),
                          child: Text('Privacy Policy',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: AppColors.orange,
                                    decoration: TextDecoration.underline,
                                  )),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    _buildInfoCard(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  TextStyle? _fieldStyle(BuildContext context) =>
      Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: AppColors.navy,
            fontWeight: FontWeight.w500,
          );

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
      decoration: const BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.orange,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.local_fire_department_rounded,
              color: AppColors.white,
              size: 32,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Welcome back',
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  color: AppColors.white,
                  fontSize: 28,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Sign in to order gas delivered to your door',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.gray400,
                ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.navy,
            ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gray200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_fire_department_outlined,
                  color: AppColors.orange, size: 18),
              const SizedBox(width: 8),
              Text(
                'How MobiGas works',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontSize: 13,
                      color: AppColors.navy,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _infoRow('Order cooking gas — delivered to your door'),
          _infoRow('Compare prices from verified vendors near you'),
          _infoRow('Pay cash or M-Pesa on delivery'),
          _infoRow('Confirm with your delivery PIN when it arrives'),
        ],
      ),
    );
  }

  Widget _infoRow(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_outline_rounded,
              color: AppColors.success, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.gray600,
                    height: 1.4,
                    fontSize: 12,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}