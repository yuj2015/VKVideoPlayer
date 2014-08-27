//
//  Created by Viki.
//  Copyright (c) 2014 Viki Inc. All rights reserved.
//

#import "VKVideoPlayer.h"
#import "VKVideoPlayerConfig.h"
#import "VKVideoPlayerCaption.h"
#import "VKVideoPlayerSettingsManager.h"
#import "VKVideoPlayerLayerView.h"
#import "VKVideoPlayerTrack.h"
#import "NSObject+VKFoundation.h"
#import "VKVideoPlayerExternalMonitor.h"
#import "VKVideoPlayerView.h"
#import <MediaPlayer/MediaPlayer.h>
#import <objc/runtime.h>

#define degreesToRadians(x) (M_PI * x / 180.0f)

#ifdef DEBUG
static const int ddLogLevel = LOG_LEVEL_WARN;
#else
static const int ddLogLevel = LOG_LEVEL_WARN;
#endif

NSString *kTracksKey		= @"tracks";
NSString *kPlayableKey		= @"playable";

static const NSString *ItemStatusContext;


typedef enum {
  VKVideoPlayerCaptionPositionTop = 1111,
  VKVideoPlayerCaptionPositionBottom
} VKVideoPlayerCaptionPosition;

@interface VKVideoPlayer()
@property (nonatomic, assign) BOOL scrubbing;
@property (nonatomic, assign) NSTimeInterval beforeSeek;
@property (nonatomic, assign) NSTimeInterval previousPlaybackTime;
@property (nonatomic, assign) double previousIndicatedBandwidth;

@property (nonatomic, strong) id timeObserver;

@property (nonatomic, strong) id<VKVideoPlayerCaptionProtocol> subtitles;
@property (nonatomic, strong) id subtitleTimer;


@end


@implementation VKVideoPlayer

- (id)init {
  self = [super init];
  if (self) {
    self.playerView = [[VKVideoPlayerView alloc] init];
    [self initialize];
  }
  return self;
}

- (id)initWithVideoPlayerView:(UIView<VKVideoPlayerViewInterface> *)videoPlayerView {
  self = [super init];
  if (self) {
    self.playerView = videoPlayerView;
    [self initialize];
  }
  return self;
}

- (void)dealloc {
  [self removeObservers];

  [self.externalMonitor deactivate];
  
  self.timeObserver = nil;
  self.avPlayer = nil;
  self.subtitles = nil;
  self.subtitleTimer = nil;
  
  self.playerItem = nil;

  [self pauseContent];
}

#pragma mark - initialize
- (void)initialize {
  [self initializeProperties];
  [self initializePlayerView];
  [self addObservers];
}

- (void)initializeProperties {
  self.state = VKVideoPlayerStateUnknown;
  self.scrubbing = NO;
  self.beforeSeek = 0.0;
  self.previousPlaybackTime = 0;
  self.supportedOrientations = VKSharedUtility.isPad ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskAllButUpsideDown;

//  self.forceRotate = NO;
}

- (void)initializePlayerView {
  self.playerView.delegate = self;
  [self.playerView initializeView];
}

- (void)loadCurrentVideoTrack {
  __weak __typeof__(self) weakSelf = self;
  RUN_ON_UI_THREAD(^{
    [weakSelf initPlayerWithTrack:self.videoTrack];
  });
}

#pragma mark - Error Handling

- (NSString*)videoPlayerErrorCodeToString:(VKVideoPlayerErrorCode)code {
  switch (code) {
    case kVideoPlayerErrorVideoBlocked:
      return @"kVideoPlayerErrorVideoBlocked";
      break;
    case kVideoPlayerErrorFetchStreamError:
      return @"kVideoPlayerErrorFetchStreamError";
      break;
    case kVideoPlayerErrorStreamNotFound:
      return @"kVideoPlayerErrorStreamNotFound";
      break;
    case kVideoPlayerErrorAssetLoadError:
      return @"kVideoPlayerErrorAssetLoadError";
      break;
    case kVideoPlayerErrorDurationLoadError:
      return @"kVideoPlayerErrorDurationLoadError";
      break;
    case kVideoPlayerErrorAVPlayerFail:
      return @"kVideoPlayerErrorAVPlayerFail";
      break;
    case kVideoPlayerErrorAVPlayerItemFail:
      return @"kVideoPlayerErrorAVPlayerItemFail";
      break;
    case kVideoPlayerErrorUnknown:
    default:
      return @"kVideoPlayerErrorUnknown";
      break;
  }
}

- (void)handleErrorCode:(VKVideoPlayerErrorCode)errorCode track:(id<VKVideoPlayerTrackProtocol>)track {
  [self handleErrorCode:errorCode track:track customMessage:nil];
}

- (void)handleErrorCode:(VKVideoPlayerErrorCode)errorCode track:(id<VKVideoPlayerTrackProtocol>)track customMessage:(NSString*)customMessage {
  RUN_ON_UI_THREAD(^{
    if ([self.delegate respondsToSelector:@selector(handleErrorCode:track:customMessage:)]) {
      [self.delegate handleErrorCode:errorCode track:track customMessage:customMessage];
    }
  });
}

#pragma mark - KVO

- (void)setTimeObserver:(id)timeObserver {
  if (_timeObserver) {
    DDLogVerbose(@"TimeObserver: remove %@", _timeObserver);
    [self.avPlayer removeTimeObserver:_timeObserver];
  }
  _timeObserver = timeObserver;
  if (timeObserver) {
    DDLogVerbose(@"TimeObserver: setup %@", _timeObserver);
  }
}

- (void)setSubtitleTimer:(id)captionBottomTimer {
  if (_subtitleTimer) [self.avPlayer removeTimeObserver:_subtitleTimer];
  _subtitleTimer = captionBottomTimer;
}

