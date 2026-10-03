import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';

import 'audio_handler.dart';

import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:on_audio_query/on_audio_query.dart';

SamsonAudioHandler? audioHandler;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Permission.notification.request();
  audioHandler = await AudioService.init(
    builder: () => SamsonAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.samson.music.audio',
      androidNotificationChannelName: 'SAMSON Music',
      androidNotificationOngoing: true,
      artDownscaleWidth: 512,
      artDownscaleHeight: 512,
      preloadArtwork: true,
    ),
  );
  runApp(const SAMSONApp());
}

class SAMSONApp extends StatelessWidget {
  const SAMSONApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SAMSON',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF101010),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1DB954),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const MusicHomePage(),
    );
  }
}

class MusicHomePage extends StatefulWidget {
  const MusicHomePage({super.key});

  @override
  State<MusicHomePage> createState() => _MusicHomePageState();
}

class _MusicHomePageState extends State<MusicHomePage> {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  AudioPlayer get _player => audioHandler?.player ?? AudioPlayer();
  final TextEditingController _searchController = TextEditingController();

  List<SongModel> _songs = [];
  int _currentIndex = -1;
  bool _loading = true;
  bool _hasPermission = false;
  String _search = '';

  List<SongModel> get _filteredSongs {
    if (_search.trim().isEmpty) return _songs;

    final query = _search.toLowerCase();
    return _songs.where((song) {
      return song.title.toLowerCase().contains(query) ||
          (song.artist ?? '').toLowerCase().contains(query) ||
          (song.album ?? '').toLowerCase().contains(query);
    }).toList();
  }

  SongModel? get _currentSong {
    if (_currentIndex < 0 || _currentIndex >= _songs.length) return null;
    return _songs[_currentIndex];
  }

  @override
  void initState() {
    super.initState();
    audioHandler!.onNext = _playNext;
    audioHandler!.onPrevious = _playPrevious;
    _loadSongs();
  }

