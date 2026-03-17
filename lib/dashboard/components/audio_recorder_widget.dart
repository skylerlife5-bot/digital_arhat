import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

class AudioNoteWidget extends StatefulWidget {
  final Function(String?) onRecordingComplete;
  const AudioNoteWidget({super.key, required this.onRecordingComplete});

  @override
  State<AudioNoteWidget> createState() => _AudioNoteWidgetState();
}

class _AudioNoteWidgetState extends State<AudioNoteWidget>
    with SingleTickerProviderStateMixin {
  late AudioRecorder _audioRecorder;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  final AudioPlayer _audioPlayer = AudioPlayer();

  String? _audioPath;
  bool _isRecording = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _audioRecorder = AudioRecorder();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Please allow microphone permission / براہِ کرم مائیکروفون اجازت دیں',
            ),
          ),
        );
        return;
      }

      HapticFeedback.lightImpact();
      final directory = await getApplicationDocumentsDirectory();
      final path =
          '${directory.path}/audio_note_${DateTime.now().millisecondsSinceEpoch}.m4a';

      const config = RecordConfig();
      await _audioRecorder.start(config, path: path);

      setState(() {
        _isRecording = true;
        _audioPath = null;
      });
      _pulseController.repeat(reverse: true);
    } catch (e) {
      debugPrint("Error starting record: $e");
    }
  }

  Future<void> _stopRecording() async {
    HapticFeedback.lightImpact();
    final path = await _audioRecorder.stop();
    _pulseController.stop();
    _pulseController.reset();
    setState(() {
      _isRecording = false;
      _audioPath = path;
    });
    widget.onRecordingComplete(path);
  }

  void _playRecording() async {
    if (_audioPath != null) {
      HapticFeedback.lightImpact();
      await _audioPlayer.play(DeviceFileSource(_audioPath!));
      setState(() => _isPlaying = true);
      _audioPlayer.onPlayerComplete.listen((event) {
        setState(() => _isPlaying = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const goldColor = Color(0xFFFFD700);
    const deepGreen = Color(0xFF0D2F1B);

    String statusLabel;
    if (_isRecording) {
      statusLabel = 'Recording... / ریکارڈنگ جاری ہے';
    } else if (_audioPath != null) {
      statusLabel = 'Recorded successfully / کامیابی سے ریکارڈ ہوگیا';
    } else {
      statusLabel = 'Tap to record / ریکارڈ کرنے کے لیے دبائیں';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _isRecording
              ? goldColor
              : Colors.white.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Voice note for buyers / خریدار کے لیے صوتی پیغام',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Explain quality, stock, or delivery details in your own voice / اپنی آواز میں معیار، اسٹاک، یا ترسیل کی تفصیل بتائیں',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              ScaleTransition(
                scale: _pulseAnimation,
                child: ElevatedButton.icon(
                  onPressed: _isRecording ? _stopRecording : _startRecording,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isRecording ? Colors.redAccent : goldColor,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                  label: Text(
                    _isRecording
                        ? 'Stop / بند کریں'
                        : 'Record / ریکارڈ',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: _isRecording
                        ? Colors.red.shade200
                        : Colors.white.withValues(alpha: 0.88),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (_audioPath != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: deepGreen.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _playRecording,
                    icon: Icon(
                      _isPlaying ? Icons.pause_circle : Icons.play_circle,
                      color: goldColor,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _isPlaying
                          ? 'Playing... / چل رہا ہے'
                          : 'Tap play to listen / سننے کے لیے پلے دبائیں',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.88),
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      setState(() => _audioPath = null);
                      widget.onRecordingComplete(null);
                    },
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    label: const Text(
                      'Remove',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