- (void)addObservers {
  AVAudioSession *audioSession = [AVAudioSession sharedInstance];
  [audioSession setActive:YES error:nil];
  [audioSession addObserver:self forKeyPath:@"outputVolume" options:0 context:nil];
  
  NSNotificationCenter *defaultCenter = [NSNotificationCenter defaultCenter];
  [defaultCenter addObserver:self selector:@selector(reachabilityChanged:) name:kReachabilityChangedNotification object:nil];
  [defaultCenter addObserver:self selector:@selector(playerItemReadyToPlay) name:kVKVideoPlayerItemReadyToPlay object:nil];
  [defaultCenter addObserver:self selector:@selector(orientationChanged:) name:UIDeviceOrientationDidChangeNotification object:[UIDevice currentDevice]];

  NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
  [defaults addObserver:self forKeyPath:kVKSettingsSubtitlesEnabledKey options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:nil];
  [defaults addObserver:self forKeyPath:kVKSettingsTopSubtitlesEnabledKey options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:nil];
}

- (void)removeObservers {
  AVAudioSession *audioSession = [AVAudioSession sharedInstance];
  [audioSession setActive:NO error:nil];
  [audioSession removeObserver:self forKeyPath:@"outputVolume"];
  
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
  [defaults removeObserver:self forKeyPath:kVKSettingsSubtitlesEnabledKey];
  [defaults removeObserver:self forKeyPath:kVKSettingsTopSubtitlesEnabledKey];
  
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
  if (object == [NSUserDefaults standardUserDefaults]) {
    if ([keyPath isEqualToString:kVKSettingsSubtitlesEnabledKey]) {
      NSString  *fromLang, *toLang;
      if ([[change valueForKeyPath:NSKeyValueChangeNewKey] boolValue]) {
        fromLang = @"null";
        toLang = VKSharedVideoPlayerSettingsManager.subtitleLanguageCode;
      } else {
        self.subtitleTimer = nil;
        self.subtitles = nil;
        [self.playerView clearSubtitles];
        fromLang = VKSharedVideoPlayerSettingsManager.subtitleLanguageCode;
        toLang = @"null";
      }
      
      if ([self.delegate respondsToSelector:@selector(videoPlayer:didChangeSubtitleFrom:to:)]) {
        [self.delegate videoPlayer:self didChangeSubtitleFrom:fromLang to:toLang];
      }
    }
  }
  
  // Observer AVPlayer and AVPlayerItem to determine when media is ready to play
  if (object == self.avPlayer) {
    if ([keyPath isEqualToString:@"status"]) {
      switch ([self.avPlayer status]) {
        case AVPlayerStatusReadyToPlay:
          DDLogVerbose(@"AVPlayerStatusReadyToPlay");
          if (self.playerItem.status == AVPlayerItemStatusReadyToPlay) {
            [[NSNotificationCenter defaultCenter] postNotificationName:kVKVideoPlayerItemReadyToPlay object:nil];
          }
          break;
        case AVPlayerStatusFailed:
          DDLogVerbose(@"AVPlayerStatusFailed");
          [self handleErrorCode:kVideoPlayerErrorAVPlayerFail track:self.track];
        default:
          break;
      }
    }
  }
  
  if (object == self.playerItem) {
    if ([keyPath isEqualToString:@"playbackBufferEmpty"]) {
      DDLogVerbose(@"playbackBufferEmpty: %@", self.playerItem.isPlaybackBufferEmpty ? @"yes" : @"no");
      if (self.playerItem.isPlaybackBufferEmpty && [self currentTime] > 0 && [self currentTime] < [self.player currentItemDuration] - 1 && self.state == VKVideoPlayerStateContentPlaying) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kVKVideoPlayerPlaybackBufferEmpty object:nil];
      }
    }
    if ([keyPath isEqualToString:@"playbackLikelyToKeepUp"]) {
      DDLogVerbose(@"playbackLikelyToKeepUp: %@", self.playerItem.playbackLikelyToKeepUp ? @"yes" : @"no");
      if (self.playerItem.playbackLikelyToKeepUp) {
        if (self.state == VKVideoPlayerStateContentPlaying && ![self isPlayingVideo]) {
          [[NSNotificationCenter defaultCenter] postNotificationName:kVKVideoPlayerPlaybackLikelyToKeepUp object:nil];
          [self.player play];
        }
      }
    }
    if ([keyPath isEqualToString:@"status"]) {
      switch ([self.playerItem status]) {
        case AVPlayerItemStatusReadyToPlay:
          DDLogVerbose(@"AVPlayerItemStatusReadyToPlay");
          if ([self.avPlayer status] == AVPlayerStatusReadyToPlay) {
            [[NSNotificationCenter defaultCenter] postNotificationName:kVKVideoPlayerItemReadyToPlay object:nil];
          }
          break;
        case AVPlayerItemStatusFailed:
          DDLogVerbose(@"AVPlayerItemStatusFailed");
          [self handleErrorCode:kVideoPlayerErrorAVPlayerItemFail track:self.track];
        default:
          break;
      }
    }
  }
  
  if (object == [AVAudioSession sharedInstance]) {
    if ([keyPath isEqual:@"outputVolume"]) {
      [self volumeChanged:nil];
    }
  }
}

- (void)reachabilityChanged:(NSNotification*)notification {
  Reachability* curReachability = notification.object;
  if (curReachability == VKSharedUtility.wifiReach) {
    DDLogVerbose(@"Reachability Changed: %@", [VKSharedUtility.wifiReach isReachableViaWiFi] ? @"Wifi Detected." : @"Cellular Detected.");
    [self reloadCurrentVideoTrack];
  }
}

