//
//  Created by Viki.
//  Copyright (c) 2014 Viki Inc. All rights reserved.
//

#import "VKVideoPlayerView.h"
#import "VKScrubber.h"
#import <QuartzCore/QuartzCore.h>
#import "DDLog.h"
#import "VKVideoPlayerConfig.h"
#import "VKFoundation.h"
#import "VKScrubber.h"
#import "VKVideoPlayerTrack.h"
#import "UIImage+VKFoundation.h"
#import "VKVideoPlayerSettingsManager.h"
#import "VKVideoPlayerLayerView.h"

#define PADDING 8
#define VKSubtitlePadding 10

#ifdef DEBUG
  static const int ddLogLevel = LOG_LEVEL_WARN;
#else
  static const int ddLogLevel = LOG_LEVEL_WARN;
#endif

@interface VKVideoPlayerView()
@property (nonatomic, strong) NSMutableArray* customControls;
@property (nonatomic, strong) NSMutableArray* portraitControls;
@property (nonatomic, strong) NSMutableArray* landscapeControls;
@end

@implementation VKVideoPlayerView

- (void)dealloc {
  [self removeObservers];
}

- (void)initialize {
  // Define portrait and landscape frames
  CGRect bounds = [[UIScreen mainScreen] bounds];
  self.portraitFrame = CGRectMake(0, 0, MIN(bounds.size.width, bounds.size.height), MAX(bounds.size.width, bounds.size.height));
  self.landscapeFrame = CGRectMake(0, 0, MAX(bounds.size.width, bounds.size.height), MIN(bounds.size.width, bounds.size.height));
  
  self.customControls = [NSMutableArray array];
  self.portraitControls = [NSMutableArray array];
  self.landscapeControls = [NSMutableArray array];
  [[NSBundle mainBundle] loadNibNamed:NSStringFromClass([self class]) owner:self options:nil];
  self.view.frame = self.frame;
  self.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
  [self addSubview:self.view];

  self.captionButton.titleLabel.font = THEMEFONT(@"fontRegular", 13.0f);
  [self.captionButton setTitleColor:THEMECOLOR(@"colorFont4") forState:UIControlStateNormal];
  
  self.currentTimeLabel.font = THEMEFONT(@"fontRegular", DEVICEVALUE(16.0f, 10.0f));
  self.currentTimeLabel.textColor = THEMECOLOR(@"colorFont4");
  self.totalTimeLabel.font = THEMEFONT(@"fontRegular", DEVICEVALUE(16.0f, 10.0f));
  self.totalTimeLabel.textColor = THEMECOLOR(@"colorFont4");
  
  [self.scrubber addTarget:self action:@selector(updateTimeLabels) forControlEvents:UIControlEventValueChanged];
    
  UIView* overlay = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.bottomControls.frame.size.width, self.bottomControls.frame.size.height)];
  overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth;
  overlay.backgroundColor = THEMECOLOR(@"colorBackground8");
  overlay.alpha = 0.6f;
  [self.bottomControls addSubview:overlay];
  [self.bottomControls sendSubviewToBack:overlay];
  
  [self.captionButton setTitle:[VKSharedVideoPlayerSettingsManager.subtitleLanguageCode uppercaseString] forState:UIControlStateNormal];
  [self.captionButton setTitle:@"EN" forState:UIControlStateNormal];
  
  self.externalDeviceLabel.adjustsFontSizeToFitWidth = YES;
  
  self.fullscreenButton.hidden = NO;  
  
  for (UIButton* button in @[
    self.doneButton
  ]) {
    [button setBackgroundImage:[[UIImage imageWithColor:THEMECOLOR(@"colorBackground8")] imageByApplyingAlpha:0.6f] forState:UIControlStateNormal];
    button.layer.cornerRadius = 4.0f;
    button.clipsToBounds = YES;
  }
  
  [self.doneButton addTarget:self action:@selector(doneButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
  
//  [self layoutForOrientation:[[UIApplication sharedApplication] statusBarOrientation]];
  [self addObservers];
}

- (id)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    [self initialize];
  }
  return self;
}

