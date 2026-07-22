// lib/features/bnpl/pezesha_statement_upload_screen.dart
//
// "Improve your credit score" — attach an M-Pesa statement (required)
// and a bank statement (optional), both PDF, so Pezesha can (re)score
// the borrower and return an updated limit. This is the flow from
// Pezesha's own deck: attach statement -> confirm phone + passcode ->
// submit -> new score/limit comes back.
//
// Shared by both apps — ownerType decides who's being scored, same
// pattern as PezeshaLoanStatusScreen. Requires `file_selector` and
// `firebase_storage` in pubspec.yaml.
//
// file_selector, NOT file_picker: file_picker's Android module still
// uses the pre-AGP-9 Gradle DSL and fails to configure on this
// toolchain ('Configuration with name implementation not found').
// file_selector is maintained by flutter.dev and builds cleanly.
//
// VERIFY: see pezesha_service.dart's submitStatementsForScoring
// comment — the Cloud Function contract isn't confirmed yet.

import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:mobigas/core/config/currency.dart';
import 'package:mobigas/core/services/pezesha_service.dart';

const _navy = Color(0xFF0D1B40);
const _orange = Color(0xFFF97316);
const _success = Color(0xFF16A34A);

class PezeshaStatementUploadScreen extends StatefulWidget {
  final String ownerType; // 'customer' | 'vendor'
  final String country;

  /// Pre-fills the phone field with the contact number already on
  /// file, so the borrower isn't retyping something MobiGas already
  /// knows. Optional — leave null if the caller doesn't have it handy.
  final String? initialPhone;

  const PezeshaStatementUploadScreen({
    super.key,
    required this.ownerType,
    required this.country,
    this.initialPhone,
  });

  @override
  State<PezeshaStatementUploadScreen> createState() =>
      _PezeshaStatementUploadScreenState();
}

enum _Step { form, submitting, result, error }