- (NSString*)observedBitrateBucket:(NSNumber*)observedKbps {
  NSString* observedKbpsString = @"";
  if ([observedKbps integerValue] <= 100) {
    observedKbpsString = @"0-100";
  } else if ([observedKbps integerValue] <= 200) {
    observedKbpsString = @"101-200";
  } else if ([observedKbps integerValue] <= 400) {
    observedKbpsString = @"201-400";
  } else if ([observedKbps integerValue] <= 600) {
    observedKbpsString = @"401-600";
  } else if ([observedKbps integerValue] <= 800) {
    observedKbpsString = @"601-800";
  } else if ([observedKbps integerValue] <= 1000) {
    observedKbpsString = @"801-1000";
  } else if ([observedKbps integerValue] > 1000) {
    observedKbpsString = @">1000";
  }
  return observedKbpsString;
}

- (void)periodicTimeObserver:(CMTime)time {
  NSTimeInterval timeInSeconds = CMTimeGetSeconds(time);
  NSTimeInterval lastTimeInSeconds = _previousPlaybackTime;
  
  if (timeInSeconds <= 0) {
    return;
  }
  
  if ([self isPlayingVideo]) {
    NSTimeInterval interval = fabs(timeInSeconds - _previousPlaybackTime);
    if (interval < 2 ) {
      if (self.subtitles) {
        [self updateSubtitles];
      }
    }

    _previousPlaybackTime = timeInSeconds;
  }
  
  if ([self.player currentItemDuration] > 1) {
    NSDictionary *info = [NSDictionary dictionaryWithObject:[NSNumber numberWithFloat:timeInSeconds] forKey:@"scrubberValue"];
    [[NSNotificationCenter defaultCenter] postNotificationName:kVKVideoPlayerScrubberValueUpdatedNotification object:self userInfo:info];
    
    NSDictionary *durationInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                                  [NSNumber numberWithBool:self.track.hasPrevious], @"hasPreviousVideo",
                                  [NSNumber numberWithBool:self.track.hasNext], @"hasNextVideo",
                                  [NSNumber numberWithDouble:[self.player currentItemDuration]], @"duration",
                                  nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:kVKVideoPlayerDurationDidLoadNotification object:self userInfo:durationInfo];
  }

  [self.playerView hideControlsIfNecessary];
  
  if ([self.delegate respondsToSelector:@selector(videoPlayer:didPlayFrame:time:lastTime:)]) {
    [self.delegate videoPlayer:self didPlayFrame:self.track time:timeInSeconds lastTime:lastTimeInSeconds];
  }
}

- (void)seekToTimeInSecond:(float)sec userAction:(BOOL)isUserAction completionHandler:(void (^)(BOOL finished))completionHandler {
  [self scrubbingBegin];
  [self scrubbingEndAtSecond:sec userAction:isUserAction completionHandler:completionHandler];
}

- (void)scrubbingEndAtSecond:(float)sec userAction:(BOOL)isUserAction completionHandler:(void (^)(BOOL finished))completionHandler {
  [self.player seekToTimeInSeconds:sec completionHandler:completionHandler];
}


#pragma mark - Playback position

- (void)seekToLastWatchedDuration {
  RUN_ON_UI_THREAD(^{
    
    [self.playerView setPlayButtonsEnabled:NO];
    
    CGFloat lastWatchedTime = [self.track.lastDurationWatchedInSeconds floatValue];
    if (lastWatchedTime > 5) lastWatchedTime -= 5;
    
    DDLogVerbose(@"Seeking to last watched duration: %f", lastWatchedTime);
    [self.playerView setScrubberValue:([self.player currentItemDuration] > 0) ? lastWatchedTime / [self.player currentItemDuration] : 0.0f animated:NO];
    
    [self.player seekToTimeInSeconds:lastWatchedTime completionHandler:^(BOOL finished) {
      if (finished) [self playContent];
      [self.playerView setPlayButtonsEnabled:YES];
      
      if ([self.delegate respondsToSelector:@selector(videoPlayer:didStartVideo:)]) {
        [self.delegate videoPlayer:self didStartVideo:self.track];
      }
    }];
    
  });
}

- (void)playerDidPlayToEnd:(NSNotification *)notification {
  DDLogVerbose(@"Player: Did play to the end");
  RUN_ON_UI_THREAD(^{

    self.track.isPlayedToEnd = YES;
    [self pauseContent:NO completionHandler:^{
      if ([self.delegate respondsToSelector:@selector(videoPlayer:didPlayToEnd:)]) {
        [self.delegate videoPlayer:self didPlayToEnd:self.track];
      }
    }];

  });
}

#pragma mark - AVPlayer wrappers

- (BOOL)isPlayingVideo {
  return (self.avPlayer && self.avPlayer.rate != 0.0);
}


#pragma mark - Airplay

- (UIView<VKVideoPlayerViewInterface> *)activePlayerView {
  if (self.externalMonitor.isConnected) {
    return self.externalMonitor.externalView;
  } else {
    return self.playerView;
  }
}

- (BOOL)isPlayingOnExternalDevice {
  return self.externalMonitor.isConnected;
}

#pragma mark - Handle Videos
- (void)loadVideoWithTrack:(id<VKVideoPlayerTrackProtocol>)track {
  VoidBlock completionHandler = ^{
    self.track = track;
    [self initPlayerWithTrack:self.track];
  };
  
  switch (self.state) {
    case VKVideoPlayerStateUnknown:
    case VKVideoPlayerStateSuspended:
    case VKVideoPlayerStateError:
    case VKVideoPlayerStateContentPaused:
    case VKVideoPlayerStateContentLoading:
      completionHandler();
      break;
    case VKVideoPlayerStateContentPlaying:
      [self pauseContent:NO completionHandler:completionHandler];
      break;
    default:
      break;
  };
}
- (void)loadVideoWithStreamURL:(NSURL*)streamURL {
  [self loadVideoWithTrack:[[VKVideoPlayerTrack alloc] initWithStreamURL:streamURL]];
}