- (void) awakeFromNib {
  [super awakeFromNib];
  [self initialize];
}

- (void)layoutSubviews {
  [super layoutSubviews];
}

- (void)initializeView {
  [self setPlayButtonsSelected:NO];
  [self.scrubber setValue:0.0f animated:NO];
  self.controlHideCountdown = kPlayerControlsAutoHideTime;
  self.playButton.center = self.view.center;
  [self.view bringSubviewToFront:self.playButton];
}

#pragma mark - KVO
- (void)addObservers {
  [self.scrubber addObserver:self forKeyPath:@"maximumValue" options:0 context:nil];
  
  NSNotificationCenter *defaultCenter = [NSNotificationCenter defaultCenter];
  [defaultCenter addObserver:self selector:@selector(durationDidLoad:) name:kVKVideoPlayerDurationDidLoadNotification object:nil];
  [defaultCenter addObserver:self selector:@selector(scrubberValueUpdated:) name:kVKVideoPlayerScrubberValueUpdatedNotification object:nil];
  
  NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
  [defaults addObserver:self forKeyPath:kVKSettingsSubtitleLanguageCodeKey options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:nil];
}

- (void)removeObservers {
  NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
  [defaults removeObserver:self forKeyPath:kVKSettingsSubtitleLanguageCodeKey];
  
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [self.scrubber removeObserver:self forKeyPath:@"maximumValue"];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
  if ([keyPath isEqualToString:kVKSettingsSubtitleLanguageCodeKey]) {
    [self.captionButton setTitle:[VKSharedVideoPlayerSettingsManager.subtitleLanguageCode uppercaseString] forState:UIControlStateNormal];
  }
  
  if (object == self.scrubber) {
    if ([keyPath isEqualToString:@"maximumValue"]) {
      DDLogVerbose(@"scrubber Value change: %f", self.scrubber.value);
      RUN_ON_UI_THREAD(^{
        [self updateTimeLabels];
      });
    }
  }
}

#pragma mark - View States
- (void)viewForContentLoading:(BOOL)isPlayingOnExternalDevice {
  [self setControlsEnabled:NO];
}

- (void)viewForContentPaused:(BOOL)isPlayingOnExternalDevice {
  [self setControlsEnabled:YES];
  [self setPlayButtonsSelected:YES];
  self.playerLayerView.hidden = NO;
  self.subtitleLabel.hidden = NO;
  self.messageLabel.hidden = YES;
  self.externalDeviceView.hidden = !isPlayingOnExternalDevice;
}

- (void)viewForContentPlaying:(BOOL)isPlayingOnExternalDevice {
  self.controlHideCountdown = kPlayerControlsAutoHideTime;
  [self setControlsEnabled:YES];
  [self setPlayButtonsSelected:NO];
  self.playerLayerView.hidden = NO;
  self.subtitleLabel.hidden = NO;
  self.messageLabel.hidden = YES;
  self.externalDeviceView.hidden = !isPlayingOnExternalDevice;
}

- (void)viewForSuspended:(BOOL)isPlayingOnExternalDevice {
  
}

- (void)viewForDismissed:(BOOL)isPlayingOnExternalDevice {
  self.playerLayerView.hidden = YES;
  [self setControlsEnabled:NO];
}

- (void)viewForError:(BOOL)isPlayingOnExternalDevice {
  self.externalDeviceView.hidden = YES;
  self.playerLayerView.hidden = YES;
  [self setControlsEnabled:NO];
  self.messageLabel.hidden = NO;
  self.controlHideCountdown = kPlayerControlsDisableAutoHide;
}

#pragma mark - Auto hide
- (void)resetAutoHideCountdown {
  self.controlHideCountdown = kPlayerControlsAutoHideTime;
}

- (void)disableAutoHide {
  self.controlHideCountdown = kPlayerControlsDisableAutoHide;
}

#pragma mark - Scrubber Interface
- (float)getScrubberValue {
  return self.scrubber.value;
}

- (void)setScrubberValue:(float)value animated:(BOOL)animated {
  [self.scrubber setValue:value animated:animated];
}