  Future<void> _loadSongs() async {
    setState(() => _loading = true);

    try {
      bool permission = await _audioQuery.permissionsStatus();

      if (!permission) {
        permission = await _audioQuery.permissionsRequest();
      }

      if (!permission) {
        if (mounted) {
          setState(() {
            _hasPermission = false;
            _loading = false;
          });
        }
        return;
      }

      final songs = await _audioQuery.querySongs(
        sortType: SongSortType.TITLE,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      );

      if (!mounted) return;

      setState(() {
        _songs = songs.where((song) => song.uri != null).toList();
        _hasPermission = true;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage('Could not load music: $error');
    }
  }

  Future<void> _playSong(int index) async {
    if (index < 0 || index >= _songs.length) return;

    final song = _songs[index];
    if (song.uri == null) return;

    try {
      await audioHandler!.loadAndPlay(
        uri: Uri.parse(song.uri!),
        title: song.title,
        artist: song.artist ?? 'Unknown artist',
        album: song.album ?? '',
      );

      if (mounted) {
        setState(() => _currentIndex = index);
      }
    } catch (error) {
      _showMessage('Unable to play this song.');
    }
  }

  Future<void> _togglePlayback() async {
    if (_player.playing) {
      await _player.pause();
    } else if (_currentSong != null) {
      await _player.play();
    } else if (_songs.isNotEmpty) {
      await _playSong(0);
    }
  }

  Future<void> _playNext() async {
    if (_songs.isEmpty) return;
    final next = (_currentIndex + 1) % _songs.length;
    await _playSong(next);
  }

  Future<void> _playPrevious() async {
    if (_songs.isEmpty) return;
    final previous = _currentIndex <= 0 ? _songs.length - 1 : _currentIndex - 1;
    await _playSong(previous);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatDuration(int? milliseconds) {
    if (milliseconds == null || milliseconds <= 0) return '--:--';
    final duration = Duration(milliseconds: milliseconds);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final songs = _filteredSongs;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/images/samson_music_logo.png',
                width: 40,
                height: 40,
                fit: BoxFit.cover,
              ),
            ),
            SizedBox(width: 10),
            Text('SAMSON', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh library',
            onPressed: _loadSongs,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 14, 18, 8),
              child: Text(
                'Your music. Your world.',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _search = value),
                decoration: InputDecoration(
                  hintText: 'Search songs, artists, albums...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: const Color(0xFF242424),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Your Library',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${_songs.length} songs',
                    style: const TextStyle(color: Colors.white60),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : !_hasPermission
                  ? _PermissionMessage(onRetry: _loadSongs)
                  : songs.isEmpty
                  ? Center(
                      child: Text(
                        _search.isNotEmpty
                            ? 'No matching songs found.'
                            : 'No music found on your phone.',
                        style: const TextStyle(color: Colors.white60),
                      ),
                    )
                  : ListView.builder(
                      itemCount: songs.length,
                      itemBuilder: (context, index) {
                        final song = songs[index];
                        final originalIndex = _songs.indexOf(song);
                        final isCurrent = originalIndex == _currentIndex;

                        return ListTile(
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: QueryArtworkWidget(
                              id: song.id,
                              type: ArtworkType.AUDIO,
                              artworkWidth: 52,
                              artworkHeight: 52,
                              nullArtworkWidget: Container(
                                width: 52,
                                height: 52,
                                color: const Color(0xFF292929),
                                child: const Icon(
                                  Icons.music_note,
                                  color: Color(0xFF1DB954),
                                ),
                              ),
                            ),
                          ),
                          title: Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isCurrent
                                  ? const Color(0xFF1DB954)
                                  : Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            song.artist ?? 'Unknown artist',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Text(
                            _formatDuration(song.duration),
                            style: const TextStyle(color: Colors.white54),
                          ),
                          onTap: () => _playSong(originalIndex),
                        );
                      },
                    ),
            ),
            if (_currentSong != null) _buildMiniPlayer(),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniPlayer() {
    final song = _currentSong!;

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF282828),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              QueryArtworkWidget(
                id: song.id,
                type: ArtworkType.AUDIO,
                artworkWidth: 45,
                artworkHeight: 45,
                nullArtworkWidget: const SizedBox(
                  width: 45,
                  height: 45,
                  child: Icon(Icons.music_note, color: Color(0xFF1DB954)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      song.artist ?? 'Unknown artist',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white60,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _playPrevious,
                icon: const Icon(Icons.skip_previous),
              ),
              StreamBuilder<PlayerState>(
                stream: _player.playerStateStream,
                builder: (context, snapshot) {
                  final playing = snapshot.data?.playing ?? false;
                  return IconButton(
                    onPressed: _togglePlayback,
                    icon: Icon(
                      playing ? Icons.pause : Icons.play_arrow,
                      size: 32,
                      color: const Color(0xFF1DB954),
                    ),
                  );
                },
              ),
              IconButton(
                onPressed: _playNext,
                icon: const Icon(Icons.skip_next),
              ),
            ],
          ),
          StreamBuilder<Duration>(
            stream: _player.positionStream,
            builder: (context, snapshot) {
              final position = snapshot.data ?? Duration.zero;
              final total = _player.duration ?? Duration.zero;
              final max = total.inMilliseconds.toDouble();
              final value = position.inMilliseconds.toDouble().clamp(
                0.0,
                max > 0 ? max : 1.0,
              );

              return Slider(
                min: 0,
                max: max > 0 ? max : 1,
                value: value,
                activeColor: const Color(0xFF1DB954),
                onChanged: (newValue) {
                  _player.seek(Duration(milliseconds: newValue.round()));
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PermissionMessage extends StatelessWidget {
  const _PermissionMessage({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_open, size: 56, color: Colors.white54),
            const SizedBox(height: 16),
            const Text(
              'SAMSON needs permission to access music on your phone.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Grant Permission'),
            ),
          ],
        ),
      ),
    );
  }
}