- (void)setTrack:(id<VKVideoPlayerTrackProtocol>)track {
  // Clear player before loading new track
  [self clearPlayer];
  
  // Load new track and update views
  _track = track;
  
  // Post notification once track has been changed
  [[NSNotificationCenter defaultCenter] postNotificationName:kVKVideoPlayerUpdateVideoTrack object:track];
}


- (void)clearPlayer {
  self.playerItem = nil;
  self.avPlayer = nil;
  self.player = nil;
}

// NOTE: This method can be overridden if you want to selectively init different players
- (void)initPlayerWithTrack:(id<VKVideoPlayerTrackProtocol>)track {
  // Reset isReadyToPlay property
  self.isReadyToPlay = NO;
  
  if (!track.isVideoLoadedBefore) {
    track.isVideoLoadedBefore = YES;
  }
  
  // Get the stream url
  NSURL *streamURL = [track streamURL];
  
  // If no stream found, handle error
  if (!streamURL) {
    [self handleErrorCode:kVideoPlayerErrorFetchStreamError track:track];
    DDLogWarn(@"Unable to fetch stream");
    return;
  }
  
  // Content now loading
  self.state = VKVideoPlayerStateContentLoading;
  
  // Get asset to create AVPlayerItem and AVPlayer
  AVURLAsset* asset = [[AVURLAsset alloc] initWithURL:streamURL options:@{ AVURLAssetPreferPreciseDurationAndTimingKey : @YES }];
  [asset loadValuesAsynchronouslyForKeys:@[kTracksKey, kPlayableKey] completionHandler:^{
    // Completion handler block.
    RUN_ON_UI_THREAD(^{
      if (self.state == VKVideoPlayerStateDismissed) return;
      if (![asset.URL.absoluteString isEqualToString:streamURL.absoluteString]) {
        DDLogVerbose(@"Ignore stream load success. Requested to load: %@ but the current stream should be %@.", asset.URL.absoluteString, streamURL.absoluteString);
        return;
      }
      NSError *error = nil;
      AVKeyValueStatus status = [asset statusOfValueForKey:kTracksKey error:&error];
      if (status == AVKeyValueStatusLoaded) {
        // Init AVPlayerItem and AVPlayer
        self.playerItem = [AVPlayerItem playerItemWithAsset:asset];
        self.avPlayer = [self playerWithPlayerItem:self.playerItem];
        self.player = (id<VKPlayer>)self.avPlayer;
        [[self activePlayerView].playerLayerView setPlayer:self.avPlayer];
      } else {
        // You should deal with the error appropriately.
        [self handleErrorCode:kVideoPlayerErrorAssetLoadError track:track];
        DDLogWarn(@"The asset's tracks were not loaded:\n%@", error);
      }
    });
  }];
}

- (void)playerItemReadyToPlay {
  DDLogVerbose(@"Player: playerItemReadyToPlay");
  
  /* Set isReadyToPlay property to true to signify that media is ready
   * This is a separate BOOL instead of a player state because we might
   * want to play ads (StateSuspended) before player item is ready
   */
  self.isReadyToPlay = YES;
  
  RUN_ON_UI_THREAD(^{
    switch (self.state) {
      case VKVideoPlayerStateContentLoading:
      case VKVideoPlayerStateError:{
        /**
         * If player is loading or in error state
         * Pause player and then check if should auto play
         */
        [self pauseContent:NO completionHandler:^{
          // If should not auto start video, return
          if ([self.delegate respondsToSelector:@selector(shouldVideoPlayer:startVideo:)]) {
            if (![self.delegate shouldVideoPlayer:self startVideo:self.track]) {
              return;
            }
          }
          // Start the video by seeking to last watched duration
          if ([self.delegate respondsToSelector:@selector(videoPlayer:willStartVideo:)]) {
            [self.delegate videoPlayer:self willStartVideo:self.track];
          }
          [self seekToLastWatchedDuration];
        }];
        break;
      }
      default:
        /** 
         * Do nothing if player is:
         * Unknown - Content wasn't loaded, this shouldn't even happen
         * Paused - There is already existing content
         * Playing - There is already existing content
         * Suspended - Ads are playing, do nothing till ads finish
         * Dismissed - Player has been dismiss, do nothing
         */
        break;
    }    
  });
}

- (void)setPlayerItem:(AVPlayerItem *)playerItem {
  [_playerItem removeObserver:self forKeyPath:@"status"];
  [_playerItem removeObserver:self forKeyPath:@"playbackBufferEmpty"];
  [_playerItem removeObserver:self forKeyPath:@"playbackLikelyToKeepUp"];
  [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:_playerItem];
  _playerItem = playerItem;
  _previousIndicatedBandwidth = 0.0f;
  
  if (!playerItem) {
    return;
  }
  
  [_playerItem addObserver:self forKeyPath:@"status" options:0 context:&ItemStatusContext];
  [_playerItem addObserver:self forKeyPath:@"playbackBufferEmpty" options:NSKeyValueObservingOptionNew context:nil];
  [_playerItem addObserver:self forKeyPath:@"playbackLikelyToKeepUp" options:NSKeyValueObservingOptionNew context:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerDidPlayToEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:_playerItem];
}

