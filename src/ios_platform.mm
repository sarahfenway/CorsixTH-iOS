/*
Copyright (c) 2026 CorsixTH iOS port contributors

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

// Compiled as Objective-C++ with ARC, on iOS only.

#include "ios_platform.h"

#import <Foundation/Foundation.h>

namespace ios_platform {

std::string icloud_documents_dir() {
  @autoreleasepool {
    NSFileManager* manager = [NSFileManager defaultManager];
    // nil when the user isn't signed in to iCloud or iCloud Drive is off.
    if (manager.ubiquityIdentityToken == nil) {
      return std::string();
    }
    // nil asks for the first container in the app's entitlements; this is
    // also nil if the app was built without the iCloud entitlement.
    NSURL* container = [manager URLForUbiquityContainerIdentifier:nil];
    if (container == nil) {
      return std::string();
    }
    // Files under Documents show up in iCloud Drive (Files app, Finder) in a
    // folder named after the app.
    NSURL* documents = [container URLByAppendingPathComponent:@"Documents"
                                                  isDirectory:YES];
    NSError* error = nil;
    if (![manager createDirectoryAtURL:documents
            withIntermediateDirectories:YES
                             attributes:nil
                                  error:&error]) {
      NSLog(@"CorsixTH: can't use iCloud Drive: %@", error);
      return std::string();
    }
    return std::string(documents.path.fileSystemRepresentation);
  }
}

void request_downloads(const std::string& dir) {
  @autoreleasepool {
    NSFileManager* manager = [NSFileManager defaultManager];
    NSURL* root = [NSURL fileURLWithPath:@(dir.c_str()) isDirectory:YES];
    NSDirectoryEnumerator<NSURL*>* entries =
        [manager enumeratorAtURL:root
            includingPropertiesForKeys:nil
                               options:0
                          errorHandler:nil];
    for (NSURL* url in entries) {
      NSString* name = url.lastPathComponent;
      NSURL* item = url;
      // Older iCloud versions show a not-yet-downloaded "name" as
      // ".name.icloud"; the download has to be requested for "name".
      if ([name hasPrefix:@"."] && [name hasSuffix:@".icloud"] &&
          name.length > 8) {
        NSString* real =
            [name substringWithRange:NSMakeRange(1, name.length - 8)];
        item = [[url URLByDeletingLastPathComponent]
            URLByAppendingPathComponent:real];
      }
      // Does nothing for files that are already downloaded.
      [manager startDownloadingUbiquitousItemAtURL:item error:nil];
    }
  }
}

}  // namespace ios_platform
