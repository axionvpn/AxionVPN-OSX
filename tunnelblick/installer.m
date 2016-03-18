/*
 * Copyright 2004, 2005, 2006, 2007, 2008, 2009 by Angelo Laub
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

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <sys/stat.h>

#import "defines.h"
#import "sharedRoutines.h"

#import "ConfigurationConverter.h"
#import "NSFileManager+TB.h"
#import "NSString+TB.h"

// NOTE: THIS PROGRAM MUST BE RUN AS ROOT VIA executeAuthorized
//
// This program is called when something needs to be secured.
// It accepts two to five arguments, and always does some standard housekeeping in
// addition to the specific tasks specified by the command line arguments.
//
// Usage:
//
//     installer bitMask
//     installer bitMask bundleVersion bundleVersionString
//     installer bitmask targetPath   [sourcePath]
//
// where
//   bitMask (See defines.h for bit assignments) -- DETERMINES WHAT THE INSTALLER WILL DO:
//
//     INSTALLER_COPY_APP:      set to copy this app to /Applications/XXXXX.app
//                                  (Any existing /Applications/XXXXX.app will be moved to the Trash)
//
//     INSTALLER_SECURE_APP:    set to secure AxionVPN.app and all of its contents
//                                  (also set if INSTALLER_COPY_APP)
//     INSTALLER_SECURE_TBLKS:  set to secure all .tblk packages in Configurations, Shared, and the alternate configuration path
//
//	   INSTALLER_CONVERT_NON_TBLKS: set to convert all .ovpn and .conf files (and their associated keys, scripts, etc.) to .tblk packages
//
//	   INSTALLER_MOVE_LIBRARY_OPENVPN: set to move ~/Library/openvpn to ~/Library/Application Support/Tunnelblick
//
//     INSTALLER_MOVE_NOT_COPY: set to move, instead of copy, if target path and source path are supplied
//
//     INSTALLER_DELETE:        set to delete target path
//
// targetPath          is the path to a configuration (.ovpn or .conf file, or .tblk package) to be secured
// sourcePath          is the path to be copied or moved to targetPath before securing targetPath
//
// It does the following:
//      (1) ALWAYS creates directories or repair their ownership/permissions as needed
//             and converts old entries in L_AS_T_TBLKS to the new format, with an bundleId_edition folder enclosing a .tblk
//      (2) if INSTALLER_MOVE_LIBRARY_OPENVPN, moves the contents of the old configuration folder
//          at ~/Library/openvpn to ~/Library/Application Support/Tunnelblick/Configurations
//          and replaces it with a symlink to the new location.
//      (3) If INSTALLER_CONVERT_NON_TBLKS, all private .ovpn or .conf files are converted to .tblks
//      (4) If INSTALLER_COPY_APP, this app is copied to /Applications
//      (5) Renames /Library/LaunchDaemons/net.tunnelblick.startup.*
//               to                        net.tunnelblick.tunnelblick.startup.*
//      (6) If INSTALLER_SECURE_APP, secures AxionVPN.app by setting the ownership and permissions of its components.
//      (7) If INSTALLER_COPY_APP, L_AS_T_TBLKS is pruned by removing all but the highest edition of each container
//      (8) If INSTALLER_SECURE_TBLKS, secures all .tblk packages in the following folders:
//           /Library/Application Support/Tunnelblick/Shared
//           ~/Library/Application Support/Tunnelblick/Configurations
//           /Library/Application Support/Tunnelblick/Users/<username>
//
//      (9) If INSTALLER_DELETE is clear and sourcePath is given,
//             copies or moves sourcePath to targetPath. Copies unless INSTALLER_MOVE_NOT_COPY is set.  (Also copies or moves the shadow copy if deleting a private configuration)
//     (10) If INSTALLER_DELETE is clear and targetPath is given,
//             secures the .ovpn or .conf file or a .tblk package at targetPath
//     (11) If INSTALLER_DELETE is set and targetPath is given,
//             deletes the .ovpn or .conf file or .tblk package at targetPath (also deletes the shadow copy if deleting a private configuration)
//     (12) Set up tunnelblickd
//
// When finished (or if an error occurs), the file /tmp/tunnelblick-authorized-running is deleted to indicate the program has finished
//
//        (10) is done when creating a shadow configuration file
//                     or copying a .tblk to install it
//                     or moving a .tblk to make it private or shared
//        (11) is done when repairing a shadow configuration file or after copying or moving a .tblk

FILE          * gLogFile;					  // FILE for log
NSFileManager * gFileMgr;                     // [NSFileManager defaultManager]
NSString      * gPrivatePath;                 // Path to ~/Library/Application Support/Tunnelblick/Configurations
NSString      * gDeployPath;                  // Path to AxionVPN.app/Contents/Resources/Deploy
uid_t           gRealUserID;                  // User ID & Group ID for the real user (i.e., not "root:wheel", which is what we are running as)
gid_t           gRealGroupID;
NSAutoreleasePool * pool;

BOOL makeUnlockedAtPath(NSString * path);
BOOL moveContents(NSString * fromPath, NSString * toPath);
NSString * firstPartOfPath(NSString * path);
NSString * lastPartOfPath(NSString * path);
void safeCopyOrMovePathToPath(NSString * fromPath, NSString * toPath, BOOL moveNotCopy);
BOOL deleteThingAtPath(NSString * path);
BOOL convertAllPrivateOvpnAndConfToTblk(void);
BOOL tunnelblickTestPrivateOnlyHasTblks(void);

//**************************************************************************************************************************

void errorExit();
void errorExitIfAnySymlinkInPath(NSString * path,
								 int testPoint);

void debugLog(NSString * string) {
	
	// Call this function to create files in /tmp to show progress through this program
	// when there are problems that cause the log not to be available
	// For example, if this installer hangs.
	//
	// "string" is a string identifier indicating where debugLog was called from.
	
	static unsigned int debugLogMessageCounter = 0;
	
	NSString * path = [NSString stringWithFormat: @"/tmp/0-%u-tunnelblick-installer-%@.txt", ++debugLogMessageCounter, string];
	[[NSFileManager defaultManager] createFileAtPath: path contents: [NSData data] attributes: nil];
}

void openLog(BOOL clearLog) {
    
    const char * path = [INSTALLER_LOG_PATH fileSystemRepresentation];
	
	if (  clearLog  ) {
		gLogFile = fopen(path, "w");
	} else {
		gLogFile = fopen(path, "a");
	}
    
	if (  gLogFile == NULL  ) {
		errorExit();
	}
}

void appendLog(NSString * s) {
    
	if (  gLogFile != NULL  ) {
		fprintf(gLogFile, "%s\n", [s UTF8String]);
	} else {
		NSLog(@"%@", s);
	}
}

void closeLog(void) {
    
	if (  gLogFile != NULL  ) {
		fclose(gLogFile);
	}
}

void deleteFlagFile(NSString * path) {
    
	const char * fsrPath = [path fileSystemRepresentation];
    struct stat sb;
	if (  0 == stat(fsrPath, &sb)  ) {
        if (  (sb.st_mode & S_IFMT) == S_IFREG  ) {
            if (  0 != unlink(fsrPath)  ) {
                appendLog([NSString stringWithFormat: @"Unable to delete %@", path]);
            }
        } else {
            appendLog([NSString stringWithFormat: @"%@ is not a regular file; st_mode = 0%lo", path, (unsigned long) sb.st_mode]);
        }
    } else {
        appendLog([NSString stringWithFormat: @"stat of %@ failed\nError was '%s'", path, strerror(errno)]);
    }
}

void errorExit() {
    
#ifdef TBDebug
	id stackTrace = (  [NSThread respondsToSelector: @selector(callStackSymbols)]
                     ? (id) [NSThread callStackSymbols]
                     : (id) @"not available");
    appendLog([NSString stringWithFormat: @"installer: errorExit: Stack trace: %@", stackTrace]);
#endif
	
    // Leave AUTHORIZED_ERROR_PATH to indicate an error occurred
    deleteFlagFile(AUTHORIZED_RUNNING_PATH);
	closeLog();
    
    [pool drain];
    exit(EXIT_FAILURE);
}

void freeAuthRef(AuthorizationRef authRef) {
	
	if (  authRef != NULL  ) {
		OSStatus status = AuthorizationFree(authRef, kAuthorizationFlagDefaults);
		if (  status != errAuthorizationSuccess  ) {
			appendLog([NSString stringWithFormat: @"AuthorizationFree(0x%lx) returned %ld", (unsigned long)authRef, (long)status]);
			errorExit();
		}
	}
}

void pruneL_AS_T_TBLKS() {
    
    // Prune L_AS_T_TblKS by removing all but the highest edition of each container
    
    NSDictionary * bundleIdEditions = highestEditionForEachBundleIdinL_AS_T(); // Key = bundleId; object = edition
    
	if (  [bundleIdEditions count] != 0  ) {
		NSString * bundleIdAndEdition;
		NSDirectoryEnumerator * outerDirEnum = [gFileMgr enumeratorAtPath: L_AS_T_TBLKS];
		while (  (bundleIdAndEdition = [outerDirEnum nextObject])  ) {
			[outerDirEnum skipDescendents];
			NSString * containerPath = [L_AS_T_TBLKS stringByAppendingPathComponent: bundleIdAndEdition];
			BOOL isDir;
			if (   ( ! [bundleIdAndEdition hasPrefix: @"."] )
                && ( ! [bundleIdAndEdition hasSuffix: @".tblk"] )
				&& [gFileMgr fileExistsAtPath: containerPath isDirectory: &isDir]
				&& isDir  ) {
				NSString * bundleId = [bundleIdAndEdition stringByDeletingPathEdition];
				if (  ! bundleId  ) {
					appendLog([NSString stringWithFormat: @"Container path does not have a bundleId: %@", containerPath]);
					break;
				}
				NSString * edition  = [bundleIdAndEdition pathEdition];
				if (  ! edition  ) {
					appendLog([NSString stringWithFormat: @"Container path does not have an edition: %@", containerPath]);
					break;
				}
				NSString * highestEdition = [bundleIdEditions objectForKey: bundleId];
				if (  ! highestEdition  ) {
					appendLog(@"New entry in L_AS_T_TBLKS appeared during pruning");
					break;
				}
				if (  ! [edition isEqualToString: highestEdition]  ) {
					if (  ! [gFileMgr tbRemoveFileAtPath: containerPath handler: nil]  ) {
						appendLog([NSString stringWithFormat: @"While pruning L_AS_T_TBLKS, could not remove %@", containerPath]);
						errorExit();
					}
					
					appendLog([NSString stringWithFormat: @"Pruned L_AS_T_TBLKS by removing %@", containerPath]);
				}
			}
		}
	}
}

void resolveSymlinksInPath(NSString * targetPath) {
	
	// There are symlinks in a .tblk for files which are not readable by the user but should be propagated from one configuration to another when installing an updated configuration.
	// These symlinks need to be replaced by the files to which they point.
	//
	// This is safe to do as root because only Tunnelblick or an admin can invoke the installer as root, and Tunnelblick allows only its own symlinks.
	// (Tunnelblick resolves symlinks provided by the user while running as the user.)
	//
	// Because the target is a temporary copy, we replace the symlinks with the file contents in a file owned by root:wheel with permissions 0700, so the file cannot be read except by root.
	// The final, possibly less restrictive, ownership and permissions will be set later.
	
	if (  ! [targetPath hasSuffix: @".tblk"] ) {
		return;
	}
	
	NSString * file;
	NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: targetPath];
	while (  (file = [dirEnum nextObject])  ) {
		NSString * fullPath = [targetPath stringByAppendingPathComponent: file];
		NSDictionary * fullPathAttributes = [gFileMgr tbFileAttributesAtPath: fullPath traverseLink: NO];
		if (  [fullPathAttributes fileType] == NSFileTypeSymbolicLink  ) {
			
			NSString * resolvedPath = [gFileMgr tbPathContentOfSymbolicLinkAtPath: fullPath];
			if (  ! (   [resolvedPath hasPrefix: L_AS_T_SHARED]
                     || [resolvedPath hasPrefix: L_AS_T_TBLKS]
                     || [resolvedPath hasPrefix: L_AS_T_USERS]
                     || [resolvedPath hasPrefix: gDeployPath]
                     )  ) {
                appendLog([NSString stringWithFormat: @"Symlink is not to an allowed path: %@", resolvedPath]);
                errorExit();
            }
            
			NSData * data = [gFileMgr contentsAtPath: resolvedPath];
			
			if (  ! data  ) {
				appendLog([NSString stringWithFormat: @"Could not get contents of %@", resolvedPath]);
				errorExit();
			}
			
			if (  ! [gFileMgr tbRemoveFileAtPath: fullPath handler: nil]  ) {
				appendLog([NSString stringWithFormat: @"Could not remove (before replacing): %@", fullPath]);
				errorExit();
			}
			
			NSDictionary * attributes = [NSDictionary dictionaryWithObjectsAndKeys:
										 [NSNumber numberWithInt: 0], NSFileOwnerAccountID,
										 [NSNumber numberWithInt: 0], NSFileGroupOwnerAccountID,
										 [NSNumber numberWithInt: 0700], NSFilePosixPermissions,
										 nil];
            
			if (  [gFileMgr createFileAtPath: fullPath contents: data attributes: attributes]  ) {
				appendLog([NSString stringWithFormat: @"Replaced symlink at %@\n with copy of %@", fullPath, resolvedPath]);
			} else {
				appendLog([NSString stringWithFormat: @"Could not replace symlink at %@\n     with a copy of %@", fullPath, resolvedPath]);
				errorExit();
            }
		}
	}
}


BOOL isLaunchDaemonLoaded(void) {
	
	// Must have uid=0 (not merely euid=0) for runTool(launchctl) to work properly
    if (  setuid(0)  ) {
		appendLog([NSString stringWithFormat: @"setuid(0) failed; error was %d: '%s'", errno, strerror(errno)]);
		errorExit();
	}
	if (  setgid(0)  ) {
		appendLog([NSString stringWithFormat: @"setgid(0) failed; error was %d: '%s'", errno, strerror(errno)]);
		errorExit();
	}
 	
	if (  ! [gFileMgr fileExistsAtPath: TUNNELBLICKD_PLIST_PATH]  ) {
		appendLog([NSString stringWithFormat: @"No file at %@; assuming tunnelblickd is not loaded", TUNNELBLICKD_PLIST_PATH]);
		return NO;
	}
	
	NSString * stdoutString = @"";
	NSString * stderrString = @"";
	NSArray * arguments = [NSArray arrayWithObject: @"list"];
	OSStatus status = runTool(TOOL_PATH_FOR_LAUNCHCTL, arguments, &stdoutString, &stderrString);
	if (   (status != EXIT_SUCCESS)
		|| [stdoutString isEqualToString: @""]  ) {
        
        appendLog([NSString stringWithFormat: @"'%@ list' failed or had no output; assuming tunnelblickd is not loaded; error was %d: '%s'\nstdout = '%@'\nstderr='%@'",
                   TOOL_PATH_FOR_LAUNCHCTL, errno, strerror(errno), stdoutString, stderrString]);
		return NO;
	}
	
	BOOL result = ([stdoutString rangeOfString: @"net.tunnelblick.tunnelblick.tunnelblickd"].length != 0);
	return result;
}

void loadLaunchDaemonUsingLaunchctl(void) {
	
	// Must have uid=0 (not merely euid=0) for runTool(launchctl) to work properly
    if (  setuid(0)  ) {
		appendLog([NSString stringWithFormat: @"setuid(0) failed; error was %d: '%s'", errno, strerror(errno)]);
		errorExit();
	}
	if (  setgid(0)  ) {
		appendLog([NSString stringWithFormat: @"setgid(0) failed; error was %d: '%s'", errno, strerror(errno)]);
		errorExit();
	}
 	
	NSString * stdoutString = @"";
	NSString * stderrString = @"";
	
	if (  [gFileMgr fileExistsAtPath: TUNNELBLICKD_PLIST_PATH]  ) {
		NSArray * arguments = [NSArray arrayWithObjects: @"unload", TUNNELBLICKD_PLIST_PATH, nil];
		OSStatus status = runTool(TOOL_PATH_FOR_LAUNCHCTL, arguments, &stdoutString, &stderrString);
		if (  status != EXIT_SUCCESS  ) {
			appendLog([NSString stringWithFormat: @"'%@ unload' failed; error was %d: '%s'\nstdout = '%@'\nstderr='%@'",
                       TOOL_PATH_FOR_LAUNCHCTL, errno, strerror(errno), stdoutString, stderrString]);
			// Continue even after the error. If we can load, it doesn't matter that we didn't unload.
		}
		
		stdoutString = @"";
		stderrString = @"";
	}
	
	NSArray * arguments = [NSArray arrayWithObjects: @"load", TUNNELBLICKD_PLIST_PATH, nil];
	OSStatus status = runTool(TOOL_PATH_FOR_LAUNCHCTL, arguments, &stdoutString, &stderrString);
	if (  status == EXIT_SUCCESS  ) {
		appendLog(@"Used launchctl to load tunnelblickd");
	} else {
		appendLog([NSString stringWithFormat: @"'%@ load' failed; error was %d: '%s'\nstdout = '%@'\nstderr='%@'",
                   TOOL_PATH_FOR_LAUNCHCTL, errno, strerror(errno), stdoutString, stderrString]);
		errorExit();
	}
}

/* DISABLED BECAUSE THIS IS NOT AVAILABLE ON 10.4 and 10.5
 *
 * When/if this is enabled, must add the ServiceManagement framework, too, via the following line at the start of this file:
 *
 *      #import <ServiceManagement/ServiceManagement.h>
 *
 * That framework is not on 10.4, and the SMJobSubmit() function is not available on 10.5
 
void  loadLaunchDaemonUsingSMJobSubmit(NSDictionary * newPlistContents) {
	
	// Obtain the right to change the system launchd domain
	AuthorizationItem right;
	right.name = kSMRightModifySystemDaemons;
	right.valueLength = 0;
	right.value = NULL;
	right.flags = 0;
	
	AuthorizationRights requestedRights;
	requestedRights.count = 1;
	requestedRights.items = &right;
	
	AuthorizationRef authRef = NULL;
	
	OSStatus status = AuthorizationCreate(&requestedRights,
										  kAuthorizationEmptyEnvironment,
										  (  kAuthorizationFlagDefaults
										   | kAuthorizationFlagExtendRights),
										  &authRef);
	if (  errAuthorizationSuccess != status  ) {
		appendLog([NSString stringWithFormat: @"Unable to create an AuthorizationRef with the 'kSMRightModifySystemDaemons' right; status = %d", status]);
		freeAuthRef(authRef);
		errorExit();
	}
	
	// Unload the existing LaunchDaemon if if is loaded
	NSString * daemonLabel = @"net.tunnelblick.tunnelblick.tunnelblickd";
	CFErrorRef removeError = NULL;
	if (  ! SMJobRemove(kSMDomainSystemLaunchd, (CFStringRef)daemonLabel, authRef, TRUE , &removeError)) {	// TRUE = do not return until removed
		if (  CFErrorGetCode(removeError) != kSMErrorJobNotFound ) {
			appendLog([NSString stringWithFormat: @"Unable to unload %@; error: %@", daemonLabel, (NSError *)removeError]);
			if (  removeError  ) CFRelease(removeError);
			freeAuthRef(authRef);
			errorExit();
		}
		appendLog([NSString stringWithFormat: @"Do not need to unload old %@", daemonLabel]);
	} else {
		appendLog([NSString stringWithFormat: @"Unloaded old %@", daemonLabel]);
	}
	if (  removeError  ) CFRelease(removeError);
	
	// Load the new daemon
	CFDictionaryRef cfPlist = (CFDictionaryRef)[NSDictionary dictionaryWithDictionary: newPlistContents];
	CFErrorRef submitError = NULL;
	if (  ! SMJobSubmit(kSMDomainSystemLaunchd, cfPlist, authRef, &submitError)  ) {
		appendLog([NSString stringWithFormat: @"SMJobSubmit failed to load %@; error: %@", daemonLabel, (NSError *)submitError]);
		if (  submitError  ) CFRelease(submitError);
		freeAuthRef(authRef);
		errorExit();
	} else {
		appendLog([NSString stringWithFormat: @"Loaded new %@", daemonLabel]);
	}
	if (  submitError  ) CFRelease(submitError);
	
	freeAuthRef(authRef);
}

 */

