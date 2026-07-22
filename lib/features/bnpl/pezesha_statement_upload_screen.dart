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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded, color: _success, size: 56),
            const SizedBox(height: 16),
            Text(
              offer != null
                  ? 'You\'re now approved for up to '
                      '${Currency.formatFor(widget.country, offer.amount)}.'
                  : 'Your documents were submitted. No limit is available '
                      'yet — keep ordering through MobiGas to build your '
                      'record.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: _navy, fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _orange, foregroundColor: Colors.white),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

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
