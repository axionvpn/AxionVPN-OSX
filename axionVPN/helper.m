/*
 * Copyright 2005, 2006, 2007, 2008, 2009 Angelo Laub
 * Contributions by Jonathan K. Bullard Copyright 2010, 2011, 2012, 2013, 2014. All rights reserved.
 *
 *  This file is part of Tunnelblick.
 *
 *  Tunnelblick is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License version 2
 *  as published by the Free Software Foundation.
 *
 *  Tunnelblick is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program (see the file COPYING included with this
 *  distribution); if not, write to the Free Software Foundation, Inc.,
 *  59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 *  or see http://www.gnu.org/licenses/.
 */

#import "helper.h"

#import <mach/mach_time.h>
#import <sys/stat.h>
#import <sys/sysctl.h>
#import <sys/utsname.h>
#import <unistd.h>

#import "defines.h"
#import "sharedRoutines.h"

#import "AlertWindowController.h"
#import "AuthAgent.h"
#import "KeyChain.h"
#import "MenuController.h"
#import "NSApplication+LoginItem.h"
#import "NSFileManager+TB.h"
#import "TBUserDefaults.h"

// PRIVATE FUNCTIONS:
void           localizableStrings       (void);
BOOL           copyOrMoveCredentials    (NSString * fromDisplayName,
                                         NSString * toDisplayName,
                                         BOOL       moveNotCopy);

// The following external, global variables are used by functions in this file and must be declared and set elsewhere before the
// functions in this file are called:
extern NSMutableArray  * gConfigDirs;
extern NSString        * gPrivatePath;
extern NSString        * gDeployPath;
extern NSFileManager   * gFileMgr;
extern TBUserDefaults  * gTbDefaults;
extern NSThread        * gMainThread;
extern CFUserNotificationRef gUserNotification;

void appendLog(NSString * msg)
{
	NSLog(@"%@", msg);
}

NSNumber * tbNumberWithInteger (NSInteger number)
{
    if (  runningOnLeopardOrNewer()  ) {
        return [NSNumber numberWithInteger: number];
    }
    
    return [NSNumber numberWithInt: (unsigned int)number];
}

NSNumber * tbNumberWithUnsignedInteger (NSUInteger number)
{
    if (  runningOnLeopardOrNewer()  ) {
        return [NSNumber numberWithUnsignedInteger: number];
    }
    
    return [NSNumber numberWithUnsignedInt: (int)number];
}

NSUInteger tbUnsignedIntegerValue(NSNumber * number)
{
    if (  runningOnLeopardOrNewer()  ) {
        return [number unsignedIntegerValue];
    }
    
    return [number unsignedIntValue];
}
uint64_t nowAbsoluteNanoseconds (void)
{
    // The next three lines were adapted from http://shiftedbits.org/2008/10/01/mach_absolute_time-on-the-iphone/
    mach_timebase_info_data_t info;
    mach_timebase_info(&info);
    uint64_t nowNs = (unsigned long long)mach_absolute_time() * (unsigned long long)info.numer / (unsigned long long)info.denom;
    return nowNs;
}

BOOL runningABetaVersion (void) {
    NSString * version = [[[NSBundle mainBundle] infoDictionary] objectForKey: @"CFBundleShortVersionString"];
    return ([version rangeOfString: @"beta"].length != 0);
}

BOOL runningOnMainThread (void) {
    
    if (  runningOnLeopardOrNewer()  ) {
        return [NSThread isMainThread];
    }
    
    return (  gMainThread == [NSThread currentThread]  );
}

BOOL runningOnNewerThan(unsigned majorVersion, unsigned minorVersion)
{
    unsigned major, minor, bugFix;
    OSStatus status = getSystemVersion(&major, &minor, &bugFix);
    if (  status != 0) {
        NSLog(@"getSystemVersion() failed");
        [((MenuController *)[NSApp delegate]) terminateBecause: terminatingBecauseOfError];
        return FALSE;
    }
    
    return ( (major > majorVersion) || (minor > minorVersion) );
}

BOOL runningOnTigerOrNewer(void)
{
    return runningOnNewerThan(10, 3);
}

BOOL runningOnLeopardOrNewer(void)
{
    return runningOnNewerThan(10, 4);
}

BOOL runningOnSnowLeopardOrNewer(void)
{
    return runningOnNewerThan(10, 5);
}

BOOL runningOnSnowLeopardPointEightOrNewer(void) {
    
    unsigned major, minor, bugFix;
    OSStatus status = getSystemVersion(&major, &minor, &bugFix);
    if (  status != 0) {
        NSLog(@"getSystemVersion() failed");
        [((MenuController *)[NSApp delegate]) terminateBecause: terminatingBecauseOfError];
        return FALSE;
    }
    
    if (  major < 10  ) {
        return FALSE;
    }
    
    if (  (major > 10) || (minor > 6)  ) {
        return TRUE;
    }
    
    return (  (minor == 6) && (bugFix > 7)  );
}

BOOL runningOnLionOrNewer(void)
{
    return runningOnNewerThan(10, 6);
}

BOOL runningOnMountainLionOrNewer(void)
{
    return runningOnNewerThan(10, 7);
}

BOOL runningOnMavericksOrNewer(void)
{
    return runningOnNewerThan(10, 8);
}

BOOL runningOnYosemiteOrNewer(void)
{
    return runningOnNewerThan(10, 9);
}

BOOL runningOnIntel(void) {
    
    // Returns NO if it can be determined that this is a PowerPC, YES otherwise
    
	unsigned value = 0;
	unsigned long length = sizeof(value);
	
	int error = sysctlbyname("hw.cputype", &value, &length, NULL, 0);
	if (  error == 0 ) {
		switch(value) {
			case 7:
                return YES; // Intel
                break;
                
			case 18:
                return NO;  // PPC
                break;
                
			default:
                NSLog(@"Unknown CPU type %u; assuming Intel", value);
                return YES;
		}
	}
    
    NSLog(@"An error occured trying to detect CPU type with sysctlbyname; assuming Intel; error was %lu: %s", (long)errno, strerror(errno));
    return YES;
}

