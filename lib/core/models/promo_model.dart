import 'package:cloud_firestore/cloud_firestore.dart';

class PromoModel {
  final String id;
  final String title;
  final String highlightText;
  final String discountText;
  final String imageUrl;
  final String ctaText;
  final String targetAudience; // customer | vendor | all
  final String targetCountry;  // KE | TZ | UG | all
  final String actionType;     // route | url
  final String actionTarget;
  final bool isActive;
  final int priority;
  final String frequency;      // once_ever | once_per_day | every_launch
  final DateTime? startDate;
  final DateTime? endDate;

  // Sponsored / third-party advertiser fields
  final bool isSponsored;
  final String advertiserName;
  final String advertiserLogoUrl;
  final String campaignId;
  final String disclosureText;

  PromoModel({
    required this.id,
    required this.title,
    required this.highlightText,
    required this.discountText,
    required this.imageUrl,
    required this.ctaText,
    required this.targetAudience,
    required this.targetCountry,
    required this.actionType,
    required this.actionTarget,
    required this.isActive,
    required this.priority,
    required this.frequency,
    this.startDate,
    this.endDate,
    this.isSponsored = false,
    this.advertiserName = '',
    this.advertiserLogoUrl = '',
    this.campaignId = '',
    this.disclosureText = 'Ads by MobiGas',
  });

  factory PromoModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PromoModel(
      id: doc.id,
      title: data['title'] ?? '',
      highlightText: data['highlightText'] ?? '',
      discountText: data['discountText'] ?? '',
      imageUrl: data['imageUrl'] ?? '',
      ctaText: data['ctaText'] ?? 'Order Now',
      targetAudience: data['targetAudience'] ?? 'all',
      targetCountry: data['targetCountry'] ?? 'all',
      actionType: data['actionType'] ?? 'route',
      actionTarget: data['actionTarget'] ?? '/',
      isActive: data['isActive'] ?? false,
      priority: data['priority'] ?? 99,
      frequency: data['frequency'] ?? 'once_per_day',
      startDate: (data['startDate'] as Timestamp?)?.toDate(),
      endDate: (data['endDate'] as Timestamp?)?.toDate(),
      isSponsored: data['isSponsored'] ?? false,
      advertiserName: data['advertiserName'] ?? '',
      advertiserLogoUrl: data['advertiserLogoUrl'] ?? '',
      campaignId: data['campaignId'] ?? '',
      disclosureText: data['disclosureText'] ?? 'Ads by MobiGas',
    );
  }

  bool get isWithinDateRange {
    final now = DateTime.now();
    if (startDate != null && now.isBefore(startDate!)) return false;
    if (endDate != null && now.isAfter(endDate!)) return false;
    return true;
  }
}
