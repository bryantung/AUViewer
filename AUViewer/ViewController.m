//
//  ViewController.m
//  AUViewer
//
//  Created by Bryan Tung on 3/27/13.
//  Copyright (c) 2013 Bryan Tung. All rights reserved.
//
//  3/27
//  AVAsset/AVAssetReader/AVAssetWritter/MPMediaPicker
//  iPod library audio raw export
//
//  3/28
//  AVPlayer
//  HTTP audio stream request
//

#import "ViewController.h"

@interface ViewController ()

@property (nonatomic)   MPMediaPickerController *mPicker;
@property (nonatomic)   AVPlayer                *streamPlayer;
@property (nonatomic)   NSTimer                 *checkBufferedTimer;
@property (nonatomic)   NSTimer                 *playbackTimeUpdate;

@end

@implementation ViewController

static NSString *streamPlayerPlaybackNotification = @"streamPlayerPlaybackNotification";
static NSString *streamPlayerStatusNotification = @"streamPlayerStatusNotification";

#pragma mark -
#pragma mark Media Picker

- (IBAction)pickASong:(id)sender
{
    // trigger modal view MPMediaPickerController
    if (_mPicker) {
        // dismiss if presented
        [_mPicker dismissViewControllerAnimated:YES completion:nil];
        _mPicker = nil;
        return;
    }
    MPMediaPickerController *picker = [[MPMediaPickerController alloc] initWithMediaTypes:MPMediaTypeAnyAudio];
    [picker setAllowsPickingMultipleItems:NO];
    [picker setDelegate:self];
    [self presentViewController:picker animated:YES completion:nil];
    _mPicker = picker;
}

- (void)mediaPickerDidCancel:(MPMediaPickerController *)mediaPicker
{
    [mediaPicker dismissViewControllerAnimated:YES completion:nil];
    _mPicker = nil;
}