#if MAC_OS_X_VERSION_MIN_REQUIRED != MAC_OS_X_VERSION_10_4
BOOL runningOn64BitKernel(void) {
    
    // Returns NO if it can be determined that this is a 32-bit kernel, YES otherwise
    
    struct utsname name;
    
    int error = uname(&name);
    
	if (  error == 0 ) {
        NSString * version = [NSString stringWithUTF8String: name.version];
        if (  [version rangeOfString: @"i386"].length != 0  ) {
            return NO;
        }
        if (  [version rangeOfString: @"X86_64"].length == 0  ) {
            NSLog(@"Unable to determine  32- or 64-bit kernel with uname(), assuming 64-bit kernel; version was '%@'", version);
        }
	} else {
        NSLog(@"An error occured trying to determine 32- or 64-bit kernel with uname(), assuming 64-bit kernel; error was %lu: %s", (long)errno, strerror(errno));
    }
    
    return YES;
}
#endif //MACOSX_DEPLOYMENT_TARGET > MAC_OS_X_VERSION_10_4

BOOL displaysHaveDifferentSpaces(void) {
    
    if (   runningOnMavericksOrNewer()  ) {
        
        NSString * spacesPrefsPath = [NSHomeDirectory() stringByAppendingPathComponent: @"/Library/Preferences/com.apple.spaces.plist"];
        NSDictionary * dict = [NSDictionary dictionaryWithContentsOfFile: spacesPrefsPath];
        if (  dict  ) {
            id obj = [dict objectForKey: @"spans-displays"];
            if (  obj  ) {
                if (  [obj respondsToSelector: @selector(boolValue)]  ) {
                    return ! [obj boolValue];
                } else {
                    NSLog(@"The 'spans-displays' preference from %@ does not respond to boolValue", spacesPrefsPath);
                }
            }
        } else {
            NSLog(@"Unable to load dictionary from %@", spacesPrefsPath);
        }
        
        return YES; // Error, so assume displays do have different spaces
    }
    
    return NO;
}

BOOL mustPlaceIconInStandardPositionInStatusBar(void) {
    
    NSStatusBar *bar = [NSStatusBar systemStatusBar];
    if (  ! [bar respondsToSelector: @selector(_statusItemWithLength:withPriority:)]  ) {
        return YES;
    }
    if (  ! [bar respondsToSelector: @selector(_insertStatusItem:withPriority:)]  ) {
        return YES;
    }
    
    if (   runningOnMavericksOrNewer()
        && ([[NSScreen screens] count] != 1)
        && displaysHaveDifferentSpaces()  ) {
        return YES;
    }
    
    return NO;
}

