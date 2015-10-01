//
//  NSApplication+LoginItem.m
//  MenuCalendar
//
//  Created by Dirk Theisen on Thu Feb 26 2004.
//  Copyright 2004 Objectpark Software. All rights reserved.
//  Contributions by Jonathan K. Bullard Copyright 2010, 2011, 2012, 2013, 2014. All rights reserved.
//
//  Permission to use, copy, modify, and distribute this software for any
//  purpose with or without fee is hereby granted, provided that the above
//  copyright notice and this permission notice appear in all copies.
// 
//  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
//  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
//  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
//  ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
//  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
//  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
//  OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.


#import "NSApplication+LoginItem.h"

#import <AppKit/AppKit.h>
#import <signal.h>
#import <sys/sysctl.h>
#import <sys/types.h>
#import <sys/stat.h>

#import "defines.h"
#import "helper.h"
#import "sharedRoutines.h"

#import "MenuController.h"
#import "NSArray+cArray.h"
#import "NSFileManager+TB.h"
#import "TBUserDefaults.h"
#import "UKLoginItemRegistry/UKLoginItemRegistry.h"

// The following external, global variable is used by functions in this file and must be declared and set elsewhere before the
// functions in this file are called:
extern NSFileManager  * gFileMgr;
extern TBUserDefaults * gTbDefaults;

@implementation NSApplication (LoginItem)

- (void) killOtherInstances
/*" Tries to terminate (SIGTERM) all other processes that happen to be named like the current running process name. Useful for stopping old versions or duplicates of the running application. "*/
{
    int         myPid = [[NSProcessInfo processInfo] processIdentifier];
    const char* myProcessName = [[[NSProcessInfo processInfo] processName] UTF8String];
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    struct kinfo_proc* info;
    size_t length;
    int count, i;
    
    // KERN_PROC_ALL has 3 elements, all others have 4
    unsigned level = 3;
    
    if (sysctl(mib, level, NULL, &length, NULL, 0) < 0) return;
    // Allocate memory for info structure:
    if (!(info = NSZoneMalloc(NULL, length))) return;
    if (sysctl(mib, level, info, &length, NULL, 0) < 0) {
        NSZoneFree(NULL, info);
        return;
    }
    
    // Calculate number of processes:
    count = length / sizeof(struct kinfo_proc);
    for (i = 0; i < count; i++) {
        char* command = info[i].kp_proc.p_comm;
        pid_t pid = info[i].kp_proc.p_pid;
        //NSLog(@"Found running command: '%s'", command);
        // Test, if this command is called like us:
        if (pid!=myPid && strncmp(myProcessName, command, MAXCOMLEN)==0) {
            // Actually kill it:
            if (kill(pid, SIGTERM) !=0) {
                NSLog(@"Error while killing process: Error was '%s'", strerror(errno)); 
            }
        }
    }    
    NSZoneFree(NULL, info);
}

- (int) countOtherInstances
// Returns the number of other instances of a process (cribbed from killOtherInstances, above)
{
    int         myPid = [[NSProcessInfo processInfo] processIdentifier];
    const char* myProcessName = [[[NSProcessInfo processInfo] processName] UTF8String];
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    struct kinfo_proc* info;
    size_t length;
    int count, i;
    int returnCount = 0;
    
    // KERN_PROC_ALL has 3 elements, all others have 4
    unsigned level = 3;
    
    if (sysctl(mib, level, NULL, &length, NULL, 0) < 0) return (-1);
    // Allocate memory for info structure:
    if (!(info = NSZoneMalloc(NULL, length))) return (-1);
    if (sysctl(mib, level, info, &length, NULL, 0) < 0) {
        NSZoneFree(NULL, info);
        return(-1);
    }
    
    // Calculate number of processes:
    count = length / sizeof(struct kinfo_proc);
    for (i = 0; i < count; i++) {
        char* command = info[i].kp_proc.p_comm;
        pid_t pid = info[i].kp_proc.p_pid;
        //NSLog(@"Found running command: '%s'", command);
        // Test, if this command is called like us:
        if (pid!=myPid && strncmp(myProcessName, command, MAXCOMLEN)==0) {
            returnCount++;
        }
    }    
    NSZoneFree(NULL, info);
    return(returnCount);
}

