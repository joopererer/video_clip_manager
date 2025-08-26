import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../data/models.dart';
import 'platform_support.dart';

/// 播放器类型枚举
enum PlayerType {
  local,    // 本地视频播放器
  embedded, // 内嵌WebView播放器
  external, // 外部播放器 (通过本地播放器播放流)
}

/// 播放器状态
enum PlayerState {
  idle,
  loading,
  playing,
  paused,
  error,
}

/// 统一视频播放器适配器
class UnifiedVideoPlayer extends ChangeNotifier {
  Player? _localPlayer;
  VideoController? _videoController;
  WebViewController? _webViewController;

  PlayerType _currentPlayerType = PlayerType.local;
  PlayerState _playerState = PlayerState.idle;
  Duration _currentPosition = Duration.zero;
  Duration _duration = Duration.zero;

  dynamic _currentVideo; // OnlineVideo 或 OriginalVideo
  OnlineVideoClip? _currentClip;

  bool _isPlaying = false;
  bool _isMuted = false;
  double _volume = 1.0;

  VoidCallback? _onPositionChanged;
  VoidCallback? _onStateChanged;
  VoidCallback? _onError;

  // Getters for state variables
  PlayerType get currentPlayerType => _currentPlayerType;
  PlayerState get playerState => _playerState;
  Duration get currentPosition => _currentPosition;
  Duration get duration => _duration;
  bool get isPlaying => _isPlaying;
  bool get isMuted => _isMuted;
  double get volume => _volume;
  dynamic get currentVideo => _currentVideo;
  OnlineVideoClip? get currentClip => _currentClip;

  /// Initializes the player.
  Future<void> initialize() async {
    MediaKit.ensureInitialized();
    _localPlayer = Player();
    _videoController = VideoController(_localPlayer!);
    
    // 监听本地播放器状态
    _localPlayer!.stream.position.listen((position) {
      _currentPosition = position;
      _onPositionChanged?.call();
      notifyListeners();
    });
    
    _localPlayer!.stream.duration.listen((duration) {
      _duration = duration;
      notifyListeners();
    });
    
    _localPlayer!.stream.playing.listen((playing) {
      _isPlaying = playing;
      _playerState = playing ? PlayerState.playing : PlayerState.paused;
      _onStateChanged?.call();
      notifyListeners();
    });
    
    _localPlayer!.stream.error.listen((error) {
      _playerState = PlayerState.error;
      _onError?.call();
      notifyListeners();
    });
  }

  /// Plays a local video.
  Future<void> playLocalVideo(OriginalVideo video, {OnlineVideoClip? clip}) async {
    _disposeCurrentPlayer();
    
    _currentVideo = video;
    _currentClip = clip;
    _currentPlayerType = PlayerType.local;
    _playerState = PlayerState.loading;
    notifyListeners();
    
    try {
      await _localPlayer!.open(Media(video.path));
      
      if (clip != null) {
        // 设置片段播放范围
        await _localPlayer!.seek(clip.startTime);
        _duration = clip.endTime - clip.startTime;
      } else {
        _duration = Duration.zero; // 将由播放器自动获取
      }
      
      _playerState = PlayerState.playing;
      _isPlaying = true;
      notifyListeners();
    } catch (e) {
      _playerState = PlayerState.error;
      notifyListeners();
      rethrow;
    }
  }

  /// Plays an online video, choosing between embedded or external (stream) player.
  Future<void> playOnlineVideo(OnlineVideo video, {OnlineVideoClip? clip}) async {
    _disposeCurrentPlayer();
    
    _currentVideo = video;
    _currentClip = clip;
    
    final platformSupport = PlatformFactory.getPlatformByUrl(video.url);
    
    if (platformSupport.supportsEmbeddedPlayback()) {
      // 使用内嵌播放器
      await _playWithEmbeddedPlayer(video, platformSupport, clip);
    } else {
      // 使用外部播放器
      await _playWithExternalPlayer(video, platformSupport, clip);
    }
  }

  /// Plays online video using an embedded WebView.
  Future<void> _playWithEmbeddedPlayer(
    OnlineVideo video, 
    PlatformSupport platformSupport, 
    OnlineVideoClip? clip
  ) async {
    _currentPlayerType = PlayerType.embedded;
    _playerState = PlayerState.loading;
    notifyListeners();
    
    try {
      final embedUrl = platformSupport.getEmbedUrl(video.id);
      _webViewController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(NavigationDelegate(
          onPageFinished: (String url) {
            _playerState = PlayerState.playing;
            _isPlaying = true;
            notifyListeners();
          },
        ))
        ..loadRequest(Uri.parse(embedUrl));
      
      // 注入控制脚本
      final controlScript = platformSupport.getPlayerControlScript();
      await _webViewController!.runJavaScript(controlScript);
      
    } catch (e) {
      _playerState = PlayerState.error;
      notifyListeners();
      rethrow;
    }
  }