NSString *condensedConfigFileContentsFromString(NSString * fullString) {
	
	// Returns a string from an OpenVPN configuration file with empty lines and comments removed
	
	NSArray * lines = [fullString componentsSeparatedByString: @"\n"];
	
	NSMutableString * outString = [[[NSMutableString alloc] initWithCapacity: [fullString length]] autorelease];
	NSString * line;
	NSEnumerator * e = [lines objectEnumerator];
	while (  (line = [e nextObject])  ) {
        line = [line stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if (  [line length] != 0  ) {
			NSString * firstChar = [line substringToIndex: 1];
			if (   ( ! [firstChar isEqualToString: @";"] )
				&& ( ! [firstChar isEqualToString: @"#"] )  ) {
				[outString appendFormat: @"%@\n", line];
			}
		}
	}
	
	return [NSString stringWithString: outString];
}

// Returns an escaped version of a string so it can be sent over the management interface
NSString * escaped(NSString *string)
{
	NSMutableString * stringOut = [[string mutableCopy] autorelease];
	[stringOut replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:NSLiteralSearch range:NSMakeRange(0, [stringOut length])];
	[stringOut replaceOccurrencesOfString:@"\"" withString:@"\\\"" options:NSLiteralSearch range:NSMakeRange(0, [stringOut length])];
	return stringOut;
}

// Returns the path of the configuration folder in which a specified configuration file is contained
// Returns nil if it is not in any configuration folder
NSString * firstPartOfPath(NSString * thePath)
{
    unsigned i;
    for (i=0; i < [gConfigDirs count]; i++) {
        if (  [thePath hasPrefix: [[gConfigDirs objectAtIndex: i] stringByAppendingString: @"/"]]  ) {
            return [[[gConfigDirs objectAtIndex: i] copy] autorelease];
        }
    }
    
    NSString *altPath = [L_AS_T_USERS stringByAppendingPathComponent: NSUserName()];
    if (  [thePath hasPrefix: [altPath stringByAppendingString:@ "/"]]  ) {
        return altPath;
    }
    
    NSLog(@"firstPartOfPath: Path %@ does not have a prefix that is in any gConfigDirs entry", thePath);
    return nil;
}

// The name of the configuration file, but prefixed by any folders it is contained in after /Deploy or /Configurations
//      = configPath less the Deploy or Configurations folder prefix (but including the extension)
// Used for constructing path to shadow copy of the configuration and as an argument to openvpnstart
NSString * lastPartOfPath(NSString * thePath)
{
    return [thePath substringFromIndex: [firstPartOfPath(thePath) length]+1];
}

// Returns the first component of a path
NSString * firstPathComponent(NSString * path)
{
    NSRange slash = [path rangeOfString: @"/"];
    if ( slash.location == 0 ) {
        slash = [[path substringFromIndex: 1] rangeOfString: @"/"];
    }
    if ( slash.location == NSNotFound) {
        slash.location = [path length];
    }
    return [path substringToIndex: slash.location];
}


NSString * displayNameFromPath (NSString * thePath) {
	
	// Returns the display name for a configuration, given a configuration file's path (either a .tblk or a .ovpn)
	
	NSString * last = lastPartOfPath(thePath);
	
	if (  [last hasSuffix: @".tblk"]  ) {							// IS a .tblk
		return [last substringToIndex: [last length] - 5];
	}
	
	if (  [last hasSuffix: @"/Contents/Resources/config.ovpn"]  ) {	// Is IN a .tblk
		return [[[[last stringByDeletingLastPathComponent]	// Remove config.ovpn
				  stringByDeletingLastPathComponent]		// Remove Resources
				 stringByDeletingLastPathComponent]			// Remove Contents
				stringByDeletingPathExtension];				// Remove .tblk
	}
	
	if (   [last hasSuffix: @".ovpn"]								// Is a non-tblk configuration file
		|| [last hasSuffix: @".conf"]  ) {
		return [last substringToIndex: [last length] - 5];
	}
	
	NSLog(@"displayNameFromPath: invalid path '%@'", thePath);
	return nil;
}

// Returns the path of the configuration file within a .tblk, or nil if there is no such configuration file
NSString * configPathFromTblkPath(NSString * path)
{
    NSString * cfgPath = [path stringByAppendingPathComponent:@"Contents/Resources/config.ovpn"];
    BOOL isDir;
    
    if (   [gFileMgr fileExistsAtPath: cfgPath isDirectory: &isDir]
        && (! isDir)  ) {
        return cfgPath;
    }
    
    return nil;
}

// Returns the path of the .tblk that a configuration file is enclosed within, or nil if the configuration file is not enclosed in a .tblk
NSString * tblkPathFromConfigPath(NSString * path)
{
    NSString * answer = path;
    while (   ! [[answer pathExtension] isEqualToString: @"tblk"]
           && [answer length] != 0
           && ! [answer isEqualToString: @"/"]  ) {
        answer = [answer stringByDeletingLastPathComponent];
    }
    
    if (  [[answer pathExtension] isEqualToString: @"tblk"]  ) {
        return answer;
    }
    
    return nil;
}

// Returns YES if file doesn't exist, or has the specified ownership and permissions
BOOL checkOwnerAndPermissions(NSString * fPath, uid_t uid, gid_t gid, mode_t permsShouldHave)
{
    if (  ! [gFileMgr fileExistsAtPath: fPath]  ) {
        return YES;
    }
    
    NSDictionary *fileAttributes = [gFileMgr tbFileAttributesAtPath:fPath traverseLink:YES];
    unsigned long perms = [fileAttributes filePosixPermissions];
    NSNumber *fileOwner = [fileAttributes fileOwnerAccountID];
    NSNumber *fileGroup = [fileAttributes fileGroupOwnerAccountID];
    
    if (   (perms == permsShouldHave)
        && [fileOwner isEqualToNumber:[NSNumber numberWithInt:(int) uid]]
        && [fileGroup isEqualToNumber:[NSNumber numberWithInt:(int) gid]]) {
        return YES;
    }
    
    NSLog(@"File %@ is owned by %@:%@ with permissions: %lo but must be owned by %ld:%ld with permissions %lo",
          fPath, fileOwner, fileGroup, perms, (long)uid, (long)gid, (long)permsShouldHave);
    return NO;
}

// Returns a string with the version # for Tunnelblick, e.g., "Tunnelbick 3.0b12 (build 157)"
NSString * tunnelblickVersion(NSBundle * bundle)
{
    NSString * infoVersion = [bundle objectForInfoDictionaryKey:@"CFBundleVersion"];
    NSString * infoShort   = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSString * infoBuild   = [bundle objectForInfoDictionaryKey:@"Build"];
    
    if (  [[infoVersion class] isSubclassOfClass: [NSString class]] && [infoVersion rangeOfString: @"3.0b"].location == NSNotFound  ) {
        // No "3.0b" in CFBundleVersion, so it is a build number, which means that the CFBundleShortVersionString has what we want
        return [NSString stringWithFormat: @"Tunnelblick %@", infoShort];
    }
    
    // We must construct the string from what we have in infoShort and infoBuild.
    //Strip "Tunnelblick " from the front of the string if it exists (it may not)
    NSString * appVersion = (  [infoShort hasPrefix: @"Tunnelblick "]
                             ? [infoShort substringFromIndex: [@"Tunnelblick " length]]
                             : infoShort);
    
    NSString * appVersionWithoutBuild;
    NSUInteger parenStart;
    if (  ( parenStart = ([appVersion rangeOfString: @" ("].location) ) == NSNotFound  ) {
        // No " (" in version, so it doesn't have a build # in it
        appVersionWithoutBuild   = appVersion;
    } else {
        // Remove the parenthesized build
        appVersionWithoutBuild   = [appVersion substringToIndex: parenStart];
    }
    
    NSMutableString * version = [NSMutableString stringWithCapacity: 30];
    [version appendString: NSLocalizedString(@"Tunnelblick", @"Window title")];
    if (  appVersionWithoutBuild  ) {
        [version appendFormat: @" %@", appVersionWithoutBuild];
    }
    if (  infoBuild  ) {
        [version appendFormat: @" (build %@)", infoBuild];
    }
    if (  ( ! appVersionWithoutBuild ) &&  ( ! infoBuild) ) {
        [version appendFormat: @" (no version information available)"];
    }
    return (version);
}

AlertWindowController * TBShowAlertWindow (NSString * title,
						NSString * msg) {
	
	// Displays an alert window and returns the window controller immediately, so it doesn't block the main thread.
	// Used for informational messages that do not return a choice or have any side effects.
    //
    // The window controller is returned so that it can be closed programmatically if the conditions that caused
    // the window to be opened change.
	
	AlertWindowController * awc = [[[AlertWindowController alloc] init] autorelease];
	[awc setHeadline: title];
	[awc setMessage:  msg];
	NSWindow * win = [awc window];
    [win center];
	[awc showWindow:  nil];
	[win makeKeyAndOrderFront: nil];
    [NSApp activateIgnoringOtherApps: YES];
	return awc;
}


// Takes the same arguments as, and is similar to, NSRunAlertPanel
// DOES NOT BEHAVE IDENTICALLY to NSRunAlertPanel:
//   * Stays on top of other windows
//   * Blocks the runloop
//   * Displays the Tunnelblick icon
//   * If title is nil, "Alert" will be used.
//   * If defaultButtonLabel is nil, "OK" will be used.

int TBRunAlertPanel(NSString * title, NSString * msg, NSString * defaultButtonLabel, NSString * alternateButtonLabel, NSString * otherButtonLabel)
{
    return TBRunAlertPanelExtended(title, msg, defaultButtonLabel, alternateButtonLabel, otherButtonLabel, nil, nil, nil, NSAlertDefaultReturn);
}

// Like TBRunAlertPanel but allows a "do not show again" preference key and checkbox, or a checkbox for some other function.
// If the preference is set, the panel is not shown and "notShownReturnValue" is returned.
// If the preference can be changed by the user, and the checkboxResult pointer is not nil, the panel will include a checkbox with the specified label.
// If the preference can be changed by the user, the preference is set if the user checks the box and the button that is clicked corresponds to the notShownReturnValue.
// If the checkboxResult pointer is not nil, the initial value of the checkbox will be set from it, and the value of the checkbox is returned to it.
int TBRunAlertPanelExtended(NSString * title,
                            NSString * msg,
                            NSString * defaultButtonLabel,
                            NSString * alternateButtonLabel,
                            NSString * otherButtonLabel,
                            NSString * doNotShowAgainPreferenceKey,
                            NSString * checkboxLabel,
                            BOOL     * checkboxResult,
							int		   notShownReturnValue)
{
    if (  doNotShowAgainPreferenceKey && [gTbDefaults boolForKey: doNotShowAgainPreferenceKey]  ) {
        return notShownReturnValue;
    }
    
    NSMutableDictionary * dict = [[[NSMutableDictionary alloc] initWithObjectsAndKeys:
                                   msg,  kCFUserNotificationAlertMessageKey,
                                   [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"tunnelblick" ofType: @"icns"]],
                                   kCFUserNotificationIconURLKey,
                                   nil] autorelease];
    if ( title ) {
        [dict setObject: title
                 forKey: (NSString *)kCFUserNotificationAlertHeaderKey];
    } else {
        [dict setObject: NSLocalizedString(@"Alert", @"Window title")
                 forKey: (NSString *)kCFUserNotificationAlertHeaderKey];
    }
    
    if ( defaultButtonLabel ) {
        [dict setObject: defaultButtonLabel
                 forKey: (NSString *)kCFUserNotificationDefaultButtonTitleKey];
    } else {
        [dict setObject: NSLocalizedString(@"OK", @"Button")
                 forKey: (NSString *)kCFUserNotificationDefaultButtonTitleKey];
    }
    
    if ( alternateButtonLabel ) {
        [dict setObject: alternateButtonLabel
                 forKey: (NSString *)kCFUserNotificationAlternateButtonTitleKey];
    }
    
    if ( otherButtonLabel ) {
        [dict setObject: otherButtonLabel
                 forKey: (NSString *)kCFUserNotificationOtherButtonTitleKey];
    }
    
    if (  checkboxLabel  ) {
        if (   checkboxResult
            || ( doNotShowAgainPreferenceKey && [gTbDefaults canChangeValueForKey: doNotShowAgainPreferenceKey] )
            ) {
            [dict setObject: checkboxLabel forKey:(NSString *)kCFUserNotificationCheckBoxTitlesKey];
        }
    }
    
    SInt32 error = 0;
    CFOptionFlags response = 0;

    CFOptionFlags checkboxChecked = 0;
    if (  checkboxResult  ) {
        if (  * checkboxResult  ) {
            checkboxChecked = CFUserNotificationCheckBoxChecked(0);
        }
    }
    
    [NSApp activateIgnoringOtherApps:YES];
	if (  gUserNotification  ) {
        NSLog(@"TBRunAlertExtended called but a panel already exists!");
        CFRelease(gUserNotification);
        gUserNotification = NULL;
    }
    
    gUserNotification = CFUserNotificationCreate(NULL, 0.0, checkboxChecked, &error, (CFDictionaryRef) dict);
    
    if (   error
        || (gUserNotification == NULL)
        ) {
        
		NSLog(@"CFUserNotificationCreate() returned with error = %ld; notification = 0x%lX, so TBRunAlertExtended is terminating Tunnelblick after attempting to display an error window using CFUserNotificationDisplayNotice",
              (long) error, (long) gUserNotification);
        if (  gUserNotification != NULL  ) {
            CFRelease(gUserNotification);
            gUserNotification = NULL;
        }
        
        // Try showing a regular window (but it will disappear when Tunnelblick terminates)
        TBShowAlertWindow(NSLocalizedString(@"Alert", @"Window title"),
                          [NSString stringWithFormat:
                           NSLocalizedString(@"Tunnelblick could not display a window.\n\n"
                                             @"CFUserNotificationCreate() returned with error = %ld; notification = 0x%lX", @"Window text"),
                           (long) error, (unsigned long) gUserNotification]);
        
        // Try showing a modal alert window
        SInt32 status = CFUserNotificationDisplayNotice(60.0,
                                                        kCFUserNotificationStopAlertLevel,
                                                        NULL,
                                                        NULL,
                                                        NULL,
                                                        (CFStringRef) NSLocalizedString(@"Alert", @"Window title"),
                                                        (CFStringRef) [NSString stringWithFormat:
                                                                       NSLocalizedString(@"Tunnelblick could not display a window.\n\n"
                                                                                         @"CFUserNotificationCreate() returned with error = %ld; notification = 0x%lX", @"Window text"),
                                                                       (long) error, (long) gUserNotification],
                                                        NULL);
        NSLog(@"CFUserNotificationDisplayNotice() returned %ld", (long) status);
        if (  gUserNotification != NULL  ) {
            CFRelease(gUserNotification);
            gUserNotification = NULL;
        }
        [((MenuController *)[NSApp delegate]) terminateBecause: terminatingBecauseOfError];
        return NSAlertErrorReturn; // Make the Xcode code analyzer happy
    }
    
	SInt32 responseReturnCode = CFUserNotificationReceiveResponse(gUserNotification, 0.0, &response);
    
    if (  gUserNotification != NULL  ) {
        CFRelease(gUserNotification);
        gUserNotification = NULL;
    }
    
    if (  responseReturnCode  ) {
        NSLog(@"CFUserNotificationReceiveResponse() returned %ld with response = %ld, so TBRunAlertExtended is returning NSAlertErrorReturn",
              (long) responseReturnCode, (long) response);
        return NSAlertErrorReturn;
    }
    
    if (  checkboxResult  ) {
        if (  response & CFUserNotificationCheckBoxChecked(0)  ) {
            * checkboxResult = TRUE;
        } else {
            * checkboxResult = FALSE;
        }
    } 

    switch (response & 0x3) {
        case kCFUserNotificationDefaultResponse:
			if (  notShownReturnValue == NSAlertDefaultReturn  ) {
				if (  checkboxLabel  ) {
					if (   doNotShowAgainPreferenceKey
						&& [gTbDefaults canChangeValueForKey: doNotShowAgainPreferenceKey]
						&& ( response & CFUserNotificationCheckBoxChecked(0) )  ) {
						[gTbDefaults setBool: TRUE forKey: doNotShowAgainPreferenceKey];
					}
				}
			}
				
            return NSAlertDefaultReturn;
            
        case kCFUserNotificationAlternateResponse:
			if (  notShownReturnValue == NSAlertAlternateReturn  ) {
				if (  checkboxLabel  ) {
					if (   doNotShowAgainPreferenceKey
						&& [gTbDefaults canChangeValueForKey: doNotShowAgainPreferenceKey]
						&& ( response & CFUserNotificationCheckBoxChecked(0) )  ) {
						[gTbDefaults setBool: TRUE forKey: doNotShowAgainPreferenceKey];
					}
				}
			}
			
            return NSAlertAlternateReturn;
            
        case kCFUserNotificationOtherResponse:
			if (  notShownReturnValue == NSAlertOtherReturn  ) {
				if (  checkboxLabel  ) {
					if (   doNotShowAgainPreferenceKey
						&& [gTbDefaults canChangeValueForKey: doNotShowAgainPreferenceKey]
						&& ( response & CFUserNotificationCheckBoxChecked(0) )  ) {
						[gTbDefaults setBool: TRUE forKey: doNotShowAgainPreferenceKey];
					}
				}
			}
			
            return NSAlertOtherReturn;
            
        default:
            NSLog(@"CFUserNotificationReceiveResponse() returned a response but it wasn't the default, alternate, or other response, so TBRunAlertExtended() is returning NSAlertErrorReturn");
            return NSAlertErrorReturn;
    }
}