-(NSMutableArray *) pIdsForOpenVPNProcessesOnlyMain: (BOOL) onlyMain {
    
    // Returns an array of NSNumber objects, each with the pid for an OpenVPN process
    // Returns nil on error, empty array if no OpenVPN processes running
    //
    // if onlyMain is TRUE, returns only processes named 'openvpn'
    // else returns process whose names _start_ with 'openvpn' (e.g. 'openvpn-down-root')
    //
    //  (modified version of countOtherInstances, above)
    
    NSMutableArray * retArray = [NSMutableArray arrayWithCapacity: 2];
    const char* processName = "openvpn";
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    struct kinfo_proc* info;
    size_t length;
    int count, i;
    
    // KERN_PROC_ALL has 3 elements, all others have 4
    unsigned level = 3;
    
    if (sysctl(mib, level, NULL, &length, NULL, 0) < 0) return (nil);
    // Allocate memory for info structure:
    if (!(info = NSZoneMalloc(NULL, length))) return (nil);
    if (sysctl(mib, level, info, &length, NULL, 0) < 0) {
        NSZoneFree(NULL, info);
        return(nil);
    }
    
    // Get each process ID:
    count = length / sizeof(struct kinfo_proc);
    for (i = 0; i < count; i++) {
        char* command = info[i].kp_proc.p_comm;
        pid_t pid = info[i].kp_proc.p_pid;
        if (strncmp(processName, command, MAXCOMLEN)==0) {
            if (   (! onlyMain)
                || (strlen(command) == strlen(processName))  ) {
                [retArray addObject: [NSNumber numberWithInt: (int) pid]];
            }
        }
    }
    NSZoneFree(NULL, info);
    
    return(retArray);
}

// Waits up to five seconds for a process to be gone
// (Modified version of NSApplication+LoginItem's killOtherInstances)
// Returns TRUE if process has terminated, otherwise returns FALSE
- (BOOL) waitUntilNoProcessWithID: (pid_t) pid
{
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    struct kinfo_proc* info;
    size_t length;
    int count, i, j;
    BOOL found = FALSE;
    
    // KERN_PROC_ALL has 3 elements, all others have 4
    unsigned level = 3;
    
    if (sysctl(mib, level, NULL, &length, NULL, 0) < 0) {
        NSLog(@"Error: waitUntilNoProcessWithID: sysctl call #1: errno = %d\n%s", errno, strerror(errno));
        return FALSE;
    }
    
    for (j=0; j<6; j++) {   // Check six times, one second wait between each = five second maximum wait
        
        if (  j != 0  ) {       // Don't sleep first time through
            sleep(1);
        }
        // Allocate memory for info structure:
        if (  (info = NSZoneMalloc(NULL, length)) != 0  ) {
            
            if (  sysctl(mib, level, info, &length, NULL, 0) == 0  ) {
                // Calculate number of processes:
                count = length / sizeof(struct kinfo_proc);
                found = FALSE;
                for (i = 0; i < count; i++) {
                    if (  info[i].kp_proc.p_pid == pid  ) {
                        found = TRUE;
                        break;
                    }
                    
                }
                
                NSZoneFree(NULL, info);
                
                if (  ! found  ) {
                    return TRUE;
                }
                
            } else {
                NSZoneFree(NULL, info);
                NSLog(@"Error: waitUntilNoProcessWithID: sysctl call #2: length = %lu errno = %ld\n%s", (long) length, (long) errno, strerror(errno));
            }
            
        } else {
            NSLog(@"Error: waitUntilNoProcessWithID: NSZoneMalloc failed");
        }
        
    }
    
    if (  ! found  ) {
        return TRUE;
    }

    NSLog(@"Error: Timeout (5 seconds) waiting for OpenVPN process %d to terminate", pid);
    return FALSE;
}

