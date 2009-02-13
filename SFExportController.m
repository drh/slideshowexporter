//
//  SFExportController.m
//  SFExportController
//
//  Created by Apple; modified by Dave Hanson on 11/17/2008.
//  Copyright 2008 Google Inc. All rights reserved.
//
/*

File: SFExportController.m

Version: 1.0

Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple
Inc. ("Apple") in consideration of your agreement to the
following terms, and your use, installation, modification or
redistribution of this Apple software constitutes acceptance of these
terms.  If you do not agree with these terms, please do not use,
install, modify or redistribute this Apple software.

In consideration of your agreement to abide by the following terms, and
subject to these terms, Apple grants you a personal, non-exclusive
license, under Apple's copyrights in this original Apple software (the
"Apple Software"), to use, reproduce, modify and redistribute the Apple
Software, with or without modifications, in source and/or binary forms;
provided that if you redistribute the Apple Software in its entirety and
without modifications, you must retain this notice and the following
text and disclaimers in all such redistributions of the Apple Software.
Neither the name, trademarks, service marks or logos of Apple Inc.
may be used to endorse or promote products derived from the Apple
Software without specific prior written permission from Apple.  Except
as expressly stated in this notice, no other rights or licenses, express
or implied, are granted by Apple herein, including but not limited to
any patent rights that may be infringed by your derivative works or by
other works in which the Apple Software may be incorporated.

The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.

IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.

Copyright © 2007 Apple Inc. All Rights Reserved
*/

#import "SFExportController.h"
#import <QuickTime/QuickTime.h>
#import "external/gtm/GTMDefines.h"

static int const kFullSize = 99999;

// Private methods used in SFExportController.
@interface SFExportController (PrivateMethods)

- (BOOL)createDir:(NSString *)dir;
- (BOOL)writeImagesJs:(NSArray *)names toPath:(NSString *)dest;
- (BOOL)writeIndexHtml:(NSString *)dest;

@end

@implementation SFExportController

- (id)initWithExportImageObj:(id <ExportImageProtocol>)obj {
  if (self = [super init]) {
    exportMgr_ = obj;
    progress_.message = nil;
    progressLock_ = [[NSLock alloc] init];
  }
  return self;
}

- (void)dealloc {
  [exportDir_ release];
  [progressLock_ release];
  [progress_.message release];
  [super dealloc];
}

// public methods
- (void)awakeFromNib {
  [sizePopUp_ selectItemWithTag:1];
  [qualityPopUp_ selectItemWithTag:2];
  [metadataButton_ setState:NSOffState];
}

// getters/setters
- (NSString *)exportDir {
  return exportDir_;
}

- (void)setExportDir:(NSString *)dir {
  [exportDir_ autorelease];
  exportDir_ = [dir retain];
}

- (int)size {
  return size_;
}

- (void)setSize:(int)size {
  size_ = size;
}

- (int)quality {
  return quality_;
}

- (void)setQuality:(int)quality {
  quality_ = quality;
}

- (int)metadata {
  return metadata_;
}

- (void)setMetadata:(int)metadata {
  metadata_ = metadata;
}

// protocol implementation
- (NSView <ExportPluginBoxProtocol> *)settingsView {
  return settingsBox_;
}

- (NSView *)firstView {
  return firstView_;
}

- (void)viewWillBeActivated {
}

- (void)viewWillBeDeactivated {
}

- (NSString *)requiredFileType {
  return @"";
}

- (BOOL)wantsDestinationPrompt {
  return YES;
}

- (NSString *)getDestinationPath {
  return @"";
}

- (NSString *)defaultFileName {
  return @"";
}

- (NSString *)defaultDirectory {
  NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDesktopDirectory, NSUserDomainMask, YES);
  if ([paths count] < 1) {
    NSLog(@"Failed to get path to user's desktop");
    return @"~/Desktop/";
  }
  return [paths objectAtIndex:0];
}

