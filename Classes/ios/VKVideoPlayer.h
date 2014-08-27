//
//  Created by Viki.
//  Copyright (c) 2014 Viki Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "VKVideoPlayerCaption.h"
#import "VKVideoPlayerTrack.h"
#import "VKScrubber.h"

typedef enum {
  // The video was flagged as blocked due to licensing restrictions (geo or device).
  kVideoPlayerErrorVideoBlocked = 900,
  
  // There was an error fetching the stream.
  kVideoPlayerErrorFetchStreamError,
  
  // Could not find the stream type for video.
  kVideoPlayerErrorStreamNotFound,
  
  // There was an error loading the video as an asset.
  kVideoPlayerErrorAssetLoadError,
  
  // There was an error loading the video's duration.
  kVideoPlayerErrorDurationLoadError,
  
  // AVPlayer failed to load the asset.
  kVideoPlayerErrorAVPlayerFail,
  
  // AVPlayerItem failed to load the asset.
  kVideoPlayerErrorAVPlayerItemFail,
  
  // Chromecast failed to load the stream.
  kVideoPlayerErrorChromecastLoadFail,
  
  // There was an unknown error.
  kVideoPlayerErrorUnknown,
  
} VKVideoPlayerErrorCode;


typedef enum {
  VKVideoPlayerStateUnknown,
  VKVideoPlayerStateContentLoading,
  VKVideoPlayerStateContentPlaying,
  VKVideoPlayerStateContentPaused,
  VKVideoPlayerStateSuspended,        // Player suspended for ad playback
  VKVideoPlayerStateDismissed,      // Player dismissed when dismissing view controller
  VKVideoPlayerStateError
} VKVideoPlayerState;

typedef enum {
  VKVideoPlayerControlEventTapPlayerView,
  VKVideoPlayerControlEventTapNext,
  VKVideoPlayerControlEventTapPrevious,
  VKVideoPlayerControlEventTapDone,
  VKVideoPlayerControlEventTapFullScreen,
  VKVideoPlayerControlEventTapCaption,
  VKVideoPlayerControlEventTapVideoQuality,
  VKVideoPlayerControlEventSwipeNext,
  VKVideoPlayerControlEventSwipePrevious,
  VKVideoPlayerControlEventTapPlay,
  VKVideoPLayerControlEventTapPause
} VKVideoPlayerControlEvent;


@class VKVideoPlayer;
@class VKVideoPlayerLayerView;

@protocol VKVideoPlayerDelegate <NSObject>
@optional
- (void)videoPlayer:(VKVideoPlayer *)videoPlayer willChangeStateTo:(VKVideoPlayerState)toState;
- (void)videoPlayer:(VKVideoPlayer *)videoPlayer didChangeStateFrom:(VKVideoPlayerState)fromState;
- (BOOL)shouldVideoPlayer:(VKVideoPlayer *)videoPlayer startVideo:(id<VKVideoPlayerTrackProtocol>)track;
- (void)videoPlayer:(VKVideoPlayer *)videoPlayer willStartVideo:(id<VKVideoPlayerTrackProtocol>)track;
- (void)videoPlayer:(VKVideoPlayer *)videoPlayer didStartVideo:(id<VKVideoPlayerTrackProtocol>)track;

- (void)videoPlayer:(VKVideoPlayer *)videoPlayer didPlayFrame:(id<VKVideoPlayerTrackProtocol>)track time:(NSTimeInterval)time lastTime:(NSTimeInterval)lastTime;
- (void)videoPlayer:(VKVideoPlayer *)videoPlayer didPlayToEnd:(id<VKVideoPlayerTrackProtocol>)track;
- (void)videoPlayer:(VKVideoPlayer *)videoPlayer didControlByEvent:(VKVideoPlayerControlEvent)event;
- (void)videoPlayer:(VKVideoPlayer *)videoPlayer didChangeSubtitleFrom:(NSString*)fronLang to:(NSString*)toLang;
- (void)videoPlayer:(VKVideoPlayer *)videoPlayer willChangeOrientationTo:(UIInterfaceOrientation)orientation;
- (void)videoPlayer:(VKVideoPlayer *)videoPlayer didChangeOrientationFrom:(UIInterfaceOrientation)orientation;

- (void)handleErrorCode:(VKVideoPlayerErrorCode)errorCode track:(id<VKVideoPlayerTrackProtocol>)track customMessage:(NSString*)customMessage;
@end


@protocol VKVideoPlayerExternalMonitorProtocol;

@protocol VKVideoPlayerViewDelegate <VKScrubberDelegate>
@property (nonatomic, readonly) VKVideoPlayerTrack *videoTrack;
@property (nonatomic, readonly) UIInterfaceOrientation visibleInterfaceOrientation;

- (void)fullScreenButtonTapped;
- (void)playButtonPressed;
- (void)pauseButtonPressed;

- (void)captionButtonTapped;
- (void)videoQualityButtonTapped;

- (void)doneButtonTapped;

- (void)playerViewSingleTapped;

- (void)scrubbingBegin;
- (void)scrubbingEnd;
@end

@protocol VKVideoPlayerViewInterface <NSObject>

@required

// The player layer that the AVPlayer will play content on
@property (strong, nonatomic) VKVideoPlayerLayerView *playerLayerView;

// Delegate to allow the view to pass commands back to the player
@property (weak, nonatomic) id<VKVideoPlayerViewDelegate> delegate;

// Method to initialize view
- (void)initializeView;

