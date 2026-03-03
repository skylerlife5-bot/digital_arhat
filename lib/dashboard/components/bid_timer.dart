import 'dart:async';
import 'package:flutter/material.dart';

class BidTimer extends StatefulWidget {
  final DateTime? endTime;
  const BidTimer({super.key, required this.endTime});

  @override
  State<BidTimer> createState() => _BidTimerState();
}

class _BidTimerState extends State<BidTimer> with SingleTickerProviderStateMixin {
  late Timer _timer;
  Duration _duration = const Duration();
  late AnimationController _blinkController;

  @override
  void initState() {
    super.initState();
    
    // 1. Blinking animation setup (Urgent zone ke liye)
    _blinkController = AnimationController(
      vsync: this, 
      duration: const Duration(milliseconds: 500),
    );

    // Initial calculation (For immediate display)
    _duration = _remainingDuration();

    _startTimer();
  }

  Duration _remainingDuration() {
    final DateTime? bidEndTime = widget.endTime?.toUtc();
    if (bidEndTime == null) {
      return const Duration(days: 3650);
    }

    final now = DateTime.now().toUtc();
    final remaining = bidEndTime.difference(now);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;

      final DateTime? bidEndTime = widget.endTime?.toUtc();
      setState(() {
        if (bidEndTime == null) {
          _duration = const Duration(days: 3650);
          _blinkController.stop();
          return;
        }

        final now = DateTime.now().toUtc();
        final remaining = bidEndTime.difference(now);
        if (remaining.isNegative) {
          _duration = Duration.zero;
          _timer.cancel();
          _blinkController.stop();
        } else {
          _duration = remaining;
          
          // 2. Urgent logic: Agar 10 min se kam reh jayein toh blink shuru karein
          if (_duration.inMinutes < 10 && !_blinkController.isAnimating) {
            _blinkController.repeat(reverse: true);
          }
        }
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _blinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isPendingApproval = widget.endTime == null;

    if (isPendingApproval) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.orangeAccent, width: 1.5),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified_user, color: Colors.orangeAccent, size: 18),
            SizedBox(width: 8),
            Text(
              'Awaiting Admin Approval',
              style: TextStyle(
                color: Colors.orangeAccent,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    // Professional thresholding for bidding urgency:
    // >12h: Blue (calm), <1h: Red (urgent), otherwise Green (active)
    final bool isUrgent = _duration.inHours < 1 && _duration.inSeconds > 0;
    final bool isLongWindow = _duration.inHours >= 12;
    bool isFinished = _duration.inSeconds <= 0;

    final Color activeColor = isLongWindow ? Colors.lightBlueAccent : const Color(0xFF39FF14);
    final Color activeBg = isLongWindow ? const Color(0xFF0E223A) : const Color(0xFF111111);

    return FadeTransition(
      opacity: isUrgent ? _blinkController : const AlwaysStoppedAnimation(1.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          // Modern colors with alpha handling
          color: isFinished 
              ? Colors.grey.withValues(alpha: 0.2) 
              : (isUrgent ? Colors.red.withValues(alpha: 0.2) : activeBg),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isFinished 
                ? Colors.grey 
                : (isUrgent ? Colors.redAccent : activeColor),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isFinished ? Icons.timer_off : Icons.access_time_filled, 
              color: isFinished ? Colors.grey : (isUrgent ? Colors.redAccent : activeColor), 
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              _formatDuration(_duration),
              style: TextStyle(
                color: isFinished ? Colors.grey : (isUrgent ? Colors.redAccent : activeColor),
                fontWeight: FontWeight.bold,
                fontSize: 16,
                fontFamily: 'Courier', // Steady digits ke liye
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    if (d.inSeconds <= 0) return "Waqt Khatam!";
    
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    
    String hours = twoDigits(d.inHours);
    String minutes = twoDigits(d.inMinutes.remainder(60));
    String seconds = twoDigits(d.inSeconds.remainder(60));
    
    return "$hours:$minutes:$seconds";
  }
}