#pragma mark - Subtitles
- (void)clearTimedComments {
  NSLog(@"clear timed comments");
}

- (void)updateSubtitlesWithHTML:(NSString *)html options:(NSMutableDictionary *)options {
  if (!VKSharedVideoPlayerSettingsManager.isSubtitlesEnabled) {
    return;
  }
  
  NSAttributedString *string = [[NSAttributedString alloc] initWithHTMLData:[html dataUsingEncoding:NSUTF8StringEncoding] options:options documentAttributes:NULL];
  self.subtitleLabel.attributedString = string;
  self.subtitleLabel.isAccessibilityElement = YES;
  self.subtitleLabel.accessibilityLabel = [html stripHtml];
  
  [self updateSubtitlesPosition];
  DDLogVerbose(@"Set bottom caption: %@", [html stripHtml]);
}

- (void)updateSubtitlesPosition {
  int padding = VKSubtitlePadding;
  int paddingForBottomControls = 0;
  if (!self.isControlsHidden) {
    paddingForBottomControls = self.bottomControls.frame.size.height;
  }
  
  self.subtitleLabel.frame = CGRectMake(padding, padding, self.frame.size.width - padding * 2, self.frame.size.height - padding - paddingForBottomControls);
  
  [self.subtitleLabel sizeToFit];
  self.subtitleLabel.center = CGPointMake(self.frame.size.width * 0.5f, self.subtitleLabel.center.y);
  [self.subtitleLabel setFrameOriginY:self.frame.size.height - self.subtitleLabel.frame.size.height - padding - paddingForBottomControls];
}

- (void)clearSubtitles {
  [self.subtitleLabel setAttributedString:[[NSAttributedString alloc] initWithHTMLData:[@"" dataUsingEncoding:NSUTF8StringEncoding] options:nil documentAttributes:NULL]];
}

#pragma mark - UI Controls

- (IBAction)playButtonTapped:(id)sender {

  UIButton* playButton;
  if ([sender isKindOfClass:[UIButton class]]) {
    playButton = (UIButton*)sender;
  }

  if (playButton.selected)  {
    [self.delegate playButtonPressed];
    [self setPlayButtonsSelected:NO];
  } else {
    [self.delegate pauseButtonPressed];
    [self setPlayButtonsSelected:YES];
  }
}

- (IBAction)fullscreenButtonTapped:(id)sender {
//  self.fullscreenButton.selected = !self.fullscreenButton.selected;
//  BOOL isFullScreen = self.fullscreenButton.selected;
//  
//  if (isFullScreen) {
//    [self performOrientationChange:UIInterfaceOrientationLandscapeRight];
//  } else {
//    [self performOrientationChange:UIInterfaceOrientationPortrait];
//  }
  
  [self.delegate fullScreenButtonTapped];
}

- (IBAction)captionButtonTapped:(id)sender {
  [self.delegate captionButtonTapped];
}

- (IBAction)doneButtonTapped:(id)sender {
  [self.delegate doneButtonTapped];
}

- (void)setDelegate:(id<VKVideoPlayerViewDelegate>)delegate {
  _delegate = delegate;
  self.scrubber.delegate = delegate;
}

- (void)durationDidLoad:(NSNotification *)notification {
  NSDictionary *info = [notification userInfo];
  NSNumber* duration = [info objectForKey:@"duration"];
  [self.delegate videoTrack].totalVideoDuration = duration;
  RUN_ON_UI_THREAD(^{
    self.scrubber.maximumValue = [duration floatValue];
    self.scrubber.hidden = NO;
  });
}

- (void)scrubberValueUpdated:(NSNotification *)notification {
  NSDictionary *info = [notification userInfo];
  RUN_ON_UI_THREAD(^{
    DDLogVerbose(@"scrubberValueUpdated: %@", [info objectForKey:@"scrubberValue"]);
    [self.scrubber setValue:[[info objectForKey:@"scrubberValue"] floatValue] animated:YES];
    [self updateTimeLabels];
  });
}