- (BOOL)treatSingleSelectionDifferently {
  return NO;
}

- (BOOL)handlesMovieFiles {
  return NO;
}

- (BOOL)validateUserCreatedPath:(NSString *)path {
  return NO;
}

- (void)clickExport {
  [exportMgr_ clickExport];
}

- (void)startExport:(NSString *)path {
  [self setSize:[sizePopUp_ selectedTag]];
  [self setQuality:[qualityPopUp_ selectedTag]];
  [self setMetadata:[metadataButton_ state]];

  int count = [exportMgr_ imageCount];

  // check for conflicting file names
  NSFileManager *fileManager = [NSFileManager defaultManager];
  int i;
  for (i = 0; i < count; ++i) {
    NSString *fileName = [NSString stringWithFormat:@"images/%d.jpg", i + 1];
    NSString *fullPath = [path stringByAppendingPathComponent:fileName];
    if ([fileManager fileExistsAtPath:fullPath])
      break;
  }
  if (i != count) {
    if (NSRunCriticalAlertPanel(@"File exists",
        @"One or more images already exist in directory.",
        @"Replace", nil, @"Cancel") == NSAlertDefaultReturn)
      [exportMgr_ startExport];
  } else {
    [exportMgr_ startExport];
  }
}

- (void)performExport:(NSString *)path {
  int count = [exportMgr_ imageCount];
  BOOL succeeded = YES;
  cancelExport_ = NO;

  [self setExportDir:path];
  _GTMDevLog(@"performExport path: %@, count: %d", [self exportDir], count);

  // set export options
  ImageExportOptions imageOptions;
  bzero(&imageOptions, sizeof imageOptions);
  imageOptions.format = kQTFileTypeJPEG;
  switch ([self quality]) {
    case 0:  imageOptions.quality = EQualityLow;  break;
    case 1:  imageOptions.quality = EQualityMed;  break;
    case 2:  imageOptions.quality = EQualityHigh; break;
    case 3:  imageOptions.quality = EQualityMax;  break;
    default: imageOptions.quality = EQualityHigh; break;
  }
  imageOptions.rotation = 0.0;
  switch ([self size]) {
    case 0:
      imageOptions.width = 320;
      imageOptions.height = 320;
      break;
    case 1:
      imageOptions.width = 640;
      imageOptions.height = 640;
      break;
    case 2:
      imageOptions.width = 1280;
      imageOptions.height = 1280;
      break;
    case 3:
      imageOptions.width = kFullSize;
      imageOptions.height = kFullSize;
      break;
    default:
      imageOptions.width = 1280;
      imageOptions.height = 1280;
      break;
  }
  if ([self metadata] == NSOnState)
    imageOptions.metadata = EMBoth;
  else
    imageOptions.metadata = NO;

  // set thumbnail options so they load fast
  ImageExportOptions thumbnailOptions;
  thumbnailOptions.quality = EQualityLow;
  thumbnailOptions.format = kQTFileTypePNG;
  thumbnailOptions.width = 100;
  thumbnailOptions.height = 100;

  // do the export
  [self lockProgress];
  progress_.indeterminateProgress = NO;
  progress_.totalItems = count - 1;
  [progress_.message autorelease];
  progress_.message = @"Exporting";
  [self unlockProgress];

  NSString *dir = [self exportDir];

  // create the thumbnails and images directories
  NSString *imagesDir = [dir stringByAppendingPathComponent:@"images"];
  NSString *thumbnailsDir = [dir stringByAppendingPathComponent:@"thumbnails"];
  NSString *dest = imagesDir;
  succeeded = [self createDir:dest];
  if (succeeded) {
    dest = thumbnailsDir;
    succeeded = [self createDir:dest];
  }

  NSMutableArray *names;
  if (succeeded) {
    names = [NSMutableArray arrayWithCapacity:count];
    for (int i = 0; cancelExport_ == NO && succeeded == YES && i < count; ++i) {
      [self lockProgress];
      progress_.currentItem = i;
      [progress_.message autorelease];
      progress_.message = [[NSString stringWithFormat:@"Image %d of %d",
          i + 1, count] retain];
      [self unlockProgress];

      dest = [imagesDir stringByAppendingPathComponent:
          [NSString stringWithFormat:@"%d.jpg", i + 1]];
      succeeded = [exportMgr_ exportImageAtIndex:i dest:dest
          options:&imageOptions];
      if (succeeded) {
        dest = [thumbnailsDir stringByAppendingPathComponent:
            [NSString stringWithFormat:@"%d.png", i + 1]];
        succeeded = [exportMgr_ exportImageAtIndex:i dest:dest
            options:&thumbnailOptions];
      }
      [names addObject:[NSString stringWithFormat:@"%d", i + 1]];
    }
  }

  // copy index.html and write images.js
  if (succeeded) {
    dest = [dir stringByAppendingPathComponent:@"index.html"];
    succeeded = [self writeIndexHtml:dest];
  }
  if (succeeded) {
    dest = [dir stringByAppendingPathComponent:@"images.js"];
    succeeded = [self writeImagesJs:names toPath:dest];
  }

  [self lockProgress];
  [progress_.message autorelease];
  if (!succeeded) { // handle failure
    progress_.message = [[NSString stringWithFormat:@"Unable to create %@",
        dest] retain];
    [self cancelExport];
    progress_.shouldCancel = YES;
  } else { // handle success
    progress_.message = nil;
    progress_.shouldStop = YES;
  }
  [self unlockProgress];
}