// Methods to customize view for various player states
- (void)viewForContentLoading:(BOOL)isPlayingOnExternalDevice;
- (void)viewForContentPaused:(BOOL)isPlayingOnExternalDevice;
- (void)viewForContentPlaying:(BOOL)isPlayingOnExternalDevice;
- (void)viewForSuspended:(BOOL)isPlayingOnExternalDevice;
- (void)viewForError:(BOOL)isPlayingOnExternalDevice;
- (void)viewForDismissed:(BOOL)isPlayingOnExternalDevice;

@optional

/** 
 * To enable subtitle support, include the following:
 */

// SubtitleLabel of DTAttributedLabel class
@property (strong, nonatomic) DTAttributedLabel *subtitleLabel;

// Method to clear subtitles
- (void)clearSubtitles;

// Method to update subtitles with text, this is called periodically by the player
- (void)updateSubtitlesWithHTML:(NSString *)html options:(NSMutableDictionary *)options;


/**
 * To enable scrubber support, include the following methods
 * 
 * NOTE: You can use your own scrubber class, or the VKScrubber class 
 * included in this project. If you use your own scrubber class, it must 
 * inform the player of scrubbing start and end by using the scrubbingBegin 
 * and scrubbingEnd delegate methods
 */

// Method to update the scrubber to accurately display playback time
- (void)setScrubberValue:(float)value animated:(BOOL)animated;

// Method to get the current time the scrubber is at
- (float)getScrubberValue;


/**
 * To enable auto-hide UI support, include the following
 */

// Property to track auto hide countdown
@property (assign, nonatomic) NSInteger controlHideCountdown;

// This method is called every second, use it to determine if you should hide your controls
- (void)hideControlsIfNecessary;

// This method is used to reset and/or re-enable the auto hide countdown
- (void)resetAutoHideCountdown;

// This method is used to disable auto hide
- (void)disableAutoHide;

/**
 * Loading UI support
 */

// Use this method to show/hide an activity indicator or any other loading state UI
- (void)setLoading:(BOOL)isLoading;

@property (assign, nonatomic) CGRect portraitFrame;
@property (assign, nonatomic) CGRect landscapeFrame;

// Play button settings
- (void)setPlayButtonsSelected:(BOOL)selected;
- (void)setPlayButtonsEnabled:(BOOL)enabled;

@end

@protocol VKPlayer <NSObject>
- (void)play;
- (void)pause;
- (CMTime)currentCMTime;
- (NSTimeInterval)currentItemDuration;
- (void)seekToTimeInSeconds:(float)time completionHandler:(void (^)(BOOL finished))completionHandler;
@end


@interface AVPlayer (VKPlayer)
- (void)seekToTimeInSeconds:(float)time completionHandler:(void (^)(BOOL finished))completionHandler;
- (NSTimeInterval)currentItemDuration;
- (CMTime)currentCMTime;
@end


@interface VKVideoPlayer : NSObject<
VKVideoPlayerViewDelegate
>
@property (nonatomic, strong) UIView<VKVideoPlayerViewInterface> *playerView;
@property (nonatomic, strong) id<VKVideoPlayerTrackProtocol> track;
@property (nonatomic, weak) id<VKVideoPlayerDelegate> delegate;
@property (nonatomic, assign) VKVideoPlayerState state;
@property (nonatomic, strong) AVPlayer *avPlayer;
@property (nonatomic, strong) AVPlayerItem* playerItem;
@property (nonatomic, strong) id<VKPlayer> player;
@property (nonatomic, assign) UIInterfaceOrientation visibleInterfaceOrientation;
@property (nonatomic, assign) UIInterfaceOrientationMask supportedOrientations;
@property (nonatomic, assign) BOOL isFullScreen;

@property (nonatomic, strong) id<VKVideoPlayerExternalMonitorProtocol> externalMonitor;

//@property (nonatomic, assign) CGRect portraitFrame;
//@property (nonatomic, assign) CGRect landscapeFrame;
//@property (nonatomic, assign) BOOL forceRotate;

@property (nonatomic, assign) BOOL isReadyToPlay;

- (id)initWithVideoPlayerView:(UIView<VKVideoPlayerViewInterface> *)videoPlayerView;

- (void)seekToLastWatchedDuration;
- (void)seekToTimeInSecond:(float)sec userAction:(BOOL)isUserAction completionHandler:(void (^)(BOOL finished))completionHandler;
- (BOOL)isPlayingVideo;
- (BOOL)isPlayingOnExternalDevice;
- (NSTimeInterval)currentTime;
- (void)performOrientationChange:(UIInterfaceOrientation)deviceOrientation;

#pragma mark - Error Handling
- (NSString*)videoPlayerErrorCodeToString:(VKVideoPlayerErrorCode)code;

#pragma mark - Resource
- (void)loadVideoWithTrack:(id<VKVideoPlayerTrackProtocol>)track;
- (void)loadVideoWithStreamURL:(NSURL*)streamURL;
- (void)reloadCurrentVideoTrack;
- (void)initPlayerWithTrack:(id<VKVideoPlayerTrackProtocol>)track;
- (UIView<VKVideoPlayerViewInterface> *)activePlayerView;

#pragma mark - Controls
- (void)playContent;
- (void)pauseContent;
- (void)pauseContentWithCompletionHandler:(void (^)())completionHandler;
- (void)pauseContent:(BOOL)isUserAction completionHandler:(void (^)())completionHandler;
- (void)dismiss;

#pragma mark - Captions
- (void)clearCaptions;
- (void)loadSubtitles:(id<VKVideoPlayerCaptionProtocol>)subtitles;

#pragma mark - Ad State Support
- (BOOL)beginAdPlayback;
- (BOOL)endAdPlayback;
@end
