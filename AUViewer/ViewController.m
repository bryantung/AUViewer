//
//  ViewController.m
//  AUViewer
//
//  Created by Bryan Tung on 3/27/13.
//  Copyright (c) 2013 Bryan Tung. All rights reserved.
//

#import "ViewController.h"

@interface ViewController ()

@property (nonatomic)   MPMediaPickerController *mPicker;

@end

@implementation ViewController

#pragma mark -
#pragma mark MediaPicker

- (IBAction)pickASong:(id)sender
{
    //trigger modal view MPMediaPickerController
    if (_mPicker) {
        //dismiss if presented
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
    //user has picked an item
    [mediaPicker dismissViewControllerAnimated:YES completion:nil];
    MPMediaItem *pickedItem = [[mediaItemCollection items] objectAtIndex:0];
    //put UI to ignore state
    [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
    [_spinner startAnimating];
    //call export operation
    //return if operation has failed
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
    //using AVFoundation AVAsset API to read and write (AVAssetReader/AVAssetWriter)
    //get picked file from picker
    AVURLAsset *asset = [AVURLAsset assetWithURL:[mediaItem valueForProperty:MPMediaItemPropertyAssetURL]];
    
    //reader and writer initialize
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
    //setting writer's output options
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
    //set and ready to read and write to raw
    AVAssetTrack *soundTrack = [asset.tracks objectAtIndex:0];
	[assetWriter startSessionAtSourceTime:CMTimeMake(0, soundTrack.naturalTimeScale)];
    dispatch_queue_t mediaOutputQueue = dispatch_queue_create("mediaOutputQueue", NULL);
    [assetWriterInput requestMediaDataWhenReadyOnQueue:mediaOutputQueue usingBlock:^{
        //start writing
        while (assetWriterInput.readyForMoreMediaData) {
            CMSampleBufferRef bufferRef = [assetReaderOutput copyNextSampleBuffer];
            if (!bufferRef) {
                //reader eof
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
                //write complete
                break;
            }
            [assetWriterInput appendSampleBuffer:bufferRef];
        }
    }];
    
    return YES;
}

- (NSURL *)exportURL
{
    //return the user document directory: iTunes file sharing
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
