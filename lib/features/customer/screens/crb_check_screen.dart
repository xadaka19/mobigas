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

  _ApprovalState _state = _ApprovalState.checking;
  int _currentStep = 0;
  double _bankApprovedLimit = 0;
  String _approvedBank = '';

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
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    setState(() => _currentStep = 1);

    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() => _currentStep = 2);

    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() => _currentStep = 3);

    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    // TODO: real bank API call
    _bankApprovedLimit = 3200;
    _approvedBank = 'Stima SACCO';

    _pulseController.stop();

    if (_bankApprovedLimit > 0) {
      setState(() => _state = _ApprovalState.approved);
      _checkController.forward();
    } else {
      setState(() => _state = _ApprovalState.rejected);
    }
  }

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
          child: _state == _ApprovalState.checking
              ? _buildChecking()
              : _state == _ApprovalState.approved
                  ? _buildApproved()
                  : _buildRejected(),
        ),
      ),
    );
  }

  Widget _buildChecking() {
    final steps = [
      'Sending your details to partner banks...',
      'Banks reviewing your application...',
      'Checking credit eligibility...',
      'Finalising your credit limit...',
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
            );
          },
        ),
        const SizedBox(height: 40),
        Text(
          'Checking eligibility',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppColors.white,
                fontSize: 22,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'Our partner banks are reviewing your application',
          textAlign: TextAlign.center,
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
            margin: const EdgeInsets.only(bottom: 12),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                          : const Icon(
                              Icons.radio_button_unchecked_rounded,
                              color: AppColors.gray600,
                              size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    steps[i],
                    style:
                        Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: isDone
                                  ? AppColors.success
                                  : isActive
                                      ? AppColors.white
                                      : AppColors.gray600,
                            ),
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
    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 20),
          ScaleTransition(
            scale: _checkAnim,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.success.withValues(alpha: 0.15),
              ),
              child: const Icon(Icons.check_circle_rounded,
                  color: AppColors.success, size: 64),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'You\'re approved!',
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  color: AppColors.white,
                  fontSize: 28,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            '$_approvedBank has approved your gas credit.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.gray400,
                  height: 1.6,
                ),
          ),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: AppColors.orange.withValues(alpha: 0.3)),
            ),
            child: Column(
              children: [
                Text(
                  'Your gas credit limit',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.gray400,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'KES ${_bankApprovedLimit.toStringAsFixed(0)}',
                  style: Theme.of(context)
                      .textTheme
                      .displayLarge
                      ?.copyWith(
                        color: AppColors.orange,
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'financed by $_approvedBank',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.gray400,
                      ),
                ),
                const Divider(height: 24, color: Colors.white12),
                _approvalRow(Icons.account_balance_outlined,
                    'Financed by', _approvedBank),
                _approvalRow(Icons.payments_outlined,
                    'Bank pays vendor directly', 'On delivery'),
                _approvalRow(Icons.trending_up_rounded,
                    'Limit grows', 'As you repay on time'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: AppColors.white.withValues(alpha: 0.1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'How it works',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.white,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 12),
                _howRow('1', 'You order gas on the MobiGas app'),
                _howRow('2',
                    '$_approvedBank pays the vendor when you confirm delivery with your PIN'),
                _howRow('3',
                    'You repay $_approvedBank within 30 days via M-Pesa'),
                _howRow('4',
                    'Your limit grows automatically as you repay on time'),
              ],
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => context.go('/home'),
            child: const Text('Start ordering gas'),
          ),
        ],
      ),
    );
  }

  Widget _approvalRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: AppColors.orange, size: 16),
          const SizedBox(width: 8),
          Text(label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.gray400,
                    fontSize: 12,
                  )),
          const Spacer(),
          Text(value,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  )),
        ],
      ),
    );
  }

  Widget _howRow(String step, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(
              color: AppColors.orange,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(step,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  )),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.gray400,
                      height: 1.4,
                      fontSize: 12,
                    )),
          ),
        ],
      ),
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
          child: const Icon(Icons.cancel_rounded,
              color: AppColors.error, size: 64),
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
          'Our partner banks could not approve your application at this time. You can try again after 3 months.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: AppColors.gray400,
                height: 1.6,
              ),
        ),
        const SizedBox(height: 40),
        ElevatedButton(
          onPressed: () => context.go('/'),
          style:
              ElevatedButton.styleFrom(backgroundColor: AppColors.error),
          child: const Text('Back to home'),
        ),
      ],
    );
  }
}

enum _ApprovalState { checking, approved, rejected }
