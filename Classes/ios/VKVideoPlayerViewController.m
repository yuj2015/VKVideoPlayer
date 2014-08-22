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
#import <IMAAVPlayerContentPlayhead.h>
#import <IMAAdDisplayContainer.h>
#import <IMAAdsRequest.h>


const char* AdEventNames[] = {
  "All Ads Complete",
  "Clicked",
  "Complete",
  "First Quartile",
  "Loaded",
  "Midpoint",
  "Pause",
  "Resume",
  "Third Quartile",
  "Started",
};

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
  
  self.player = [[VKVideoPlayer alloc] init];
  self.player.delegate = self;
  self.player.view.frame = self.view.bounds;
  self.player.forceRotate = YES;
  [self.view addSubview:self.player.view];
  
  if (VKSharedAirplay.isConnected) {
    [VKSharedAirplay activate:self.player];
  }
  
  [self setupAdsLoader];
  
  [self logMessage:@"IMA SDK version: %@", [IMAAdsLoader sdkVersion]];
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  self.applicationIdleTimerDisabled = [UIApplication sharedApplication].isIdleTimerDisabled;
  [UIApplication sharedApplication].idleTimerDisabled = YES;
  [[UIApplication sharedApplication] setStatusBarHidden:NO];
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  [self requestAds];
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
  [self.player setCaptionToBottom:subtitle];
}

#pragma mark - App States

- (void)applicationWillResignActive {
  self.player.view.controlHideCountdown = -1;
  if (self.player.state == VKVideoPlayerStateContentPlaying) [self.player pauseContent:NO completionHandler:nil];
}

- (void)applicationDidBecomeActive {
  self.player.view.controlHideCountdown = kPlayerControlsDisableAutoHide;
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
  if (self.player.isFullScreen) {
    return UIInterfaceOrientationIsLandscape(interfaceOrientation);
  } else {
    return NO;
  }
}

# pragma mark - Google IMA
- (IMASettings *)createIMASettings {
  IMASettings *settings = [[IMASettings alloc] init];
  settings.ppid = @"IMA_PPID_0";
  settings.language = @"en";
  return settings;
}

- (void)setupAdsLoader {
  // Initalize Google IMA ads Loader.
  self.adsLoader = [[IMAAdsLoader alloc] initWithSettings:[self createIMASettings]];
  // Implement delegate methods to get callbacks from the adsLoader.
  self.adsLoader.delegate = self;
}

# pragma mark - IMAAdsLoaderDelegate
- (void)adsLoader:(IMAAdsLoader *)loader adsLoadedWithData:(IMAAdsLoadedData *)adsLoadedData {
  [self logMessage:@"Loaded ads."];
  self.adsManager = adsLoadedData.adsManager;
  if (self.adsManager.adCuePoints.count > 0) {
    NSMutableString *cuePoints = [NSMutableString stringWithString:@"("];
    for (NSNumber *cuePoint in self.adsManager.adCuePoints) {
      [cuePoints appendFormat:@"%@, ", cuePoint];
    }
    [cuePoints replaceCharactersInRange:NSMakeRange([cuePoints length]-2, 2)
                             withString:@")"];
    [self logMessage:[NSString stringWithFormat:@"Ad cue points received: %@",
                      cuePoints]];
  }
  self.adsManager.delegate = self;
  
  // Default values, change these if you want to provide custom bitrate and
  // MIME types. If left to default, the SDK will select media files based
  // on the current network conditions and all MIME types supported on iOS.
  IMAAdsRenderingSettings *settings = [[IMAAdsRenderingSettings alloc] init];
  settings.bitrate = kIMAAutodetectBitrate;
  settings.mimeTypes = @[@"video/mp4", @"application/x-mpegURL"];
  [self.adsManager initializeWithContentPlayhead:self.contentPlayhead
                            adsRenderingSettings:settings];
}

- (void)adsLoader:(IMAAdsLoader *)loader failedWithErrorData:(IMAAdLoadingErrorData *)adErrorData {
  [self logMessage:@"Ad loading error: code:%d, message: %@",
   adErrorData.adError.code,
   adErrorData.adError.message];
  [self.player playContent];
}

