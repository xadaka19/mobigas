import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:mobigas/core/theme/app_theme.dart';
import 'package:mobigas/core/services/firebase_service.dart';
import 'package:mobigas/core/models/app_models.dart';

/// Detailed sales & fulfillment statistics for a vendor, with a
/// month-on-month breakdown and a PDF export — built specifically so
/// a vendor can hand their MobiGas transaction history to ANY bank,
/// not just MobiGas's partner banks, as independent proof of income.
class VendorStatisticsScreen extends StatefulWidget {
  final Map<String, dynamic> vendorData;
  const VendorStatisticsScreen({super.key, required this.vendorData});

  @override
  State<VendorStatisticsScreen> createState() =>
      _VendorStatisticsScreenState();
}

class _MonthStat {
  final DateTime month; // first day of the month, for sorting/labeling
  int fulfilled = 0;
  int cancelled = 0;
  double cashSales = 0;
  double creditSales = 0;
  double get totalSales => cashSales + creditSales;
  _MonthStat(this.month);
}

class _VendorStatisticsScreenState extends State<VendorStatisticsScreen> {
  String get _vendorId => FirebaseAuth.instance.currentUser?.uid ?? '';
  bool _isGeneratingPdf = false;

  Stream<List<OrderModel>> get _allOrdersStream {
    return FirebaseService.orders
        .where('vendorId', isEqualTo: _vendorId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return _orderFromMap(doc.id, data);
            }).toList());
  }

  OrderModel _orderFromMap(String docId, Map<String, dynamic> data) {
    return OrderModel(
      orderId: data['orderId'] ?? docId,
      customerId: data['customerId'] ?? '',
      vendorId: data['vendorId'] ?? '',
      vendorName: data['vendorName'] ?? '',
      vendorPhone: data['vendorPhone'] ?? '',
      customerName: data['customerName'] ?? '',
      customerArea: data['customerArea'] ?? '',
      listing: GasListing(
        size: data['gasSize'] ?? '',
        kg: data['gasKg'] ?? 0,
        price: (data['gasPrice'] ?? 0).toDouble(),
        available: true,
        productType: GasProductType.values.firstWhere(
          (t) => t.name == (data['gasProductType'] ?? 'refill'),
          orElse: () => GasProductType.refill,
        ),
      ),
      paymentMethod: PaymentMethod.values.firstWhere(
        (m) => m.name == (data['paymentMethod'] ?? 'credit'),
        orElse: () => PaymentMethod.credit,
      ),
      finderFee: (data['finderFee'] ?? 0).toDouble(),
      bankDisbursementAmount: (data['bankDisbursementAmount'] ?? 0).toDouble(),
      originationFeeToMobigas:
          (data['originationFeeToMobigas'] ?? 0).toDouble(),
      pin: data['pin'] ?? '',
      status: OrderStatus.values.firstWhere(
        (e) => e.name == data['status'],
        orElse: () => OrderStatus.pending,
      ),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      partnerBankName: data['partnerBankName'] ?? '',
      riderName: data['riderName'],
      riderPhone: data['riderPhone'],
    );
  }

  /// Builds a continuous last-12-months series (including months with
  /// zero orders) — a bank reviewing this wants to see the shape of
  /// the business over time, not just months where something happened.
  List<_MonthStat> _monthlyBreakdown(List<OrderModel> orders) {
    final now = DateTime.now();
    final months = <String, _MonthStat>{};
    for (int i = 11; i >= 0; i--) {
      final m = DateTime(now.year, now.month - i, 1);
      months['${m.year}-${m.month}'] = _MonthStat(m);
    }
    for (final o in orders) {
      final key = '${o.createdAt.year}-${o.createdAt.month}';
      final stat = months[key];
      if (stat == null) continue; // outside the 12-month window
      if (o.status == OrderStatus.delivered) {
        stat.fulfilled++;
        if (o.paymentMethod == PaymentMethod.cash) {
          stat.cashSales += o.listing.price;
        } else {
          stat.creditSales += o.listing.price;
        }
      } else if (o.status == OrderStatus.cancelled) {
        stat.cancelled++;
      }
    }
    return months.values.toList();
  }

  String _monthLabel(DateTime m) {
    const names = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${names[m.month - 1]} ${m.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.orangeWarm,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: StreamBuilder<List<OrderModel>>(
                stream: _allOrdersStream,
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.orange));
                  }
                  final orders = snap.data!;
                  final delivered = orders
                      .where((o) => o.status == OrderStatus.delivered)
                      .toList();
                  final cancelled = orders
                      .where((o) => o.status == OrderStatus.cancelled)
                      .length;
                  final defaulted = orders
                      .where((o) => o.status == OrderStatus.defaulted)
                      .length;
                  final cashSales = delivered
                      .where((o) => o.paymentMethod == PaymentMethod.cash)
                      .fold(0.0, (a, o) => a + o.listing.price);
                  final creditSales = delivered
                      .where((o) => o.paymentMethod == PaymentMethod.credit)
                      .fold(0.0, (a, o) => a + o.listing.price);
                  final totalSales = cashSales + creditSales;
                  final fulfillmentRate = (delivered.length + cancelled) == 0
                      ? 0.0
                      : delivered.length / (delivered.length + cancelled);
                  final monthly = _monthlyBreakdown(orders);

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Overview',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                    color: AppColors.navy,
                                    fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        _summaryGrid(
                          totalSales: totalSales,
                          cashSales: cashSales,
                          creditSales: creditSales,
                          fulfilled: delivered.length,
                          cancelled: cancelled,
                          defaulted: defaulted,
                          fulfillmentRate: fulfillmentRate,
                        ),
                        const SizedBox(height: 28),
                        Row(
                          children: [
                            Text('Month-on-month',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                        color: AppColors.navy,
                                        fontWeight: FontWeight.w700)),
                            const Spacer(),
                            Text('Last 12 months',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: AppColors.gray400)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _monthlyTable(monthly),
                        const SizedBox(height: 28),
                        ElevatedButton.icon(
                          onPressed: _isGeneratingPdf
                              ? null
                              : () => _sharePdf(
                                  delivered, cancelled, defaulted, monthly,
                                  totalSales, cashSales, creditSales,
                                  fulfillmentRate),
                          icon: _isGeneratingPdf
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.white),
                                )
                              : const Icon(Icons.picture_as_pdf_rounded,
                                  size: 20),
                          label: Text(_isGeneratingPdf
                              ? 'Preparing report...'
                              : 'Share PDF report'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 52),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Share this report with any bank as proof of your MobiGas sales history — not limited to MobiGas partner banks.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: AppColors.gray400,
                                  height: 1.4,
                                  fontSize: 11),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: const BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(Icons.arrow_back_ios_rounded,
                color: AppColors.white, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Statistics & Reports',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(color: AppColors.white)),
                Text(widget.vendorData['businessName'] ?? '',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.gray400)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryGrid({
    required double totalSales,
    required double cashSales,
    required double creditSales,
    required int fulfilled,
    required int cancelled,
    required int defaulted,
    required double fulfillmentRate,
  }) {
    final cards = [
      ('Total sales', 'KES ${totalSales.toStringAsFixed(0)}',
          Icons.account_balance_wallet_rounded, AppColors.success),
      ('Cash sales', 'KES ${cashSales.toStringAsFixed(0)}',
          Icons.payments_rounded, AppColors.navy),
      ('Credit sales', 'KES ${creditSales.toStringAsFixed(0)}',
          Icons.credit_score_rounded, AppColors.orange),
      ('Orders fulfilled', '$fulfilled',
          Icons.check_circle_rounded, AppColors.success),
      ('Orders cancelled', '$cancelled',
          Icons.cancel_rounded, AppColors.error),
      ('Fulfillment rate', '${(fulfillmentRate * 100).toStringAsFixed(0)}%',
          Icons.trending_up_rounded, AppColors.orange),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: cards
          .map((c) => Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.gray200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(c.$3, color: c.$4, size: 20),
                    const Spacer(),
                    Text(c.$2,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                                color: AppColors.navy,
                                fontWeight: FontWeight.w800,
                                fontSize: 16)),
                    Text(c.$1,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                                color: AppColors.gray400, fontSize: 11)),
                  ],
                ),
              ))
          .toList(),
    );
  }

  Widget _monthlyTable(List<_MonthStat> monthly) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gray200),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: AppColors.gray100,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Expanded(
                    flex: 2,
                    child: Text('Month',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.gray600,
                            fontWeight: FontWeight.w700))),
                Expanded(
                    child: Text('Orders',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.gray600,
                            fontWeight: FontWeight.w700))),
                Expanded(
                    flex: 2,
                    child: Text('Sales',
                        textAlign: TextAlign.end,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.gray600,
                            fontWeight: FontWeight.w700))),
              ],
            ),
          ),
          ...monthly.map((m) => Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: const BoxDecoration(
                  border: Border(
                      top: BorderSide(color: AppColors.gray200, width: 0.5)),
                ),
                child: Row(
                  children: [
                    Expanded(
                        flex: 2,
                        child: Text(_monthLabel(m.month),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.navy))),
                    Expanded(
                        child: Text('${m.fulfilled}',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.navy))),
                    Expanded(
                        flex: 2,
                        child: Text(
                            'KES ${m.totalSales.toStringAsFixed(0)}',
                            textAlign: TextAlign.end,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: AppColors.navy,
                                    fontWeight: FontWeight.w600))),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Future<void> _sharePdf(
    List<OrderModel> delivered,
    int cancelled,
    int defaulted,
    List<_MonthStat> monthly,
    double totalSales,
    double cashSales,
    double creditSales,
    double fulfillmentRate,
  ) async {
    setState(() => _isGeneratingPdf = true);
    try {
      final businessName = widget.vendorData['businessName'] ?? 'Vendor';
      final ownerName = widget.vendorData['ownerName'] ?? '';
      final phone = widget.vendorData['phone'] ?? '';
      final now = DateTime.now();
      final navy = PdfColor.fromInt(0xFF0D1B40);
      final orange = PdfColor.fromInt(0xFFF97316);
      final gray = PdfColor.fromInt(0xFF6B7280);

      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          header: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('MobiGas',
                      style: pw.TextStyle(
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold,
                          color: orange)),
                  pw.Text(
                      '${now.day}/${now.month}/${now.year}',
                      style: pw.TextStyle(fontSize: 10, color: gray)),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Text('Vendor Sales & Fulfillment Statement',
                  style: pw.TextStyle(
                      fontSize: 12, color: gray, fontStyle: pw.FontStyle.italic)),
              pw.Divider(color: navy, thickness: 1),
              pw.SizedBox(height: 8),
            ],
          ),
          footer: (context) => pw.Column(
            children: [
              pw.Divider(color: PdfColors.grey300),
              pw.Text(
                'This statement reflects transactions recorded on the MobiGas platform '
                'and is provided for the vendor\'s own use, including with third-party '
                'lenders. MobiGas does not guarantee third-party credit decisions.',
                style: pw.TextStyle(fontSize: 8, color: gray),
              ),
              pw.SizedBox(height: 4),
              pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
                  style: pw.TextStyle(fontSize: 8, color: gray)),
            ],
          ),
          build: (context) => [
            pw.Container(
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(
                color: navy,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(businessName,
                      style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white)),
                  if (ownerName.isNotEmpty)
                    pw.Text('Owner: $ownerName',
                        style: pw.TextStyle(
                            fontSize: 10, color: PdfColors.grey300)),
                  if (phone.isNotEmpty)
                    pw.Text('Phone: $phone',
                        style: pw.TextStyle(
                            fontSize: 10, color: PdfColors.grey300)),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Text('Summary',
                style: pw.TextStyle(
                    fontSize: 13, fontWeight: pw.FontWeight.bold, color: navy)),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              columnWidths: const {
                0: pw.FlexColumnWidth(2),
                1: pw.FlexColumnWidth(1),
              },
              children: [
                _pdfRow('Total sales (all time)',
                    'KES ${totalSales.toStringAsFixed(0)}', bold: true),
                _pdfRow('Cash sales', 'KES ${cashSales.toStringAsFixed(0)}'),
                _pdfRow(
                    'Credit sales', 'KES ${creditSales.toStringAsFixed(0)}'),
                _pdfRow('Orders fulfilled', '${delivered.length}'),
                _pdfRow('Orders cancelled', '$cancelled'),
                if (defaulted > 0)
                  _pdfRow('Credit orders defaulted', '$defaulted'),
                _pdfRow('Fulfillment rate',
                    '${(fulfillmentRate * 100).toStringAsFixed(0)}%'),
              ],
            ),
            pw.SizedBox(height: 20),
            pw.Text('Month-on-month (last 12 months)',
                style: pw.TextStyle(
                    fontSize: 13, fontWeight: pw.FontWeight.bold, color: navy)),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              columnWidths: const {
                0: pw.FlexColumnWidth(1.5),
                1: pw.FlexColumnWidth(1),
                2: pw.FlexColumnWidth(1.2),
                3: pw.FlexColumnWidth(1.2),
                4: pw.FlexColumnWidth(1.2),
              },
              children: [
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _pdfHeaderCell('Month'),
                    _pdfHeaderCell('Orders'),
                    _pdfHeaderCell('Cash (KES)'),
                    _pdfHeaderCell('Credit (KES)'),
                    _pdfHeaderCell('Total (KES)'),
                  ],
                ),
                ...monthly.map((m) => pw.TableRow(children: [
                      _pdfCell(_monthLabel(m.month)),
                      _pdfCell('${m.fulfilled}'),
                      _pdfCell(m.cashSales.toStringAsFixed(0)),
                      _pdfCell(m.creditSales.toStringAsFixed(0)),
                      _pdfCell(m.totalSales.toStringAsFixed(0)),
                    ])),
              ],
            ),
          ],
        ),
      );

      final bytes = await pdf.save();
      await Printing.sharePdf(
        bytes: bytes,
        filename:
            'MobiGas_Statement_${businessName.replaceAll(' ', '_')}_${now.year}${now.month.toString().padLeft(2, '0')}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not generate report: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
    if (mounted) setState(() => _isGeneratingPdf = false);
  }

  pw.TableRow _pdfRow(String label, String value, {bool bold = false}) {
    return pw.TableRow(children: [
      pw.Padding(
        padding: const pw.EdgeInsets.all(6),
        child: pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.all(6),
        child: pw.Text(value,
            style: pw.TextStyle(
                fontSize: 10,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
      ),
    ]);
  }

  pw.Widget _pdfHeaderCell(String text) => pw.Padding(
        padding: const pw.EdgeInsets.all(6),
        child: pw.Text(text,
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
      );

  pw.Widget _pdfCell(String text) => pw.Padding(
        padding: const pw.EdgeInsets.all(6),
        child: pw.Text(text, style: const pw.TextStyle(fontSize: 9)),
      );
}
