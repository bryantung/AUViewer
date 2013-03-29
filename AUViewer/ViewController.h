//
//  ViewController.h
//  AUViewer
//
//  Created by Bryan Tung on 3/27/13.
//  Copyright (c) 2013 Bryan Tung. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>

@interface ViewController : UIViewController<MPMediaPickerControllerDelegate, UIAlertViewDelegate, AVAudioPlayerDelegate>{
    
}

@property (weak, nonatomic) IBOutlet    UIButton                *pickSongButton;
@property (weak, nonatomic) IBOutlet    UIActivityIndicatorView *spinner;
@property (weak, nonatomic) IBOutlet    UISegmentedControl      *streamSelect;
@property (weak, nonatomic) IBOutlet    UIButton                *playbackControl;
@property (weak, nonatomic) IBOutlet    UILabel                 *durationLabel;
@property (weak, nonatomic) IBOutlet    UILabel                 *timingLabel;
@property (weak, nonatomic) IBOutlet    UIProgressView          *bufferBar;
@property (weak, nonatomic) IBOutlet    UISlider                *playbackProgress;

- (IBAction)pickASong:(id)sender;
- (IBAction)streamSeleted:(UISegmentedControl *)sender forEvent:(UIEvent *)event;
- (IBAction)playbackTap:(UIButton *)sender;

@end