BOOL isUserAnAdmin(void)
{
    // Run "id -Gn" to get a list of names of the groups the user is a member of
	NSString * stdoutString = nil;
	NSArray  * arguments = [NSArray arrayWithObjects: @"-Gn", nil];
	OSStatus status = runTool(TOOL_PATH_FOR_ID, arguments, &stdoutString, nil);
	if (  status != 0  ) {
		NSLog(@"Assuming user is not an administrator because '%@ -Gn' returned status %ld", TOOL_PATH_FOR_ID, (long)status);
		return NO;
	}
	
    // If the "admin" group appears in the output, the user is a member of the "admin" group, so they are an admin.
    // Group names don't include spaces and are separated by spaces, so this is easy. We just have to
    // handle admin being at the start or end of the output by pre- and post-fixing a space.
    
    NSString * groupNames = [NSString stringWithFormat:@" %@ ", [stdoutString stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]]];
    NSRange rng = [groupNames rangeOfString:@" admin "];
    return (rng.location != NSNotFound);
}

NSString * newTemporaryDirectoryPath(void)
{
    //**********************************************************************************************
    // Start of code for creating a temporary directory from http://cocoawithlove.com/2009/07/temporary-files-and-folders-in-cocoa.html
    // Modified to check for malloc returning NULL, use strlcpy, use gFileMgr, and use more readable length for stringWithFileSystemRepresentation
    
    NSString   * tempDirectoryTemplate = [NSTemporaryDirectory() stringByAppendingPathComponent: @"Tunnelblick-XXXXXX"];
    const char * tempDirectoryTemplateCString = [tempDirectoryTemplate fileSystemRepresentation];
    
    size_t bufferLength = strlen(tempDirectoryTemplateCString) + 1;
    char * tempDirectoryNameCString = (char *) malloc( bufferLength );
    if (  ! tempDirectoryNameCString  ) {
        NSLog(@"Unable to allocate memory for a temporary directory name");
        [((MenuController *)[NSApp delegate]) terminateBecause: terminatingBecauseOfError];
        return nil;
    }
    
    strlcpy(tempDirectoryNameCString, tempDirectoryTemplateCString, bufferLength);
    
    char * dirPath = mkdtemp(tempDirectoryNameCString);
    if (  ! dirPath  ) {
        NSLog(@"Unable to create a temporary directory");
        [((MenuController *)[NSApp delegate]) terminateBecause: terminatingBecauseOfError];
    }
    
    NSString *tempFolder = [gFileMgr stringWithFileSystemRepresentation: tempDirectoryNameCString
                                                                 length: strlen(tempDirectoryNameCString)];
	// Change from /var to /private/var to avoid using a symlink
	if (  [tempFolder hasPrefix: @"/var/"]  ) {
		NSDictionary * fileAttributes = [gFileMgr tbFileAttributesAtPath: @"/var" traverseLink: NO];
		if (  [[fileAttributes objectForKey: NSFileType] isEqualToString: NSFileTypeSymbolicLink]  ) {
			if ( [[gFileMgr tbPathContentOfSymbolicLinkAtPath: @"/var"] isEqualToString: @"private/var"]  ) {
					NSString * afterVar = [tempFolder substringFromIndex: 5];
					tempFolder = [@"/private/var" stringByAppendingPathComponent:afterVar];
			} else {
				NSLog(@"Warning: /var is a symlink but not to /private/var so it is being left intact");
			}
		}
	}
    
	free(tempDirectoryNameCString);
    
    // End of code from http://cocoawithlove.com/2009/07/temporary-files-and-folders-in-cocoa.html
    //**********************************************************************************************
    
    return [tempFolder retain];
}


