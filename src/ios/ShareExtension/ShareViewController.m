//
//  ShareViewController.m
//  OpenWith - Share Extension
//

//
// The MIT License (MIT)
//
// Copyright (c) 2017 Jean-Christophe Hoelt
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

#import <UIKit/UIKit.h>
#import <Social/Social.h>
#import <AVFoundation/AVFoundation.h>
#import "ShareViewController.h"

@interface ShareViewController : UIViewController {
    int _verbosityLevel;
    NSUserDefaults *_userDefaults;
    NSString *_backURL;
    NSMutableArray *_attachmentArray;
}
@property (nonatomic) int verbosityLevel;
@property (nonatomic,retain) NSUserDefaults *userDefaults;
@property (nonatomic,retain) NSString *backURL;
@property (nonatomic,retain) NSString *hostBundleID;
@property (nonatomic) int bitsToLoad;
@property (nonatomic,retain) NSMutableArray *attachmentArray;

@end

/*
 * Constants
 */

#define VERBOSITY_DEBUG  0
#define VERBOSITY_INFO  10
#define VERBOSITY_WARN  20
#define VERBOSITY_ERROR 30

@implementation ShareViewController

@synthesize verbosityLevel = _verbosityLevel;
@synthesize userDefaults = _userDefaults;
@synthesize backURL = _backURL;
@synthesize attachmentArray = _attachmentArray;

- (void) log:(int)level message:(NSString*)message {
    if (level >= self.verbosityLevel) {
        NSLog(@"[ShareViewController.m]%@", message);
    }
}

- (void) debug:(NSString*)message { [self log:VERBOSITY_DEBUG message:message]; }
- (void) info:(NSString*)message { [self log:VERBOSITY_INFO message:message]; }
- (void) warn:(NSString*)message { [self log:VERBOSITY_WARN message:message]; }
- (void) error:(NSString*)message { [self log:VERBOSITY_ERROR message:message]; }

- (void) viewDidLoad {
    [super viewDidLoad];

    printf("did load");
    [self debug:@"[viewDidLoad]"];

    [self submit];
}

- (void) setup {
    self.userDefaults = [[NSUserDefaults alloc] initWithSuiteName:SHAREEXT_GROUP_IDENTIFIER];
    self.verbosityLevel = [self.userDefaults integerForKey:@"verbosityLevel"];
    self.attachmentArray = [[NSMutableArray alloc] init];
    [self debug:@"[setup]"];
}

- (BOOL) isContentValid {
    return YES;
}

- (void) openURL:(nonnull NSURL *)url {
    NSString *className = @"UIApplication";
    if (NSClassFromString(className)) {
        id object = [NSClassFromString(className) performSelector: @selector(sharedApplication)];
        [object performSelector: @selector(openURL:) withObject: url];
    }
}

- (void) dataFetched {
    self.bitsToLoad--;
    if (self.bitsToLoad == 0) {
        [self.extensionContext completeRequestReturningItems:self.extensionContext.inputItems completionHandler:nil];
        NSDictionary *dict = @{
                               @"backURL": self.backURL,
                               @"items": self.attachmentArray
                               };
        [self.userDefaults setObject:dict forKey:SHAREEXT_USERDEFAULTS_DATA_KEY];
        [self.userDefaults synchronize];
        // Emit a URL that opens the cordova app
        NSString *url = [NSString stringWithFormat:@"%@://share", SHAREEXT_APP_URL_SCHEME];
        // I don't know why but here we need to wait for some time. If the user choose the share icon from the expanded list, it looks like we
        // should leave some time for the list to be closed.
        [NSThread sleepForTimeInterval:0.5];
        [self openURL:[NSURL URLWithString:url]];
    }
}

- (NSString *) saveImageToAppGroupFolder: (NSURL *) sourceUrl imageIndex: (int) imageIndex {
    assert( NULL != sourceUrl );
    NSData * data = [NSData dataWithContentsOfURL:sourceUrl];
    UIImage * image = [UIImage imageWithData:data];
    NSData * jpegData = UIImageJPEGRepresentation(image, 1.0);
    NSURL * containerURL = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier: SHAREEXT_GROUP_IDENTIFIER];
    NSString * documentsPath = containerURL.path;
    NSString * fileName = [NSString stringWithFormat: @"image%d.jpg", imageIndex];
    NSString * filePath = [documentsPath stringByAppendingPathComponent: fileName];
    [jpegData writeToFile: filePath atomically: YES];
    return filePath;
}

