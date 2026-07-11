import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mobigas/core/theme/app_theme.dart';
import 'package:mobigas/core/services/google_auth_service.dart';
import 'package:mobigas/core/services/firebase_service.dart';
import 'package:mobigas/core/services/firestore_service.dart';

enum _VendorAuthMode { signIn, register }

class VendorLoginScreen extends StatefulWidget {
  const VendorLoginScreen({super.key});

  @override
  State<VendorLoginScreen> createState() => _VendorLoginScreenState();
}

class _VendorLoginScreenState extends State<VendorLoginScreen> {
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  _VendorAuthMode _mode = _VendorAuthMode.signIn;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  /// Requires at least 8 characters with at least one letter, one
  /// number, and one special character. Checked separately (rather
  /// than one combined regex) so the error message can say exactly
  /// which rule failed instead of a generic "invalid password".
  String? _passwordRuleError(String password) {
    if (password.length < 8) {
      return 'Password must be at least 8 characters.';
    }
    if (!RegExp(r'[A-Za-z]').hasMatch(password)) {
      return 'Password must include at least one letter.';
    }
    if (!RegExp(r'\d').hasMatch(password)) {
      return 'Password must include at least one number.';
    }
    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=~`\[\]/\\;]').hasMatch(password)) {
      return 'Password must include at least one special character.';
    }
    return null;
  }

  /// After ANY successful auth (sign-in or registration), reject a
  /// customer account. Mirrors the guard already in AuthProvider for
  /// the customer app, but in the other direction — a customer's
  /// email/password identity must never be treated as a vendor.
  Future<bool> _rejectIfCustomer(String uid) async {
    final isCustomer = await FirestoreService.isRegisteredCustomer(uid);
    if (isCustomer) {
      await GoogleAuthService.signOut();
      _showError('This account is registered as a MobiGas customer. '
          'Please use the MobiGas app to sign in.');
      return true;
    }
    return false;
  }

  Future<void> _submitEmailPassword() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      _showError('Enter a valid email address');
      return;
    }

    if (_mode == _VendorAuthMode.register) {
      final ruleError = _passwordRuleError(password);
      if (ruleError != null) {
        _showError(ruleError);
        return;
      }
      if (password != _confirmPasswordController.text) {
        _showError('Passwords do not match.');
        return;
      }
    } else if (password.isEmpty) {
      _showError('Enter your password');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final UserCredential credential;
      if (_mode == _VendorAuthMode.register) {
        credential = await FirebaseService.auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      } else {
        credential = await FirebaseService.auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      }

      final uid = credential.user!.uid;
      if (await _rejectIfCustomer(uid)) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      if (!mounted) return;
      setState(() => _isLoading = false);
      // Same destination as the Google path — setup happens inside
      // the dashboard, not a separate onboarding screen.
      context.go('/vendor-home');
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError(_authError(e.code));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError('Something went wrong. Please try again.');
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      _showError('Enter your email address to reset password');
      return;
    }
    try {
      await FirebaseService.auth.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Reset link sent to $email'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } on FirebaseAuthException catch (e) {
      _showError(_authError(e.code));
    }
  }

  String _authError(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No vendor account found with this email';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password';
      case 'invalid-email':
        return 'That email address is not valid';
      case 'email-already-in-use':
        return 'An account already exists with this email. Try signing in instead.';
      case 'account-exists-with-different-credential':
        return 'This email is already registered. Sign in with your password.';
      case 'weak-password':
        return 'Password is too weak.';
      case 'too-many-requests':
        return 'Too many attempts. Wait a moment and try again.';
      case 'network-request-failed':
        return 'No internet connection';
      default:
        return 'Something went wrong. Please try again.';
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isGoogleLoading = true);

    final credential = await GoogleAuthService.signInWithGoogle();

    if (!mounted) return;

    if (credential == null) {
      setState(() => _isGoogleLoading = false);
      _showError('Google sign-in failed. Please try again.');
      return;
    }

    final uid = credential.user!.uid;

    // SECURITY GUARD: reject a customer account signing in here.
    // Nothing about a successful Google credential tells us which
    // app the person meant to use — without this check, a customer's
    // Google account could land straight on the vendor dashboard.
    if (await _rejectIfCustomer(uid)) {
      if (mounted) setState(() => _isGoogleLoading = false);
      return;
    }

    setState(() => _isGoogleLoading = false);
    if (!mounted) return;
    // Always go to home — setup happens inside the dashboard
    context.go('/vendor-home');
  }

  bool get _busy => _isLoading || _isGoogleLoading;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                const SizedBox(height: 8),
                // Logo
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: AppColors.orange,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(
                    Icons.local_fire_department_rounded,
                    color: AppColors.white,
                    size: 52,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'MobiGas Vendor',
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                        color: AppColors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Deliver gas. Get paid on every order.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.gray400,
                      ),
                ),
                const SizedBox(height: 32),
                // Value props
                _valueProp(Icons.payments_rounded,
                    'Get paid on every delivery — cash or M-Pesa, direct to you'),
                const SizedBox(height: 12),
                _valueProp(Icons.people_outline_rounded,
                    'New customers delivered to you'),
                const SizedBox(height: 12),
                _valueProp(Icons.insights_rounded,
                    'Track your sales and export reports anytime'),
                const SizedBox(height: 32),
                // Google Sign-In button
                _isGoogleLoading
                    ? const CircularProgressIndicator(color: AppColors.orange)
                    : GestureDetector(
                        onTap: _busy ? null : _signInWithGoogle,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.white,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SvgPicture.asset(
                                'assets/icon/google_icon.svg',
                                width: 24,
                                height: 24,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Continue with Google',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      color: AppColors.navy,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                const SizedBox(height: 20),
                _divider('or use email and password'),
                const SizedBox(height: 20),
                _buildEmailPasswordForm(),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _mode == _VendorAuthMode.signIn
                          ? "Don't have a vendor account? "
                          : 'Already have a vendor account? ',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.gray400,
                          ),
                    ),
                    GestureDetector(
                      onTap: _busy
                          ? null
                          : () => setState(() {
                                _mode = _mode == _VendorAuthMode.signIn
                                    ? _VendorAuthMode.register
                                    : _VendorAuthMode.signIn;
                              }),
                      child: Text(
                        _mode == _VendorAuthMode.signIn
                            ? 'Create account'
                            : 'Sign in',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
                    Text('By continuing you agree to our ',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.gray600,
                              fontSize: 11,
                            )),
                    GestureDetector(
                      onTap: () => context.push('/vendor-terms'),
                      child: Text('Terms',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppColors.orange,
                                fontSize: 11,
                                decoration: TextDecoration.underline,
                              )),
                    ),
                    Text(' & ',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.gray600,
                              fontSize: 11,
                            )),
                    GestureDetector(
                      onTap: () => context.push('/vendor-privacy'),
                      child: Text('Privacy Policy',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppColors.orange,
                                fontSize: 11,
                                decoration: TextDecoration.underline,
                              )),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmailPasswordForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Email address'),
        TextFormField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          enabled: !_busy,
          style: _fieldStyle(),
          decoration: const InputDecoration(
            hintText: 'you@business.com',
            prefixIcon: Icon(Icons.email_outlined,
                color: AppColors.gray400, size: 20),
          ),
        ),
        const SizedBox(height: 16),
        _fieldLabel('Password'),
        TextFormField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          autocorrect: false,
          enableSuggestions: false,
          enabled: !_busy,
          autofillHints: [
            _mode == _VendorAuthMode.register
                ? AutofillHints.newPassword
                : AutofillHints.password,
          ],
          style: _fieldStyle(),
          decoration: InputDecoration(
            hintText: _mode == _VendorAuthMode.register
                ? 'At least 8 characters'
                : 'Enter your password',
            prefixIcon: const Icon(Icons.lock_outline_rounded,
                color: AppColors.gray400, size: 20),
            suffixIcon: IconButton(
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
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
        if (_mode == _VendorAuthMode.register) ...[
          const SizedBox(height: 6),
          Text(
            'Letters, numbers, and a special character (e.g. ! @ # \$ %).',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.gray400,
                  fontSize: 11,
                ),
          ),
          const SizedBox(height: 16),
          _fieldLabel('Confirm password'),
          TextFormField(
            controller: _confirmPasswordController,
            obscureText: _obscureConfirmPassword,
            autocorrect: false,
            enableSuggestions: false,
            enabled: !_busy,
            style: _fieldStyle(),
            decoration: InputDecoration(
              hintText: 'Re-enter your password',
              prefixIcon: const Icon(Icons.lock_outline_rounded,
                  color: AppColors.gray400, size: 20),
              suffixIcon: IconButton(
                onPressed: () => setState(
                    () => _obscureConfirmPassword = !_obscureConfirmPassword),
                icon: Icon(
                  _obscureConfirmPassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: AppColors.gray400,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
        if (_mode == _VendorAuthMode.signIn) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _busy ? null : _resetPassword,
              child: const Text(
                'Forgot password?',
                style: TextStyle(color: AppColors.orange),
              ),
            ),
          ),
        ] else
          const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _busy ? null : _submitEmailPassword,
            child: _isLoading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.white,
                    ),
                  )
                : Text(_mode == _VendorAuthMode.signIn
                    ? 'Sign in'
                    : 'Create vendor account'),
          ),
        ),
      ],
    );
  }

  // Input fields are filled white by the global InputDecorationTheme
  // (filled: true, fillColor: AppColors.white). White text on a white
  // fill was invisible — which is why nothing showed as you typed.
  // Navy matches the working customer login.
  TextStyle? _fieldStyle() => const TextStyle(
        color: AppColors.navy,
        fontWeight: FontWeight.w500,
      );

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.white,
            ),
      ),
    );
  }

  Widget _divider(String label) {
    return Row(
      children: [
        Expanded(child: Divider(color: AppColors.white.withValues(alpha: 0.15))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.gray400,
                  fontSize: 12,
                ),
          ),
        ),
        Expanded(child: Divider(color: AppColors.white.withValues(alpha: 0.15))),
      ],
    );
  }

  Widget _valueProp(IconData icon, String text) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.orange.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: AppColors.orange, size: 18),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.white,
                ),
          ),
        ),
      ],
    );
  }
}