- (void)setAvPlayer:(AVPlayer *)avPlayer {
  self.timeObserver = nil;
  self.subtitleTimer = nil;
  [_avPlayer removeObserver:self forKeyPath:@"status"];
  _avPlayer = avPlayer;
  
  if (!avPlayer) {
    return;
  }
  
  __weak __typeof(self) weakSelf = self;
  [_avPlayer addObserver:self forKeyPath:@"status" options:0 context:nil];
  self.timeObserver = [_avPlayer addPeriodicTimeObserverForInterval:CMTimeMake(1, 1) queue:NULL usingBlock:^(CMTime time){
    [weakSelf periodicTimeObserver:time];
  }];
  
  if (self.subtitles) {
    [self loadSubtitles:self.subtitles];
  }
  
  [self.playerView clearSubtitles];
}

- (AVPlayer*)playerWithPlayerItem:(AVPlayerItem*)playerItem {
  AVPlayer* player = [AVPlayer playerWithPlayerItem:playerItem];
  if ([player respondsToSelector:@selector(setAllowsAirPlayVideo:)]) player.allowsAirPlayVideo = NO;
  if ([player respondsToSelector:@selector(setAllowsExternalPlayback:)]) player.allowsExternalPlayback = NO;
  return player;
}

- (void)reloadCurrentVideoTrack {
  __weak __typeof__(self) weakSelf = self;
  RUN_ON_UI_THREAD(^{
    VoidBlock completionHandler = ^{
      weakSelf.state = VKVideoPlayerStateContentLoading;
      [weakSelf initPlayerWithTrack:self.videoTrack];
    };
    
    switch (self.state) {
      case VKVideoPlayerStateUnknown:
      case VKVideoPlayerStateContentLoading:
      case VKVideoPlayerStateContentPaused:
      case VKVideoPlayerStateError:
        DDLogVerbose(@"Reload stream now.");
        completionHandler();
        break;
      case VKVideoPlayerStateContentPlaying:
        DDLogVerbose(@"Reload stream after pause.");
        [self pauseContent:NO completionHandler:completionHandler];
        break;
      case VKVideoPlayerStateDismissed:
      case VKVideoPlayerStateSuspended:
        break;
    }
  });
}

- (float)currentBitRateInKbps {
  return [self.playerItem.accessLog.events.lastObject observedBitrate]/1000;
}


#pragma mark -

- (NSTimeInterval)currentTime {
  if (!self.track.isVideoLoadedBefore) {
    return [self.track.lastDurationWatchedInSeconds doubleValue] > 0 ? [self.track.lastDurationWatchedInSeconds doubleValue] : 0.0f;
  } else return CMTimeGetSeconds([self.player currentCMTime]);
}

#pragma mark - Subtitles
- (DTCSSStylesheet*)captionStyleSheet:(NSString*)color {
  float fontSize = 1.3f;
  float shadowSize = 1.0f;
  
  switch ([[VKSharedUtility setting:kVKSettingsSubtitleSizeKey] integerValue]) {
    case 1:
      fontSize = 1.5f;
      break;
    case 2:
      fontSize = 2.0f;
      shadowSize = 1.2f;
      break;
    case 3:
      fontSize = 3.5f;
      shadowSize = 1.5f;
      break;
  }
  
  DTCSSStylesheet* stylesheet = [[DTCSSStylesheet alloc] initWithStyleBlock:[NSString stringWithFormat:@"body{\
                                                                             text-align: center;\
                                                                             font-size: %fem;\
                                                                             font-family: Helvetica Neue;\
                                                                             font-weight: bold;\
                                                                             color: %@;\
                                                                             text-shadow: -%fpx -%fpx %fpx #000, %fpx -%fpx %fpx #000, -%fpx %fpx %fpx #000, %fpx %fpx %fpx #000;\
                                                                             vertical-align: bottom;\
                                                                             }", fontSize, color, shadowSize, shadowSize, shadowSize, shadowSize, shadowSize, shadowSize, shadowSize, shadowSize, shadowSize, shadowSize, shadowSize, shadowSize]];
  return stylesheet;
}


- (void)loadSubtitles:(id<VKVideoPlayerCaptionProtocol>)subtitles {
  if (!subtitles.boundryTimes.count) {
    [self.playerView clearSubtitles];
    self.subtitleTimer = nil;
    self.subtitles = nil;
    return;
  }
  
  
  __weak __typeof(self) weakSelf = self;
  DDLogVerbose(@"Subs: %@ - segment count %d", subtitles, (int)subtitles.segments.count);
  id subtitleTimer = [self.avPlayer addBoundaryTimeObserverForTimes:subtitles.boundryTimes queue:NULL usingBlock:^{
    [weakSelf updateSubtitles];
  }];
  
  self.subtitleTimer = subtitleTimer;
  self.subtitles = subtitles;
  
  [self updateSubtitles];
}

- (void)updateSubtitles {
  if (!self.subtitles || !VKSharedVideoPlayerSettingsManager.isSubtitlesEnabled) {
    return;
  }
  
  // Check if view supports subtitles
  if ([self.playerView respondsToSelector:@selector(updateSubtitlesWithHTML:options:)]) {
    float timeInMilliseconds = CMTimeGetSeconds([self.player currentCMTime]) * 1000;
    NSString* html = [self.subtitles contentAtTime:timeInMilliseconds];
    NSString *color = @"#FFF";
    NSMutableDictionary* options = [NSMutableDictionary dictionaryWithObject:[self captionStyleSheet:color] forKey:DTDefaultStyleSheet];
    
    [self.playerView updateSubtitlesWithHTML:html options:options];
  }
}

#pragma mark - Ad State Support
- (BOOL)beginAdPlayback {
  switch (self.state) {
    case VKVideoPlayerStateDismissed:
    case VKVideoPlayerStateError:
      // Do not play ad in these states
      return NO;
    case VKVideoPlayerStateContentPlaying:
      [self pauseContent];
    case VKVideoPlayerStateContentLoading:
    case VKVideoPlayerStateContentPaused:
      self.state = VKVideoPlayerStateSuspended;
      return YES;
    default:
      return NO;
  }
}

