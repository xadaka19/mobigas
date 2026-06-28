import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:mobigas/core/theme/app_theme.dart';
import 'package:mobigas/core/providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Determine if input is email or phone
  bool get _isEmail => _identifierController.text.contains('@');

  String get _loginIdentifier {
    final input = _identifierController.text.trim();
    if (_isEmail) return input;
    // Phone — convert to email format used during registration
    String phone = input.replaceAll(' ', '');
    if (phone.startsWith('0')) {
      phone = '254${phone.substring(1)}';
    }
    return '$phone@mobigas.app';
  }

  Future<void> _login() async {
    final input = _identifierController.text.trim();
    if (input.isEmpty) {
      _showError('Enter your email or phone number');
      return;
    }
    if (!_isEmail && input.length < 9) {
      _showError('Enter a valid phone number');
      return;
    }
    if (_isEmail && !input.contains('.')) {
      _showError('Enter a valid email address');
      return;
    }
    if (_passwordController.text.length < 6) {
      _showError('Enter your password');
      return;
    }

    final auth = context.read<AuthProvider>();
    await auth.login(_loginIdentifier, _passwordController.text);

    if (auth.error != null) {
      _showError(auth.error!);
    } else if (mounted) {
      context.go('/home');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isLoading = auth.state == AuthState.loading;

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
                    const SizedBox(height: 8),
                    _label('Email or phone number'),
                    TextFormField(
                      controller: _identifierController,
                      keyboardType: TextInputType.emailAddress,
                      onChanged: (_) => setState(() {}),
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: AppColors.navy,
                            fontWeight: FontWeight.w500,
                          ),
                      decoration: InputDecoration(
                        hintText: 'jane@gmail.com or 0712 345 678',
                        prefixIcon: Icon(
                          _isEmail
                              ? Icons.email_outlined
                              : Icons.phone_outlined,
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
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: AppColors.navy,
                            fontWeight: FontWeight.w500,
                          ),
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
                          if (!_isEmail) {
                            _showError(
                                'Enter your email address to reset password');
                            return;
                          }
                          final email = _identifierController.text.trim();
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
                        child: Text(
                          'Forgot password?',
                          style: TextStyle(color: AppColors.orange),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: isLoading ? null : _login,
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
                            'Sign up',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: AppColors.orange,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
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
            'Sign in to order gas on credit',
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
              const Icon(Icons.account_balance_outlined,
                  color: AppColors.orange, size: 18),
              const SizedBox(width: 8),
              Text(
                'How MobiGas credit works',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontSize: 13,
                      color: AppColors.navy,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _infoRow('Order gas on credit — delivered to your door'),
          _infoRow('Our partner bank finances your gas purchase'),
          _infoRow('Repay the bank within 30 days via M-Pesa'),
          _infoRow('Your limit grows as you repay on time'),
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