- (BOOL)            wait: (int)        waitSeconds
     untilNoProcessNamed: (NSString *) processName {

    // Waits up to a specified time for there to be no processes with a specified name
    // (Modified version of NSApplication+LoginItem's killOtherInstances)
    // Returns TRUE if process has terminated, otherwise returns FALSE

    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    struct kinfo_proc* info;
    size_t length;
    int count, i, j;
    const char * processNameCString = [processName UTF8String];
    
    // KERN_PROC_ALL has 3 elements, all others have 4
    unsigned level = 3;
    
    if (sysctl(mib, level, NULL, &length, NULL, 0) < 0) {
        NSLog(@"Error: wait:untilNoProcessNamed: sysctl call #1: errno = %d\n%s", errno, strerror(errno));
        return FALSE;
    }
    
    for (j=0; j<(waitSeconds+1); j++) {   // Check with a one second wait between each test
        
        if (  j != 0  ) {       // Don't sleep first time through
            sleep(1);
        }
        // Allocate memory for info structure:
        if (  (info = NSZoneMalloc(NULL, length)) != 0  ) {
            
            if (  sysctl(mib, level, info, &length, NULL, 0) == 0  ) {
                // Calculate number of processes:
                count = length / sizeof(struct kinfo_proc);
                BOOL found = FALSE;
                for (i = 0; i < count; i++) {
                    char* command = info[i].kp_proc.p_comm;
                    if (strncmp(processNameCString, command, MAXCOMLEN)==0) {
                        found = TRUE;
                        break;
                    }
                }
                
                NSZoneFree(NULL, info);
                
                if (  ! found  ) {
                    return TRUE;
                }
                
            } else {
                NSZoneFree(NULL, info);
                NSLog(@"Error: wait:untilNoProcessNamed: sysctl call #2: length = %lu errno = %ld\n%s", (long) length, (long) errno, strerror(errno));
            }
            
        } else {
            NSLog(@"Error: wait:untilNoProcessNamed: NSZoneMalloc failed");
        }
    }
    
    NSLog(@"Error: Timeout wait:untilNoProcessNamed: '%@' to terminate", processName);
    return FALSE;
}

-(void) haveDealtWithOldLoginItem  {
    
    // Invoked on main thread because gTbDefaults may not be thread-safe
	
	[gTbDefaults setBool: TRUE forKey: @"haveDealtWithOldLoginItem"];
}

-(void) deleteOurLoginItemLeopardOrNewer {
    
	// This is a modified version of a method from http://blog.originate.com/blog/2013/10/07/answers-to-common-questions-in-cocoa-development/
	
    NSURL * ourURL = [NSURL fileURLWithPath: @"/Applications/Tunnelblick.app/"];
    
	OSStatus status;
	LSSharedFileListItemRef existingItem = NULL;
	
	LSSharedFileListRef lsLoginItems = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
	if (  lsLoginItems  ) {
		UInt32 seed = 0U;
		CFArrayRef lsLoginItemsSnapshot = LSSharedFileListCopySnapshot(lsLoginItems, &seed);
		NSArray * currentLoginItems = (NSArray *)lsLoginItemsSnapshot;
		if (  currentLoginItems  ) {
			NSUInteger ix;
			for (  ix=0; ix<[currentLoginItems count]; ix++  ) {
				LSSharedFileListItemRef item = (LSSharedFileListItemRef)[currentLoginItems objectAtIndex: ix];
				
				UInt32 resolutionFlags = kLSSharedFileListNoUserInteraction | kLSSharedFileListDoNotMountVolumes;
				CFURLRef URL = NULL;
				status = LSSharedFileListItemResolve(item, resolutionFlags, &URL, /*outRef*/ NULL);
				if (  status == noErr  ) {
					if (  ! URL  ) {
						NSLog(@"deleteOurLoginItem: loginItemsArray contains a NULL object");
					}
					BOOL foundIt = CFEqual(URL, (CFTypeRef)(ourURL));
					
					if (  foundIt  ) {
						existingItem = item;
						break;
					}
				} else if (  status != -35 /* nsvErr -- no such volume */  ) {
					NSLog(@"deleteOurLoginItem: LSSharedFileListItemResolve returned status = %ld for item = 0x%lX; url was %@",
						  (long) status, (unsigned long) item, ((URL == NULL) ? @"NULL" : @"not NULL"));
				}
				if (  URL  ) {
					CFRelease(URL);
				}
			}
			
			if (   existingItem == NULL  ) {
				NSLog(@"No old login item to remove");
                [self performSelectorOnMainThread: @selector(haveDealtWithOldLoginItem) withObject: nil waitUntilDone: NO];
            } else {
				status = LSSharedFileListItemRemove(lsLoginItems, existingItem);
				if (  status == noErr  ) {
					NSLog(@"Succesfully removed the old login item");
                    [self performSelectorOnMainThread: @selector(haveDealtWithOldLoginItem) withObject: nil waitUntilDone: NO];
                } else {
					NSLog(@"deleteOurLoginItem: LSSharedFileListItemRemove returned status = %ld for loginItem for %@", (long) status, ourURL);
				}
			}
			
			CFRelease(lsLoginItemsSnapshot);
			
		} else {
            NSLog(@"deleteOurLoginItem: LSSharedFileListCopySnapshot() returned NULL");
		}
		
		CFRelease(lsLoginItems);
		
	} else {
        NSLog(@"deleteOurLoginItem: LSSharedFileListCreate() returned NULL");
	}
}

