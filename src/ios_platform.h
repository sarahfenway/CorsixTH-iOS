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

#ifndef CORSIX_TH_IOS_PLATFORM_H_
#define CORSIX_TH_IOS_PLATFORM_H_

#include <string>

//! iOS-only services that need Apple's Foundation framework (ios_platform.mm).
namespace ios_platform {

//! Path of the Documents folder in the app's iCloud Drive container, or an
//! empty string when iCloud Drive can't be used (signed out of iCloud, iCloud
//! Drive turned off, or the app was built without the iCloud entitlement).
std::string icloud_documents_dir();

//! Asks iCloud to download every file under dir. Saves made on another device
//! may only exist as placeholders here until they are downloaded.
void request_downloads(const std::string& dir);

}  // namespace ios_platform

#endif  // CORSIX_TH_IOS_PLATFORM_H_