void loadLaunchDaemon (NSDictionary * newPlistContents, BOOL forceLoad) {
	
	// 'runningOnSnowLeopardOrNewer' is not in sharedRoutines, so we don't use it -- we load the launch daemon the old way, with 'launchctl load'
	// Left the new code in to make it easy to implement the new way -- with 'SMJobSubmit()' on 10.6.8 and higher -- in case a later version of OS X messes with 'launchctl load'
	// To implement the new way, too, move 'runningOnSnowLeopardOrNewer' to sharedRoutines and un-comment the code below to use 'loadLaunchDaemonUsingSMJobSubmit'.
	
	if (   forceLoad
        || (! isLaunchDaemonLoaded())  ) {
//      if (  runningOnSnowLeopardOrNewer()  ) {
//          loadLaunchDaemonUsingSMJobSubmit(newPlistContents);
// 	    } else {
	    (void) newPlistContents;  // Can remove this if the above lines are un-commmented
		loadLaunchDaemonUsingLaunchctl();
//	    }
	}
}

int main(int argc, char *argv[])
{
	pool = [NSAutoreleasePool new];
    
    if (  (argc < 2)  || (argc > 4)  ) {
		openLog(FALSE);
        appendLog([NSString stringWithFormat: @"Wrong number of arguments -- expected 1 to 3, given %d", argc-1]);
        errorExit();
	}

    unsigned arg1 = (unsigned) strtol(argv[1], NULL, 10);
    
	BOOL clearLog         = (arg1 & INSTALLER_CLEAR_LOG) != 0;
	
    BOOL copyApp          = (arg1 & INSTALLER_COPY_APP) != 0;
	
    BOOL secureApp        = copyApp || ( (arg1 & INSTALLER_SECURE_APP)   != 0 );
    BOOL secureTblks      = copyApp || ( (arg1 & INSTALLER_SECURE_TBLKS) != 0 );		// secureTblks will also be set if any private .ovpn or .conf configurations were converted to .tblks
	BOOL convertNonTblks  = (arg1 & INSTALLER_CONVERT_NON_TBLKS) != 0;
	BOOL moveLibOpenvpn   = (arg1 & INSTALLER_MOVE_LIBRARY_OPENVPN) != 0;

    BOOL moveNotCopy      = (arg1 & INSTALLER_MOVE_NOT_COPY) != 0;
    BOOL deleteConfig     = (arg1 & INSTALLER_DELETE) != 0;
	
    BOOL helperIsToBeSuid = (arg1 & INSTALLER_HELPER_IS_TO_BE_SUID) != 0;
    
    BOOL forceLoadLaunchDaemon = copyApp || secureApp;
    
	openLog(  clearLog  );
	
	NSBundle * ourBundle = [NSBundle mainBundle];
	NSString * resourcesPath = [ourBundle bundlePath]; // (installer itself is in Resources)
    NSArray  * execComponents = [resourcesPath pathComponents];
	if (  [execComponents count] < 3  ) {
        appendLog([NSString stringWithFormat: @"too few execComponents; resourcesPath = %@", resourcesPath]);
        errorExit();
    }
	NSString * ourAppName = [execComponents objectAtIndex: [execComponents count] - 3];
	if (  [ourAppName hasSuffix: @".app"]  ) {
		ourAppName = [ourAppName substringToIndex: [ourAppName length] - 4];
	}
    
    // We use Deploy located in the Tunnelblick in /Applications, even if we are running from some other location and are copying the application there
#ifndef TBDebug
	gDeployPath = @"/Applications/AxionVPN.app/Contents/Resources/Deploy";
#else
	gDeployPath = [resourcesPath stringByAppendingPathComponent: @"Deploy"];
#endif
    
	// Log the arguments installer was started with
	unsigned long firstArg = strtoul(argv[1], NULL, 10);
	NSMutableString * argString = [NSMutableString stringWithFormat: @" 0x%04lx", firstArg];
	int i;
	for (  i=2; i<argc; i++  ) {
		[argString appendFormat: @"\n     %@", [NSString stringWithUTF8String: argv[i]]];
	}
	NSCalendarDate * date = [NSCalendarDate date];
	NSString * dateMsg = [date descriptionWithCalendarFormat:@"%Y-%m-%d %H:%M:%S"];
	
	appendLog([NSString stringWithFormat: @"Tunnelblick installer started %@. %d arguments:%@", dateMsg, argc - 1, argString]);
	
    gFileMgr = [NSFileManager defaultManager];
    
    //MIKE fix Later
    gPrivatePath = [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Tunnelblick/Configurations/"] copy];
    
    // If we copy the .app to /Applications, other changes to the .app affect THAT copy, otherwise they affect the currently running copy
    NSString * appResourcesPath = (copyApp
                                   
                                   ? [[[@"/Applications"
                                        stringByAppendingPathComponent: [ourAppName stringByAppendingPathExtension: @"app"]]
                                       stringByAppendingPathComponent: @"Contents"]
                                      stringByAppendingPathComponent: @"Resources"]

                                   : [[resourcesPath copy] autorelease]);
    
    gRealUserID  = getuid();
    gRealGroupID = getgid();
    
    BOOL isDir;
    
    NSString * firstPath = nil;
    if (  argc > 2  ) {
        firstPath = [gFileMgr stringWithFileSystemRepresentation: argv[2] length: strlen(argv[2])];
        if (  ! [firstPath hasPrefix: [gPrivatePath stringByAppendingString: @"/"]]  ) {
            errorExitIfAnySymlinkInPath(firstPath, 10);
        }
    }
    NSString * secondPath = nil;
    if (  argc > 3  ) {
        secondPath = [gFileMgr stringWithFileSystemRepresentation: argv[3] length: strlen(argv[3])];
        if (  ! [secondPath hasPrefix: [gPrivatePath stringByAppendingString: @"/"]]  ) {
            errorExitIfAnySymlinkInPath(secondPath, 11);
        }
    }
    
    //**************************************************************************************************************************
    // (1) Create directories or repair their ownership/permissions as needed
    //        and convert old entries in L_AS_T_TBLKS to the new format, with an bundleId_edition folder enclosing a .tblk
    
    if (  ! createDirWithPermissionAndOwnership(@"/Library/Application Support/Tunnelblick",
                                                PERMS_SECURED_FOLDER, 0, 0)  ) {
        errorExit();
    }
    
    if (  ! createDirWithPermissionAndOwnership(L_AS_T_LOGS,
                                                PERMS_SECURED_FOLDER, 0, 0)  ) {
        errorExit();
    }
    
	if (  ( ! helperIsToBeSuid)  ) {
		if (  ! createDirWithPermissionAndOwnership(TUNNELBLICKD_LOG_FOLDER,
													PERMS_SECURED_FOLDER, 0, 0)  ) {
			errorExit();
		}
	}
    
    if (  ! createDirWithPermissionAndOwnership(L_AS_T_SHARED,
                                                PERMS_SECURED_FOLDER, 0, 0)  ) {
        errorExit();
    }
    
    if (  ! createDirWithPermissionAndOwnership(L_AS_T_TBLKS,
                                                PERMS_SECURED_FOLDER, 0, 0)  ) {
        errorExit();
    }
    
    if (  ! createDirWithPermissionAndOwnership(L_AS_T_USERS,
                                                PERMS_SECURED_FOLDER, 0, 0)  ) {
        errorExit();
    }
    
    if (  ! createDirWithPermissionAndOwnership([L_AS_T_USERS stringByAppendingPathComponent: NSUserName()],
                                                PERMS_SECURED_FOLDER, 0, 0)  ) {
        errorExit();
    }
    
    NSString * userL_AS_T_Path= [[[NSHomeDirectory()
                                   stringByAppendingPathComponent: @"Library"]
                                  stringByAppendingPathComponent: @"Application Support"]
                                 stringByAppendingPathComponent: @"Tunnelblick"];
    
    if (  ! createDirWithPermissionAndOwnership(userL_AS_T_Path,
                                                PERMS_PRIVATE_FOLDER, gRealUserID, ADMIN_GROUP_ID)  ) {
        errorExit();
    }
    
    if (  ! createDirWithPermissionAndOwnership([userL_AS_T_Path stringByAppendingPathComponent: @"Configurations"],
                                                PERMS_PRIVATE_FOLDER, gRealUserID, ADMIN_GROUP_ID)  ) {
        errorExit();
    }
	
        //**************************************************************************************************************************
    // (2)
    // Deal with migration to new configuration path
	
	if (  moveLibOpenvpn  ) {
		
		NSString * oldConfigDirPath = [NSHomeDirectory() stringByAppendingPathComponent: @"Library/openvpn"];
		NSString * newConfigDirPath = [NSHomeDirectory() stringByAppendingPathComponent: @"Library/Application Support/Tunnelblick/Configurations"];
		
		// Verify that new configuration folder exists
		if (  [gFileMgr fileExistsAtPath: newConfigDirPath isDirectory: &isDir]  ) {
			if (  isDir  ) {
				// If old configurations folder exists (and is a folder):
				// Move its contents to the new configurations folder and delete it
				NSDictionary * fileAttributes = [gFileMgr tbFileAttributesAtPath: oldConfigDirPath traverseLink: NO];
				if (  ! [[fileAttributes objectForKey: NSFileType] isEqualToString: NSFileTypeSymbolicLink]  ) {
					if (  [gFileMgr fileExistsAtPath: oldConfigDirPath isDirectory: &isDir]  ) {
						if (  isDir  ) {
							// Move old configurations folder's contents to the new configurations folder and delete the old folder
							if (  moveContents(oldConfigDirPath, newConfigDirPath)  ) {
								appendLog([NSString stringWithFormat: @"Moved contents of %@ to %@", oldConfigDirPath, newConfigDirPath]);
								secureTblks = TRUE; // We may have moved some .tblks, so we should secure them
								// Delete the old configuration folder
								makeUnlockedAtPath(oldConfigDirPath);
								if (  ! [gFileMgr tbRemoveFileAtPath:oldConfigDirPath handler: nil]  ) {
									appendLog([NSString stringWithFormat: @"Unable to remove %@", oldConfigDirPath]);
									errorExit();
								}
							} else {
								appendLog([NSString stringWithFormat: @"Unable to move all contents of %@ to %@", oldConfigDirPath, newConfigDirPath]);
								errorExit();
							}
						} else {
							appendLog([NSString stringWithFormat: @"%@ is not a symbolic link or a folder", oldConfigDirPath]);
							errorExit();
						}
					}
				}
			} else {
				appendLog([NSString stringWithFormat: @"Warning: %@ exists but is not a folder", newConfigDirPath]);
				if ( secureTblks ) {
					errorExit();
				}
			}
		} else {
			appendLog([NSString stringWithFormat: @"Warning: Private configuration folder %@ does not exist", newConfigDirPath]);
			if ( secureTblks ) {
				errorExit();
			}
		}
	}
	
    //**************************************************************************************************************************
	// (3) If INSTALLER_CONVERT_NON_TBLKS, all .ovpn or .conf files are converted to .tblks
	//Axion Delete
	if (  convertNonTblks  ) {
		if ( ! tunnelblickTestPrivateOnlyHasTblks()  ) {
			appendLog(@"\nBeginning conversion of .ovpn and .conf configurations to .tblk configurations...");
			
			if (  ! convertAllPrivateOvpnAndConfToTblk()  ) {
				appendLog(@"Conversion of .ovpn and .conf configurations to .tblk configurations failed");
				errorExit();
			}
			
			secureTblks = TRUE;
			appendLog(@"Conversion of .ovpn and .conf configurations to .tblk configurations succeeded\n");
		}
	}
	
    //**************************************************************************************************************************
    // (4)
    // If INSTALLER_COPY_APP is set:
    //    Move /Applications/XXXXX.app to the Trash, then copy this app to /Applications/XXXXX.app
    
    if (  copyApp  ) {
        NSString * currentPath = [[[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
        NSString * targetPath  = @"/Applications/AxionVPN.app";
        if (  [gFileMgr fileExistsAtPath: targetPath]  ) {
            errorExitIfAnySymlinkInPath(targetPath, 1);
            if (  [[NSWorkspace sharedWorkspace] performFileOperation: NSWorkspaceRecycleOperation
                                                               source: @"/Applications"
                                                          destination: @""
                                                                files: [NSArray arrayWithObject: @"AxionVPN.app"]
                                                                  tag: nil]  ) {
                appendLog([NSString stringWithFormat: @"Moved %@ to the Trash", targetPath]);
            } else {
                appendLog([NSString stringWithFormat: @"Unable to move %@ to the Trash", targetPath]);
                errorExit();
            }
        }
        
        if (  ! [gFileMgr tbCopyPath: currentPath toPath: targetPath handler: nil]  ) {
            appendLog([NSString stringWithFormat: @"Unable to copy %@ to %@", currentPath, targetPath]);
            errorExit();
        } else {
            appendLog([NSString stringWithFormat: @"Copied %@ to %@", currentPath, targetPath]);
        }
    }
    
    //**************************************************************************************************************************
    //      (5) Renames /Library/LaunchDaemons/net.tunnelblick.startup.*
    //               to                        net.tunnelblick.tunnelblick.startup.*
    
    NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: @"/Library/LaunchDaemons"];
    NSString * file;
    NSString * oldPrefix = @"com.AxionVPN.startup.";
    NSString * newPrefix = @"com.AxionVPN.AxionVPN.startup.";
    while (  (file = [dirEnum nextObject])  ) {
        [dirEnum skipDescendents];
        if (  [file hasPrefix:  oldPrefix]) {
            NSString * newFile = [newPrefix stringByAppendingString: [file substringFromIndex: [oldPrefix length]]];
            NSString * newPath = [@"/Library/LaunchDaemons" stringByAppendingPathComponent: newFile];
            NSString * oldPath = [@"/Library/LaunchDaemons" stringByAppendingPathComponent: file];
            if (  0 == rename([oldPath fileSystemRepresentation], [newPath fileSystemRepresentation])  ) {
                appendLog([NSString stringWithFormat: @"Renamed %@ to %@", oldPath, newFile]);
            } else {
                appendLog([NSString stringWithFormat: @"Unable to rename %@ to %@; error = '%s' (%ld)",
                           oldPath, newFile, strerror(errno), (long)errno]);
                errorExit();
            }
            
        }
    }
    
    //**************************************************************************************************************************
    // (6)
    // If requested, secure AxionVPN.app by setting the ownership and permissions of it and all its components
    if ( secureApp ) {
        
        NSString *contentsPath				= [appResourcesPath stringByDeletingLastPathComponent];
        NSString *infoPlistPath				= [contentsPath stringByAppendingPathComponent: @"Info.plist"];
        NSString *openvpnstartPath          = [appResourcesPath stringByAppendingPathComponent:@"openvpnstart"                                   ];
        NSString *openvpnPath               = [appResourcesPath stringByAppendingPathComponent:@"openvpn"                                        ];
        NSString *atsystemstartPath         = [appResourcesPath stringByAppendingPathComponent:@"atsystemstart"                                  ];
        NSString *installerPath             = [appResourcesPath stringByAppendingPathComponent:@"installer"                                      ];
        NSString *ssoPath                   = [appResourcesPath stringByAppendingPathComponent:@"standardize-scutil-output"                      ];
        NSString *pncPath                   = [appResourcesPath stringByAppendingPathComponent:@"process-network-changes"                        ];
        NSString *tunnelblickdPath          = [appResourcesPath stringByAppendingPathComponent:@"tunnelblickd"                                   ];
        NSString *tunnelblickHelperPath     = [appResourcesPath stringByAppendingPathComponent:@"tunnelblick-helper"                             ];
        NSString *leasewatchPath            = [appResourcesPath stringByAppendingPathComponent:@"leasewatch"                                     ];
        NSString *leasewatch3Path           = [appResourcesPath stringByAppendingPathComponent:@"leasewatch3"                                    ];
        NSString *pncPlistPath              = [appResourcesPath stringByAppendingPathComponent:@"ProcessNetworkChanges.plist"                    ];
        NSString *leasewatchPlistPath       = [appResourcesPath stringByAppendingPathComponent:@"LeaseWatch.plist"                               ];
        NSString *leasewatch3PlistPath      = [appResourcesPath stringByAppendingPathComponent:@"LeaseWatch3.plist"                              ];
		NSString *launchAtLoginScriptPath   = [appResourcesPath stringByAppendingPathComponent:@"launchAtLogin.sh"                               ];
        NSString *clientUpPath              = [appResourcesPath stringByAppendingPathComponent:@"client.up.osx.sh"                               ];
        NSString *clientDownPath            = [appResourcesPath stringByAppendingPathComponent:@"client.down.osx.sh"                             ];
        NSString *clientNoMonUpPath         = [appResourcesPath stringByAppendingPathComponent:@"client.nomonitor.up.osx.sh"                     ];
        NSString *clientNoMonDownPath       = [appResourcesPath stringByAppendingPathComponent:@"client.nomonitor.down.osx.sh"                   ];
        NSString *clientNewUpPath           = [appResourcesPath stringByAppendingPathComponent:@"client.up.tunnelblick.sh"                       ];
        NSString *clientNewDownPath         = [appResourcesPath stringByAppendingPathComponent:@"client.down.tunnelblick.sh"                     ];
        NSString *clientNewRoutePreDownPath = [appResourcesPath stringByAppendingPathComponent:@"client.route-pre-down.tunnelblick.sh"           ];
        NSString *clientNewAlt1UpPath       = [appResourcesPath stringByAppendingPathComponent:@"client.1.up.tunnelblick.sh"                     ];
        NSString *clientNewAlt1DownPath     = [appResourcesPath stringByAppendingPathComponent:@"client.1.down.tunnelblick.sh"                   ];
        NSString *clientNewAlt2UpPath       = [appResourcesPath stringByAppendingPathComponent:@"client.2.up.tunnelblick.sh"                     ];
        NSString *clientNewAlt2DownPath     = [appResourcesPath stringByAppendingPathComponent:@"client.2.down.tunnelblick.sh"                   ];
        NSString *clientNewAlt3UpPath       = [appResourcesPath stringByAppendingPathComponent:@"client.3.up.tunnelblick.sh"                     ];
        NSString *clientNewAlt3DownPath     = [appResourcesPath stringByAppendingPathComponent:@"client.3.down.tunnelblick.sh"                   ];
        NSString *freePublicDnsServersPath  = [appResourcesPath stringByAppendingPathComponent:@"FreePublicDnsServersList.txt"                   ];
        NSString *iconSetsPath              = [appResourcesPath stringByAppendingPathComponent:@"IconSets"                                       ];
        
        // The names of our launchd .plists file should not change when rebranded, so we break the strings so that global search/replace doesn't see them
		NSString *launchAtLoginPlistPath    = [appResourcesPath stringByAppendingPathComponent:@"net.tunnelblick.tunnel" @"blick.LaunchAtLogin.plist"];
		NSString *tunnelblickdPlistPath     = [appResourcesPath stringByAppendingPathComponent:@"net.tunnelblick.tunnel" @"blick.tunnelblickd.plist"];
        
        NSString *tunnelblickPath = [contentsPath stringByDeletingLastPathComponent];
        
		BOOL okSoFar = checkSetOwnership(tunnelblickPath, YES, 0, 0);
        
        okSoFar = okSoFar && checkSetPermissions(infoPlistPath,             PERMS_SECURED_READABLE,   YES);
        
        okSoFar = okSoFar && checkSetPermissions(appResourcesPath,          PERMS_SECURED_FOLDER,     YES);

        okSoFar = okSoFar && checkSetPermissions(openvpnPath,               PERMS_SECURED_FOLDER,     YES);

        okSoFar = okSoFar && checkSetPermissions(openvpnstartPath,          PERMS_SECURED_EXECUTABLE, YES);
        
        okSoFar = okSoFar && checkSetPermissions(launchAtLoginScriptPath,   PERMS_SECURED_EXECUTABLE, YES);
		
        okSoFar = okSoFar && checkSetPermissions(atsystemstartPath,         PERMS_SECURED_ROOT_EXEC,  YES);
        okSoFar = okSoFar && checkSetPermissions(installerPath,             PERMS_SECURED_ROOT_EXEC,  YES);
        okSoFar = okSoFar && checkSetPermissions(leasewatchPath,            PERMS_SECURED_ROOT_EXEC,  YES);
        okSoFar = okSoFar && checkSetPermissions(leasewatch3Path,           PERMS_SECURED_ROOT_EXEC,  YES);
        okSoFar = okSoFar && checkSetPermissions(pncPath,                   PERMS_SECURED_ROOT_EXEC,  YES);
        okSoFar = okSoFar && checkSetPermissions(ssoPath,                   PERMS_SECURED_ROOT_EXEC,  YES);
        okSoFar = okSoFar && checkSetPermissions(tunnelblickdPath,          PERMS_SECURED_ROOT_EXEC,  ( ! helperIsToBeSuid));
        
        okSoFar = okSoFar && checkSetPermissions(pncPlistPath,              PERMS_SECURED_READABLE,   YES);
        okSoFar = okSoFar && checkSetPermissions(leasewatchPlistPath,       PERMS_SECURED_READABLE,   YES);
        okSoFar = okSoFar && checkSetPermissions(leasewatch3PlistPath,      PERMS_SECURED_READABLE,   YES);
        okSoFar = okSoFar && checkSetPermissions(launchAtLoginPlistPath,    PERMS_SECURED_READABLE,   YES);
        okSoFar = okSoFar && checkSetPermissions(tunnelblickdPlistPath,     PERMS_SECURED_READABLE,   ( ! helperIsToBeSuid));
        okSoFar = okSoFar && checkSetPermissions(freePublicDnsServersPath,  PERMS_SECURED_READABLE,   YES);
        
        okSoFar = okSoFar && checkSetPermissions(clientUpPath,              PERMS_SECURED_ROOT_EXEC,  NO);
        okSoFar = okSoFar && checkSetPermissions(clientDownPath,            PERMS_SECURED_ROOT_EXEC,  NO);
        okSoFar = okSoFar && checkSetPermissions(clientNoMonUpPath,         PERMS_SECURED_ROOT_EXEC,  NO);
        okSoFar = okSoFar && checkSetPermissions(clientNoMonDownPath,       PERMS_SECURED_ROOT_EXEC,  NO);
        okSoFar = okSoFar && checkSetPermissions(clientNewUpPath,           PERMS_SECURED_ROOT_EXEC,  YES);
        okSoFar = okSoFar && checkSetPermissions(clientNewDownPath,         PERMS_SECURED_ROOT_EXEC,  YES);
        okSoFar = okSoFar && checkSetPermissions(clientNewRoutePreDownPath, PERMS_SECURED_ROOT_EXEC,  YES);
        okSoFar = okSoFar && checkSetPermissions(clientNewAlt1UpPath,       PERMS_SECURED_ROOT_EXEC,  YES);
        okSoFar = okSoFar && checkSetPermissions(clientNewAlt1DownPath,     PERMS_SECURED_ROOT_EXEC,  YES);
        okSoFar = okSoFar && checkSetPermissions(clientNewAlt2UpPath,       PERMS_SECURED_ROOT_EXEC,  YES);
        okSoFar = okSoFar && checkSetPermissions(clientNewAlt2DownPath,     PERMS_SECURED_ROOT_EXEC,  YES);
        okSoFar = okSoFar && checkSetPermissions(clientNewAlt3UpPath,       PERMS_SECURED_ROOT_EXEC,  YES);
        okSoFar = okSoFar && checkSetPermissions(clientNewAlt3DownPath,     PERMS_SECURED_ROOT_EXEC,  YES);
        
        // Check/set OpenVPN version folders and openvpn and openvpn-down-root.so in them
        NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: openvpnPath];
        NSString * file;
        BOOL isDir;
        while (  (file = [dirEnum nextObject])  ) {
			[dirEnum skipDescendents];
            NSString * fullPath = [openvpnPath stringByAppendingPathComponent: file];
            if (   [gFileMgr fileExistsAtPath: fullPath isDirectory: &isDir]
                && isDir  ) {
                if (  [file hasPrefix: @"openvpn-"]  ) {
                    okSoFar = okSoFar && checkSetPermissions(fullPath, PERMS_SECURED_FOLDER, YES);
                    
                    NSString * thisOpenvpnPath = [fullPath stringByAppendingPathComponent: @"openvpn"];
                    okSoFar = okSoFar && checkSetPermissions(thisOpenvpnPath, PERMS_SECURED_EXECUTABLE, YES);
                    
                    NSString * thisOpenvpnDownRootPath = [fullPath stringByAppendingPathComponent: @"openvpn-down-root.so"];
                    okSoFar = okSoFar && checkSetPermissions(thisOpenvpnDownRootPath, PERMS_SECURED_ROOT_EXEC, NO);
                }
            }
        }
        
		// Secure _CodeSignature if it is present. All of its contents should have 0644 permissions
		NSString * codeSigPath = [contentsPath stringByAppendingPathComponent: @"_CodeSignature"];
		if (   [gFileMgr fileExistsAtPath: codeSigPath isDirectory: &isDir]
			&& isDir  ) {
			okSoFar = okSoFar && checkSetPermissions(codeSigPath, PERMS_SECURED_FOLDER, YES);
			dirEnum = [gFileMgr enumeratorAtPath: codeSigPath];
			while (  (file = [dirEnum nextObject])  ) {
				NSString * itemPath = [codeSigPath stringByAppendingPathComponent: file];
				okSoFar = okSoFar && checkSetPermissions(itemPath, 0644, YES);
			}
		}
		

		
        // Secure IconSets
        if (   [gFileMgr fileExistsAtPath: iconSetsPath isDirectory: &isDir]
            && isDir  ) {
			okSoFar = okSoFar && secureOneFolder(iconSetsPath, NO, 0);
        } else {
            appendLog([NSString stringWithFormat: @"Missing IconSets folder, which should be at %@", iconSetsPath]);
            errorExit();
        }
        
		// Secure the app's Deploy folder
        if (   [gFileMgr fileExistsAtPath: gDeployPath isDirectory: &isDir]
            && isDir  ) {
			okSoFar = okSoFar && secureOneFolder(gDeployPath, NO, 0);
        }
		
		// Save this for last, so if something goes wrong, it isn't SUID inside a damaged app
		if (  okSoFar  ) {
            okSoFar = okSoFar && checkSetPermissions(tunnelblickHelperPath, (helperIsToBeSuid ? PERMS_SECURED_SUID : PERMS_SECURED_EXECUTABLE), YES);
        }
        
		if (  ! okSoFar  ) {
            appendLog(@"Unable to secure AxionVPN.app");
            errorExit();
        }
    }
    
    //**************************************************************************************************************************
    // (7) If INSTALLER_COPY_APP, L_AS_T_TBLKS is pruned by removing all but the highest edition of each container
    
    if (  copyApp  ) {
        pruneL_AS_T_TBLKS();
    }
    
    //**************************************************************************************************************************
    // (8)
    // If requested, secure all .tblk packages
    if (  secureTblks  ) {
        NSString * altPath = [L_AS_T_USERS stringByAppendingPathComponent: NSUserName()];

        // First, copy any .tblks that are in private to alt (unless they are already there)
        NSString * file;
        NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: gPrivatePath];
        while (  (file = [dirEnum nextObject])  ) {
			if (  [[file pathExtension] isEqualToString: @"tblk"]  ) {
				[dirEnum skipDescendents];
                NSString * privateTblkPath = [gPrivatePath stringByAppendingPathComponent: file];
                NSString * altTblkPath     = [altPath stringByAppendingPathComponent: file];
                if (  ! [gFileMgr fileExistsAtPath: altTblkPath]  ) {
					if (  ! createDirWithPermissionAndOwnership([altTblkPath stringByDeletingLastPathComponent], PERMS_SECURED_FOLDER, 0, 0)  ) {
						errorExit();
					}
                    if (  [gFileMgr tbCopyPath: privateTblkPath toPath: altTblkPath handler: nil]  ) {
                        appendLog([NSString stringWithFormat: @"Created shadow copy of %@", privateTblkPath]);
                    } else {
                        appendLog([NSString stringWithFormat: @"Unable to create shadow copy of %@", privateTblkPath]);
                        errorExit();
                    }
				}
            }
        }
        
        // Now secure shared tblks, private tblks, and shadow copies of private tblks 
        
        NSArray * foldersToSecure = [NSArray arrayWithObjects: L_AS_T_SHARED, gPrivatePath, altPath, nil];
        
        BOOL okSoFar = YES;
        unsigned i;
        for (i=0; i < [foldersToSecure count]; i++) {
            NSString * folderPath = [foldersToSecure objectAtIndex: i];
            BOOL isPrivate = [folderPath hasPrefix: gPrivatePath];
            okSoFar = okSoFar && secureOneFolder(folderPath, isPrivate, gRealUserID);
		}
        
        if (  ! okSoFar  ) {
            appendLog([NSString stringWithFormat: @"Warning: Unable to secure all .tblk packages"]);
        }
    }
    
    //**************************************************************************************************************************
    // (9)
    // If requested, copy or move a .tblk package (also move/copy/create a shadow copy if a private configuration)
    // Like the NSFileManager "movePath:toPath:handler" method, we move by copying, then deleting, because we may be moving
    // from one disk to another (e.g., home folder on network to local hard drive)
    
    //MIKE
    if (   secondPath
        && ( ! deleteConfig )  ) {
		
		NSString * sourcePath = [[secondPath copy] autorelease];
		NSString * targetPath = [[firstPath  copy] autorelease];
        
        // Make sure we are dealing with .tblks
        if (  ! [[sourcePath pathExtension] isEqualToString: @"tblk"]  ) {
            appendLog([NSString stringWithFormat: @"Only .tblks may be copied or moved: Not a .tblk: %@", sourcePath]);
            errorExit();
        }
        if (  ! [[targetPath pathExtension] isEqualToString: @"tblk"]  ) {
            appendLog([NSString stringWithFormat: @"Only .tblks may be copied or moved: Not a .tblk: %@", targetPath]);
            errorExit();
        }

        // Create the enclosing folder(s) if necessary. Owned by root unless if in gPrivatePath, in which case it is owned by the user
        NSString * enclosingFolder = [targetPath stringByDeletingLastPathComponent];
        uid_t  own   = 0;
        gid_t  grp   = 0;
		mode_t perms = PERMS_SECURED_FOLDER;
		
        if (  [targetPath hasPrefix: [gPrivatePath stringByAppendingString: @"/"]]  ) {
            own   = gRealUserID;
            grp   = ADMIN_GROUP_ID;
			perms = PERMS_PRIVATE_FOLDER;
        }
        errorExitIfAnySymlinkInPath(enclosingFolder, 2);
        
        if (  ! createDirWithPermissionAndOwnership(enclosingFolder, perms, own, grp)  ) {
            errorExit();
        }
        
        // Make sure we can delete the original if we are moving instead of copying
        if (  moveNotCopy  ) {
            if (  ! makeUnlockedAtPath(targetPath)  ) {
                errorExit();
            }
        }
        
		// Resolve symlinks
		//
        // Do the move or copy
        //
		// Secure the target
		//
        // If   we MOVED OR COPIED TO PRIVATE
        // Then create a shadow copy of the target and secure the shadow copy
        //
        // If   we MOVED FROM PRIVATE
        // Then delete the shadow copy of the target

        resolveSymlinksInPath(sourcePath);
		
        safeCopyOrMovePathToPath(sourcePath, targetPath, moveNotCopy);
		
		BOOL targetIsPrivate = [targetPath hasPrefix: [gPrivatePath stringByAppendingString: @"/"]];
		uid_t uid = (  targetIsPrivate
					 ? gRealUserID
					 : 0);
		secureOneFolder(targetPath, targetIsPrivate, uid);

        
		NSString * lastPartOfTarget = lastPartOfPath(targetPath);
        
#ifdef AXION_DONT_BUILD
        if (   targetIsPrivate  ) {
			
            NSString * shadowTargetPath   = [NSString stringWithFormat: @"%@/%@/%@",
                                             L_AS_T_USERS,
                                             NSUserName(),
                                             lastPartOfTarget];
            
			errorExitIfAnySymlinkInPath(shadowTargetPath, 2);
			
            BOOL deletedOldShadowCopy = FALSE;
			if (  [gFileMgr fileExistsAtPath: shadowTargetPath]  ) {
				if (  ! deleteThingAtPath(shadowTargetPath)  ) {
					errorExit();
				}
                
                deletedOldShadowCopy = TRUE;
			}
			
			// Create container for shadow copy
			enclosingFolder = [shadowTargetPath stringByDeletingLastPathComponent];
			if (   ( ! [gFileMgr fileExistsAtPath: shadowTargetPath isDirectory: &isDir])
				&& isDir  ) {
				errorExitIfAnySymlinkInPath(enclosingFolder, 2);
				createDirWithPermissionAndOwnership(enclosingFolder, PERMS_SECURED_FOLDER, 0, 0);
			}
			
			safeCopyOrMovePathToPath(targetPath, shadowTargetPath, FALSE);	// Copy the target because the source may have _moved_ to the target
            
            secureOneFolder(shadowTargetPath, NO, 0);
            
            if (  deletedOldShadowCopy  ) {
                appendLog([NSString stringWithFormat: @"Updated secure (shadow) copy of %@", lastPartOfTarget]);
            } else {
                appendLog([NSString stringWithFormat: @"Created secure (shadow) copy of %@", lastPartOfTarget]);
            }
        }
#endif
        
        
        if (  [sourcePath hasPrefix: [gPrivatePath stringByAppendingString: @"/"]]  ) {
            if (  moveNotCopy  ) {
                NSString * lastPartOfSource = lastPartOfPath(sourcePath);
                NSString * shadowSourcePath   = [NSString stringWithFormat: @"%@/%@/%@",
                                                 L_AS_T_USERS,
                                                 NSUserName(),
                                                 lastPartOfSource];
				if (  [gFileMgr fileExistsAtPath: shadowSourcePath]  ) {
					if (  ! deleteThingAtPath(shadowSourcePath)  ) {
						errorExit();
					}
                }
				appendLog([NSString stringWithFormat: @"Deleted secure (shadow) copy of %@", lastPartOfSource]);
            }
        }
    }
    
    
    //**************************************************************************************************************************
    // (10)
    // If requested, secure a single file or .tblk package
    if (   firstPath
        && ( ! secondPath   )
        && ( ! deleteConfig )  ) {
        
        // Make sure we are dealing with .tblks
        if (  ! [[firstPath pathExtension] isEqualToString: @"tblk"]  ) {
            appendLog([NSString stringWithFormat: @"Only .tblks may be copied or moved: Not a .tblk: %@", firstPath]);
            errorExit();
        }

        BOOL okSoFar = TRUE;
        NSString * ext = [firstPath pathExtension];
        if (  [ext isEqualToString: @"ovpn"] || [ext isEqualToString: @"conf"]  ) {
            if (  [firstPath hasPrefix: [gPrivatePath stringByAppendingString: @"/"]]  ) {
                okSoFar = okSoFar && checkSetOwnership(firstPath, NO, gRealUserID, gRealGroupID);
            } else {
                okSoFar = okSoFar && checkSetOwnership(firstPath, NO, 0, 0);
            }
            okSoFar = okSoFar && checkSetPermissions(firstPath, 0644, YES);
        } else if (  [ext isEqualToString: @"tblk"]  ) {
            BOOL isPrivate = [firstPath hasPrefix: [gPrivatePath stringByAppendingString: @"/"]];
            okSoFar = okSoFar && secureOneFolder(firstPath, isPrivate, gRealUserID);
        } else {
            appendLog([NSString stringWithFormat: @"trying to secure unknown item at %@", firstPath]);
            errorExit();
        }
        if (  ! okSoFar  ) {
            appendLog([NSString stringWithFormat: @"unable to secure %@", firstPath]);
            errorExit();
        }
    }
    
    //**************************************************************************************************************************
    // (11)
    // If requested, delete a single file or .tblk package (also deletes the shadow copy if deleting a private configuration)
    if (   firstPath
        && deleteConfig  ) {
        NSString * ext = [firstPath pathExtension];
        if (  [ext isEqualToString: @"tblk"]  ) {
            if (  [gFileMgr fileExistsAtPath: firstPath]  ) {
                errorExitIfAnySymlinkInPath(firstPath, 6);
				makeUnlockedAtPath(firstPath);
                if (  ! [gFileMgr tbRemoveFileAtPath: firstPath handler: nil]  ) {
                    appendLog([NSString stringWithFormat: @"unable to remove %@", firstPath]);
                } else {
                    appendLog([NSString stringWithFormat: @"removed %@", firstPath]);
                }
                
                // Delete shadow copy, too, if it exists
                if (  [firstPartOfPath(firstPath) isEqualToString: gPrivatePath]  ) {
                    NSString * shadowCopyPath = [NSString stringWithFormat: @"%@/%@/%@",
                                                 L_AS_T_USERS,
                                                 NSUserName(),
                                                 lastPartOfPath(firstPath)];
                    if (  [gFileMgr fileExistsAtPath: shadowCopyPath]  ) {
                        errorExitIfAnySymlinkInPath(shadowCopyPath, 7);
						makeUnlockedAtPath(shadowCopyPath);
                        if (  ! [gFileMgr tbRemoveFileAtPath: shadowCopyPath handler: nil]  ) {
                            appendLog([NSString stringWithFormat: @"unable to remove %@", shadowCopyPath]);
                        } else {
                            appendLog([NSString stringWithFormat: @"removed %@", shadowCopyPath]);
                        }
                    }
                }
            }
        } else {
            appendLog([NSString stringWithFormat: @"trying to remove unknown item at %@", firstPath]);
            errorExit();
        }
    }
    
    //**************************************************************************************************************************
    // (12) Set up tunnelblickd to load when the computer starts
	
	if (  ! helperIsToBeSuid  ) {
		// Check to see if the tunnelblickd .plist file is up-to-date
		// If we are debugging, it needs the 'Debug' key set and the the 'Program' value pointing to our copy of tunnelblickd
		
		// NOTE: The name of the tunnelblickd .plist file in Resources does not change when rebranded, hence the split constant strings when referring to it
		NSString * ourPlistPath = [resourcesPath stringByAppendingPathComponent: @"net.tunnel" @"blick.tunnel" @"blick.tunnelblickd.plist"];
		
		NSMutableDictionary * newPlistContents = [[[NSDictionary dictionaryWithContentsOfFile: ourPlistPath] mutableCopy] autorelease];
		
#ifdef TBDebug
		NSString * daemonPath = [resourcesPath stringByAppendingPathComponent: @"tunnelblickd"];
		[newPlistContents setObject: daemonPath                     forKey: @"Program"];
		[newPlistContents setObject: [NSNumber numberWithBool: YES] forKey: @"Debug"];
		NSDictionary * installedPlistContents = nil; // Force install or replace of plist
#else
		NSDictionary * installedPlistContents = [NSDictionary dictionaryWithContentsOfFile: TUNNELBLICKD_PLIST_PATH];
#endif
		
		if (  ! [installedPlistContents isEqualToDictionary: newPlistContents]  ) {
			
			// Install or replace the tunnelblickd .plist in /Library/LaunchDaemons
			
			BOOL hadExistingPlist = [gFileMgr fileExistsAtPath: TUNNELBLICKD_PLIST_PATH];
			if (  hadExistingPlist  ) {
				if (  ! [gFileMgr tbRemoveFileAtPath: TUNNELBLICKD_PLIST_PATH handler: nil]  ) {
					appendLog([NSString stringWithFormat: @"Unable to delete %@", TUNNELBLICKD_PLIST_PATH]);
					errorExit();
				}
			}
			if (  [newPlistContents writeToFile: TUNNELBLICKD_PLIST_PATH atomically: YES] ) {
                if (  ! checkSetOwnership(TUNNELBLICKD_PLIST_PATH, NO, 0, 0)  ) {
                    errorExit();
                }
                if (  ! checkSetPermissions(TUNNELBLICKD_PLIST_PATH, PERMS_SECURED_READABLE, YES)  ) {
                    errorExit();
                }
				appendLog([NSString stringWithFormat: @"%@ %@", (hadExistingPlist ? @"Replaced" : @"Installed"), TUNNELBLICKD_PLIST_PATH]);
			} else {
				appendLog([NSString stringWithFormat: @"Unable to create %@", TUNNELBLICKD_PLIST_PATH]);
				errorExit();
			}
		} else {
            if (  ! checkSetOwnership(TUNNELBLICKD_PLIST_PATH, NO, 0, 0)  ) {
                errorExit();
            }
            if (  ! checkSetPermissions(TUNNELBLICKD_PLIST_PATH, PERMS_SECURED_READABLE, YES)  ) {
                errorExit();
            }
        }
		
        // We must load the new launch daemon, too, so it is used immediately, even before the next system start
        loadLaunchDaemon(newPlistContents, forceLoadLaunchDaemon);
	}
	
    //**************************************************************************************************************************
    // DONE
    
	appendLog(@"AxionVPN installer finished without error");
	
    deleteFlagFile(AUTHORIZED_ERROR_PATH);
    deleteFlagFile(AUTHORIZED_RUNNING_PATH);
	closeLog();
    
    [pool release];
    exit(EXIT_SUCCESS);
}

//**************************************************************************************************************************
void safeCopyOrMovePathToPath(NSString * fromPath, NSString * toPath, BOOL moveNotCopy)
{
	// Copies or moves a folder, but unlocks everything in the copy (or target, if it is a move)
	
    // Copy the file or package to a ".temp" file/folder first, then rename it
    // This avoids a race condition: folder change handling code runs while copy is being made, so it sometimes can
    // see the .tblk (which has been copied) but not the config.ovpn (which hasn't been copied yet), so it complains.
    NSString * dotTempPath = [toPath stringByAppendingPathExtension: @"temp"];
    errorExitIfAnySymlinkInPath(dotTempPath, 3);
    [gFileMgr tbRemoveFileAtPath:dotTempPath handler: nil];
    if (  ! [gFileMgr tbCopyPath: fromPath toPath: dotTempPath handler: nil]  ) {
        appendLog([NSString stringWithFormat: @"Failed to copy %@ to %@", fromPath, dotTempPath]);
        [gFileMgr tbRemoveFileAtPath:dotTempPath handler: nil];
        errorExit();
	}
	appendLog([NSString stringWithFormat: @"Copied %@\n    to %@", fromPath, dotTempPath]);
    
    // Make sure everything in the copy is unlocked
    makeUnlockedAtPath(dotTempPath);
    NSString * file;
    NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: dotTempPath];
    while (  (file = [dirEnum nextObject])  ) {
        makeUnlockedAtPath([dotTempPath stringByAppendingPathComponent: file]);
    }
    
    // Now, if we are doing a move, delete the original file, to avoid a similar race condition that will cause a complaint
    // about duplicate configuration names.
    if (  moveNotCopy  ) {
        errorExitIfAnySymlinkInPath(fromPath, 4);
		makeUnlockedAtPath(fromPath);
        if (  ! deleteThingAtPath(fromPath)  ) {
            errorExit();
        }
    }
    
    errorExitIfAnySymlinkInPath(toPath, 5);
	makeUnlockedAtPath(toPath);
    [gFileMgr tbRemoveFileAtPath:toPath handler: nil];
    int status = rename([dotTempPath fileSystemRepresentation], [toPath fileSystemRepresentation]);
    if (  status != 0 ) {
        appendLog([NSString stringWithFormat: @"Failed to rename %@ to %@; error was %d: '%s'", dotTempPath, toPath, errno, strerror(errno)]);
        [gFileMgr tbRemoveFileAtPath:dotTempPath handler: nil];
        errorExit();
    }
    
    appendLog([NSString stringWithFormat: @"Renamed %@\n     to %@", dotTempPath, toPath]);
}

