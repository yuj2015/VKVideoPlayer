//
//  VKVideoPlayerTwo.h
//  VKVideoPlayer
//
//  Created by Jonathan Ong on 27/8/14.
//  Copyright (c) 2014 Viki Inc. All rights reserved.
//

#import "VKVideoPlayer.h"

@protocol VKVikiVideoPlayerViewInterface <VKVideoPlayerViewInterface>

@end

@interface VKVideoPlayerTwo : VKVideoPlayer

@property (strong, nonatomic) UIView<VKVikiVideoPlayerViewInterface> *playerView;
@end
