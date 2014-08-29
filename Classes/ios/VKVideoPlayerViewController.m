//
//  Created by Viki.
//  Copyright (c) 2014 Viki Inc. All rights reserved.
//

#import "VKVideoPlayerViewController.h"
#import "VKVideoPlayerConfig.h"
#import "VKFoundation.h"
#import "VKVideoPlayerCaptionSRT.h"
#import "VKVideoPlayerAirPlay.h"
#import "VKVideoPlayerSettingsManager.h"
#import "VKVideoPlayerView.h"

@interface VKVideoPlayerViewController () {
}

@property (assign) BOOL applicationIdleTimerDisabled;
@end

@implementation VKVideoPlayerViewController

- (id)init {
  self = [super initWithNibName:NSStringFromClass([self class]) bundle:nil];
  if (self) {
    self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [self initialize];
  }
  return self;
}


- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
  self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
  if (self) {
    self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [self initialize];
  }
  return self;
}

- (void)initialize {
  [VKSharedAirplay setup];
}
- (void)dealloc {
  [VKSharedAirplay deactivate];
}

- (void)viewDidUnload {
  [super viewDidUnload];
}

- (void)viewDidLoad {
  [super viewDidLoad];
  
  VKVideoPlayerView *playerView = [[VKVideoPlayerView alloc] initWithFrame:self.view.frame];
  self.player = [[VKVideoPlayerTwo alloc] initWithVideoPlayerView:playerView];
  self.player.delegate = self;
//  self.player.view.frame = self.view.frame;
//  self.player.forceRotate = YES;
  [self.view addSubview:self.player.playerView];
  
  if (VKSharedAirplay.isConnected) {
    [VKSharedAirplay activate:self.player];
  }
  
  [VKSharedUtility setSetting:@YES forKey:kVKSettingsSubtitlesEnabledKey];
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  self.applicationIdleTimerDisabled = [UIApplication sharedApplication].isIdleTimerDisabled;
  [UIApplication sharedApplication].idleTimerDisabled = YES;
  [[UIApplication sharedApplication] setStatusBarHidden:NO];
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated {
  [UIApplication sharedApplication].idleTimerDisabled = self.applicationIdleTimerDisabled;
  [super viewWillDisappear:animated];
}

- (BOOL)prefersStatusBarHidden {
  return NO;
}

- (void)playVideoWithStreamURL:(NSURL*)streamURL {
  [self.player loadVideoWithTrack:[[VKVideoPlayerTrack alloc] initWithStreamURL:streamURL]];
}

- (void)setSubtitle:(VKVideoPlayerCaption*)subtitle {
  [self.player loadSubtitles:subtitle];
}

#pragma mark - App States

- (void)applicationWillResignActive {
  self.player.playerView.controlHideCountdown = -1;
  if (self.player.state == VKVideoPlayerStateContentPlaying) [self.player pauseContentWithCompletionHandler:nil];
}

- (void)applicationDidBecomeActive {
  self.player.playerView.controlHideCountdown = 5;
}

#pragma mark - VKVideoPlayerControllerDelegate
- (void)videoPlayer:(VKVideoPlayer*)videoPlayer didControlByEvent:(VKVideoPlayerControlEvent)event {
  if (event == VKVideoPlayerControlEventTapDone) {
    [self dismissViewControllerAnimated:YES completion:nil];
  }
}

#pragma mark - Orientation
- (BOOL)shouldAutorotate {
  return NO;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
  if (self.player.playerView.isFullScreen) {
    return UIInterfaceOrientationIsLandscape(interfaceOrientation);
  } else {
    return NO;
  }
}

@end
