import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobigas/core/theme/app_theme.dart';

class TermsScreen extends StatelessWidget {
  final bool isPrivacyPolicy;
  const TermsScreen({super.key, this.isPrivacyPolicy = false});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        } else {
          context.go('/login');
        }
      },
      child: Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: AppColors.white,
        leading: BackButton(
          color: AppColors.white,
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              context.go('/login');
            }
          },
        ),
        title: Text(
          isPrivacyPolicy ? 'Privacy Policy' : 'Terms of Service',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppColors.white,
              ),
        ),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: isPrivacyPolicy ? _buildPrivacyPolicy(context) : _buildTerms(context),
      ),
    ),
    );
  }

  Widget _buildTerms(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(context, 'Terms of Service'),
        _date(context, 'Effective: January 2025'),
        _section(context, '1. About MobiGas',
            'MobiGas is a digital marketplace platform that connects customers with local gas vendors and partner financial institutions for gas purchases on credit. MobiGas does not issue credit or lend money.'),
        _section(context, '2. Gas Credit',
            'Credit is provided by our partner banks and SACCOs, not by MobiGas. You repay the bank directly. MobiGas earns a referral fee from the bank for connecting you.'),
        _section(context, '3. Your Responsibilities',
            '• You must provide accurate personal information during registration.\n• You must have an empty cylinder ready for exchange on delivery.\n• You must repay the bank within the agreed period.\n• You are responsible for the actions of your guarantors.'),
        _section(context, '4. Guarantors',
            'By adding guarantors, you confirm you have obtained their consent to be listed. Guarantors may be contacted in case of payment default.'),
        _section(context, '5. Delivery',
            'Gas is delivered by registered vendors. MobiGas is not responsible for delivery delays caused by vendors or third parties.'),
        _section(context, '6. Account',
            'You are responsible for keeping your account credentials secure. Notify us immediately of any unauthorized access.'),
        _section(context, '7. Termination',
            'MobiGas may suspend or terminate accounts that violate these terms or engage in fraudulent activity.'),
        _section(context, '8. Contact',
            'For questions about these terms, contact us at legal@mobigas.co.ke'),
      ],
    );
  }

  Widget _buildPrivacyPolicy(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(context, 'Privacy Policy'),
        _date(context, 'Effective: January 2025'),
        _section(context, '1. Data We Collect',
            '• Personal: Name, phone number, email, National ID\n• Location: GPS coordinates for vendor matching\n• Biometric: Selfie photo for identity verification\n• Financial: Credit history shared by partner banks\n• Device: FCM token for push notifications'),
        _section(context, '2. How We Use Your Data',
            '• To create and manage your account\n• To match you with nearby gas vendors\n• To share your KYC data with partner banks for credit approval\n• To send order and payment notifications\n• To verify your identity via selfie'),
        _section(context, '3. Data Sharing',
            'We share your personal data only with:\n• Partner banks/SACCOs for credit approval\n• Gas vendors for delivery purposes\n• As required by Kenyan law\n\nWe do NOT sell your personal data to third parties.'),
        _section(context, '4. Data Storage',
            'Your data is stored on Google Firebase servers. Selfie photos are stored in Firebase Storage. We comply with the Kenya Data Protection Act 2019 and are registered with the ODPC.'),
        _section(context, '5. Your Rights',
            '• Access your personal data\n• Correct inaccurate data\n• Request deletion of your account\n• Withdraw consent for data sharing\n\nContact: privacy@mobigas.co.ke'),
        _section(context, '6. Security',
            'We use industry-standard encryption (AES-256) to protect your data. Your selfie is stored securely and only accessible to authorized MobiGas staff.'),
        _section(context, '7. CRB Consent',
            'By using MobiGas, you consent to sharing your personal information with partner financial institutions for credit assessment purposes.'),
        _section(context, '8. Contact',
            'Data Protection Officer: dpo@mobigas.co.ke\nOffice: Nairobi, Kenya'),
      ],
    );
  }

  Widget _heading(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text,
          style: Theme.of(context).textTheme.displayMedium?.copyWith(
                color: AppColors.navy,
                fontSize: 22,
              )),
    );
  }

  Widget _date(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Text(text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.gray400,
              )),
    );
  }

  Widget _section(BuildContext context, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w700,
                  )),
          const SizedBox(height: 6),
          Text(body,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.gray600,
                    height: 1.6,
                  )),
        ],
      ),
    );
  }
}
