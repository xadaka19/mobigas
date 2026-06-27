import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobigas/core/theme/app_theme.dart';

class CrbCheckScreen extends StatefulWidget {
  const CrbCheckScreen({super.key});

  @override
  State<CrbCheckScreen> createState() => _CrbCheckScreenState();
}

class _CrbCheckScreenState extends State<CrbCheckScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _checkController;
  late Animation<double> _checkAnim;

  _CrbState _state = _CrbState.checking;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _checkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _checkAnim = CurvedAnimation(
      parent: _checkController,
      curve: Curves.elasticOut,
    );

    _runCheck();
  }

  Future<void> _runCheck() async {
    // Simulate CRB check steps
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    setState(() => _currentStep = 1);

    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() => _currentStep = 2);

    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() => _currentStep = 3);

    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;

    // Mock: approved
    _pulseController.stop();
    setState(() => _state = _CrbState.approved);
    _checkController.forward();
  }

  int _currentStep = 0;

  @override
  void dispose() {
    _pulseController.dispose();
    _checkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: _state == _CrbState.checking
              ? _buildChecking()
              : _state == _CrbState.approved
                  ? _buildApproved()
                  : _buildRejected(), // _CrbState.rejected
        ),
      ),
    );
  }

  Widget _buildChecking() {
    final steps = [
      'Verifying your National ID...',
      'Checking CRB credit history...',
      'Reviewing repayment records...',
      'Calculating credit limit...',
    ];

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            return Container(
              width: 100 + (_pulseController.value * 20),
              height: 100 + (_pulseController.value * 20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.orange
                    .withValues(alpha: 0.1 + _pulseController.value * 0.1),
              ),
              child: child,
            );
          },
          child: const Center(
            child: SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                color: AppColors.orange,
                strokeWidth: 3,
              ),
            ),
          ),
        ),
        const SizedBox(height: 40),
        Text(
          'Running credit check',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppColors.white,
                fontSize: 22,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'This takes just a few seconds',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.gray400,
              ),
        ),
        const SizedBox(height: 48),
        ...List.generate(steps.length, (i) {
          final isDone = i < _currentStep;
          final isActive = i == _currentStep;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDone
                  ? AppColors.success.withValues(alpha: 0.1)
                  : isActive
                      ? AppColors.orange.withValues(alpha: 0.1)
                      : AppColors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDone
                    ? AppColors.success.withValues(alpha: 0.3)
                    : isActive
                        ? AppColors.orange.withValues(alpha: 0.3)
                        : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: isDone
                      ? const Icon(Icons.check_circle_rounded,
                          color: AppColors.success, size: 20)
                      : isActive
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.orange,
                              ),
                            )
                          : const Icon(Icons.radio_button_unchecked_rounded,
                              color: AppColors.gray600, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  steps[i],
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: isDone
                            ? AppColors.success
                            : isActive
                                ? AppColors.white
                                : AppColors.gray600,
                        fontWeight: isActive
                            ? FontWeight.w500
                            : FontWeight.w400,
                      ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildApproved() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ScaleTransition(
          scale: _checkAnim,
          child: Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.success.withValues(alpha: 0.15),
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              color: AppColors.success,
              size: 64,
            ),
          ),
        ),
        const SizedBox(height: 32),
        Text(
          'Credit approved!',
          style: Theme.of(context).textTheme.displayMedium?.copyWith(
                color: AppColors.white,
                fontSize: 28,
              ),
        ),
        const SizedBox(height: 12),
        Text(
          'Your credit history is clean. You are approved to order gas on credit.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: AppColors.gray400,
                height: 1.6,
              ),
        ),
        const SizedBox(height: 32),
        // Credit limit card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.orange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.orange.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            children: [
              Text(
                'Your starting credit limit',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.gray400,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'KES 1,500',
                style: Theme.of(context)
                    .textTheme
                    .displayLarge
                    ?.copyWith(
                      color: AppColors.orange,
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Covers one 6kg cylinder',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.gray400,
                    ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Your limit grows automatically as you repay on time.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.gray400,
                        fontSize: 11,
                        height: 1.4,
                      ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 40),
        ElevatedButton(
          onPressed: () => context.go('/home'),
          child: const Text('Start ordering gas'),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => context.go('/home'),
          child: Text(
            'Go to dashboard',
            style: TextStyle(color: AppColors.gray400),
          ),
        ),
      ],
    );
  }

  Widget _buildRejected() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 110,
          height: 110,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.error.withValues(alpha: 0.15),
          ),
          child: const Icon(
            Icons.cancel_rounded,
            color: AppColors.error,
            size: 64,
          ),
        ),
        const SizedBox(height: 32),
        Text(
          'Not approved',
          style: Theme.of(context).textTheme.displayMedium?.copyWith(
                color: AppColors.white,
                fontSize: 28,
              ),
        ),
        const SizedBox(height: 12),
        Text(
          'Your CRB record shows outstanding defaults. Clear your credit history and try again.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: AppColors.gray400,
                height: 1.6,
              ),
        ),
        const SizedBox(height: 40),
        ElevatedButton(
          onPressed: () => context.go('/'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
          ),
          child: const Text('Back to home'),
        ),
      ],
    );
  }
}

enum _CrbState { checking, approved }