- (void)mediaPicker:(MPMediaPickerController *)mediaPicker didPickMediaItems:(MPMediaItemCollection *)mediaItemCollection
{
    // user has picked an item
    [mediaPicker dismissViewControllerAnimated:YES completion:nil];
    MPMediaItem *pickedItem = [[mediaItemCollection items] objectAtIndex:0];
    // put UI to ignore state
    [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
    [_spinner startAnimating];
    // call export operation
    // return if operation has failed
    if (![self readAudioChunksWithMediaItem:pickedItem]) {
        [[UIApplication sharedApplication] endIgnoringInteractionEvents];
        [_spinner stopAnimating];
    }
    
    _mPicker = nil;
}

#pragma mark -
#pragma mark RAW export operations

- (BOOL)readAudioChunksWithMediaItem:(MPMediaItem *)mediaItem
{
    // using AVFoundation AVAsset API to read and write (AVAssetReader/AVAssetWriter)
    // get picked file from picker
    AVURLAsset *asset = [AVURLAsset assetWithURL:[mediaItem valueForProperty:MPMediaItemPropertyAssetURL]];
    
    // reader and writer initialize
    NSError *error = nil;
    AVAssetReader *assetReader = [AVAssetReader assetReaderWithAsset:asset error:&error];
    if (!assetReader||error) {
        NSLog(@"assetReader failed: %@",error);
        return NO;
    }
    
    AVAssetWriter *assetWriter = [AVAssetWriter assetWriterWithURL:[self exportURL] fileType:AVFileTypeCoreAudioFormat error:&error];
    if (!assetWriter||error) {
        NSLog(@"assetWriter failed: %@",error);
        return NO;
    }
    
    AVAssetReaderOutput *assetReaderOutput = [AVAssetReaderAudioMixOutput assetReaderAudioMixOutputWithAudioTracks:asset.tracks audioSettings:nil];
    if (!assetReaderOutput||error) {
        NSLog(@"assetReaderOutput failed: %@",error);
        return NO;
    }
    // setting writer's output options
    AudioChannelLayout audioChannelLayout;
	memset(&audioChannelLayout, 0, sizeof(AudioChannelLayout));
	audioChannelLayout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo;
    AVAssetWriterInput *assetWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:[NSDictionary dictionaryWithObjectsAndKeys:
                                                                                                                              [NSNumber numberWithInt:kAudioFormatLinearPCM], AVFormatIDKey,
                                                                                                                              [NSNumber numberWithFloat:44100.0f], AVSampleRateKey,
                                                                                                                              [NSNumber numberWithInt:2], AVNumberOfChannelsKey,
                                                                                                                              [NSData dataWithBytes:&audioChannelLayout length:sizeof(audioChannelLayout)], AVChannelLayoutKey, 
                                                                                                                              [NSNumber numberWithInt:16], AVLinearPCMBitDepthKey, 
                                                                                                                              [NSNumber numberWithBool:NO], AVLinearPCMIsNonInterleaved, 
                                                                                                                              [NSNumber numberWithBool:NO], AVLinearPCMIsFloatKey, 
                                                                                                                              [NSNumber numberWithBool:NO], AVLinearPCMIsBigEndianKey, 
                                                                                                                              nil]];
    assetWriterInput.expectsMediaDataInRealTime = NO;
    if (!assetWriterInput||error) {
        NSLog(@"assetWriterInput failed: %@",error);
        return NO;
    }
    
    if (![assetReader canAddOutput:assetReaderOutput]) {
        NSLog(@"assetReader cannot add output");
        return NO;
    }
    [assetReader addOutput:assetReaderOutput];
    
    if (![assetWriter canAddInput:assetWriterInput]) {
		NSLog(@"assetWriter cannot add input");
		return NO;
	}
	[assetWriter addInput:assetWriterInput];
    
    if (![assetReader startReading]) {
        NSLog(@"assetReader start reading has failed: %@",assetReader.error);
        return NO;
    }
    
    if (![assetWriter startWriting]) {
        NSLog(@"assetWriter start writing has failed: %@",assetWriter.error);
        return NO;
    }
    // set and ready to read and write to raw
    AVAssetTrack *soundTrack = [asset.tracks objectAtIndex:0];
	[assetWriter startSessionAtSourceTime:CMTimeMake(0, soundTrack.naturalTimeScale)];
    dispatch_queue_t mediaOutputQueue = dispatch_queue_create("mediaOutputQueue", NULL);
    [assetWriterInput requestMediaDataWhenReadyOnQueue:mediaOutputQueue usingBlock:^{
        // start writing
        while (assetWriterInput.readyForMoreMediaData) {
            CMSampleBufferRef bufferRef = [assetReaderOutput copyNextSampleBuffer];
            if (!bufferRef) {
                // reader eof
                [assetWriterInput markAsFinished];
				[assetWriter finishWritingWithCompletionHandler:^{}];
				[assetReader cancelReading];
                
				dispatch_sync(dispatch_get_main_queue(), ^{
                    [[UIApplication sharedApplication] endIgnoringInteractionEvents];
					[_spinner stopAnimating];
                    UIAlertView *completeAlert = [[UIAlertView alloc] initWithTitle:@"Export complete"
                                                                            message:[NSString stringWithFormat:@"The song: %@ has been exported succesfully!",[mediaItem valueForProperty:MPMediaItemPropertyTitle]]
                                                                           delegate:self
                                                                  cancelButtonTitle:@"Dismiss"
                                                                  otherButtonTitles:nil];
                    [completeAlert show];
				});
                // write complete
                break;
            }
            [assetWriterInput appendSampleBuffer:bufferRef];
        }
    }];
    
    return YES;
}

- (NSURL *)exportURL
{
    // return the user document directory: iTunes file sharing
	NSString *docDirPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
	NSString *exportFilePath = [docDirPath stringByAppendingPathComponent:@"RAW-exported.caf"];
    
	if([[NSFileManager defaultManager] fileExistsAtPath:exportFilePath]) {
		NSError *error = nil;
		if(![[NSFileManager defaultManager] removeItemAtPath:exportFilePath error:&error]) {
			NSLog(@"old temp file remove failed: %@", error);
		}
	}
    
	return [NSURL fileURLWithPath:exportFilePath];
}

#pragma mark -
#pragma mark AVPlayer functions