- (ExportPluginProgress *)progress {
  return &progress_;
}

- (void)lockProgress {
  [progressLock_ lock];
}

- (void)unlockProgress {
  [progressLock_ unlock];
}

- (void)cancelExport {
  cancelExport_ = YES;
}

- (NSString *)name {
  return @"Slide Show Exporter";
}

// private methods
- (BOOL)createDir:(NSString *)dir {
  NSFileManager *mgr = [NSFileManager defaultManager];
  return [mgr createDirectoryAtPath:dir attributes:nil];
}

- (BOOL)writeImagesJs:(NSArray *)names toPath:(NSString *)dest {
  int count = [names count];
  NSMutableString *buffer = [NSMutableString stringWithCapacity:20*count];
  for (int i = 0; i < count; ++i) {
    [buffer appendFormat:@"pushimage('%@');\n", [names objectAtIndex:i]];
  }

  // ignore remove errors
  [[NSFileManager defaultManager] removeFileAtPath:dest handler:nil];
  NSError *error;
  BOOL succeeded = [buffer writeToFile:dest atomically:NO
      encoding:NSUTF8StringEncoding error:&error];
  if (succeeded) {
    _GTMDevLog(@"Wrote initialization to %@", dest);
  } else {
    NSLog(@"Failed to write initialization to %@", dest);
  }
  return succeeded;
}

- (BOOL)writeIndexHtml:(NSString *)dest {
  BOOL succeeded = NO;
  NSBundle *bundle = [NSBundle bundleForClass:[self class]];
  NSString *indexHtmlPath = [bundle pathForResource:@"index" ofType:@"html"];

  if (indexHtmlPath)  {
    NSFileManager *mgr = [NSFileManager defaultManager];
    // copy index.html to the top-level export directory; ignore remove errors
    [mgr removeFileAtPath:dest handler:nil];
    succeeded = [mgr copyPath:indexHtmlPath toPath:dest handler:nil];
    if (succeeded) {
      _GTMDevLog(@"Copied %@ to %@", indexHtmlPath, dest);
    } else {
      NSLog(@"Failed to copy %@ to %@", indexHtmlPath, dest);
    }
  } else {
    NSLog(@"Could not find index.html");
  }
  return succeeded;
}

@end
