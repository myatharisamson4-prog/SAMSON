import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

class SamsonAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  final AudioPlayer player = AudioPlayer();
  Future<void> Function()? onNext;
  Future<void> Function()? onPrevious;

  StreamSubscription<PlaybackEvent>? _playbackEventSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;

  SamsonAudioHandler() {
    _playbackEventSubscription = player.playbackEventStream.listen((event) {
      _updatePlaybackState();
    });

    _playerStateSubscription = player.playerStateStream.listen((state) {
      _updatePlaybackState();
    });
  }

  Future<void> loadAndPlay({
    required Uri uri,
    required String title,
    required String artist,
    required String album,
  }) async {
    final item = MediaItem(
      id: uri.toString(),
      title: title,
      artist: artist,
      album: album,
      artUri: Uri.parse('asset:///assets/images/samson_music_logo.png'),
    );

    mediaItem.add(item);
    queue.add([item]);

    await player.setAudioSource(AudioSource.uri(uri, tag: item));

    await player.play();
  }

  void _updatePlaybackState() {
    final playing = player.playing;
    final processingState = player.processingState;

    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        androidCompactActionIndices: const [0, 1, 2],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        processingState: switch (processingState) {
          ProcessingState.idle => AudioProcessingState.idle,
          ProcessingState.loading => AudioProcessingState.loading,
          ProcessingState.buffering => AudioProcessingState.buffering,
          ProcessingState.ready => AudioProcessingState.ready,
          ProcessingState.completed => AudioProcessingState.completed,
        },
        playing: playing,
        updatePosition: player.position,
        bufferedPosition: player.bufferedPosition,
        speed: player.speed,
        queueIndex: 0,
      ),
    );
  }

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> stop() async {
    await player.stop();
    await super.stop();
  }

  @override
  Future<void> skipToNext() async {
    await onNext?.call();
  }

  @override
  Future<void> skipToPrevious() async {
    await onPrevious?.call();
  }

  Future<void> dispose() async {
    await _playbackEventSubscription?.cancel();
    await _playerStateSubscription?.cancel();
    await player.dispose();
  }
}