// Modified from http://developer.apple.com/library/mac/#documentation/Carbon/Conceptual/ProvidingUserAssitAppleHelp/using_ah_functions/using_ah_functions.html#//apple_ref/doc/uid/TP30000903-CH208-CIHFABIE
OSStatus MyGotoHelpPage (NSString * pagePath, NSString * anchorName)
{
    OSStatus err = noErr;
    
    if (  runningOnSnowLeopardOrNewer()  ) {
        
        CFBundleRef myApplicationBundle = NULL;
        CFStringRef myBookName = NULL;
        
        myApplicationBundle = CFBundleGetMainBundle();
        if (myApplicationBundle == NULL) {
            err = fnfErr;
            goto bail;
        }
        
        myBookName = CFBundleGetValueForInfoDictionaryKey(
                                                          myApplicationBundle,
                                                          CFSTR("CFBundleHelpBookName"));
        if (myBookName == NULL) {
            err = fnfErr;
            goto bail;
        }
        
        if (CFGetTypeID(myBookName) != CFStringGetTypeID()) {
            err = paramErr;
            goto bail;
        }
        
        err = AHGotoPage (myBookName, (CFStringRef) pagePath, (CFStringRef) anchorName);// 5
    } else {
        NSString * fullPath = [[NSBundle mainBundle] pathForResource: pagePath ofType: nil inDirectory: @"help"];
        if (  fullPath  ) {
            err = (  [[NSWorkspace sharedWorkspace] openFile: fullPath]
                   ? 0
                   : fnfErr);
        } else {
            NSLog(@"Unable to locate %@ in 'help' resource folder", pagePath);
            err = fnfErr;
        }
    }
    
bail:
	if ( err != noErr  ) { 
		NSLog(@"Error %ld in MyGotoHelpPage()", (long) err);
	}
	
    return err;
}

