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

@interface ViewController : UIViewController<MPMediaPickerControllerDelegate, UIAlertViewDelegate>{
    
}

@property (weak, nonatomic) IBOutlet UIButton *pickSongButton;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *spinner;

- (IBAction)pickASong:(id)sender;

@end
