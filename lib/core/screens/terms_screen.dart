import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobigas/core/theme/app_theme.dart';

/// Which app is showing this screen — content differs meaningfully
/// between the two, so this picks which detailed copy to render
/// rather than showing generic shared terms.
enum TermsAudience { customer, vendor }

class TermsScreen extends StatelessWidget {
  final bool isPrivacyPolicy;
  final TermsAudience audience;
  const TermsScreen({
    super.key,
    this.isPrivacyPolicy = false,
    required this.audience,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        } else {
          context.pop();
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
                context.pop();
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
          child: _buildContent(context),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (audience == TermsAudience.vendor) {
      return isPrivacyPolicy
          ? _buildVendorPrivacy(context)
          : _buildVendorTerms(context);
    }
    return isPrivacyPolicy
        ? _buildCustomerPrivacy(context)
        : _buildCustomerTerms(context);
  }

  // ── CUSTOMER TERMS ───────────────────────────────────────────────
  Widget _buildCustomerTerms(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(context, 'Terms of Service — Customers'),
        _date(context, 'Effective: July 2026'),
        _section(context, '1. About MobiGas',
            'MobiGas is a digital marketplace platform that connects customers with verified local gas vendors for fast cooking gas delivery. MobiGas does not sell gas itself — vendors listed on the platform are independent businesses, and MobiGas facilitates the connection between you and them.'),
        _section(context, '2. Placing Orders',
            '• You may order gas refills, full cylinder kits, grill kits, burners, regulators, and related accessories from verified vendors near you.\n• Prices are set independently by each vendor and may vary by brand and cylinder size.\n• You must have an empty cylinder ready for exchange where the order is a refill (exchange) order — a full kit order includes a new cylinder and no exchange is required.'),
        _section(context, '3. Delivery',
            '• Gas is delivered by independently operated, MobiGas-verified vendors.\n• Estimated delivery times shown are set by the vendor and are estimates, not guarantees.\n• MobiGas is not responsible for delivery delays, damages, or disputes arising from the vendor\u2019s conduct, though we may assist in mediating and may suspend vendors who repeatedly fail to deliver as promised.'),
        _section(context, '4. Payments',
            'Payment is made directly to the vendor on delivery via the payment method they have on file (cash, M-Pesa, till, or paybill). MobiGas does not hold or process these funds. Only confirm delivery with your PIN after you have received your gas.'),
        _section(context, '5. Delivery PIN',
            'Each order includes a delivery confirmation PIN. Keep it private and only share it with the vendor once your gas has been delivered as ordered. Sharing your PIN before delivery is at your own risk.'),
        _section(context, '6. Referrals',
            'If you were referred using a referral code, that code is recorded once at signup and cannot be changed later. Referral rewards, if any, are subject to separate promotional terms.'),
        _section(context, '7. Your Account',
            'You are responsible for keeping your login credentials secure and for all activity under your account. Notify us immediately at legal@mobigas.co.ke of any unauthorized access.'),
        _section(context, '8. Termination',
            'MobiGas may suspend or terminate accounts that violate these terms, provide false information, or engage in fraudulent activity.'),
        _section(context, '9. Limitation of Liability',
            'MobiGas provides a marketplace connecting customers and vendors. To the extent permitted by Kenyan law, MobiGas is not liable for losses arising from vendor conduct or third-party actions outside our direct control.'),
        _section(context, '10. Governing Law',
            'These terms are governed by the laws of Kenya. Disputes will first be addressed through our support channels before any formal proceedings.'),
        _section(context, '11. Contact',
            'For questions about these terms, contact us at legal@mobigas.co.ke'),
      ],
    );
  }

  // ── CUSTOMER PRIVACY ──────────────────────────────────────────────
  Widget _buildCustomerPrivacy(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(context, 'Privacy Policy — Customers'),
        _date(context, 'Effective: July 2026'),
        _section(context, '1. Data We Collect',
            '• Personal: Name, phone number, email, National ID\n• Location: GPS coordinates and delivery address, used to match you with nearby vendors and to deliver your order\n• Profile photo: An optional selfie photo, used for your account profile and identity verification\n• Order data: Your order history and delivery details\n• Device: FCM token, used for order and delivery push notifications'),
        _section(context, '2. How We Use Your Data',
            '• To create and manage your account\n• To match you with nearby, verified gas vendors\n• To share your delivery details with the vendor fulfilling your order\n• To send order and delivery status notifications\n• To operate the referral program, where applicable'),
        _section(context, '3. Data Sharing',
            'We share your personal data only with:\n• Gas vendors, limited to what\u2019s needed for delivery (name, phone, location, order details)\n• Regulators or courts, where required by Kenyan law\n\nWe do NOT sell your personal data to third parties.'),
        _section(context, '4. Data Storage',
            'Your data is stored on Google Firebase servers. Profile photos are stored in Firebase Storage with restricted access. We comply with the Kenya Data Protection Act, 2019, and are registered with the Office of the Data Protection Commissioner (ODPC).'),
        _section(context, '5. Your Rights',
            'Under the Data Protection Act, you may:\n• Access the personal data we hold about you\n• Correct inaccurate data\n• Request deletion of your account and associated data, subject to statutory retention requirements (e.g. transaction records required for tax purposes)\n\nTo request deletion, email privacy@mobigas.co.ke from your registered email address, or visit mobigas.co.ke/delete-account.'),
        _section(context, '6. Security',
            'We use industry-standard encryption to protect data in storage and in transit. Your profile photo and National ID are accessible only to authorized MobiGas staff.'),
        _section(context, '7. Retention',
            'We retain your data for as long as your account is active, and for a period afterward as required for legal, tax, or dispute-resolution obligations.'),
        _section(context, '8. Contact',
            'Data Protection Officer: dpo@mobigas.co.ke\nOffice: Nairobi, Kenya'),
      ],
    );
  }

  // ── VENDOR TERMS ──────────────────────────────────────────────────
  Widget _buildVendorTerms(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(context, 'Terms of Service — Vendors'),
        _date(context, 'Effective: July 2026'),
        _section(context, '1. About This Agreement',
            'This agreement governs your use of the MobiGas platform as a gas vendor. MobiGas is a marketplace connecting you with customers; it does not purchase, resell, or take title to any gas or equipment you list.'),
        _section(context, '2. Eligibility & Verification',
            'To go online and receive orders, you must be verified by MobiGas. Verification requires, at minimum:\n• A valid EPRA certificate, or a sub-dealer/agent authorization letter from an EPRA-licensed parent vendor\n• Business registration documents appropriate to your business type (National ID for sole proprietors; registration certificate for registered businesses)\n• A county business permit\n• A fire clearance certificate\n• A photo of your retail point showing the cylinder holding cage and surrounding premises\n• Evidence of a compliant weighing scale (a calibration certificate, or a clear photo of a scale rated for at least 300kg)\n• Brand authorization for each gas brand you list (a brand letter, or an independent dealer association letter)\n\nMobiGas reviews these documents manually. You will not be able to go online until all required documents are uploaded and approved.'),
        _section(context, '3. Re-Verification',
            'Uploading a replacement for any previously approved document automatically resets its approval status and sends it back for re-review. Your verified badge and online status are not affected by unrelated profile edits, such as updating prices or business details.'),
        _section(context, '4. Listings & Pricing',
            '• You are solely responsible for the accuracy of the brands, products, sizes, and prices you list.\n• Refill, full-kit, and grill-kit prices are set per brand and per cylinder size — you may list different prices for different brands at the same size.\n• You may mark any product as unavailable at any time; unavailable products are not shown to customers.\n• Prices you set are the amounts customers pay you on delivery; MobiGas does not add markups on your behalf, and does not guarantee any particular order volume.'),
        _section(context, '5. Fulfilling Orders',
            '• You must honor the delivery time you have set for your listings and communicate promptly with customers if delays occur.\n• Repeated failure to deliver, or delivering products that do not match your listing, may result in suspension or removal from the platform.\n• Where an order involves a cylinder exchange, you are responsible for collecting the customer\u2019s empty cylinder as part of the transaction, unless the order is a full-kit order.'),
        _section(context, '6. Payments',
            '• Customers pay you directly on delivery — cash, or M-Pesa to the payment method you have on file (Buy Goods/Till, Paybill, or direct M-Pesa number).\n• MobiGas does not hold, collect, or process customer payments on your behalf.\n• You are responsible for ensuring your payment details are accurate and up to date; MobiGas is not liable for payments misdirected due to incorrect details you provided.\n• Platform fees, where applicable (such as finder fees on completed orders), are communicated in the app and are payable to MobiGas as invoiced.'),
        _section(context, '7. Referral Program',
            'If you were referred by another vendor using a referral code, that code is recorded once at your first setup and cannot be changed afterward. Referral rewards, if any, are governed by separate promotional terms.'),
        _section(context, '8. Ratings & Standing',
            'Your rating and review history reflect actual customer feedback and are not reset by routine profile edits (e.g. price updates, location changes). MobiGas may adjust visibility of vendors with sustained poor ratings.'),
        _section(context, '9. Compliance',
            'You are responsible for maintaining compliance with all applicable EPRA regulations, county licensing requirements, and Kenyan law relating to LPG storage, handling, and sale, independent of your verification status on MobiGas.'),
        _section(context, '10. Suspension & Termination',
            'MobiGas may suspend or terminate your account for expired or fraudulent documentation, repeated customer complaints, non-compliance with EPRA or county requirements, or violation of these terms.'),
        _section(context, '11. Limitation of Liability',
            'MobiGas facilitates connections between vendors and customers and reviews submitted documents for completeness, but does not guarantee the accuracy of any vendor\u2019s regulatory compliance beyond that review. To the extent permitted by law, MobiGas is not liable for regulatory penalties, disputes, or losses arising from your business operations.'),
        _section(context, '12. Governing Law',
            'These terms are governed by the laws of Kenya.'),
        _section(context, '13. Contact',
            'For questions about these terms, contact us at vendors@mobigas.co.ke'),
      ],
    );
  }

  // ── VENDOR PRIVACY ────────────────────────────────────────────────
  Widget _buildVendorPrivacy(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(context, 'Privacy Policy — Vendors'),
        _date(context, 'Effective: July 2026'),
        _section(context, '1. Data We Collect',
            '• Personal: Business name, owner/contact name, phone number, email, National ID or Business Registration Number\n• Location: GPS coordinates and address of your business premises, shown to customers for delivery matching\n• Verification documents: EPRA certificate or sub-dealer authorization, business registration, business permit, fire certificate, weighing scale certificate/photo, brand authorization or dealer association letter, and a photo of your premises\n• Payment details: M-Pesa number, till number, or paybill and account number, used so customers can pay you on delivery\n• Business data: Brands stocked, product listings, prices, and delivery time estimates\n• Device: FCM token, used for order notifications'),
        _section(context, '2. How We Use Your Data',
            '• To create and display your vendor profile to customers\n• To match you with nearby customers based on your location\n• To verify your regulatory compliance via the documents you upload\n• To show customers your payment details so they can pay you directly on delivery\n• To send you order and account notifications\n• To review and re-review verification documents when updated'),
        _section(context, '3. Data Sharing',
            'We share your data only with:\n• Customers browsing the platform — limited to your business name, location, brands, prices, delivery time, and rating\n• Customers with an active order from you — additionally your phone number and payment details, so they can contact and pay you\n• Regulators (e.g. EPRA, county authorities), only where required by law or in response to a lawful request\n\nWe do NOT sell your personal or business data to third parties. Your verification documents (ID, certificates, permits) are never shown to customers — only your business profile is public.'),
        _section(context, '4. Data Storage',
            'Your data, including verification documents and premises photos, is stored on Google Firebase servers (Firestore and Firebase Storage) with access restricted to authorized MobiGas staff conducting verification review. We comply with the Kenya Data Protection Act, 2019, and are registered with the ODPC.'),
        _section(context, '5. Your Rights',
            'Under the Data Protection Act, you may:\n• Access the personal and business data we hold about you\n• Correct inaccurate data\n• Request deletion of your account, subject to any statutory retention obligations (e.g. records required for regulatory compliance)\n• Withdraw consent for certain data uses, which may affect your ability to remain verified or online\n\nContact: privacy@mobigas.co.ke'),
        _section(context, '6. Security',
            'We use industry-standard encryption to protect your data in storage and in transit. Verification documents are accessible only to authorized MobiGas verification staff.'),
        _section(context, '7. Retention',
            'We retain your data for as long as your vendor account is active, and afterward for a period required to meet regulatory, tax, or dispute-resolution obligations.'),
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