- (void)updateTimeLabels {
  DDLogVerbose(@"Updating TimeLabels: %f", self.scrubber.value);
  
  [self.currentTimeLabel setFrameWidth:100.0f];
  [self.totalTimeLabel setFrameWidth:100.0f];
  
  self.currentTimeLabel.text = [VKSharedUtility timeStringFromSecondsValue:(int)self.scrubber.value];
  [self.currentTimeLabel sizeToFit];
  [self.currentTimeLabel setFrameHeight:CGRectGetHeight(self.bottomControls.frame)];
  
  self.totalTimeLabel.text = [VKSharedUtility timeStringFromSecondsValue:(int)self.scrubber.maximumValue];
  [self.totalTimeLabel sizeToFit];
  [self.totalTimeLabel setFrameHeight:CGRectGetHeight(self.bottomControls.frame)];
  
  [self layoutSlider];
}

- (void)layoutSliderForOrientation:(UIInterfaceOrientation)interfaceOrientation {
//  if (UIInterfaceOrientationIsPortrait(interfaceOrientation)) {
//    [self.totalTimeLabel setFrameOriginX:CGRectGetMinX(self.fullscreenButton.frame) - self.totalTimeLabel.frame.size.width];
//  } else {
//    [self.totalTimeLabel setFrameOriginX:CGRectGetMinX(self.captionButton.frame) - self.totalTimeLabel.frame.size.width - PADDING];
//  }
  
  CGFloat bottomControlsWidth = self.bottomControls.frame.size.width;
  CGFloat bottomControlsHeight = self.bottomControls.frame.size.height;
  
  CGFloat leftOffset = 0.0f;
  CGFloat rightOffset = bottomControlsWidth;
  
  // Play Button
  if (!self.playButton.hidden) {
    [self.playButton setFrameOriginX:leftOffset + 2];
    [self.playButton setFrameOriginY:(bottomControlsHeight - self.playButton.frame.size.height) / 2];
    leftOffset = CGRectGetMaxX(self.playButton.frame);
  }
  
  // Current Time Label
  if (!self.currentTimeLabel.hidden) {
    [self.currentTimeLabel setFrameOriginX:leftOffset + 6];
    [self.currentTimeLabel setFrameOriginY:(bottomControlsHeight - self.currentTimeLabel.frame.size.height)];
    leftOffset = CGRectGetMaxX(self.currentTimeLabel.frame);
  }
  
  // Full Screen Button
  if (!self.fullscreenButton.hidden) {
    [self.fullscreenButton setFrameOriginX:rightOffset - 4 - self.fullscreenButton.frame.size.width];
    [self.fullscreenButton setFrameOriginY:(bottomControlsHeight - self.fullscreenButton.frame.size.height) / 2];
    rightOffset = CGRectGetMinX(self.fullscreenButton.frame);
  }
  
  // Captions Button
  if (!self.captionButton.hidden) {
    [self.captionButton setFrameOriginX:rightOffset - 4 - self.captionButton.frame.size.width];
    [self.captionButton setFrameOriginY:(bottomControlsHeight - self.captionButton.frame.size.height) / 2];
    rightOffset = CGRectGetMinX(self.captionButton.frame);
  }
  
  // Total Time Label
  if (!self.totalTimeLabel.hidden) {
    [self.totalTimeLabel setFrameOriginX:rightOffset - 2 - self.totalTimeLabel.frame.size.width];
    [self.totalTimeLabel setFrameOriginY:(bottomControlsHeight - self.captionButton.frame.size.height) / 2];
    rightOffset = CGRectGetMinX(self.totalTimeLabel.frame);
  }
  
  // Scrubber
  if (!self.scrubber.hidden) {
    [self.scrubber setFrameOriginX:leftOffset + 4];
    [self.scrubber setFrameWidth:self.totalTimeLabel.frame.origin.x - self.scrubber.frame.origin.x - 4];
    [self.scrubber setFrameOriginY:(bottomControlsHeight - self.scrubber.frame.size.height) / 2];
  }
}

- (void)layoutSlider {
  [self layoutSliderForOrientation:self.delegate.visibleInterfaceOrientation];
}