//**************************************************************************************************************************
BOOL deleteThingAtPath(NSString * path)
{
    errorExitIfAnySymlinkInPath(path, 8);
	makeUnlockedAtPath(path);
    if (  ! [gFileMgr tbRemoveFileAtPath: path handler: nil]  ) {
        appendLog([NSString stringWithFormat: @"Failed to delete %@", path]);
        return FALSE;
    } else {
        appendLog([NSString stringWithFormat: @"Deleted %@", path]);
    }
    
    return TRUE;
}


//**************************************************************************************************************************
BOOL moveContents(NSString * fromPath, NSString * toPath)
{
    NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: fromPath];
    NSString * file;
    while (  (file = [dirEnum nextObject])  ) {
        [dirEnum skipDescendents];
        if (  ! [file hasPrefix: @"."]  ) {
            NSString * fullFromPath = [fromPath stringByAppendingPathComponent: file];
            NSString * fullToPath   = [toPath   stringByAppendingPathComponent: file];
            if (  [gFileMgr fileExistsAtPath: fullToPath]  ) {
                appendLog([NSString stringWithFormat: @"Unable to move %@ to %@ because the destination already exists", fullFromPath, fullToPath]);
                return NO;
            } else {
                if (  ! [gFileMgr tbMovePath: fullFromPath toPath: fullToPath handler: nil]  ) {
                    appendLog([NSString stringWithFormat: @"Unable to move %@ to %@", fullFromPath, fullToPath]);
                    return NO;
                }
            }
        }
    }
    
    return YES;
}

