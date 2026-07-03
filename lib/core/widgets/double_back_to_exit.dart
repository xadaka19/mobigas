import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Wraps a screen so the phone's back button requires two presses
/// within 2 seconds to exit the app, instead of exiting immediately.
class DoubleBackToExit extends StatefulWidget {
  final Widget child;
  const DoubleBackToExit({super.key, required this.child});

  @override
  State<DoubleBackToExit> createState() => _DoubleBackToExitState();
}

class _DoubleBackToExitState extends State<DoubleBackToExit> {
  DateTime? _lastPress;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final now = DateTime.now();
        if (_lastPress == null ||
            now.difference(_lastPress!) > const Duration(seconds: 2)) {
          _lastPress = now;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Press back again to exit'),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          SystemNavigator.pop();
        }
      },
      child: widget.child,
    );
  }
}