  /// Plays online video using the local player after extracting stream URL.
  Future<void> _playWithExternalPlayer(
    OnlineVideo video, 
    PlatformSupport platformSupport, 
    OnlineVideoClip? clip
  ) async {
    _currentPlayerType = PlayerType.external;
    _playerState = PlayerState.loading;
    notifyListeners();
    
    try {
      // 尝试获取视频流URL
      final streamUrl = await platformSupport.getVideoStreamUrl(video.url);
      
      if (streamUrl != null) {
        // 使用本地播放器播放流
        await _localPlayer!.open(Media(streamUrl));
        
        if (clip != null) {
          await _localPlayer!.seek(clip.startTime);
          _duration = clip.endTime - clip.startTime;
        }
        
        _playerState = PlayerState.playing;
        _isPlaying = true;
      } else {
        // 无法获取流URL，显示错误
        _playerState = PlayerState.error;
      }
      
      notifyListeners();
    } catch (e) {
      _playerState = PlayerState.error;
      notifyListeners();
      rethrow;
    }
  }

  /// Play control methods
  Future<void> play() async {
    switch (_currentPlayerType) {
      case PlayerType.local:
        await _localPlayer?.play();
        break;
      case PlayerType.embedded:
        await _webViewController?.runJavaScript('play()');
        break;
      case PlayerType.external:
        await _localPlayer?.play();
        break;
    }
    _isPlaying = true;
    notifyListeners();
  }

  Future<void> pause() async {
    switch (_currentPlayerType) {
      case PlayerType.local:
        await _localPlayer?.pause();
        break;
      case PlayerType.embedded:
        await _webViewController?.runJavaScript('pause()');
        break;
      case PlayerType.external:
        await _localPlayer?.pause();
        break;
    }
    _isPlaying = false;
    notifyListeners();
  }

  Future<void> seek(Duration position) async {
    final targetPosition = _currentClip != null 
        ? _currentClip!.startTime + position
        : position;
    
    switch (_currentPlayerType) {
      case PlayerType.local:
        await _localPlayer?.seek(targetPosition);
        break;
      case PlayerType.embedded:
        await _webViewController?.runJavaScript('seekTo(${targetPosition.inSeconds})');
        break;
      case PlayerType.external:
        await _localPlayer?.seek(targetPosition);
        break;
    }
  }

  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    
    switch (_currentPlayerType) {
      case PlayerType.local:
        await _localPlayer?.setVolume(_volume * 100);
        break;
      case PlayerType.embedded:
        // WebView音量控制可能有限制
        break;
      case PlayerType.external:
        await _localPlayer?.setVolume(_volume * 100);
        break;
    }
    notifyListeners();
  }

  Future<void> setMuted(bool muted) async {
    _isMuted = muted;
    
    switch (_currentPlayerType) {
      case PlayerType.local:
        // 使用音量控制来实现静音
        await _localPlayer?.setVolume(muted ? 0 : _volume * 100);
        break;
      case PlayerType.embedded:
        // WebView静音控制可能有限制
        break;
      case PlayerType.external:
        // 使用音量控制来实现静音
        await _localPlayer?.setVolume(muted ? 0 : _volume * 100);
        break;
    }
    notifyListeners();
  }

  /// 获取当前播放时间
  Future<Duration> getCurrentTime() async {
    switch (_currentPlayerType) {
      case PlayerType.local:
        return _currentPosition;
      case PlayerType.embedded:
        try {
          final result = await _webViewController?.runJavaScriptReturningResult('getCurrentTime()');
          if (result is num) {
            return Duration(seconds: result.toInt());
          }
        } catch (e) {
          // 忽略错误
        }
        return _currentPosition;
      case PlayerType.external:
        return _currentPosition;
    }
  }

  /// 设置回调
  void setOnPositionChanged(VoidCallback callback) {
    _onPositionChanged = callback;
  }

  void setOnStateChanged(VoidCallback callback) {
    _onStateChanged = callback;
  }

  void setOnError(VoidCallback callback) {
    _onError = callback;
  }

  /// 释放当前播放器
  Future<void> _disposeCurrentPlayer() async {
    switch (_currentPlayerType) {
      case PlayerType.local:
        await _localPlayer?.stop();
        break;
      case PlayerType.embedded:
        _webViewController = null;
        break;
      case PlayerType.external:
        await _localPlayer?.stop();
        break;
    }
    
    _currentPlayerType = PlayerType.local;
    _playerState = PlayerState.idle;
    _currentPosition = Duration.zero;
    _isPlaying = false;
    notifyListeners();
  }

  /// 释放所有资源
  Future<void> dispose() async {
    _disposeCurrentPlayer();
    await _localPlayer?.dispose();
    super.dispose();
  }

  /// 获取视频控制器（用于UI显示）
  VideoController? get videoController => _videoController;
  
  /// 获取WebView控制器（用于UI显示）
  WebViewController? get webViewController => _webViewController;
}