//**************************************************************************************************************************
BOOL makeOneItemUnlockedAtPath(NSString * path)
{
    NSDictionary * curAttributes;
    NSDictionary * newAttributes = [NSDictionary dictionaryWithObject: [NSNumber numberWithInt:0] forKey: NSFileImmutable];
    
    unsigned i;
    unsigned maxTries = 5;
    for (i=0; i <= maxTries; i++) {
        curAttributes = [gFileMgr tbFileAttributesAtPath: path traverseLink:YES];
        if (  ! [curAttributes fileIsImmutable]  ) {
            break;
        }
        [gFileMgr tbChangeFileAttributes: newAttributes atPath: path];
        appendLog([NSString stringWithFormat: @"Unlocked %@", path]);
		if (  i != 0  ) {
			sleep(1);
		}
	}
    
    if (  [curAttributes fileIsImmutable]  ) {
        appendLog([NSString stringWithFormat: @"Failed to unlock %@ in %d attempts", path, maxTries]);
        return FALSE;
    }
	
    return TRUE;
}

//**************************************************************************************************************************
BOOL makeUnlockedAtPath(NSString * path)
{
	// To make a file hierarchy unlocked, we have to first unlock everything inside the hierarchy
	
	BOOL isDir;
	if (   [gFileMgr fileExistsAtPath: path isDirectory: &isDir]
		&& isDir  ) {
		NSString * file;
		NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: path];
		while (  (file = [dirEnum nextObject])  ) {
			makeUnlockedAtPath([path stringByAppendingPathComponent: file]);
		}
	}
	
	// Then we unlock the root of the hierarchy
	return makeOneItemUnlockedAtPath(path);
}

