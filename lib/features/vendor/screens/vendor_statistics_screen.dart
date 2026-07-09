import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:mobigas/core/theme/app_theme.dart';

/// Detailed sales & fulfillment statistics for a vendor, with a
/// month-on-month breakdown and a PDF export, so a vendor has a clear
/// record of their own trading history on the platform.
///
/// Reads from two Cloud Function-maintained aggregate collections
/// rather than the vendor's raw order history, so this screen stays
/// fast (at most 12 document reads for the trend, 1 for lifetime
/// totals) no matter how many orders a vendor accumulates over time.
/// See functions/src/index.ts: onOrderStatusChange, backfillVendorStats.
class VendorStatisticsScreen extends StatefulWidget {
  final Map<String, dynamic> vendorData;
  const VendorStatisticsScreen({super.key, required this.vendorData});

  @override
  State<VendorStatisticsScreen> createState() =>
      _VendorStatisticsScreenState();
}

class _MonthStat {
  final DateTime month;
  final int fulfilled;
  final int customerCancelled;
  final int vendorDeclined;
  final int otherCancelled;
  final double cashSales;

  const _MonthStat({
    required this.month,
    this.fulfilled = 0,
    this.customerCancelled = 0,
    this.vendorDeclined = 0,
    this.otherCancelled = 0,
    this.cashSales = 0,
  });

  int get totalCancelled =>
      customerCancelled + vendorDeclined + otherCancelled;
  double get totalSales => cashSales;

  factory _MonthStat.empty(DateTime month) => _MonthStat(month: month);

  factory _MonthStat.fromDoc(DateTime month, Map<String, dynamic> d) {
    return _MonthStat(
      month: month,
      fulfilled: (d['fulfilled'] ?? 0) as int,
      customerCancelled: (d['customerCancelled'] ?? 0) as int,
      vendorDeclined: (d['vendorDeclined'] ?? 0) as int,
      otherCancelled: (d['otherCancelled'] ?? 0) as int,
      cashSales: (d['cashSales'] ?? 0).toDouble(),
    );
  }
}

class _VendorStatisticsScreenState extends State<VendorStatisticsScreen> {
  String get _vendorId => FirebaseAuth.instance.currentUser?.uid ?? '';
  bool _isGeneratingPdf = false;

  /// Lifetime running totals — one document, updated by the Cloud
  /// Function on every order that reaches delivered/cancelled.
  Stream<DocumentSnapshot<Map<String, dynamic>>> get _alltimeStream {
    return FirebaseFirestore.instance
        .collection('vendor_stats_alltime')
        .doc(_vendorId)
        .snapshots();
  }