- (BOOL)endAdPlayback {
  if (self.state == VKVideoPlayerStateSuspended) {
    [self pauseContent];
    [self playContent];
    return YES;
  }
  return NO;
}

#pragma mark - Controls

- (NSString*)playerStateDescription:(VKVideoPlayerState)playerState {
  switch (playerState) {
    case VKVideoPlayerStateUnknown:
      return @"Unknown";
      break;
    case VKVideoPlayerStateContentLoading:
      return @"ContentLoading";
      break;
    case VKVideoPlayerStateContentPaused:
      return @"ContentPaused";
      break;
    case VKVideoPlayerStateContentPlaying:
      return @"ContentPlaying";
      break;
    case VKVideoPlayerStateSuspended:
      return @"Player Stay";
      break;
    case VKVideoPlayerStateDismissed:
      return @"Player Dismissed";
      break;
    case VKVideoPlayerStateError:
      return @"Player Error";
      break;
  }
}


- (void)setState:(VKVideoPlayerState)newPlayerState {
  RUN_ON_UI_THREAD(^{
    if ([self.delegate respondsToSelector:@selector(videoPlayer:willChangeStateTo:)]) {
      [self.delegate videoPlayer:self willChangeStateTo:newPlayerState];
    }
    
    VKVideoPlayerState oldPlayerState = self.state;
    if (oldPlayerState == newPlayerState) return;
    
    switch (oldPlayerState) {
      case VKVideoPlayerStateContentLoading:
        if ([self.playerView respondsToSelector:@selector(setLoading:)]) {
          [self.playerView setLoading:NO];
        }
        break;
      case VKVideoPlayerStateContentPlaying:
        break;
      case VKVideoPlayerStateContentPaused:
        break;
      case VKVideoPlayerStateDismissed:
        break;
      case VKVideoPlayerStateError:
        break;
      default:
        break;
    }
    
    DDLogVerbose(@"Player State: %@ -> %@", [self playerStateDescription:self.state], [self playerStateDescription:newPlayerState]);
    _state = newPlayerState;
    BOOL isPlayingOnExternalDevice = [self isPlayingOnExternalDevice];
    
    switch (newPlayerState) {
      case VKVideoPlayerStateUnknown:
        break;
      case VKVideoPlayerStateContentLoading:
        if ([self.playerView respondsToSelector:@selector(setLoading:)]) {
          [self.playerView setLoading:YES];
        }
        [self.playerView viewForContentLoading:isPlayingOnExternalDevice];
        break;
      case VKVideoPlayerStateContentPlaying: {
        [self.playerView viewForContentPlaying:isPlayingOnExternalDevice];
        break;
      }
      case VKVideoPlayerStateContentPaused: {
        self.track.lastDurationWatchedInSeconds = [NSNumber numberWithFloat:[self currentTime]];
        [self.playerView viewForContentPaused:isPlayingOnExternalDevice];
        break;
      }
      case VKVideoPlayerStateSuspended:
        [self.playerView viewForError:isPlayingOnExternalDevice];
        break;
      case VKVideoPlayerStateError:{
        [self.playerView viewForError:isPlayingOnExternalDevice];
        break;
      }
      case VKVideoPlayerStateDismissed:
        [self.playerView viewForDismissed:isPlayingOnExternalDevice];
        [self clearPlayer];
        break;
    }
    
    if ([self.delegate respondsToSelector:@selector(videoPlayer:didChangeStateFrom:)]) {
      [self.delegate videoPlayer:self didChangeStateFrom:oldPlayerState];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:kVKVideoPlayerStateChanged object:nil userInfo:@{
                                                                                                                @"oldState":[NSNumber numberWithInteger:oldPlayerState],
                                                                                                                @"newState":[NSNumber numberWithInteger:newPlayerState]
                                                                                                                }];
  });
}

- (void)playContent {
  if (self.state == VKVideoPlayerStateContentPaused && self.isReadyToPlay) {
    [self.player play];
    self.state = VKVideoPlayerStateContentPlaying;
  }
}

- (void)pauseContent {
  [self pauseContent:NO completionHandler:nil];
}

- (void)pauseContentWithCompletionHandler:(void (^)())completionHandler {
  [self pauseContent:NO completionHandler:completionHandler];
}

- (void)pauseContent:(BOOL)isUserAction completionHandler:(void (^)())completionHandler {
  
  RUN_ON_UI_THREAD(^{

    switch ([self.playerItem status]) {
      case AVPlayerItemStatusFailed:
        [self.player pause];
        self.state = VKVideoPlayerStateError;
        return;
      case AVPlayerItemStatusUnknown:
        DDLogVerbose(@"Trying to pause content but AVPlayerItemStatusUnknown.");
        self.state = VKVideoPlayerStateUnknown;
        return;
      default:
        break;
    }
    
    switch ([self.avPlayer status]) {
      case AVPlayerStatusFailed:
        [self.player pause];
        self.state = VKVideoPlayerStateError;
        return;
        break;
      case AVPlayerStatusUnknown:
        DDLogVerbose(@"Trying to pause content but AVPlayerStatusUnknown.");
        self.state = VKVideoPlayerStateUnknown;
        return;
        break;
      default:
        break;
    }    
    
    switch (self.state) {
      case VKVideoPlayerStateContentLoading:
      case VKVideoPlayerStateContentPlaying:
      case VKVideoPlayerStateContentPaused:
      case VKVideoPlayerStateSuspended:
      case VKVideoPlayerStateError:
        [self.player pause];
        self.state = VKVideoPlayerStateContentPaused;
        if (completionHandler) completionHandler();
        break;
      default:
        break;
    }
  });
}

