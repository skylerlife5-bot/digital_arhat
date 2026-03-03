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
  static const String _urduFont = 'Jameel Noori Nastaliq';

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

  // �x}"️ Recording Logic
  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        HapticFeedback.lightImpact();
        final directory = await getApplicationDocumentsDirectory();
        final path = '${directory.path}/audio_note_${DateTime.now().millisecondsSinceEpoch}.m4a';

        const config = RecordConfig();
        await _audioRecorder.start(config, path: path);

        setState(() {
          _isRecording = true;
          _audioPath = null;
        });
        _pulseController.repeat(reverse: true);
      }
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

  // �x` Playback Logic
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _isRecording ? goldColor : Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Audio Note / Awaazi Paigham",
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              fontFamily: _urduFont,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            "Maal ke bare mein bol kar batayein",
            style: TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontFamily: _urduFont,
            ),
          ),
          const SizedBox(height: 10),

          if (_audioPath == null)
            Center(
              child: GestureDetector(
                onLongPressStart: (_) => _startRecording(),
                onLongPressEnd: (_) => _stopRecording(),
              child: Column(
                children: [
                  ScaleTransition(
                    scale: _pulseAnimation,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      height: 48,
                      width: 48,
                      decoration: BoxDecoration(
                        color: _isRecording ? Colors.redAccent : goldColor,
                        shape: BoxShape.circle,
                        boxShadow: _isRecording
                            ? [
                                BoxShadow(
                                  color: Colors.redAccent.withAlpha(95),
                                  blurRadius: 14,
                                  spreadRadius: 1,
                                ),
                              ]
                            : [
                                BoxShadow(
                                  color: goldColor.withAlpha(70),
                                  blurRadius: 9,
                                ),
                              ],
                      ),
                      child: Icon(
                        _isRecording ? Icons.mic : Icons.mic_none,
                        size: 22,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isRecording
                        ? "Recording ho rahi hai... (Chorhein)"
                        : "Mic daba kar rakhein",
                    style: TextStyle(
                      color: _isRecording ? Colors.redAccent : Colors.white38,
                      fontSize: 10.5,
                      fontFamily: _urduFont,
                    ),
                  ),
                ],
              ),
              ),
            )
          else
            // Preview & Delete Layout
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                IconButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    setState(() => _audioPath = null);
                    widget.onRecordingComplete(null);
                  },
                  icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
                ),
                ElevatedButton.icon(
                  onPressed: _playRecording,
                  style: ElevatedButton.styleFrom(backgroundColor: goldColor),
                  icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.black),
                  label: const Text(
                    "Sunein",
                    style: TextStyle(color: Colors.black, fontFamily: _urduFont),
                  ),
                ),
                const Text(
                  "Record ho gaya!",
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 12,
                    fontFamily: _urduFont,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