# pragma mark - IMAAdsManagerDelegate
- (void)adsManager:(IMAAdsManager *)adsManager didReceiveAdEvent:(IMAAdEvent *)event {
  [self logMessage:@"AdsManager event (%s).", AdEventNames[event.type]];
  
  switch (event.type) {
    case kIMAAdEvent_LOADED: {
      //      [adsManager start];
      NSString *adPodInfoString =
      [NSString stringWithFormat:
       @"Showing ad %d/%d, bumper: %@, title: %@, description: %@, contentType: %@",
       event.ad.adPodInfo.adPosition,
       event.ad.adPodInfo.totalAds,
       event.ad.adPodInfo.isBumper ? @"YES" : @"NO",
       event.ad.adTitle,
       event.ad.description,
       event.ad.contentType];
      
      // Log extended data.
      NSString *extendedAdPodInfo =
      [NSString stringWithFormat:@"%@, pod index: %d, time offset: %lf, max duration: %lf",
       adPodInfoString,
       event.ad.adPodInfo.podIndex,
       event.ad.adPodInfo.timeOffset,
       event.ad.adPodInfo.maxDuration];
      
      [self logMessage:extendedAdPodInfo];
      break;
    }
    case kIMAAdEvent_ALL_ADS_COMPLETED:
      [self unloadAdsManager];
      break;
    case kIMAAdEvent_STARTED: {
      NSString *adPodInfoString =
      [NSString stringWithFormat:
       @"Showing ad %d/%d, bumper: %@, title: %@, description: %@, contentType: %@",
       event.ad.adPodInfo.adPosition,
       event.ad.adPodInfo.totalAds,
       event.ad.adPodInfo.isBumper ? @"YES" : @"NO",
       event.ad.adTitle,
       event.ad.description,
       event.ad.contentType];
      
      // Log extended data.
      NSString *extendedAdPodInfo =
      [NSString stringWithFormat:@"%@, pod index: %d, time offset: %lf, max duration: %lf",
       adPodInfoString,
       event.ad.adPodInfo.podIndex,
       event.ad.adPodInfo.timeOffset,
       event.ad.adPodInfo.maxDuration];
      
      [self logMessage:extendedAdPodInfo];
      break;
    }
    case kIMAAdEvent_PAUSE:
      //      [self setPlayButtonType:PlayButton];
      break;
    case kIMAAdEvent_RESUME:
      //      [self setPlayButtonType:PauseButton];
      break;
    case kIMAAdEvent_COMPLETE:
      break;
    default:
      // no-op
      break;
  }
}

- (void)adsManager:(IMAAdsManager *)adsManager didReceiveAdError:(IMAAdError *)error {
  [self.player playContent];
}

- (void)adsManagerDidRequestContentPause:(IMAAdsManager *)adsManager {
  [self.player pauseContent];
}

- (void)adsManagerDidRequestContentResume:(IMAAdsManager *)adsManager {
  [self.player playContent];
}

# pragma mark - Ad Utility
- (void)requestAds {
  [self logMessage:@"Requesting ads."];
  [self unloadAdsManager];
  
  
  // Create an adDisplayContainer with the ad container and companion ad slots.
  self.adDisplayContainer = [[IMAAdDisplayContainer alloc]
                             initWithAdContainer:(UIView *)self.player.view.playerLayerView
                             companionSlots:nil];
  
  self.contentPlayhead = [[IMAAVPlayerContentPlayhead alloc] initWithAVPlayer:self.player.avPlayer];
  
  // Create an adsRequest object and request ads from the ad server.
  
  NSString *testAdUrl = @"http://pubads.g.doubleclick.net/gampad/ads?sz=640x360&iu=/8036/Viki.Video.1-1-1.Short&ciu_szs&impl=s&gdfp_req=1&env=vp&output=xml_vast2&unviewed_position_start=1&url=[referrer_url]&correlator=[timestamp]&cmsid=2059&vid=1047519v&ad_rule=1&description_url=http://www.viki.com/videos/1047519v-wapop-btob-episode-14&ad_settings=4"; // Test Ad
  
  IMAAdsRequest *request =
  [[IMAAdsRequest alloc] initWithAdTagUrl:testAdUrl
                       adDisplayContainer:self.adDisplayContainer
                              userContext:nil];
  self.adsLoader.delegate = self;
  [self.adsLoader requestAdsWithRequest:request];
}

- (void)unloadAdsManager {
  if (self.adsManager != nil) {
    [self.adsManager destroy];
    self.adsManager.delegate = nil;
    self.adsManager = nil;
    self.adDisplayContainer = nil;
    self.contentPlayhead = nil;
  }
}

- (void)logMessage:(NSString *)log, ... {
  va_list args;
  va_start(args, log);
  NSString *s =
  [[NSString alloc] initWithFormat:[NSString stringWithFormat:@"%@\n", log]
                         arguments:args];
  NSLog(@"%@", s);
  va_end(args);
}

- (void)contentDidFinishPlaying {
  [self logMessage:@"Content has completed"];
  [self.adsLoader contentComplete];
}
@end