- (void)dismiss {
  if (self.state == VKVideoPlayerStateContentPlaying) {
    [self pauseContent];
  }
  self.state = VKVideoPlayerStateDismissed;
}

#pragma mark - VKScrubberDelegate

- (void)scrubbingBegin {
  [self pauseContent:NO completionHandler:^{
    _scrubbing = YES;
    if ([self.playerView respondsToSelector:@selector(disableAutoHide)] && class_getProperty([self.playerView class], "controlHideCountdown")) {
      [self.playerView disableAutoHide];
    }
    _beforeSeek = [self currentTime];
  }];
}

- (void)scrubbingEnd {
  _scrubbing = NO;
  self.state = VKVideoPlayerStateContentLoading;
  float afterSeekTime = [self.playerView getScrubberValue];
  [self scrubbingEndAtSecond:afterSeekTime userAction:YES completionHandler:^(BOOL finished) {
    if (finished) [self playContent];
  }];
}

//- (void)zoomInPressed {
//  ((AVPlayerLayer *)self.view.layer).videoGravity = AVLayerVideoGravityResizeAspectFill;
//  if ([[[UIDevice currentDevice] systemVersion] hasPrefix:@"5"]) {
//    self.view.frame = self.view.frame;
//  }
//}
//
//- (void)zoomOutPressed {
//  ((AVPlayerLayer *)self.view.layer).videoGravity = AVLayerVideoGravityResizeAspect;
//  if ([[[UIDevice currentDevice] systemVersion] hasPrefix:@"5"]) {
//    self.view.frame = self.view.frame;
//  }
//}

#pragma mark - VKVideoPlayerViewDelegate
- (id<VKVideoPlayerTrackProtocol>)videoTrack {
  return self.track;
}

- (void)videoQualityButtonTapped {
  if ([self.delegate respondsToSelector:@selector(videoPlayer:didControlByEvent:)]) {
    [self.delegate videoPlayer:self didControlByEvent:VKVideoPlayerControlEventTapVideoQuality];
  }
}

- (void)fullScreenButtonTapped {
  if ([self.delegate respondsToSelector:@selector(videoPlayer:didControlByEvent:)]) {
    [self.delegate videoPlayer:self didControlByEvent:VKVideoPlayerControlEventTapFullScreen];
  }
}

- (void)captionButtonTapped {
  if ([self.delegate respondsToSelector:@selector(videoPlayer:didControlByEvent:)]) {
    [self.delegate videoPlayer:self didControlByEvent:VKVideoPlayerControlEventTapCaption];
  }
}

- (void)playButtonPressed {
  [self playContent];
  if ([self.delegate respondsToSelector:@selector(videoPlayer:didControlByEvent:)]) {
    [self.delegate videoPlayer:self didControlByEvent:VKVideoPlayerControlEventTapPlay];
  }
}

- (void)pauseButtonPressed {
  switch (self.state) {
    case VKVideoPlayerStateContentPlaying:
      [self pauseContent:YES completionHandler:nil];
      if ([self.delegate respondsToSelector:@selector(videoPlayer:didControlByEvent:)]) {
        [self.delegate videoPlayer:self didControlByEvent:VKVideoPLayerControlEventTapPause];
      }
      break;
    default:
      break;
  }
}

- (void)doneButtonTapped {
  if ([self.delegate respondsToSelector:@selector(videoPlayer:didControlByEvent:)]) {
    [self.delegate videoPlayer:self didControlByEvent:VKVideoPlayerControlEventTapDone];
  }
}

- (void)playerViewSingleTapped {
  if ([self.delegate respondsToSelector:@selector(videoPlayer:didControlByEvent:)]) {
    [self.delegate videoPlayer:self didControlByEvent:VKVideoPlayerControlEventTapPlayerView];
  }
}

- (void)presentSubtitleLangaugePickerFromButton:(VKPickerButton*)button {
  if ([self.delegate respondsToSelector:@selector(videoPlayer:didControlByEvent:)]) {
    [self.delegate videoPlayer:self didControlByEvent:VKVideoPlayerControlEventTapDone];
  }
}

- (void)layoutNavigationAndStatusBarForOrientation:(UIInterfaceOrientation)interfaceOrientation {
  [[UIApplication sharedApplication] setStatusBarOrientation:interfaceOrientation animated:NO];
}

#pragma mark - Handle volume change

- (void)volumeChanged:(NSNotification *)notification {
  if ([self.playerView respondsToSelector:@selector(resetAutoHideCountdown)] && class_getProperty([self.playerView class], "controlHideCountdown")) {
    [self.playerView resetAutoHideCountdown];
  }
}

#pragma mark - Remote Control Events handler

- (void)remoteControlReceivedWithEvent:(UIEvent *)receivedEvent {
  if (receivedEvent.type == UIEventTypeRemoteControl) {
    switch (receivedEvent.subtype) {
      case UIEventSubtypeRemoteControlPlay:
        [self playButtonPressed];
        break;
      case UIEventSubtypeRemoteControlPause:
        [self pauseButtonPressed];
      case UIEventSubtypeRemoteControlStop:
        break;
      case UIEventSubtypeRemoteControlNextTrack:
//        [self nextTrackButtonPressed];
        break;
      case UIEventSubtypeRemoteControlPreviousTrack:
//        [self previousTrackButtonPressed];
        break;
      case UIEventSubtypeRemoteControlBeginSeekingForward:
      case UIEventSubtypeRemoteControlBeginSeekingBackward:
        [self scrubbingBegin];
        break;
      case UIEventSubtypeRemoteControlEndSeekingForward:
      case UIEventSubtypeRemoteControlEndSeekingBackward:
        [self.playerView setScrubberValue:receivedEvent.timestamp animated:NO];
//        self.view.scrubber.value = receivedEvent.timestamp;
        [self scrubbingEnd];
        break;
      default:
        break;
    }
  }
}

