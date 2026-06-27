import 'package:flutter/material.dart';
import 'package:mobigas/core/theme/app_theme.dart';

class MapPlaceholder extends StatefulWidget {
  final String customerArea;
  final String? riderName;
  final double height;
  final bool showRiderDot;

  const MapPlaceholder({
    super.key,
    required this.customerArea,
    this.riderName,
    this.height = 220,
    this.showRiderDot = true,
  });

  @override
  State<MapPlaceholder> createState() => _MapPlaceholderState();
}

class _MapPlaceholderState extends State<MapPlaceholder>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnim;
  late Animation<Offset> _riderAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _riderAnim = Tween<Offset>(
      begin: const Offset(0.15, 0.65),
      end: const Offset(0.40, 0.45),
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: Stack(
          children: [
            _buildMapBackground(),
            _buildDestinationPin(),
            if (widget.showRiderDot) _buildRiderDot(),
            _buildTopOverlay(),
            _buildBottomOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildMapBackground() {
    return Container(
      decoration: const BoxDecoration(color: Color(0xFFE8F0E8)),
      child: CustomPaint(
        painter: _MapGridPainter(),
        size: Size.infinite,
      ),
    );
  }

  Widget _buildDestinationPin() {
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (context, child) {
        return Stack(
          children: [
            Positioned(
              left: MediaQuery.of(context).size.width * 0.5 - 24,
              top: widget.height * 0.38 - 24,
              child: Transform.scale(
                scale: _pulseAnim.value,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.orange.withValues(alpha: 0.2),
                  ),
                ),
              ),
            ),
            Positioned(
              left: MediaQuery.of(context).size.width * 0.5 - 16,
              top: widget.height * 0.38 - 16,
              child: Column(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      color: AppColors.orange,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.home_rounded,
                        color: AppColors.white, size: 18),
                  ),
                  CustomPaint(
                    painter: _PinTailPainter(AppColors.orange),
                    size: const Size(12, 8),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRiderDot() {
    return AnimatedBuilder(
      animation: _riderAnim,
      builder: (context, child) {
        return Positioned(
          left: MediaQuery.of(context).size.width * _riderAnim.value.dx,
          top: widget.height * _riderAnim.value.dy,
          child: Column(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.navy,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.white, width: 2),
                ),
                child: const Icon(Icons.local_shipping_rounded,
                    color: AppColors.white, size: 18),
              ),
              if (widget.riderName != null)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.navy,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    widget.riderName!,
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopOverlay() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.navy.withValues(alpha: 0.7),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.map_outlined,
                color: AppColors.white, size: 14),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                widget.customerArea,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.orange.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Live',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomOverlay() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              AppColors.navy.withValues(alpha: 0.85),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.access_time_rounded,
                color: AppColors.orange, size: 14),
            const SizedBox(width: 6),
            const Text(
              'ETA: 15–25 min',
              style: TextStyle(
                color: AppColors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            const Icon(Icons.route_rounded,
                color: AppColors.white, size: 14),
            const SizedBox(width: 4),
            const Text(
              '0.4 km away',
              style: TextStyle(color: AppColors.white, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFFD4E6D4)
      ..strokeWidth = 0.5;

    for (double y = 0; y < size.height; y += 30) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    for (double x = 0; x < size.width; x += 30) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    final buildingPaint = Paint()..color = const Color(0xFFC8D8C8);
    final buildings = [
      Rect.fromLTWH(20, 20, 50, 35),
      Rect.fromLTWH(90, 10, 40, 45),
      Rect.fromLTWH(180, 30, 55, 30),
      Rect.fromLTWH(260, 15, 45, 40),
      Rect.fromLTWH(20, 130, 60, 35),
      Rect.fromLTWH(160, 120, 50, 40),
      Rect.fromLTWH(260, 130, 55, 35),
    ];
    for (final b in buildings) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(b, const Radius.circular(3)),
        buildingPaint,
      );
    }

    final roadPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(0, size.height * 0.55),
      Offset(size.width, size.height * 0.55),
      roadPaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.5, 0),
      Offset(size.width * 0.5, size.height),
      roadPaint..strokeWidth = 10,
    );
    canvas.drawLine(
      Offset(0, size.height * 0.25),
      Offset(size.width * 0.5, size.height * 0.25),
      roadPaint..strokeWidth = 8,
    );
  }

  @override
  bool shouldRepaint(_MapGridPainter oldDelegate) => false;
}

class _PinTailPainter extends CustomPainter {
  final Color color;
  _PinTailPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_PinTailPainter oldDelegate) => false;
}
