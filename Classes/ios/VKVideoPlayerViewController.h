//
//  Created by Viki.
//  Copyright (c) 2014 Viki Inc. All rights reserved.
//

#import "VKVideoPlayer.h"
#import "VKVideoPlayerConfig.h"
#import <IMAAdsLoader.h>

@class IMAAdDisplayContainer;
@class IMAAVPlayerContentPlayhead;

@interface VKVideoPlayerViewController: UIViewController <
  VKVideoPlayerDelegate,
  IMAAdsLoaderDelegate,
  IMAAdsManagerDelegate
>

// Google IMA
@property (nonatomic, strong) IMAAdDisplayContainer *adDisplayContainer;
@property (nonatomic, strong) IMAAVPlayerContentPlayhead *contentPlayhead;
@property (nonatomic, strong) IMAAdsLoader *adsLoader;
@property (nonatomic, strong) IMAAdsManager *adsManager;

@property (nonatomic, strong) VKVideoPlayer* player;
- (void)playVideoWithStreamURL:(NSURL*)streamURL;
- (void)setSubtitle:(VKVideoPlayerCaption*)subtitle;
@end