#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5

-(void) deleteOurLoginItemTiger {
    
    // Read the loginwindow preferences:
    CFArrayRef cfItems = CFPreferencesCopyValue((CFStringRef)@"AutoLaunchedApplicationDictionary",
                                                (CFStringRef)@"loginwindow",
                                                kCFPreferencesCurrentUser,
                                                kCFPreferencesAnyHost);
    
    NSMutableArray * loginItems = [[(NSArray *)cfItems mutableCopy] autorelease];
    
    // Delete our login item (if there is one)
    BOOL dirty = FALSE;
    NSUInteger ix;
    for (  ix = 0; ix < [loginItems count]; ix++  ) {
        
        NSDictionary *item;
        item = [loginItems objectAtIndex: ix];
        if (  [[item objectForKey: @"Path"] isEqualToString: @"/Applications/Tunnelblick.app"]  ) {
            [loginItems removeObjectAtIndex: ix];
            dirty = TRUE;
            break;
        }
    }
    
    // If we deleted anything, write the loginwindow preferences back out
    if (  dirty  ) {
        CFPreferencesSetValue((CFStringRef)@"AutoLaunchedApplicationDictionary",
                              loginItems,
                              (CFStringRef)@"loginwindow",
                              kCFPreferencesCurrentUser,
                              kCFPreferencesAnyHost);
        
        CFPreferencesSynchronize((CFStringRef) @"loginwindow",
                                 kCFPreferencesCurrentUser,
                                 kCFPreferencesAnyHost);
    }
    
    CFRelease(cfItems);
	
	if (  dirty  ) {
		NSLog(@"Succesfully removed the old login item");
	} else {
		NSLog(@"No old login item to remove");
	}
	
	[self performSelectorOnMainThread: @selector(haveDealtWithOldLoginItem) withObject: nil waitUntilDone: NO];
}

#endif

-(void) deleteOurLoginItemThread {
	
	// This runs in a separate thread because deleteOurLoginItemLeopardAndUp can stall for a long time on network access
	// to a non-existing network resource (even though kLSSharedFileListDoNotMountVolumes is specified).
    
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
	
#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5
    if (  runningOnLeopardOrNewer()  ) {
        [self deleteOurLoginItemLeopardOrNewer];
    } else {
        [self deleteOurLoginItemTiger];
    }
#else
    [self deleteOurLoginItemLeopardOrNewer];
#endif
    [pool drain];
}

-(void) setupNewAutoLaunchOnLogin {
    
    // Set up the new mechanism for controlling whether Tunnelblick is launched when the user logs in.
    
	
    // If the 'haveDealtWithOldLoginItem' preference does not exist, we should remove the Tunnelblick login item if there is one.
    // We do it in a separate thread because it can stall on network access (even though kLSSharedFileListDoNotMountVolumes is specified).
    // When the old login item has been dealt with, deleteOurLoginItemThread will invoke haveDealtWithOldLoginItem, which will set the preference.
    
    if (  ! [gTbDefaults objectForKey: @"haveDealtWithOldLoginItem"]  ) {
        NSLog(@"Launching a thread to remove the old login item (if any) so we can use the new mechanism that controls Tunnelblick's launch on login");
        [NSThread detachNewThreadSelector: @selector(deleteOurLoginItemThread) toTarget: NSApp withObject: nil];
    }
	
    // If the installed 'net.tunnelblick.tunnelblick.LaunchAtLogin.plist' is not the same as ours, update it.
    
#ifdef TBDebug
	NSLog(@"DEBUG VERSION DOES NOT UPDATE LaunchAtLogin.plist.");
#else
    // The name of the LaunchAtLogin.plist file in Resources does not change when rebranded
    NSString * ourPlistPath = @"/Applications/Tunnelblick.app/Contents/Resources/net.tunnelblick.tunnel" @"blick.LaunchAtLogin.plist";
    NSString * launchAgentsPath = [[NSHomeDirectory() stringByAppendingPathComponent: @"Library"]
								   stringByAppendingPathComponent: @"LaunchAgents"];
	NSString * installedPlistPath = [launchAgentsPath stringByAppendingPathComponent: @"net.tunnelblick.tunnelblick.LaunchAtLogin.plist"];
    if (  ! [gFileMgr contentsEqualAtPath: ourPlistPath andPath: installedPlistPath]  ) {
		[gFileMgr tbRemoveFileAtPath: installedPlistPath handler: nil];
		if (   ( createDir(launchAgentsPath, 0700) == -1  )
			|| ( ! [gFileMgr tbCopyPath: ourPlistPath toPath: installedPlistPath handler: nil] )  ) {
            NSLog(@"Failed to copy: %@ to %@", ourPlistPath, installedPlistPath);
            TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                              NSLocalizedString(@"Tunnelblick could not be configured to automatically launch itself after you log in.\n\n"
                                                @"See the Console log for details.", @"Window text"));
        } else {
            NSLog(@"Copied our 'net.tunnelblick.tunnelblick.LaunchAtLogin.plist' into ~/Library/LaunchAgents");
        }
    }