  /// Last 12 months of per-month aggregate docs — at most 12 reads
  /// regardless of how many orders exist outside that window.
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      get _monthlyStream {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month - 11, 1);
    final startKey =
        '${start.year}-${start.month.toString().padLeft(2, '0')}';
    return FirebaseFirestore.instance
        .collection('vendor_stats_monthly')
        .where('vendorId', isEqualTo: _vendorId)
        .where('yearMonth', isGreaterThanOrEqualTo: startKey)
        .orderBy('yearMonth')
        .snapshots()
        .map((snap) => snap.docs);
  }

  /// Merges the sparse monthly docs (only months with activity have a
  /// doc) into a continuous 12-month series — the shape of the
  /// business over time is clearer when quiet months are shown too.
  List<_MonthStat> _continuousMonths(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final now = DateTime.now();
    final byKey = <String, Map<String, dynamic>>{
      for (final d in docs) d.data()['yearMonth']: d.data(),
    };
    final result = <_MonthStat>[];
    for (int i = 11; i >= 0; i--) {
      final m = DateTime(now.year, now.month - i, 1);
      final key = '${m.year}-${m.month.toString().padLeft(2, '0')}';
      final data = byKey[key];
      result.add(
          data != null ? _MonthStat.fromDoc(m, data) : _MonthStat.empty(m));
    }
    return result;
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
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: _alltimeStream,
                builder: (context, alltimeSnap) {
                  if (alltimeSnap.hasError) {
                    return _errorView(alltimeSnap.error.toString());
                  }
                  return StreamBuilder<
                      List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
                    stream: _monthlyStream,
                    builder: (context, monthlySnap) {
                      if (monthlySnap.hasError) {
                        return _errorView(monthlySnap.error.toString());
                      }
                      if (!alltimeSnap.hasData || !monthlySnap.hasData) {
                        return const Center(
                            child: CircularProgressIndicator(
                                color: AppColors.orange));
                      }
                      final a = alltimeSnap.data!.data() ?? {};
                      final fulfilled = (a['fulfilled'] ?? 0) as int;
                      final customerCancelled =
                          (a['customerCancelled'] ?? 0) as int;
                      final vendorDeclined = (a['vendorDeclined'] ?? 0) as int;
                      final otherCancelled = (a['otherCancelled'] ?? 0) as int;
                      final totalCancelled = customerCancelled +
                          vendorDeclined +
                          otherCancelled;
                      final totalSales = (a['cashSales'] ?? 0).toDouble();
                      final fulfillmentRate =
                          (fulfilled + totalCancelled) == 0
                              ? 0.0
                              : fulfilled / (fulfilled + totalCancelled);
                      final monthly = _continuousMonths(monthlySnap.data!);

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
                              fulfilled: fulfilled,
                              cancelled: totalCancelled,
                              fulfillmentRate: fulfillmentRate,
                            ),
                            const SizedBox(height: 12),
                            _cancellationBreakdown(
                              customerCancelled,
                              vendorDeclined,
                              otherCancelled,
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
                                      fulfilled,
                                      customerCancelled,
                                      vendorDeclined,
                                      otherCancelled,
                                      monthly,
                                      totalSales,
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
                              'Download or share a record of your MobiGas sales history at any time.',
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
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Shown instead of an infinite spinner if either aggregate stream
  /// errors — most likely a missing Firestore composite index on
  /// vendor_stats_monthly (vendorId + yearMonth), which this query
  /// requires. The console/logcat error contains a direct link that
  /// creates the index in one click.
  Widget _errorView(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppColors.error, size: 48),
            const SizedBox(height: 16),
            Text('Could not load statistics',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: AppColors.navy)),
            const SizedBox(height: 8),
            Text(
              error.contains('failed-precondition') ||
                      error.contains('index')
                  ? 'This usually means a required database index hasn\'t been created yet. Check the app console/logs for a link that creates it automatically.'
                  : error,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.gray400, height: 1.5),
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
    required int fulfilled,
    required int cancelled,
    required double fulfillmentRate,
  }) {
    final cards = [
      ('Total sales', 'KES ${totalSales.toStringAsFixed(0)}',
          Icons.account_balance_wallet_rounded, AppColors.success),
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

  /// Breaks the aggregate "Orders cancelled" figure down by who
  /// cancelled — whether a vendor is declining orders themselves is
  /// meaningfully different from customers changing their minds.
  /// "Not recorded" only appears for orders cancelled before this
  /// tracking existed.
  Widget _cancellationBreakdown(
      int customerCancelled, int vendorDeclined, int otherCancelled) {
    if (customerCancelled + vendorDeclined + otherCancelled == 0) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gray200),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        children: [
          _breakdownItem('Cancelled by customer', customerCancelled),
          _breakdownItem('Declined by vendor', vendorDeclined),
          if (otherCancelled > 0)
            _breakdownItem('Not recorded', otherCancelled),
        ],
      ),
    );
  }

  Widget _breakdownItem(String label, int value) {
    return Text('$label: $value',
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: AppColors.gray600, fontSize: 11));
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
    int fulfilled,
    int customerCancelled,
    int vendorDeclined,
    int otherCancelled,
    List<_MonthStat> monthly,
    double totalSales,
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
                      fontSize: 12,
                      color: gray,
                      fontStyle: pw.FontStyle.italic)),
              pw.Divider(color: navy, thickness: 1),
              pw.SizedBox(height: 8),
            ],
          ),
          footer: (context) => pw.Column(
            children: [
              pw.Divider(color: PdfColors.grey300),
              pw.Text(
                'This statement reflects transactions recorded on the MobiGas platform '
                'and is provided for the vendor\'s own reference.',
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
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                    color: navy)),
            pw.SizedBox(height: 8),
            pw.Table(
              border:
                  pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              columnWidths: const {
                0: pw.FlexColumnWidth(2),
                1: pw.FlexColumnWidth(1),
              },
              children: [
                _pdfRow('Total sales (all time)',
                    'KES ${totalSales.toStringAsFixed(0)}', bold: true),
                _pdfRow('Orders fulfilled', '$fulfilled'),
                _pdfRow('Cancelled by customer', '$customerCancelled'),
                _pdfRow('Declined by vendor', '$vendorDeclined'),
                if (otherCancelled > 0)
                  _pdfRow('Cancelled (reason not recorded)',
                      '$otherCancelled'),
                _pdfRow('Fulfillment rate',
                    '${(fulfillmentRate * 100).toStringAsFixed(0)}%'),
              ],
            ),
            pw.SizedBox(height: 20),
            pw.Text('Month-on-month (last 12 months)',
                style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                    color: navy)),
            pw.SizedBox(height: 8),
            pw.Table(
              border:
                  pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              columnWidths: const {
                0: pw.FlexColumnWidth(1.5),
                1: pw.FlexColumnWidth(1),
                2: pw.FlexColumnWidth(1.2),
                3: pw.FlexColumnWidth(1),
                4: pw.FlexColumnWidth(1),
              },
              children: [
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _pdfHeaderCell('Month'),
                    _pdfHeaderCell('Orders'),
                    _pdfHeaderCell('Sales'),
                    _pdfHeaderCell('Cust.\nCancel'),
                    _pdfHeaderCell('Vendor\nDecline'),
                  ],
                ),
                ...monthly.map((m) => pw.TableRow(children: [
                      _pdfCell(_monthLabel(m.month)),
                      _pdfCell('${m.fulfilled}'),
                      _pdfCell(m.totalSales.toStringAsFixed(0)),
                      _pdfCell('${m.customerCancelled}'),
                      _pdfCell('${m.vendorDeclined}'),
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
                fontWeight:
                    bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
      ),
    ]);
  }

  pw.Widget _pdfHeaderCell(String text) => pw.Padding(
        padding: const pw.EdgeInsets.all(4),
        child: pw.Text(text,
            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
      );

  pw.Widget _pdfCell(String text) => pw.Padding(
        padding: const pw.EdgeInsets.all(4),
        child: pw.Text(text, style: const pw.TextStyle(fontSize: 8)),
      );
}