// observing key path changes:
// streamPlayer's playing rate (play/pause)
// update stream buffered length and playback current time
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context == (__bridge void *)(streamPlayerPlaybackNotification)) {
        if (_streamPlayer.rate==0.0) { // paused
            [_playbackControl setTitle:@"Play" forState:UIControlStateNormal];
        } else { // playing
            [_playbackControl setTitle:@"Pause" forState:UIControlStateNormal];
        }
    }
    if (context == (__bridge void *)(streamPlayerStatusNotification)) {
        if (_streamPlayer.status==AVPlayerStatusReadyToPlay) {
            [_streamPlayer play];
            
            if (_checkBufferedTimer) {
                [_checkBufferedTimer invalidate];
                _checkBufferedTimer = nil;
            }
            [_bufferBar setProgress:0.0];
            _checkBufferedTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(availableDuration) userInfo:nil repeats:YES];
            [_durationLabel setText:[NSString stringWithFormat:@"%02d:%02d",(int)floor(CMTimeGetSeconds([[_streamPlayer currentItem] duration])/60),((int)floor(CMTimeGetSeconds([[_streamPlayer currentItem] duration])))%60]];
            
            if (_playbackTimeUpdate) {
                [_playbackTimeUpdate invalidate];
                _playbackTimeUpdate = nil;
            }
            [_playbackProgress setValue:0.0];
            _playbackTimeUpdate = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(updatePlaybackProgress) userInfo:nil repeats:YES];
            
            [_spinner stopAnimating];
        }
    }
}

// stream select handler
- (IBAction)streamSeleted:(UISegmentedControl *)sender forEvent:(UIEvent *)event {
    NSURL *streamURL;
    switch (sender.selectedSegmentIndex) {
        case 0:
            streamURL = [NSURL URLWithString:@"http://www.bryantung.info/audio/huntersmoon.mp3"];
            break;
            
        case 1:
            streamURL = [NSURL URLWithString:@"http://www.bryantung.info/audio/drifting.mp3"];
            break;
    }
    // remove old player instance and start new player
    [_streamPlayer removeObserver:self forKeyPath:@"rate" context:(__bridge void *)(streamPlayerPlaybackNotification)];
    [_streamPlayer removeObserver:self forKeyPath:@"status" context:(__bridge void *)(streamPlayerStatusNotification)];
    _streamPlayer = nil;
    
    AVPlayer *newPlayer = [[AVPlayer alloc] initWithURL:streamURL];
    if (newPlayer.status==AVPlayerItemStatusFailed) {
        NSLog(@"stream load failed");
        [_durationLabel setText:@"--:--"];
        [_timingLabel setText:@"--:--"];
        return;
    }
    [newPlayer setActionAtItemEnd:AVPlayerActionAtItemEndPause];
    [newPlayer addObserver:self forKeyPath:@"rate" options:0 context:(__bridge void *)(streamPlayerPlaybackNotification)];
    _streamPlayer = newPlayer;
    
    [_spinner startAnimating];
    [_streamPlayer addObserver:self forKeyPath:@"status" options:0 context:(__bridge void *)(streamPlayerStatusNotification)];
}

- (IBAction)playbackTap:(UIButton *)sender {
    if ([[sender titleForState:UIControlStateNormal] isEqualToString:@"Play"]) {
        // if player has reached the end
        if (CMTimeGetSeconds(_streamPlayer.currentTime)>=CMTimeGetSeconds([_streamPlayer.currentItem duration])) {
            [_streamPlayer seekToTime:kCMTimeZero];
        }
        [_streamPlayer play];
        [sender setTitle:@"Pause" forState:UIControlStateNormal];
    } else if ([[sender titleForState:UIControlStateNormal] isEqualToString:@"Pause"]) {
        [_streamPlayer pause];
        [sender setTitle:@"Play" forState:UIControlStateNormal];
    }
}
// calculate stream buffer current length/progress
- (NSTimeInterval)availableDuration
{
    NSArray *loadedTimeRanges = [[_streamPlayer currentItem] loadedTimeRanges];
    CMTimeRange timeRange = [[loadedTimeRanges lastObject] CMTimeRangeValue];
    float startSeconds = CMTimeGetSeconds(timeRange.start);
    float durationSeconds = CMTimeGetSeconds(timeRange.duration);
    NSTimeInterval totalDuration = CMTimeGetSeconds([[_streamPlayer currentItem] duration]);
    NSTimeInterval result = startSeconds + durationSeconds;
    [_bufferBar setProgress:(result/totalDuration)];
    if (result>=totalDuration) {
        [_checkBufferedTimer invalidate];
        _checkBufferedTimer = nil;
    }
    return result;
}

- (void)updatePlaybackProgress
{
    NSTimeInterval currentTime = CMTimeGetSeconds([[_streamPlayer currentItem] currentTime]);
    NSTimeInterval duration = CMTimeGetSeconds([[_streamPlayer currentItem] duration]);
    [_playbackProgress setValue:(currentTime/duration)];
    [_timingLabel setText:[NSString stringWithFormat:@"%02d:%02d",(int)floor(currentTime/60),((int)floor(currentTime))%60]];
}

#pragma mark -
#pragma mark View Lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
    
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

@end