#endif
}

+(AuthorizationRef)getAuthorizationRef: (NSString *) msg {
	OSStatus myStatus;
	AuthorizationFlags myFlags = kAuthorizationFlagDefaults;
	AuthorizationRef myAuthorizationRef;
    
    // Add an icon and a prompt to the authorization dialog
    //
    // One would think that we could use an icon in Resources, but that doesn't work. Apparently if the path is too long
    // the icon won't be displayed. It works if the icon is in /tmp. (Not if it is in NSTemporaryDirectory() -- path too long.)
    // In addition, it seems to require a 32x32 png.
    // We create the icon dynamically so if the main Tunnelblick icon changes, the authorization dialog will show the new icon.

    NSString * tmpAuthIconPath = @"/tmp/TunnelblickAuthIcon.png";
    
    // START OF CODE adapted from comment 7 on http://cocoadev.com/forums/comments.php?DiscussionID=1215    //
                                                                                                            //
    NSImage *saveIcon = [[NSWorkspace sharedWorkspace] iconForFile: [[NSBundle mainBundle] bundlePath]];    //
                                                                                                            //
	NSImage *smallSave = [[[NSImage alloc] initWithSize:NSMakeSize(32.0, 32.0)] autorelease];             //
    // Get it's size down to 32x32                                                                          //
    [smallSave lockFocus];                                                                                  //
    [saveIcon drawInRect:NSMakeRect(0.0, 0.0, 32.0, 32.0)                                               //
                fromRect:NSMakeRect(0.0, 0.0, saveIcon.size.width, saveIcon.size.height)  //
               operation:NSCompositeSourceOver                                                              //
                fraction:1.0];                                                                             //
                                                                                                            //
    [smallSave unlockFocus];                                                                                //
    NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:[smallSave TIFFRepresentation]];             //
                                                                                                            //
    [[rep representationUsingType:NSPNGFileType properties:nil] writeToFile:tmpAuthIconPath atomically:NO]; //
                                                                                                            //
    // END OF CODE adapted from comment 7 on http://cocoadev.com/forums/comments.php?DiscussionID=1215      //
    
    const char *iconPathC = [tmpAuthIconPath fileSystemRepresentation];
    size_t iconPathLength = iconPathC ? strlen(iconPathC) : 0;

    // Prefix the prompt with a space so it is indented, like the rest of the dialog, and follow it with two newlines
    char * promptC = (char *) [[NSString stringWithFormat: @" %@\n\n", msg] UTF8String];
    size_t promptLength = strlen(promptC);
    
    AuthorizationItem environmentItems[] = {
        {kAuthorizationEnvironmentPrompt, promptLength, (void*)promptC, 0},
        {kAuthorizationEnvironmentIcon, iconPathLength, (void*)iconPathC, 0}
    };
    
    AuthorizationEnvironment myEnvironment = {2, environmentItems};
    
	myStatus = AuthorizationCreate(NULL, &myEnvironment, myFlags, &myAuthorizationRef);
	if (myStatus != errAuthorizationSuccess)
		return nil;
	AuthorizationItem myItems = {kAuthorizationRightExecute, 0, NULL, 0};
	AuthorizationRights myRights = {1, &myItems};
	myFlags = kAuthorizationFlagDefaults |
		kAuthorizationFlagInteractionAllowed |
		kAuthorizationFlagPreAuthorize |
		kAuthorizationFlagExtendRights;
	myStatus = AuthorizationCopyRights (myAuthorizationRef,&myRights, &myEnvironment, myFlags, NULL );
	if (myStatus != errAuthorizationSuccess)
		return nil;
	
	//AuthorizationFree (myAuthorizationRef, kAuthorizationFlagDefaults);
	return myAuthorizationRef;
}