#pragma mark - Orientation
- (void)orientationChanged:(NSNotification *)note {
  UIDevice * device = note.object;

  UIInterfaceOrientation rotateToOrientation;
  switch(device.orientation) {
    case UIDeviceOrientationPortrait:
      DDLogVerbose(@"ORIENTATION: Portrait");
      rotateToOrientation = UIInterfaceOrientationPortrait;
      break;
    case UIDeviceOrientationPortraitUpsideDown:
      DDLogVerbose(@"ORIENTATION: PortraitDown");
      rotateToOrientation = UIInterfaceOrientationPortraitUpsideDown;
      break;
    case UIDeviceOrientationLandscapeLeft:
      DDLogVerbose(@"ORIENTATION: LandscapeRight");
      rotateToOrientation = UIInterfaceOrientationLandscapeRight;
      break;
    case UIDeviceOrientationLandscapeRight:
      DDLogVerbose(@"ORIENTATION: LandscapeLeft");
      rotateToOrientation = UIInterfaceOrientationLandscapeLeft;
      break;
    default:
      rotateToOrientation = self.visibleInterfaceOrientation;
      break;
  }
  
  if ((1 << rotateToOrientation) & self.supportedOrientations && rotateToOrientation != self.visibleInterfaceOrientation) {
//    [self performOrientationChange:rotateToOrientation];
  }
}

//- (void)performOrientationChange:(UIInterfaceOrientation)deviceOrientation {
//
//  if ([self.delegate respondsToSelector:@selector(videoPlayer:willChangeOrientationTo:)]) {
//    [self.delegate videoPlayer:self willChangeOrientationTo:deviceOrientation];
//  }
//  
//  CGFloat degrees = [self degreesForOrientation:deviceOrientation];
//  __weak __typeof__(self) weakSelf = self;
//  UIInterfaceOrientation lastOrientation = self.visibleInterfaceOrientation;
//  self.visibleInterfaceOrientation = deviceOrientation;
//  [UIView animateWithDuration:0.3f animations:^{
//    CGRect bounds = [[UIScreen mainScreen] bounds];
//    CGRect parentBounds;
//    CGRect viewBoutnds;
//    if (UIInterfaceOrientationIsLandscape(deviceOrientation)) {
//      viewBoutnds = CGRectMake(0, 0, CGRectGetWidth(self.landscapeFrame), CGRectGetHeight(self.landscapeFrame));
//      parentBounds = CGRectMake(0, 0, CGRectGetHeight(bounds), CGRectGetWidth(bounds));
//    } else {
//      viewBoutnds = CGRectMake(0, 0, CGRectGetWidth(self.portraitFrame), CGRectGetHeight(self.portraitFrame));
//      parentBounds = CGRectMake(0, 0, CGRectGetWidth(bounds), CGRectGetHeight(bounds));
//    }
//    
//    weakSelf.view.superview.transform = CGAffineTransformMakeRotation(degreesToRadians(degrees));
//    weakSelf.view.superview.bounds = parentBounds;
//    [weakSelf.view.superview setFrameOriginX:0.0f];
//    [weakSelf.view.superview setFrameOriginY:0.0f];
//    
//    CGRect wvFrame = weakSelf.view.superview.superview.frame;
//    if (wvFrame.origin.y > 0) {
//      wvFrame.size.height = CGRectGetHeight(bounds) ;
//      wvFrame.origin.y = 0;
//      weakSelf.view.superview.superview.frame = wvFrame;
//    }
//    
//    weakSelf.view.bounds = viewBoutnds;
//    [weakSelf.view setFrameOriginX:0.0f];
//    [weakSelf.view setFrameOriginY:0.0f];
//    [weakSelf.view layoutForOrientation:deviceOrientation];
//
//  } completion:^(BOOL finished) {
//    if ([self.delegate respondsToSelector:@selector(videoPlayer:didChangeOrientationFrom:)]) {
//      [self.delegate videoPlayer:self didChangeOrientationFrom:lastOrientation];
//    }
//  }];
//  
//  [[UIApplication sharedApplication] setStatusBarOrientation:self.visibleInterfaceOrientation animated:YES];
//  [self updateCaptionView:self.view.captionBottomView caption:self.captionBottom playerView:self.view];
//  [self updateCaptionView:self.view.captionTopView caption:self.captionTop playerView:self.view];
//  self.view.fullscreenButton.selected = self.isFullScreen = UIInterfaceOrientationIsLandscape(deviceOrientation);
//}
//
//- (CGFloat)degreesForOrientation:(UIInterfaceOrientation)deviceOrientation {
//  switch (deviceOrientation) {
//    case UIInterfaceOrientationPortrait:
//      return 0;
//      break;
//    case UIInterfaceOrientationLandscapeRight:
//      return 90;
//      break;
//    case UIInterfaceOrientationLandscapeLeft:
//      return -90;
//      break;
//    case UIInterfaceOrientationPortraitUpsideDown:
//      return 180;
//      break;
//  }
//}

@end


@implementation AVPlayer (VKPlayer)

- (void)seekToTimeInSeconds:(float)time completionHandler:(void (^)(BOOL finished))completionHandler {
  if ([self respondsToSelector:@selector(seekToTime:toleranceBefore:toleranceAfter:completionHandler:)]) {
    [self seekToTime:CMTimeMakeWithSeconds(time, 1) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:completionHandler];
  } else {
    [self seekToTime:CMTimeMakeWithSeconds(time, 1) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
    completionHandler(YES);
  }
}

- (NSTimeInterval)currentItemDuration {
  return CMTimeGetSeconds([self.currentItem duration]);
}

- (CMTime)currentCMTime {
  return [self currentTime];
}

@end