//**************************************************************************************************************************
void errorExitIfAnySymlinkInPath(NSString * path, int testPoint)
{
    NSString * curPath = path;
    while (   curPath
           && ! [curPath isEqualToString: @"/"]  ) {
        if (  [gFileMgr fileExistsAtPath: curPath]  ) {
            NSDictionary * fileAttributes = [gFileMgr tbFileAttributesAtPath: curPath traverseLink: NO];
            if (  [[fileAttributes objectForKey: NSFileType] isEqualToString: NSFileTypeSymbolicLink]  ) {
                appendLog([NSString stringWithFormat: @"Apparent symlink attack detected at test point %d: Symlink is at %@, full path being tested is %@", testPoint, curPath, path]);
                errorExit();
            }
        }
        
        curPath = [curPath stringByDeletingLastPathComponent];
    }
}

NSString * firstPartOfPath(NSString * path)
{
    NSArray * paths = [NSArray arrayWithObjects:
                       gPrivatePath,
                       gDeployPath,
                       L_AS_T_SHARED, nil];
    NSEnumerator * arrayEnum = [paths objectEnumerator];
    NSString * configFolder;
    while (  (configFolder = [arrayEnum nextObject])  ) {
        if (  [path hasPrefix: [configFolder stringByAppendingString: @"/"]]  ) {
            return configFolder;
        }
    }
    return nil;
}

