import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:mobigas/core/theme/app_theme.dart';
import 'package:mobigas/core/providers/auth_provider.dart';
import 'package:mobigas/core/widgets/google_sign_in_button.dart';

/// Signup is now one screen. Phone number, delivery location and
/// verification moved to the profile banner on the home screen —
/// a customer reaches the vendor list in three fields instead of
/// three steps.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _isGoogleLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------
  // Password rules: length, at least one letter, at least one number.
  // ---------------------------------------------------------------

  bool get _hasLength => _passwordController.text.length >= 6;
  bool get _hasLetter => RegExp(r'[A-Za-z]').hasMatch(_passwordController.text);
  bool get _hasNumber => RegExp(r'[0-9]').hasMatch(_passwordController.text);

  String? _passwordProblem() {
    if (!_hasLength) return 'Password must be at least 6 characters';
    if (!_hasLetter) return 'Password must include at least one letter';
    if (!_hasNumber) return 'Password must include at least one number';
    return null;
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();

    if (name.isEmpty) {
      _showError('Enter your full name');
      return;
    }
    if (!email.contains('@') || !email.contains('.')) {
      _showError('Enter a valid email address');
      return;
    }
    final passwordProblem = _passwordProblem();
    if (passwordProblem != null) {
      _showError(passwordProblem);
      return;
    }

    setState(() => _isLoading = true);
    final auth = context.read<AuthProvider>();

    await auth.register(
      name: name,
      email: email.toLowerCase(),
      password: _passwordController.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (auth.error != null) {
      _showError(auth.error!);
      return;
    }
    context.go('/home');
  }

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
    final busy = _isLoading || _isGoogleLoading;

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
                      label: 'Continue with Google',
                    ),
                    const SizedBox(height: 20),
                    const OrDivider(label: 'or sign up with email'),
                    const SizedBox(height: 24),
                    _label('Full name'),
                    TextFormField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      style: _fieldStyle(context),
                      decoration: const InputDecoration(
                        hintText: 'e.g. Jane Wanjiku Mwangi',
                        prefixIcon: Icon(Icons.person_outline_rounded,
                            color: AppColors.gray400, size: 20),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _label('Email address'),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      style: _fieldStyle(context),
                      decoration: const InputDecoration(
                        hintText: 'e.g. jane@gmail.com',
                        prefixIcon: Icon(Icons.email_outlined,
                            color: AppColors.gray400, size: 20),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _label('Password'),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      // Explicit text keyboard — without this Android
                      // can hand back a numeric pad on some OEM
                      // keyboards, which is why passwords were coming
                      // through as digits only.
                      keyboardType: TextInputType.text,
                      autocorrect: false,
                      enableSuggestions: false,
                      autofillHints: const [AutofillHints.newPassword],
                      onChanged: (_) => setState(() {}),
                      style: _fieldStyle(context),
                      decoration: InputDecoration(
                        hintText: 'Letters and numbers, 6 or more',
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
                    _buildPasswordRules(),
                    const SizedBox(height: 28),
                    ElevatedButton(
                      onPressed: busy ? null : _submit,
                      child: _isLoading
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: AppColors.white,
                              ),
                            )
                          : const Text('Create account'),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'You can add your phone number and delivery '
                      'location right after — it takes about a minute.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.gray600,
                            fontSize: 12,
                            height: 1.5,
                          ),
                    ),
                    const SizedBox(height: 20),
                    _buildLoginLink(),
                    const SizedBox(height: 16),
                    _buildLegalRow(),
                    const SizedBox(height: 8),
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
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      decoration: const BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => context.go('/onboarding'),
            child: const Icon(Icons.arrow_back_ios_rounded,
                color: AppColors.white, size: 20),
          ),
          const SizedBox(height: 20),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.orange,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.local_fire_department_rounded,
                color: AppColors.white, size: 32),
          ),
          const SizedBox(height: 20),
          Text(
            'Create your account',
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  color: AppColors.white,
                  fontSize: 28,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Order cooking gas from vendors near you',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.gray400,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordRules() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.orangeLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.orange.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _rule('At least 6 characters', _hasLength),
          const SizedBox(height: 6),
          _rule('Includes a letter', _hasLetter),
          const SizedBox(height: 6),
          _rule('Includes a number', _hasNumber),
        ],
      ),
    );
  }

  Widget _rule(String text, bool met) {
    return Row(
      children: [
        Icon(
          met
              ? Icons.check_circle_rounded
              : Icons.radio_button_unchecked_rounded,
          size: 16,
          color: met ? AppColors.success : AppColors.orange,
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: met ? AppColors.success : AppColors.orangeDeep,
                fontSize: 12,
                fontWeight: met ? FontWeight.w600 : FontWeight.w400,
              ),
        ),
      ],
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

  Widget _buildLoginLink() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Already have an account? ',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        GestureDetector(
          onTap: () => context.go('/login'),
          child: Text(
            'Sign in',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.orange,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }

  Widget _buildLegalRow() {
    final linkStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AppColors.orange,
          fontSize: 11,
          decoration: TextDecoration.underline,
        );
    final plainStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AppColors.gray600,
          fontSize: 11,
        );

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('By continuing you agree to our ', style: plainStyle),
        GestureDetector(
          onTap: () => context.push('/terms'),
          child: Text('Terms', style: linkStyle),
        ),
        Text(' & ', style: plainStyle),
        GestureDetector(
          onTap: () => context.push('/privacy'),
          child: Text('Privacy Policy', style: linkStyle),
        ),
      ],
    );
  }
}