// We need to do video format transformation here
- (void) saveMovieToAppGroupFolder: (NSURL *) sourceUrl :(int) movieIndex :(NSItemProvider *) itemProvider {
    assert( NULL != sourceUrl );
    NSURL * containerURL = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier: SHAREEXT_GROUP_IDENTIFIER];
    NSString *documentsPath = containerURL.path;
    // AVAssetExportSession cannot export directly under app group folder. We must specify the location as /Library/Caches
    NSString *libraryPath = [documentsPath stringByAppendingPathComponent: @"Library"];
    NSString *cachePath = [libraryPath stringByAppendingPathComponent: @"Caches"];
    NSString * fileName = [NSString stringWithFormat: @"video%d.mp4", movieIndex];
    NSString * filePath = [cachePath stringByAppendingPathComponent: fileName];
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        [[NSFileManager defaultManager] removeItemAtPath:filePath error: nil];
    }
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:sourceUrl options:nil];
    NSArray *compatiblePresets = [AVAssetExportSession exportPresetsCompatibleWithAsset:asset];
    if ([compatiblePresets containsObject:AVAssetExportPresetMediumQuality]) {
        AVAssetExportSession *exportSession = [AVAssetExportSession exportSessionWithAsset:asset presetName:AVAssetExportPresetPassthrough];
        exportSession.outputURL = [NSURL fileURLWithPath:filePath];
        exportSession.outputFileType = AVFileTypeMPEG4;
        [exportSession exportAsynchronouslyWithCompletionHandler:^{
            switch ([exportSession status]) {
                case AVAssetExportSessionStatusCompleted:
                    NSLog(@"Completed exporting!");
                    break;
                case AVAssetExportSessionStatusFailed:
                    NSLog(@"Export failed: %@", [[exportSession error] localizedDescription]);
                    break;
                case AVAssetExportSessionStatusCancelled:
                    NSLog(@"Export canceled");
                    break;
                default:
                    break;
            }
            [self addItemToArray:filePath withProvider:itemProvider];
        }];
    } else {
        [self dataFetched];
    }
}

- (NSString *) storeTextToAppGroupFolder: (NSString *) text fileIndex: (int) index {
    assert( NULL != text );
    NSURL * containerURL = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier: SHAREEXT_GROUP_IDENTIFIER];
    NSString * documentsPath = containerURL.path;
    NSString * fileName = [NSString stringWithFormat: @"note%d.txt", index];
    NSString * targetPath = [documentsPath stringByAppendingPathComponent: fileName];
    @try {
        [text writeToFile:targetPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    @catch (NSException *error) {
        return NULL;
    }
    return targetPath;
}

- (NSString *) copyFileToAppGroupFolder: (NSURL *) sourceUrl fileIndex: (int) index {
    assert( NULL != sourceUrl );
    NSURL * containerURL = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier: SHAREEXT_GROUP_IDENTIFIER];
    NSString * documentsPath = containerURL.path;
    NSString * fileName = [sourceUrl.absoluteString lastPathComponent].stringByRemovingPercentEncoding;
    NSString * targetPath = [documentsPath stringByAppendingPathComponent: fileName];
    @try {
        NSData *data = [NSData dataWithContentsOfURL:sourceUrl];
        [data writeToFile:targetPath atomically:YES];
    }
    @catch (NSException *error) {
        return NULL;
    }
    return targetPath;
}


- (void) addItemToArray: (NSString *)path withProvider:(NSItemProvider*)itemProvider {
    NSString *uti = @"";
    NSArray<NSString *> *utis = [NSArray new];
    if ([itemProvider.registeredTypeIdentifiers count] > 0) {
        uti = itemProvider.registeredTypeIdentifiers[0];
        utis = itemProvider.registeredTypeIdentifiers;
    } else {
        uti = SHAREEXT_UNIFORM_TYPE_IDENTIFIER;
    }
    NSString *from = @"unknown";
    if ([self.hostBundleID isEqualToString:@"com.apple.mobileslideshow"]) from = @"photos";
    if ([self.hostBundleID isEqualToString:@"com.apple.mobilenotes"] ||
        [self.hostBundleID isEqualToString:@"com.google.Keep"]
    ) from = @"notes";
    if ([self.hostBundleID isEqualToString:@"com.apple.DocumentsApp"]) from = @"files";
    NSDictionary *dict = @{
                           @"path": path,
                           @"uti": uti,
                           @"utis": utis,
                           @"from": from
                           };
    [self.attachmentArray addObject:dict];
    [self dataFetched];
}

- (void) handleShare {
    int idx = 0;

    for (NSItemProvider* itemProvider in ((NSExtensionItem*)self.extensionContext.inputItems[0]).attachments) {
        self.bitsToLoad ++;
        idx++;
        if([itemProvider hasItemConformingToTypeIdentifier:@"public.image"]) {
            [itemProvider loadItemForTypeIdentifier:@"public.image" options:nil completionHandler:^(NSURL *item, NSError *error) {
                NSString* targetPath = [self saveImageToAppGroupFolder:item imageIndex:idx];
                [self addItemToArray:targetPath withProvider:itemProvider];
            }];
        }
        else if ([itemProvider hasItemConformingToTypeIdentifier:@"public.text"]) {
            [itemProvider loadItemForTypeIdentifier:@"public.text" options:nil completionHandler:^(NSString *item, NSError *error) {
                NSString* targetPath = [self storeTextToAppGroupFolder:item fileIndex:idx];
                [self addItemToArray:targetPath withProvider:itemProvider];
            }];
        }
        else if([itemProvider hasItemConformingToTypeIdentifier:@"public.movie"]) {
            [itemProvider loadItemForTypeIdentifier:@"public.movie" options:nil completionHandler:^(NSURL *item, NSError *error) {
                [self saveMovieToAppGroupFolder:item :idx :itemProvider];
            }];
        }
        else if ([itemProvider hasItemConformingToTypeIdentifier:@"public.data"]) {
            [itemProvider loadItemForTypeIdentifier:@"public.data" options:nil completionHandler:^(NSURL *item, NSError *error) {
                NSString* targetPath = [self copyFileToAppGroupFolder:item fileIndex:idx];
                [self addItemToArray:targetPath withProvider:itemProvider];
            }];
        }
        else {
            [self debug:[NSString stringWithFormat:@"Attachment not of type file. Is: %@", itemProvider]];
            [self dataFetched];
        }
    }
}