NSString * lastPartOfPath(NSString * path)
{
    
    NSArray * paths = [NSArray arrayWithObjects:
                       gPrivatePath,
                       gDeployPath,
                       L_AS_T_SHARED, nil];
    NSEnumerator * arrayEnum = [paths objectEnumerator];
    NSString * configFolder;
    while (  (configFolder = [arrayEnum nextObject])  ) {
        if (  [path hasPrefix: [configFolder stringByAppendingString: @"/"]]  ) {
            if (  [path length] > [configFolder length]  ) {
                return [path substringFromIndex: [configFolder length]+1];
            } else {
                appendLog([NSString stringWithFormat: @"No display name in path '%@'", path]);
                return @"X";
            }
        }
    }
    return nil;
}

BOOL tunnelblickTestPrivateOnlyHasTblks(void)
{
	NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: gPrivatePath];
	NSString * file;
	while (  (file = [dirEnum nextObject])  ) {
		if (  [[file pathExtension] isEqualToString: @"tblk"]  ) {
			[dirEnum skipDescendents];
		} else {
			if (   [[file pathExtension] isEqualToString: @"ovpn"]
				|| [[file pathExtension] isEqualToString: @"conf"]  ) {
				return NO;
			}
		}
	}
	
	return YES;
}

BOOL copyTblksToNewFolder(NSString * newFolder)
{
    NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: gPrivatePath];
    NSString * file;
    
    while (  (file = [dirEnum nextObject])  ) {
        NSString * inPath = [gPrivatePath stringByAppendingPathComponent: file];
        if (  itemIsVisible(inPath)  ) {
            if (  [[file pathExtension] isEqualToString: @"tblk"]  ) {
                NSString * outPath = [newFolder stringByAppendingPathComponent: file];
				NSString * outPathFolder = [outPath stringByDeletingLastPathComponent];
				if (  ! createDirWithPermissionAndOwnership(outPathFolder, PERMS_PRIVATE_FOLDER, gRealUserID, ADMIN_GROUP_ID)  ) {
                    appendLog([NSString stringWithFormat: @"Unable to create %@", outPathFolder]);
                    return FALSE;
				}
                if (  ! [gFileMgr tbCopyPath: inPath toPath: outPath handler: nil]  ) {
                    appendLog([NSString stringWithFormat: @"Unable to copy %@ to %@", inPath, outPath]);
                    return FALSE;
                } else {
                    appendLog([NSString stringWithFormat: @"Copied %@", file]);
				}
                
                [dirEnum skipDescendents];
            }
        }
    }
    
    return TRUE;
}

