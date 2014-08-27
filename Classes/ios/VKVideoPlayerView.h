//
//  Created by Viki.
//  Copyright (c) 2014 Viki Inc. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>

#import "VKScrubber.h"
#import "VKPickerButton.h"
#import "VKView.h"
#import "VKVideoPlayerConfig.h"
#import "VKVideoPlayerTwo.h"

#define kPlayerControlsAutoHideTime    5
#define kPlayerControlsDisableAutoHide -1

@class VKVideoPlayerTrack;
@class VKVideoPlayerLayerView;

@interface VKVideoPlayerView : UIView <VKVikiVideoPlayerViewInterface>

@property (strong, nonatomic) IBOutlet UIView *view;
@property (strong, nonatomic) IBOutlet VKVideoPlayerLayerView *playerLayerView;
@property (strong, nonatomic) IBOutlet UIView *controls;
@property (strong, nonatomic) IBOutlet UIActivityIndicatorView *activityIndicator;
@property (strong, nonatomic) IBOutlet VKPickerButton *captionButton;
@property (strong, nonatomic) IBOutlet UIButton *playButton;
@property (strong, nonatomic) IBOutlet UILabel *currentTimeLabel;
@property (strong, nonatomic) IBOutlet VKScrubber *scrubber;
@property (strong, nonatomic) IBOutlet UILabel *totalTimeLabel;
@property (strong, nonatomic) IBOutlet UIButton *fullscreenButton;
@property (strong, nonatomic) IBOutlet UIButton *doneButton;
@property (strong, nonatomic) IBOutlet UILabel *messageLabel;
@property (strong, nonatomic) IBOutlet UIView *bottomControls;
@property (strong, nonatomic) IBOutlet DTAttributedLabel* subtitleLabel;

@property (assign, nonatomic) BOOL isControlsEnabled;
@property (assign, nonatomic) BOOL isControlsHidden;

@property (weak, nonatomic) id<VKVideoPlayerViewDelegate> delegate;

@property (assign, nonatomic) NSInteger controlHideCountdown;

@property (strong, nonatomic) IBOutlet UIView* externalDeviceView;
@property (strong, nonatomic) IBOutlet UIImageView* externalDeviceImageView;
@property (strong, nonatomic) IBOutlet UILabel* externalDeviceLabel;

@property (assign, nonatomic) CGRect portraitFrame;
@property (assign, nonatomic) CGRect landscapeFrame;

- (IBAction)fullscreenButtonTapped:(id)sender;
- (IBAction)playButtonTapped:(id)sender;

- (IBAction)captionButtonTapped:(id)sender;

- (IBAction)handleSingleTap:(id)sender;

- (void)updateTimeLabels;
- (void)setControlsHidden:(BOOL)hidden;
- (void)setControlsEnabled:(BOOL)enabled;
- (void)hideControlsIfNecessary;
- (void)setLoading:(BOOL)isLoading;

- (void)setPlayButtonsSelected:(BOOL)selected;
- (void)setPlayButtonsEnabled:(BOOL)enabled;

- (void)layoutForOrientation:(UIInterfaceOrientation)interfaceOrientation;
@end