NSString * TBGetString(NSString * msg, NSString * nameToPrefill)
{
    NSMutableDictionary* panelDict = [[NSMutableDictionary alloc] initWithCapacity:6];
    [panelDict setObject:NSLocalizedString(@"Name Required", @"Window title") forKey:(NSString *)kCFUserNotificationAlertHeaderKey];
    [panelDict setObject:msg                                                  forKey:(NSString *)kCFUserNotificationAlertMessageKey];
    [panelDict setObject:@""                                                  forKey:(NSString *)kCFUserNotificationTextFieldTitlesKey];
    [panelDict setObject:nameToPrefill                                        forKey:(NSString *)kCFUserNotificationTextFieldValuesKey];
    [panelDict setObject:NSLocalizedString(@"OK", @"Button")                  forKey:(NSString *)kCFUserNotificationDefaultButtonTitleKey];
    [panelDict setObject:NSLocalizedString(@"Cancel", @"Button")              forKey:(NSString *)kCFUserNotificationAlternateButtonTitleKey];
    [panelDict setObject:[NSURL fileURLWithPath:[[NSBundle mainBundle]
                                                 pathForResource:@"tunnelblick"
                                                 ofType: @"icns"]]            forKey:(NSString *)kCFUserNotificationIconURLKey];
    SInt32 error;
    CFUserNotificationRef notification;
    CFOptionFlags response;
    
    // Get a name from the user
    notification = CFUserNotificationCreate(NULL, 30.0, 0, &error, (CFDictionaryRef)panelDict);
    [panelDict release];
    
    if((error) || (CFUserNotificationReceiveResponse(notification, 0.0, &response))) {
        CFRelease(notification);    // Couldn't receive a response
        NSLog(@"Could not get a string from the user.\n\nAn unknown error occured.");
        return nil;
    }
    
    if((response & 0x3) != kCFUserNotificationDefaultResponse) {
        CFRelease(notification);    // User clicked "Cancel"
        return nil;
    }
    
    // Get the new name from the textfield
    NSString * returnString = [(NSString*)CFUserNotificationGetResponseValue(notification, kCFUserNotificationTextFieldValuesKey, 0)
                               stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    CFRelease(notification);
    return returnString;
}


// Call with a message to display and the path of a configuration that will be renamed or installed.
// Returns with nil if cancelled, otherwise the display name of a configuration that sourcePath can be renamed to or installed to
NSString * TBGetDisplayName(NSString * msg,
                            NSString * sourcePath)
{
    NSString * nameToPrefill = [[sourcePath lastPathComponent] stringByDeletingPathExtension];
    NSString * newName = TBGetString(msg, nameToPrefill);
    while (  newName  ) {
        if (  invalidConfigurationName(newName, PROHIBITED_DISPLAY_NAME_CHARACTERS_INCLUDING_SLASH_CSTRING)  ) {
            newName = TBGetString([NSString stringWithFormat:
								   NSLocalizedString(@"Names may not include any of the following characters: %s\n\n%@", @"Window text"),
								   PROHIBITED_DISPLAY_NAME_CHARACTERS_INCLUDING_SLASH_CSTRING,
								   msg],
								  nameToPrefill);
        } else if (  [newName length] == 0  ) {
            newName = TBGetString([NSLocalizedString(@"Please enter a name and click \"OK\" or click \"Cancel\".\n\n", @"Window text") stringByAppendingString: msg], nameToPrefill);
        } else {
            NSString * targetPath = [[[sourcePath stringByDeletingLastPathComponent] stringByAppendingPathComponent: newName] stringByAppendingPathExtension: @"conf"]; // (Don't use the .conf, but may need it for lastPartOfPath)
            NSString * dispNm = [lastPartOfPath(targetPath) stringByDeletingPathExtension];
            if (  nil == [[((MenuController *)[NSApp delegate]) myConfigDictionary] objectForKey: dispNm]  ) {
                break;
            }
            newName = TBGetString([NSLocalizedString(@"That name is being used.\n\n", @"Window text") stringByAppendingString: msg], nameToPrefill);
        }
    }
    
    return newName;
}

NSString * credentialsGroupFromDisplayName (NSString * displayName)
{
	NSString * allGroup = [gTbDefaults stringForKey: @"namedCredentialsThatAllConfigurationsUse"];
	if (  [allGroup length] != 0  ) {
		return allGroup;
	}
	
	NSString * prefKey = [displayName stringByAppendingString: @"-credentialsGroup"];
	NSString * group = [gTbDefaults stringForKey: prefKey];
	if (  [group length] == 0  ) {
		return nil;
	}
	
	return group;
}	

BOOL copyCredentials(NSString * fromDisplayName, NSString * toDisplayName)
{
    return copyOrMoveCredentials(fromDisplayName, toDisplayName, FALSE);
}

BOOL moveCredentials(NSString * fromDisplayName, NSString * toDisplayName)
{
    return copyOrMoveCredentials(fromDisplayName, toDisplayName, TRUE);
}

BOOL copyOrMoveCredentials(NSString * fromDisplayName, NSString * toDisplayName, BOOL moveNotCopy)
{
	NSString * group = credentialsGroupFromDisplayName(fromDisplayName);
	if (  group  ) {
		return YES;
	}		
		
    NSString * myPassphrase = nil;
    NSString * myUsername = nil;
    NSString * myPassword = nil;
    
    NSString * fromPassphraseKey          = [fromDisplayName stringByAppendingString: @"%@-keychainHasPrivateKey"];
    NSString * fromUsernameKey            = [fromDisplayName stringByAppendingString: @"%@-keychainHasUsername"];
    NSString * fromUsernameAndPasswordKey = [fromDisplayName stringByAppendingString: @"%@-keychainHasUsernameAndPassword"];
    
    BOOL haveFromPassphrase          = [gTbDefaults boolForKey: fromPassphraseKey] && [gTbDefaults canChangeValueForKey: fromPassphraseKey];
    BOOL haveFromUsername            = [gTbDefaults boolForKey: fromPassphraseKey] && [gTbDefaults canChangeValueForKey: fromUsernameKey];
    BOOL haveFromUsernameAndPassword = [gTbDefaults boolForKey: fromPassphraseKey] && [gTbDefaults canChangeValueForKey: fromUsernameAndPasswordKey];
    
    if (   haveFromPassphrase
        || haveFromUsername
        || haveFromUsernameAndPassword  ) {
        
        AuthAgent * myAuthAgent = [[[AuthAgent alloc] initWithConfigName: fromDisplayName credentialsGroup: nil] autorelease];
        
        if (  haveFromPassphrase  ) {
            [myAuthAgent setAuthMode: @"privateKey"];
            [myAuthAgent performAuthentication];
            myPassphrase = [myAuthAgent passphrase];
            if (  moveNotCopy) {
                [myAuthAgent deleteCredentialsFromKeychainIncludingUsername: YES];
            }
        }
        
        if (  haveFromUsernameAndPassword  ) {
            [myAuthAgent setAuthMode: @"password"];
            [myAuthAgent performAuthentication];
            myUsername = [myAuthAgent username];
            myPassword = [myAuthAgent password];
            if (  moveNotCopy) {
                [myAuthAgent deleteCredentialsFromKeychainIncludingUsername: YES];
            }
        } else  if (  haveFromUsername  ) {
            [myAuthAgent setAuthMode: @"password"];
            [myAuthAgent performAuthentication];
            myUsername = [myAuthAgent username];
            if (  moveNotCopy) {
                [myAuthAgent deleteCredentialsFromKeychainIncludingUsername: YES];
            }
        }
        
        if (  myPassphrase  ) {
            KeyChain * passphraseKeychain = [[KeyChain alloc] initWithService:[@"Tunnelblick-Auth-" stringByAppendingString: toDisplayName] withAccountName: @"privateKey" ];
            [passphraseKeychain deletePassword];
            if (  [passphraseKeychain setPassword: myPassphrase] != 0  ) {
                NSLog(@"Could not store passphrase in Keychain");
            }
            [passphraseKeychain release];
        }
        
        if (  myUsername  ) {
            KeyChain * usernameKeychain   = [[KeyChain alloc] initWithService:[@"Tunnelblick-Auth-" stringByAppendingString: toDisplayName] withAccountName: @"username"   ];
            [usernameKeychain deletePassword];
            if (  [usernameKeychain setPassword: myUsername] != 0  ) {
                NSLog(@"Could not store username in Keychain");
            }
            [usernameKeychain   release];
        }
        
        if (  myPassword  ) {
            KeyChain * passwordKeychain   = [[KeyChain alloc] initWithService:[@"Tunnelblick-Auth-" stringByAppendingString: toDisplayName] withAccountName: @"password"   ];
            [passwordKeychain deletePassword];
            if (  [passwordKeychain setPassword: myPassword] != 0  ) {
                NSLog(@"Could not store password in Keychain");
            }
            [passwordKeychain   release];
        }
    }
    
    return TRUE;
}

NSMutableString * encodeSlashesAndPeriods(NSString * s)
{
    // Encode slashes and periods in the displayName so the result can act as a single component in a file name
    NSMutableString * result = [[s mutableCopy] autorelease];
    [result replaceOccurrencesOfString: @"-" withString: @"--" options: 0 range: NSMakeRange(0, [result length])];
    [result replaceOccurrencesOfString: @"." withString: @"-D" options: 0 range: NSMakeRange(0, [result length])];
    [result replaceOccurrencesOfString: @"/" withString: @"-S" options: 0 range: NSMakeRange(0, [result length])];
    return result;
}

NSString * copyrightNotice()
{
	[NSDateFormatter setDefaultFormatterBehavior: NSDateFormatterBehavior10_4];
    NSDateFormatter * dateFormat = [[[NSDateFormatter alloc] init] autorelease];
    [dateFormat setDateFormat:@"YYYY"];
    NSString * year = [dateFormat stringFromDate: [NSDate date]];
    return [NSString stringWithFormat:
            NSLocalizedString(@"Copyright © 2004-%@ Angelo Laub and others.", @"Window text"),
            year];
}

NSString * stringForLog(NSString * outputString, NSString * header)
{
    outputString = [outputString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (  [outputString length] == 0  ) {
		return @"";
	}
	outputString = [header stringByAppendingString: outputString];
    NSMutableString * tempMutableString = [[outputString mutableCopy] autorelease];
    [tempMutableString replaceOccurrencesOfString: @"\n" withString: @"\n     " options: 0 range: NSMakeRange(0, [tempMutableString length])];
	return [NSString stringWithFormat: @"%@\n", tempMutableString];
}

NSString * configLocCodeStringForPath(NSString * configPath) {
    
    unsigned code;
    
    if (  [configPath hasPrefix: [gPrivatePath  stringByAppendingString: @"/"]]  ) {
        code = CFG_LOC_PRIVATE;
        
    } else if (  [configPath hasPrefix: [gDeployPath   stringByAppendingString: @"/"]]  ) {
        code = CFG_LOC_DEPLOY;
    
    } else if (  [configPath hasPrefix: [L_AS_T_SHARED stringByAppendingString: @"/"]]  ) {
        code = CFG_LOC_SHARED;
    
    } else if (  [configPath hasPrefix: [[L_AS_T_USERS stringByAppendingPathComponent: NSUserName()] stringByAppendingString: @"/"]]  ) {
        code = CFG_LOC_ALTERNATE;
    
    } else {
        NSLog(@"configLocCodeStringForPath: unknown path %@", configPath);
        [((MenuController *)[NSApp delegate]) terminateBecause: terminatingBecauseOfError];
        return [NSString stringWithFormat: @"%u", CFG_LOC_MAX + 1];
    }
    
    return [NSString stringWithFormat: @"%u", code];
}

OSStatus runOpenvpnstart(NSArray * arguments, NSString ** stdoutString, NSString ** stderrString)
{
	// Make sure no arguments include a \t or \0
	NSUInteger i;
	for (  i=0; i<[arguments count]; i++  ) {
        NSString * arg = [arguments objectAtIndex: i];
		if (   ([arg rangeOfString: @"\t"].length != 0)
            || ([arg rangeOfString: @"\0"].length != 0)  ) {
			NSLog(@"runOpenvpnstart: Argument %lu contains one or more HTAB (ASCII 0x09) or NULL (ASCII (0x00) characters. They are not allowed in arguments. Arguments = %@", (unsigned long)i, arguments);
			return -1;
		}
	}
    
    OSStatus status = -1;
	NSString * myStdoutString = nil;
	NSString * myStderrString = nil;
    
    if (  runningOnLeopardOrNewer()  ) {
        NSString * command = [[arguments componentsJoinedByString: @"\t"] stringByAppendingString: @"\n"];
        status = runTunnelblickd(command, &myStdoutString, &myStderrString);
    } else {
        NSString * tunnelblickHelperPath = [[NSBundle mainBundle] pathForResource: @"tunnelblick-helper" ofType: nil];
        unsigned long perms = [[gFileMgr tbFileAttributesAtPath: tunnelblickHelperPath traverseLink: NO] filePosixPermissions];
        if (  (perms & S_ISUID) == 0  ) {
            NSLog(@"runOpenvpnstart: This program has not been secured. Launch Tunnelblick to secure this program.");
            return -1;
        }
        status = runTool(tunnelblickHelperPath, arguments, &myStdoutString, &myStderrString);
    }
    
    NSString * subcommand = ([arguments count] > 0
                             ? [arguments objectAtIndex: 0]
                             : @"(no subcommand!)");
    
    NSMutableString * logMsg = [NSMutableString stringWithCapacity: 100 + [myStdoutString length] + [myStderrString length]];
    
    if (  stdoutString  ) {
        *stdoutString = myStdoutString;
    } else {
        if (  [myStdoutString length] != 0  ) {
            [logMsg appendFormat: @"tunnelblickd stdout:\n'%@'\n", myStdoutString];
        }
    }
    
    if (  stderrString  ) {
        *stderrString = myStderrString;
    } else {
        if (  [myStderrString length] != 0  ) {
            [logMsg appendFormat: @"tunnelblickd stderr:\n'%@'\n", myStderrString];
        }
    }
    
    if (  status != EXIT_SUCCESS ) {
        NSString * header = [NSString stringWithFormat: @"tunnelblickd status from %@: %ld\n", subcommand, (long) status];
        [logMsg insertString: header atIndex: 0];
        NSLog(@"%@", logMsg);
    }
	
    return status;
}

BOOL tunnelblickTestPrivateOnlyHasTblks(void)
{
    NSString * privatePath = [[[[NSHomeDirectory()
                                 stringByAppendingPathComponent: @"Library"]
                                stringByAppendingPathComponent: @"Application Support"]
                               stringByAppendingPathComponent: @"Tunnelblick"]
                              stringByAppendingPathComponent: @"Configurations"];
    NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: privatePath];
    NSString * file;
    while (  (file = [dirEnum nextObject])  )
	{
        if (  [[file pathExtension] isEqualToString: @"tblk"]  )
		{
            [dirEnum skipDescendents];
        } else {
            if (   [[file pathExtension] isEqualToString: @"ovpn"]
                || [[file pathExtension] isEqualToString: @"conf"]  )
			{
                return NO;
            }
        }
    }
    
    return YES;
}

BOOL tunnelblickTestAppInApplications(void)
{
    NSString * appContainer = [[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent];
    return [appContainer isEqualToString: @"/Applications"];
}

BOOL tunnelblickTestDeployed(void)
{
    // Returns TRUE if Deploy folder exists and contains anything
    
 	NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: gDeployPath];
    NSString * file;
    BOOL haveSomethingInDeployFolder = FALSE;
    while (  (file = [dirEnum nextObject])  )
	{
        if (  ! [file hasPrefix: @"."]  )		// Ignore .DS_Store, .svn, etc.
		{
            haveSomethingInDeployFolder = TRUE;
            break;
        }
    }
    
    return haveSomethingInDeployFolder;
}

BOOL tunnelblickTestHasDeployBackups(void)
{
    // Returns TRUE if Deploy backup folder exists
    
    NSString * deployBackupsPath = @"/Library/Application Support/Tunnelblick/Backup";
	BOOL isDir;
	if (   [gFileMgr fileExistsAtPath: deployBackupsPath isDirectory: &isDir]
		&& isDir  ) {
		return YES;
	}
	
	return NO;
}

// This method translates and returns non-literal OpenVPN message.
// It is used to consolidate the use of NS LocalizedString (non-literal-string...) in one place to minimize warnings from genstrings.
//                                        ^ space inserted to keep genstrings from finding this
NSString * localizeNonLiteral(NSString * msg, NSString * type)
{
	(void) type;
	
    return NSLocalizedString(msg, type);
}

// This method is never invoked. It is a place to put strings which are used in the DMG or the .nib or come from OpenVPN
// They are here so that automated tools that deal with strings (such as the "getstrings" command) will include them.
void localizableStrings(void)
{
	// These strings come from "thank you" emails
    NSLocalizedString(@"Thanks for your Tunnelblick donation", @"Window text");
    NSLocalizedString(@"Thank you very much for your donation to the TunnelblickProject.", @"Window text");
	
	
    // This string comes from the "Other Sources/dmgFiles/background.rtf" file, used to generate an image for the DMG
    NSLocalizedString(@"Double-click to begin", @"Text on disk image");
    
    // These strings come from OpenVPN and indicate the status of a connection
    NSLocalizedString(@"ADD_ROUTES",    @"Connection status");
    NSLocalizedString(@"ASSIGN_IP",     @"Connection status");
    NSLocalizedString(@"AUTH",          @"Connection status");
    NSLocalizedString(@"CONNECTED",     @"Connection status");
    NSLocalizedString(@"CONNECTING",    @"Connection status");
    NSLocalizedString(@"EXITING",       @"Connection status");
    NSLocalizedString(@"GET_CONFIG",    @"Connection status");
    NSLocalizedString(@"RECONNECTING",  @"Connection status");
    NSLocalizedString(@"RESOLVE",       @"Connection status");
    NSLocalizedString(@"SLEEP",         @"Connection status");
    NSLocalizedString(@"TCP_CONNECT",   @"Connection status");
    NSLocalizedString(@"UDP_CONNECT",   @"Connection status");
    NSLocalizedString(@"WAIT",          @"Connection status");
	
	// These strings also indicate the status of a connection, but they are set by Tunnelblick itself, not OpenVPN
	NSLocalizedString(@"PASSWORD_WAIT",    @"Connection status");
	NSLocalizedString(@"PRIVATE_KEY_WAIT", @"Connection status");
    NSLocalizedString(@"DISCONNECTING",    @"Connection status");
}