BOOL convertAllPrivateOvpnAndConfToTblk(void)
{
    NSString * newFolder = [[gPrivatePath stringByDeletingLastPathComponent] stringByAppendingPathComponent: @"NewConfigurations"];
    NSString * logPath = [newFolder stringByAppendingPathComponent: @"Conversion.log"];
    
    [gFileMgr tbRemoveFileAtPath: logPath   handler: nil];
    [gFileMgr tbRemoveFileAtPath: newFolder handler: nil];
    
	BOOL haveDoneConversion = FALSE;
	
    NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: gPrivatePath];
    NSString * file;
    while (  (file = [dirEnum nextObject])  ) {
        NSString * inPath = [gPrivatePath stringByAppendingPathComponent: file];
		NSString * ext = [file pathExtension];
        if (  itemIsVisible(inPath)  ) {
            if (  [ext isEqualToString: @"tblk"]  ) {
                [dirEnum skipDescendents];
            } else if (   [ext isEqualToString: @"ovpn"]
                       ||  [ext isEqualToString: @"conf"]  ) {
                NSString * fileWithoutExtension = [file stringByDeletingPathExtension];
                NSString * outTblkPath = [newFolder stringByAppendingPathComponent:
										  [fileWithoutExtension stringByAppendingPathExtension: @"tblk"]];
                NSString * outTblkPathButInExistingConfigurationsFolder = [gPrivatePath stringByAppendingPathComponent:
										  [fileWithoutExtension stringByAppendingPathExtension: @"tblk"]];
                if (   [gFileMgr fileExistsAtPath: outTblkPath]
					|| [gFileMgr fileExistsAtPath: outTblkPathButInExistingConfigurationsFolder]  ) {
					fileWithoutExtension = [[fileWithoutExtension stringByAppendingString: @" from "]
											stringByAppendingString: ext];
					outTblkPath = [newFolder stringByAppendingPathComponent:
								   [fileWithoutExtension stringByAppendingPathExtension: @"tblk"]];
					outTblkPathButInExistingConfigurationsFolder = [gPrivatePath stringByAppendingPathComponent:
																	[fileWithoutExtension stringByAppendingPathExtension: @"tblk"]];
					if (   [gFileMgr fileExistsAtPath: outTblkPath]
						|| [gFileMgr fileExistsAtPath: outTblkPathButInExistingConfigurationsFolder]  ) {
						appendLog([NSString stringWithFormat: @"Unable to construct name for a .tblk for %@", file]);
						return FALSE;
					}
				}
				NSString * inConfPath = [gPrivatePath stringByAppendingPathComponent: file];
                
				if (  ! createDirWithPermissionAndOwnership(newFolder, PERMS_PRIVATE_FOLDER, gRealUserID, ADMIN_GROUP_ID)  ) {
                    appendLog([NSString stringWithFormat: @"Unable to create %@", newFolder]);
                    return FALSE;
                };
                
                ConfigurationConverter * converter = [[ConfigurationConverter alloc] init];
				NSString * conversionResults = [converter convertConfigPath: inConfPath
																 outputPath: outTblkPath
                                                          replacingTblkPath: nil
                                                                displayName: nil
													   nameForErrorMessages: inConfPath
                                                           useExistingFiles: nil
																	logFile: gLogFile
																   fromTblk: NO];
                [converter release];
                
                if (  conversionResults  ) {
                    appendLog([NSString stringWithFormat: @"Unable to convert %@ to a Tunnelblick private Configuration: %@", inConfPath, conversionResults]);
                    return FALSE;
                }
				
				haveDoneConversion = TRUE;
            }
        }
    }
	
	if (  haveDoneConversion  ) {
		if ( ! copyTblksToNewFolder(newFolder)  ) {
            appendLog(@"Unable to copy existing private .tblk configurations");
            return FALSE;
		}
		
		NSDateFormatter * f = [[[NSDateFormatter alloc] init] autorelease];
		[f setFormatterBehavior: NSDateFormatterBehavior10_4];
		[f setDateFormat: @"yyyy-MM-dd hh.mm.ss"];
		NSString * dateTimeString = [f stringFromDate: [NSDate date]];
		
		NSString * oldFolder = [[newFolder stringByDeletingLastPathComponent]
								stringByAppendingPathComponent:
								[NSString stringWithFormat: @"Configurations before conversion %@", dateTimeString]];
		if (  [gFileMgr tbMovePath: gPrivatePath toPath: oldFolder handler: nil]  ) {
			if  (  [gFileMgr tbMovePath: newFolder toPath: gPrivatePath handler: nil]  ) {
                return TRUE;
			} else {
				[gFileMgr tbMovePath: oldFolder toPath: gPrivatePath handler: nil]; // Try to restore original setup
				appendLog([NSString stringWithFormat: @"Unable to rename %@ to %@", newFolder, gPrivatePath]);
                return FALSE;
			}
		} else {
			appendLog([NSString stringWithFormat: @"Unable to rename %@ to %@", gPrivatePath, oldFolder]);
			return FALSE;
		}
	} else {
        appendLog(@"No private .ovpn or .conf configurations to be converted");
		[gFileMgr tbRemoveFileAtPath: newFolder handler: nil];
    }
    
    return TRUE;
}