class _PezeshaStatementUploadScreenState
    extends State<PezeshaStatementUploadScreen> {
  final _phoneController = TextEditingController();
  final _passcodeController = TextEditingController();

  File? _mpesaFile;
  String? _mpesaFileName;
  File? _bankFile;
  String? _bankFileName;

  bool _uploadingMpesa = false;
  bool _uploadingBank = false;

  _Step _step = _Step.form;
  String? _errorMessage;
  PezeshaLoanOffer? _newOffer;

  @override
  void initState() {
    super.initState();
    _phoneController.text = widget.initialPhone ?? '';
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _passcodeController.dispose();
    super.dispose();
  }

  Future<void> _pickPdf({required bool isMpesa}) async {
    const pdfGroup = XTypeGroup(
      label: 'PDF',
      extensions: <String>['pdf'],
      mimeTypes: <String>['application/pdf'],
    );
    final picked = await openFile(acceptedTypeGroups: <XTypeGroup>[pdfGroup]);
    if (picked == null) return;
    final file = File(picked.path);
    final name = picked.name;
    setState(() {
      if (isMpesa) {
        _mpesaFile = file;
        _mpesaFileName = name;
      } else {
        _bankFile = file;
        _bankFileName = name;
      }
    });
  }

  bool get _canSubmit =>
      _mpesaFile != null &&
      _phoneController.text.trim().length >= 9 &&
      _passcodeController.text.trim().isNotEmpty &&
      !_uploadingMpesa &&
      !_uploadingBank;

  Future<void> _submit() async {
    setState(() {
      _step = _Step.submitting;
      _errorMessage = null;
    });
    try {
      setState(() => _uploadingMpesa = true);
      final mpesaPath = await PezeshaService.uploadStatementFile(
        ownerType: widget.ownerType,
        file: _mpesaFile!,
        kind: 'mpesa',
      );
      if (mounted) setState(() => _uploadingMpesa = false);

      String? bankPath;
      if (_bankFile != null) {
        if (mounted) setState(() => _uploadingBank = true);
        bankPath = await PezeshaService.uploadStatementFile(
          ownerType: widget.ownerType,
          file: _bankFile!,
          kind: 'bank',
        );
        if (mounted) setState(() => _uploadingBank = false);
      }

      final offer = await PezeshaService.submitStatementsForScoring(
        ownerType: widget.ownerType,
        mpesaStatementPath: mpesaPath,
        mpesaStatementPhone: _phoneController.text.trim(),
        mpesaStatementPasscode: _passcodeController.text.trim(),
        bankStatementPath: bankPath,
      );

      if (!mounted) return;
      setState(() {
        _newOffer = offer;
        _step = _Step.result;
      });
    } on PezeshaException catch (e) {
      if (!mounted) return;
      setState(() {
        _step = _Step.error;
        _errorMessage = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _step = _Step.error;
        _errorMessage = 'Could not submit your documents. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Improve your credit score'),
        backgroundColor: _navy,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    switch (_step) {
      case _Step.form:
        return _buildForm();
      case _Step.submitting:
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: _orange),
              SizedBox(height: 16),
              Text('Scoring your documents…',
                  style: TextStyle(color: Colors.black54)),
            ],
          ),
        );
      case _Step.result:
        return _buildResult();
      case _Step.error:
        return _buildError();
    }
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Attach your M-Pesa statement (required) and, if you have '
            'one, a bank statement — both as PDF. Pezesha uses these to '
            'give you an updated credit score and loan limit.',
            style: TextStyle(color: Colors.black54, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 20),
          _sectionLabel('M-Pesa statement (required)'),
          const SizedBox(height: 8),
          _filePickerTile(
            fileName: _mpesaFileName,
            uploading: _uploadingMpesa,
            onTap: () => _pickPdf(isMpesa: true),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'M-Pesa phone number',
              hintText: '07XXXXXXXX',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passcodeController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Statement password',
              helperText:
                  'The password Safaricom sent you to open the statement '
                  'PDF (request it via *334# if you don\'t have it).',
              helperMaxLines: 3,
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 24),
          _sectionLabel('Bank statement (optional)'),
          const SizedBox(height: 8),
          _filePickerTile(
            fileName: _bankFileName,
            uploading: _uploadingBank,
            onTap: () => _pickPdf(isMpesa: false),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _canSubmit ? _submit : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Submit for scoring'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(
            color: _navy, fontWeight: FontWeight.w700, fontSize: 14),
      );

  Widget _filePickerTile({
    required String? fileName,
    required bool uploading,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: uploading ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _navy.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _navy.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Icon(
              fileName != null
                  ? Icons.picture_as_pdf_rounded
                  : Icons.upload_file_rounded,
              color:
                  fileName != null ? _orange : _navy.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                fileName ?? 'Tap to choose a PDF',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fileName != null ? _navy : Colors.black45,
                  fontWeight:
                      fileName != null ? FontWeight.w600 : FontWeight.w400,
                  fontSize: 13,
                ),
              ),
            ),
            if (uploading)
              const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildResult() {
    final offer = _newOffer;
    return offer != null ? _buildApproved(offer) : _buildNoLimitYet();
  }

  Widget _buildApproved(PezeshaLoanOffer offer) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded, color: _success, size: 56),
            const SizedBox(height: 16),
            Text(
              'You\'re now approved for up to '
              '${Currency.formatFor(widget.country, offer.amount)}.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: _navy, fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Repaid over ${offer.duration} days. Your statement went to '
              'Pezesha and has been deleted from MobiGas — we don\'t keep '
              'a copy.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.black54, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: _orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Scored, but Pezesha returned no limit.
  ///
  /// Deliberately NOT the green tick — nothing was approved, and
  /// dressing a decline as a success is the kind of thing people
  /// remember. The point of this state is to leave someone who has
  /// just done real work with a concrete next action, instead of the
  /// dead end the old copy ended on ("keep ordering to build your
  /// record"), which was the same non-answer they saw BEFORE
  /// uploading anything.
  ///
  /// VERIFY: Pezesha hasn't confirmed whether Datascore returns a
  /// decline reason, a minimum qualifying score, or a cool-off before
  /// re-scoring (see pezesha.ts VERIFY items). So everything suggested
  /// below is limited to what's true regardless of their scorecard —
  /// more history scores better than less — rather than inventing a
  /// reason. Replace these with the real remediation once they answer.
  Widget _buildNoLimitYet() {
    final hasBank = _bankFile != null;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.hourglass_empty_rounded, color: _orange, size: 48),
          const SizedBox(height: 16),
          const Text(
            'Not enough to set a limit yet',
            style: TextStyle(
                color: _navy, fontWeight: FontWeight.w800, fontSize: 18),
          ),
          const SizedBox(height: 8),
          const Text(
            'Pezesha scored what you sent but hasn\'t set a limit on it '
            'yet. Your statement went to them and has been deleted from '
            'MobiGas — we don\'t keep a copy.',
            style: TextStyle(color: Colors.black54, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 22),
          const Text('What usually helps',
              style: TextStyle(
                  color: _navy, fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 10),
          if (!hasBank)
            _tip('Add a bank statement. More history gives Pezesha more '
                'to score — it\'s the biggest thing you can add right now.'),
          _tip('Send 12 months instead of 6, if you have it.'),
          _tip('Keep ordering through MobiGas. Your order history builds '
              'a record that counts on your next check.'),
          const SizedBox(height: 24),
          if (!hasBank) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                // Back to the form with the M-Pesa file still selected,
                // so adding a bank statement is one more tap rather
                // than starting over.
                onPressed: () => setState(() => _step = _Step.form),
                style: ElevatedButton.styleFrom(
                    backgroundColor: _orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                child: const Text('Add a bank statement'),
              ),
            ),
            const SizedBox(height: 10),
          ],
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              // pop(false) — scoring ran but produced no limit. The
              // vendor card treats `true` as "a limit came back, reopen
              // the limit sheet", and reopening it here would just
              // repeat the answer this screen already gave in more
              // detail. The customer card likewise only re-checks on
              // true. Cancelling (system back) pops null, which both
              // read the same way.
              onPressed: () => Navigator.of(context).pop(false),
              style: OutlinedButton.styleFrom(
                foregroundColor: _navy,
                side: BorderSide(color: _navy.withValues(alpha: 0.3)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Done'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tip(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(Icons.arrow_right_rounded, size: 18, color: _orange),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(text,
                  style: const TextStyle(
                      color: Colors.black54, fontSize: 13, height: 1.4)),
            ),
          ],
        ),
      );

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_errorMessage ?? 'Something went wrong.',
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => setState(() => _step = _Step.form),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
