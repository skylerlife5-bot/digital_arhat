import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class MediaPreviewWidget extends StatefulWidget {
  const MediaPreviewWidget({
    super.key,
    required this.imageUrls,
    this.videoUrl,
    this.audioUrl,
    this.title = 'Media Section',
  });

  final List<String> imageUrls;
  final String? videoUrl;
  final String? audioUrl;
  final String title;

  @override
  State<MediaPreviewWidget> createState() => _MediaPreviewWidgetState();
}

class _MediaPreviewWidgetState extends State<MediaPreviewWidget> {
  final PageController _pageController = PageController();
  final AudioPlayer _audioPlayer = AudioPlayer();

  VideoPlayerController? _videoController;
  bool _videoLoading = false;
  int _currentImageIndex = 0;

  Duration _audioDuration = Duration.zero;
  Duration _audioPosition = Duration.zero;
  bool _audioPlaying = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
    _bindAudioStreams();
  }

  Future<void> _initVideo() async {
    final raw = (widget.videoUrl ?? '').trim();
    if (raw.isEmpty) return;

    setState(() {
      _videoLoading = true;
    });

    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(raw));
      await controller.initialize();
      controller.setLooping(false);
      controller.setVolume(1);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _videoController = controller;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _videoController = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _videoLoading = false;
        });
      }
    }
  }

  void _bindAudioStreams() {
    _audioPlayer.onDurationChanged.listen((duration) {
      if (!mounted) return;
      setState(() {
        _audioDuration = duration;
      });
    });

    _audioPlayer.onPositionChanged.listen((position) {
      if (!mounted) return;
      setState(() {
        _audioPosition = position;
      });
    });

    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() {
        _audioPlaying = state == PlayerState.playing;
      });
    });
  }

  Future<void> _toggleVideoPlay() async {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;

    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _toggleAudioPlay() async {
    final raw = (widget.audioUrl ?? '').trim();
    if (raw.isEmpty) return;

    if (_audioPlaying) {
      await _audioPlayer.pause();
      return;
    }

    if (_audioPosition > Duration.zero) {
      await _audioPlayer.resume();
      return;
    }

    await _audioPlayer.play(UrlSource(raw));
  }

  Future<void> _seekAudio(double valueMs) async {
    final target = Duration(milliseconds: valueMs.toInt());
    await _audioPlayer.seek(target);
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _pageController.dispose();
    _audioPlayer.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasImages = widget.imageUrls.isNotEmpty;
    final hasVideo = (widget.videoUrl ?? '').trim().isNotEmpty;
    final hasAudio = (widget.audioUrl ?? '').trim().isNotEmpty;

    if (!hasImages && !hasVideo && !hasAudio) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 8),
        if (hasImages) ...[
          SizedBox(
            height: 170,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  PageView.builder(
                    controller: _pageController,
                    itemCount: widget.imageUrls.length,
                    onPageChanged: (index) {
                      if (!mounted) return;
                      setState(() {
                        _currentImageIndex = index;
                      });
                    },
                    itemBuilder: (context, index) {
                      return Image.network(
                        widget.imageUrls[index],
                        fit: BoxFit.cover,
                        width: double.infinity,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: Colors.black26,
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.broken_image,
                            color: Colors.white54,
                          ),
                        ),
                      );
                    },
                  ),
                  if (widget.imageUrls.length > 1)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          '${_currentImageIndex + 1}/${widget.imageUrls.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (hasVideo) ...[
          Container(
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: _videoController?.value.isInitialized == true
                    ? _videoController!.value.aspectRatio
                    : 16 / 9,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_videoController?.value.isInitialized == true)
                      VideoPlayer(_videoController!)
                    else
                      Container(
                        color: Colors.black26,
                        alignment: Alignment.center,
                        child: _videoLoading
                            ? const CircularProgressIndicator()
                            : const Icon(
                                Icons.videocam,
                                color: Colors.white54,
                                size: 34,
                              ),
                      ),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: IconButton(
                        onPressed: _toggleVideoPlay,
                        icon: Icon(
                          _videoController?.value.isPlaying == true
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_fill,
                          color: Colors.white,
                          size: 42,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (hasAudio)
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: _toggleAudioPlay,
                      icon: Icon(
                        _audioPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                      ),
                    ),
                    const Text(
                      'Audio Note',
                      style: TextStyle(color: Colors.white70),
                    ),
                    const Spacer(),
                    Text(
                      '${_fmt(_audioPosition)} / ${_fmt(_audioDuration)}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _audioPosition.inMilliseconds.toDouble().clamp(
                    0,
                    _audioDuration.inMilliseconds.toDouble() > 0
                        ? _audioDuration.inMilliseconds.toDouble()
                        : 1,
                  ),
                  min: 0,
                  max: _audioDuration.inMilliseconds.toDouble() > 0
                      ? _audioDuration.inMilliseconds.toDouble()
                      : 1,
                  onChanged: (value) => _seekAudio(value),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