+(OSStatus) executeAuthorized:(NSString *)toolPath withArguments:(NSArray *)arguments withAuthorizationRef:(AuthorizationRef) myAuthorizationRef {
	const char * myToolPath = [gFileMgr fileSystemRepresentationWithPath: toolPath];
	char **myArguments = [arguments cArray];
	OSStatus myStatus;
	AuthorizationFlags myFlags = kAuthorizationFlagDefaults;
	myStatus = AuthorizationExecuteWithPrivileges(myAuthorizationRef, myToolPath, myFlags, myArguments, NULL);
	freeCArray(myArguments);
    if (  myStatus != 0  ) {
        NSLog(@"AuthorizationExecuteWithPrivileges returned status = %ld", (long) myStatus);
    }
	return myStatus;
}

+(BOOL) createFlagFile: (NSString *) path {
    
    int fd = open([path fileSystemRepresentation], O_RDONLY | O_CREAT, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH);
    if (fd < 0) {
        NSLog(@"Unable to create flag file %@\nError was '%s'", path, strerror(errno));
        return NO;
    } else {
        if (  0 != close(fd)  ) {
            NSLog(@"Unable to close flag file %@ with file descriptor %d\nError was '%s'", path, fd, strerror(errno));
            return NO;
        }
    }
    
    return YES;
}

+(wfeaReturnValue) waitForExecuteAuthorized: (NSString *)       toolPath
                              withArguments: (NSArray *)        arguments
                       withAuthorizationRef: (AuthorizationRef) myAuthorizationRef {
    
    // Creates a "running" and an "error" flag file, runs executeAuthorized, then waits for up to 25.55 seconds for the "running" flag file to disappear
    
    if (   ( ! [self createFlagFile: AUTHORIZED_RUNNING_PATH] )
        || ( ! [self createFlagFile: AUTHORIZED_ERROR_PATH]   )  ) {
        unlink([AUTHORIZED_RUNNING_PATH fileSystemRepresentation]);
        unlink([AUTHORIZED_ERROR_PATH fileSystemRepresentation]);
        return wfeaExecAuthFailed;
    }
    
    if (  EXIT_SUCCESS != [NSApplication executeAuthorized: toolPath withArguments: arguments withAuthorizationRef: myAuthorizationRef]  ) {
        if (  0 != unlink([AUTHORIZED_RUNNING_PATH fileSystemRepresentation])  ) {
            NSLog(@"Unable to delete %@", AUTHORIZED_RUNNING_PATH);
        }
        if (  0 != unlink([AUTHORIZED_ERROR_PATH fileSystemRepresentation])  ) {
            NSLog(@"Unable to delete %@", AUTHORIZED_ERROR_PATH);
        }
        return wfeaExecAuthFailed;
    }
    
    // Wait for up to 25.55 seconds for the program to finish -- sleeping .05 seconds first, then .1, .2, .4, .8, 1.6, 3.2, 6.4, and 12.8
    // seconds (totals 25.55 seconds) between tries as a cheap and easy throttling mechanism for a heavily loaded computer
    useconds_t sleepTime;
    struct stat sb;
    for (sleepTime=50000; sleepTime < 26000000; sleepTime=sleepTime*2) {
        usleep(sleepTime);
        
        if (  0 != stat([AUTHORIZED_RUNNING_PATH fileSystemRepresentation], &sb)  ) {
            // running flag file has been deleted, indicating we're done
			if (  0 == stat([AUTHORIZED_ERROR_PATH fileSystemRepresentation], &sb)  ) {
                // error flag file exists, so there was an error
				if (  0 != unlink([AUTHORIZED_ERROR_PATH fileSystemRepresentation])  ) {
					NSLog(@"Unable to delete %@", AUTHORIZED_ERROR_PATH);
				}
				
				return wfeaFailure;
			}
			
            return wfeaSuccess;
        }
    }
    
    NSLog(@"Timed out waiting for %@ to disappear indicting %@ finished", AUTHORIZED_RUNNING_PATH, [toolPath lastPathComponent]);
    if (  0 != unlink([AUTHORIZED_RUNNING_PATH fileSystemRepresentation])  ) {
        NSLog(@"Unable to delete %@", AUTHORIZED_RUNNING_PATH);
    }
    if (  0 != unlink([AUTHORIZED_ERROR_PATH fileSystemRepresentation])  ) {
        NSLog(@"Unable to delete %@", AUTHORIZED_ERROR_PATH);
    }
    
    return wfeaTimedOut;
}

@end