- (void)setPlayButtonsSelected:(BOOL)selected {
  self.playButton.selected = selected;
  self.playButton.center = self.view.center;
}

- (void)setPlayButtonsEnabled:(BOOL)enabled {
  self.playButton.enabled = enabled;
}

- (void)setControlsEnabled:(BOOL)enabled {
  
  self.captionButton.enabled = enabled;
  
  [self setPlayButtonsEnabled:enabled];
  
  self.scrubber.enabled = enabled;
  self.fullscreenButton.enabled = enabled;
  
  self.isControlsEnabled = enabled;
  
  NSMutableArray *controlList = self.customControls.mutableCopy;
  [controlList addObjectsFromArray:self.portraitControls];
  [controlList addObjectsFromArray:self.landscapeControls];
  for (UIView *control in controlList) {
    if ([control isKindOfClass:[UIButton class]]) {
      UIButton *button = (UIButton*)control;
      button.enabled = enabled;
    }
  }
}

- (IBAction)handleSingleTap:(id)sender {
  [self setControlsHidden:!self.isControlsHidden];
  if (!self.isControlsHidden) {
    self.controlHideCountdown = kPlayerControlsAutoHideTime;
  }
  [self.delegate playerViewSingleTapped];
}

- (void)setControlHideCountdown:(NSInteger)controlHideCountdown {
  if (controlHideCountdown == 0) {
    [self setControlsHidden:YES];
  } else {
    [self setControlsHidden:NO];
  }
  _controlHideCountdown = controlHideCountdown;
}

- (void)hideControlsIfNecessary {
  if (self.isControlsHidden) return;
  if (self.controlHideCountdown == -1) {
    [self setControlsHidden:NO];
  } else if (self.controlHideCountdown == 0) {
    [self setControlsHidden:YES];
  } else {
    self.controlHideCountdown--;
  }
}

- (void)setLoading:(BOOL)isLoading {
  if (isLoading) {
    [self.activityIndicator startAnimating];
  } else {
    [self.activityIndicator stopAnimating];
  }
}

- (void)setControlsHidden:(BOOL)hidden {
  DDLogVerbose(@"Controls: %@", hidden ? @"hidden" : @"visible");

  if (self.isControlsHidden != hidden) {
    self.isControlsHidden = hidden;
    self.controls.hidden = hidden;

    if (UIInterfaceOrientationIsLandscape(self.delegate.visibleInterfaceOrientation)) {
      for (UIView *control in self.landscapeControls) {
        control.hidden = hidden;
      }
    }
    if (UIInterfaceOrientationIsPortrait(self.delegate.visibleInterfaceOrientation)) {
      for (UIView *control in self.portraitControls) {
        control.hidden = hidden;
      }
    }
    for (UIView *control in self.customControls) {
      control.hidden = hidden;
    }
  }
  
  [self updateSubtitlesPosition];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
  if ([touch.view isKindOfClass:[VKScrubber class]] ||
      [touch.view isKindOfClass:[UIButton class]]) {
    // prevent recognizing touches on the slider
    return NO;
  }
  return YES;
}

- (void)layoutForOrientation:(UIInterfaceOrientation)interfaceOrientation {
  if (UIInterfaceOrientationIsPortrait(interfaceOrientation)) {
//    self.captionButton.hidden = YES;
    
    [self.playButton setFrameOriginY:CGRectGetMinY(self.bottomControls.frame)/2 - CGRectGetHeight(self.playButton.frame)/2];
    
    for (UIView *control in self.portraitControls) {
      control.hidden = self.isControlsHidden;
    }
    for (UIView *control in self.landscapeControls) {
      control.hidden = YES;
    }
    
  } else {
//    self.captionButton.hidden = NO;

    [self.playButton setFrameOriginY:CGRectGetMinY(self.bottomControls.frame)/2 - CGRectGetHeight(self.playButton.frame)/2];
    
    for (UIView *control in self.portraitControls) {
      control.hidden = YES;
    }
    for (UIView *control in self.landscapeControls) {
      control.hidden = self.isControlsHidden;
    }
  }
  
  [self layoutSliderForOrientation:interfaceOrientation];
}

@end
