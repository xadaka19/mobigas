import 'package:flutter/material.dart';
import 'package:mobigas/core/theme/app_theme.dart';
import 'package:mobigas/core/services/firestore_service.dart';

/// Shared per-order chat — used by both apps. Scoped to a single
/// delivery, not a general DM: a vendor and customer coordinating on
/// THIS order (e.g. "no credit to call, use this instead").
class OrderChatScreen extends StatefulWidget {
  final String orderId;
  final String customerId;
  final String vendorId;
  final String customerName;
  final String vendorName;
  final String currentUserId;
  final String currentUserType; // 'customer' | 'vendor'

  const OrderChatScreen({
    super.key,
    required this.orderId,
    required this.customerId,
    required this.vendorId,
    required this.customerName,
    required this.vendorName,
    required this.currentUserId,
    required this.currentUserType,
  });

  @override
  State<OrderChatScreen> createState() => _OrderChatScreenState();
}

class _OrderChatScreenState extends State<OrderChatScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isSending = false;

  String get _currentUserName => widget.currentUserType == 'vendor'
      ? widget.vendorName
      : widget.customerName;
  String get _otherPartyName => widget.currentUserType == 'vendor'
      ? widget.customerName
      : widget.vendorName;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await FirestoreService.ensureOrderChatExists(
      orderId: widget.orderId,
      customerId: widget.customerId,
      vendorId: widget.vendorId,
      customerName: widget.customerName,
      vendorName: widget.vendorName,
    );
    await FirestoreService.markOrderChatRead(
      orderId: widget.orderId,
      readerId: widget.currentUserId,
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _textController.text;
    if (text.trim().isEmpty || _isSending) return;
    setState(() => _isSending = true);
    _textController.clear();
    try {
      await FirestoreService.sendOrderChatMessage(
        orderId: widget.orderId,
        senderId: widget.currentUserId,
        senderType: widget.currentUserType,
        senderName: _currentUserName,
        text: text,
      );
      // Give the list a moment to receive the new message, then
      // scroll to it.
      Future.delayed(const Duration(milliseconds: 200), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
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
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: FirestoreService.watchOrderChatMessages(widget.orderId),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.orange));
                  }
                  final messages = snap.data!;
                  if (messages.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.chat_bubble_outline_rounded,
                                size: 56, color: AppColors.gray400),
                            const SizedBox(height: 12),
                            Text('No messages yet',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(color: AppColors.gray600)),
                            const SizedBox(height: 4),
                            Text(
                                'Send a message to $_otherPartyName about this order',
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: AppColors.gray400)),
                          ],
                        ),
                      ),
                    );
                  }
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_scrollController.hasClients) {
                      _scrollController.jumpTo(
                          _scrollController.position.maxScrollExtent);
                    }
                  });
                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (_, i) => _messageBubble(messages[i]),
                  );
                },
              ),
            ),
            _buildInputBar(),
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
                Text(_otherPartyName,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(color: AppColors.white)),
                Text('Order ${widget.orderId}',
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

  Widget _messageBubble(Map<String, dynamic> msg) {
    final isMine = msg['senderId'] == widget.currentUserId;
    final createdAt = msg['createdAt'] as DateTime?;
    final timeStr = createdAt != null
        ? '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}'
        : '';
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isMine ? AppColors.orange : AppColors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isMine ? 14 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 14),
          ),
          border: isMine ? null : Border.all(color: AppColors.gray200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(msg['text'] as String,
                style: TextStyle(
                    color: isMine ? AppColors.white : AppColors.navy,
                    fontSize: 14)),
            const SizedBox(height: 4),
            Text(timeStr,
                style: TextStyle(
                    color: isMine
                        ? AppColors.white.withValues(alpha: 0.7)
                        : AppColors.gray400,
                    fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Type a message...',
                filled: true,
                fillColor: AppColors.gray100,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _isSending ? null : _send,
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: AppColors.orange,
                shape: BoxShape.circle,
              ),
              child: _isSending
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.white),
                    )
                  : const Icon(Icons.send_rounded,
                      color: AppColors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