- (void) handleShareForOlderOS {

    for (NSItemProvider* itemProvider in ((NSExtensionItem*)self.extensionContext.inputItems[0]).attachments) {
        self.bitsToLoad++;

        if ([itemProvider hasItemConformingToTypeIdentifier:SHAREEXT_UNIFORM_TYPE_IDENTIFIER]) {
            [self debug:[NSString stringWithFormat:@"item provider = %@", itemProvider]];

            [itemProvider loadItemForTypeIdentifier:SHAREEXT_UNIFORM_TYPE_IDENTIFIER options:nil
                                  completionHandler: ^(id<NSSecureCoding> item, NSError *error) {
                [self addItemToArray:[(NSURL*)item absoluteString] withProvider:itemProvider];
                                  }];
        } else {
            [self dataFetched];
        }
    }
}

- (void) submit {
    [self setup];
    [self debug:@"[submit]"];

    if (@available(iOS 12, *)) {
        // iOS 12 (or newer) ObjC code
        [self handleShare];
    } else {
        // iOS 11 or older code
        [self handleShareForOlderOS];
    }
}

- (NSArray*) configurationItems {
    // To add configuration options via table cells at the bottom of the sheet, return an array of SLComposeSheetConfigurationItem here.
    return @[];
}

- (NSString*) backURLFromBundleID: (NSString*)bundleId {
    if (bundleId == nil) return nil;
    if ([bundleId isEqualToString:@"com.apple.DocumentsApp"]) return @"shareddocuments://";
    // App Store - com.apple.AppStore
    if ([bundleId isEqualToString:@"com.apple.AppStore"]) return @"itms-apps://";
    // Calculator - com.apple.calculator
    // Calendar - com.apple.mobilecal
    // Camera - com.apple.camera
    // Clock - com.apple.mobiletimer
    // Compass - com.apple.compass
    // Contacts - com.apple.MobileAddressBook
    // FaceTime - com.apple.facetime
    // Find Friends - com.apple.mobileme.fmf1
    // Find iPhone - com.apple.mobileme.fmip1
    // Game Center - com.apple.gamecenter
    // Health - com.apple.Health
    // iBooks - com.apple.iBooks
    // iTunes Store - com.apple.MobileStore
    // Mail - com.apple.mobilemail - message://
    if ([bundleId isEqualToString:@"com.apple.mobilemail"]) return @"message://";
    // Maps - com.apple.Maps - maps://
    if ([bundleId isEqualToString:@"com.apple.Maps"]) return @"maps://";
    // Messages - com.apple.MobileSMS
    // Music - com.apple.Music
    // News - com.apple.news - applenews://
    if ([bundleId isEqualToString:@"com.apple.news"]) return @"applenews://";
    // Notes - com.apple.mobilenotes - mobilenotes://
    if ([bundleId isEqualToString:@"com.apple.mobilenotes"]) return @"mobilenotes://";
    // Phone - com.apple.mobilephone
    // Photos - com.apple.mobileslideshow
    if ([bundleId isEqualToString:@"com.apple.mobileslideshow"]) return @"photos-redirect://";
    // Podcasts - com.apple.podcasts
    // Reminders - com.apple.reminders - x-apple-reminder://
    if ([bundleId isEqualToString:@"com.apple.reminders"]) return @"x-apple-reminder://";
    // Safari - com.apple.mobilesafari
    // Settings - com.apple.Preferences
    // Stocks - com.apple.stocks
    // Tips - com.apple.tips
    // Videos - com.apple.videos - videos://
    if ([bundleId isEqualToString:@"com.apple.videos"]) return @"videos://";
    // Voice Memos - com.apple.VoiceMemos - voicememos://
    if ([bundleId isEqualToString:@"com.apple.VoiceMemos"]) return @"voicememos://";
    // Wallet - com.apple.Passbook
    // Watch - com.apple.Bridge
    // Weather - com.apple.weather
    return @"";
}

// This is called at the point where the Post dialog is about to be shown.
// We use it to store the _hostBundleID
- (void) willMoveToParentViewController: (UIViewController*)parent {
    NSString *hostBundleID = [parent valueForKey:(@"_hostBundleID")];
    self.hostBundleID = hostBundleID;
    self.backURL = [self backURLFromBundleID:hostBundleID];
}

@end
