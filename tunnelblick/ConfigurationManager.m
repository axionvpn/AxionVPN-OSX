/*
 * Copyright 2010, 2011, 2012, 2013, 2014 Jonathan K. Bullard. All rights reserved.
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

#import "ConfigurationManager.h"

#import <sys/param.h>
#import <sys/mount.h>
#import <unistd.h>

#import "defines.h"
#import "helper.h"
#import "sharedRoutines.h"

#import "ConfigurationConverter.h"
#import "ConfigurationMultiUpdater.h"
#import "ListingWindowController.h"
#import "MenuController.h"
#import "MyPrefsWindowController.h"
#import "NSApplication+LoginItem.h"
#import "NSFileManager+TB.h"
#import "NSString+TB.h"
#import "TBUserDefaults.h"
#import "VPNConnection.h"

extern NSMutableArray       * gConfigDirs;
extern NSArray              * gConfigurationPreferences;
extern NSString             * gPrivatePath;
extern NSString             * gDeployPath;
extern NSFileManager        * gFileMgr;
extern TBUserDefaults       * gTbDefaults;
extern AuthorizationRef       gAuthorization;

extern NSString * lastPartOfPath(NSString * thePath);


@implementation ConfigurationManager

TBSYNTHESIZE_OBJECT(retain, NSString *, applyToAllSharedPrivate, setApplyToAllSharedPrivate)
TBSYNTHESIZE_OBJECT(retain, NSString *, applyToAllUninstall,     setApplyToAllUninstall)
TBSYNTHESIZE_OBJECT(retain, NSString *, applyToAllReplaceSkip,   setApplyToAllReplaceSkip)

TBSYNTHESIZE_OBJECT(retain, NSMutableString *, errorLog,         setErrorLog)

TBSYNTHESIZE_OBJECT(retain, NSString *, tempDirPath,             setTempDirPath)

TBSYNTHESIZE_OBJECT(retain, NSMutableArray *, installSources,    setInstallSources)
TBSYNTHESIZE_OBJECT(retain, NSMutableArray *, installTargets,    setInstallTargets)
TBSYNTHESIZE_OBJECT(retain, NSMutableArray *, replaceSources,    setReplaceSources)
TBSYNTHESIZE_OBJECT(retain, NSMutableArray *, replaceTargets,    setReplaceTargets)
TBSYNTHESIZE_OBJECT(retain, NSMutableArray *, updateSources,     setUpdateSources)
TBSYNTHESIZE_OBJECT(retain, NSMutableArray *, updateTargets,     setUpdateTargets)
TBSYNTHESIZE_OBJECT(retain, NSMutableArray *, deletions,         setDeletions)

TBSYNTHESIZE_NONOBJECT(BOOL, inhibitCheckbox,        setInhibitCheckbox)
TBSYNTHESIZE_NONOBJECT(BOOL, installToSharedOK,      setInstallToSharedOK)
TBSYNTHESIZE_NONOBJECT(BOOL, installToPrivateOK,     setInstallToPrivateOK)
TBSYNTHESIZE_NONOBJECT(BOOL, authWasNull,            setAuthWasNull)
TBSYNTHESIZE_NONOBJECT(BOOL, multipleConfigurations, setMultipleConfigurations)

+(id)   manager {
    
    return [[[ConfigurationManager alloc] init] autorelease];
}

-(void) dealloc {
    
    [applyToAllSharedPrivate release];
    [applyToAllUninstall     release];
    [applyToAllReplaceSkip   release];
    [tempDirPath             release];
	[errorLog			     release];
    [installSources          release];
    [installTargets          release];
    [replaceSources          release];
    [replaceTargets          release];
    [updateSources           release];
    [updateTargets           release];
    [deletions               release];
    
    // listingWindow IS NOT RELEASED because it needs to exist after this instance of ConfigurationManager is gone. It releases itself when the window closes.
    
    [super dealloc];
}

+(NSString *) checkForSampleConfigurationAtPath: (NSString *) cfgPath {
    
    // Returns nil or a localized error message
    
    NSString * samplePath = [[NSBundle mainBundle] pathForResource: @"openvpn" ofType: @"conf"];
    if (  [gFileMgr fileExistsAtPath: cfgPath]  ) {
        if (  ! [gFileMgr contentsEqualAtPath: cfgPath andPath: samplePath]  ) {
            return nil;
        }
    } else {
        return [NSString stringWithFormat: NSLocalizedString(@"Cannot find configuration file at %@", @"Window text"), cfgPath];
    }
    
    return [NSString stringWithFormat: NSLocalizedString(@"You have tried to install a configuration file that is a sample"
                                                         @" configuration file. The configuration file must"
                                                         @" be modified to connect to a VPN. You may also need other files, such as"
                                                         @" certificate or key files, to connect to the VPN.\n\n"
                                                         @"Consult your network administrator or your VPN service provider to obtain"
                                                         @" configuration and other files or the information you need to modify the"
                                                         @" sample file.\n\n"
                                                         @"The configuration file is at\n%@\n\n", @"Window text"), cfgPath];
    return nil;
}

+(BOOL) bundleIdentifierIsValid: (id) bundleIdentifier {
    
    // Returns TRUE if the CFBundleVersion is a valid version number, FALSE otherwise
    
    return (   [[bundleIdentifier class] isSubclassOfClass: [NSString class]]
            && ([bundleIdentifier length] != 0)
			&& [bundleIdentifier containsOnlyCharactersInString: ALLOWED_DOMAIN_NAME_CHARACTERS]
            && ( 0 == [bundleIdentifier rangeOfString: @".."].length )
            && ( ! [bundleIdentifier hasSuffix: @"."])
            && ( ! [bundleIdentifier hasPrefix: @"."])  );
}

+(BOOL) bundleVersionIsValid: (id) bundleVersion {
    
    // Returns TRUE if the CFBundleVersion is a valid version number, FALSE otherwise
	
	if (   [[bundleVersion class] isSubclassOfClass: [NSString class]]
        && [bundleVersion containsOnlyCharactersInString: @"01234567890."]
		&& ([bundleVersion length] != 0)
		&& ( ! [bundleVersion hasPrefix: @"."])
		&& ( ! [bundleVersion hasSuffix: @"."]) ) {
		
		return TRUE;
	}
	
	return FALSE;
}

+(NSString *) checkPlistEntries: (NSDictionary *) dict
                       fromPath: (NSString *)     path {
    
    // Returns nil or a localized error message
    
    if (  dict  ) {
        NSArray * stringKeys    = [NSArray arrayWithObjects:       // List of keys for string values
                                   @"CFBundleIdentifier",
                                   @"CFBundleVersion",
                                   @"CFBundleShortVersionString",
                                   @"TBPackageVersion",
                                   @"TBReplaceIdentical",
                                   @"TBSharePackage",
                                   @"SUFeedURL",
                                   @"SUPublicDSAKeyFile",
                                   nil];
		
		NSArray * booleanKeys   = [NSArray arrayWithObjects:
                                   @"SUAllowsAutomaticUpdates",
                                   @"SUEnableAutomaticChecks",
                                   @"SUEnableSystemProfiling",
                                   @"SUShowReleaseNotes",
                                   nil];
		
		NSArray * numberKeys    = [NSArray arrayWithObjects:
                                   @"SUScheduledCheckInterval",
                                   nil];
		
        NSArray * arrayKeys     = [NSArray arrayWithObjects:
                                   @"TBKeepExistingFilesList",
                                   nil];
        
        NSArray * replaceValues = [NSArray arrayWithObjects:    // List of valid values for TBReplaceIdentical
                                   @"ask",
                                   @"yes",
                                   @"no",
                                   @"force",
                                   nil];
        
        NSArray * shareValues   = [NSArray arrayWithObjects:      // List of valid values for TBSharePackage
                                   @"ask",
                                   @"private",
                                   @"shared",
                                   @"deploy",
                                   nil];
        
		BOOL hasTBPackageVersion = NO;
        NSString * key;
        NSEnumerator * e = [dict keyEnumerator];
        while (  (key = [e nextObject])  ) {
            if (  [stringKeys containsObject: key]  ) {
                id obj = [dict objectForKey: key];
                if (  ! [[obj class] isSubclassOfClass: [NSString class]]  ) {
                    return [NSString stringWithFormat: NSLocalizedString(@"Non-string value for '%@' in %@", @"Window text - First %@ is the name of a Key, second %@ is the path to an Info.plist file"), key, path];
                }
				NSString * value = (NSString *)obj;
                if (  [key isEqualToString: @"TBPackageVersion"]  ) {
                    if (  ! [value isEqualToString: @"1"]  ) {
                        return [NSString stringWithFormat: NSLocalizedString(@"Invalid value '%@' for '%@' in %@", @"Window text - First %@ is the value of a key, second %@ is the name of the key, third %@ is the path to the Info.plist file containing the key/value pair"), value, key, path];
                    }
					hasTBPackageVersion = TRUE;
                    
                } else if (  [key isEqualToString: @"CFBundleIdentifier"]  ) {
                    if (  ! [ConfigurationManager bundleIdentifierIsValid: value]  ) {
                        return [NSString stringWithFormat: NSLocalizedString(@"Invalid value '%@' for '%@' in %@", @"Window text - First %@ is the value of a key, second %@ is the name of the key, third %@ is the path to the Info.plist file containing the key/value pair"), value, key, path];
                    }
                    
                } else if (  [key isEqualToString: @"CFBundleVersion"]  ) {
                    if (  ! [ConfigurationManager bundleVersionIsValid: value]  ) {
                        return [NSString stringWithFormat: NSLocalizedString(@"Invalid value '%@' for '%@' in %@", @"Window text - First %@ is the value of a key, second %@ is the name of the key, third %@ is the path to the Info.plist file containing the key/value pair"), value, key, path];
                    }
                    
                    
                } else if (  [key isEqualToString: @"TBReplaceIdentical"]  ) {
                    if (  ! [replaceValues containsObject: value]  ) {
                        return [NSString stringWithFormat: NSLocalizedString(@"Unknown value '%@' for '%@' in %@", @"Window text - First %@ is the value of a key, second %@ is the name of the key, third %@ is the path to the Info.plist file containing the key/value pair"), value, key, path];
                    }
                    
                } else if (  [key isEqualToString: @"TBSharePackage"]  ) {
                    if (  ! [shareValues containsObject: value]  ) {
                        return [NSString stringWithFormat: NSLocalizedString(@"Unknown value '%@' for '%@' in %@", @"Window text - First %@ is the value of a key, second %@ is the name of the key, third %@ is the path to the Info.plist file containing the key/value pair"), value, key, path];
                    }
                } else if (  [key isEqualToString: @"SUFeedURL"]  ) {
					if (  ! [NSURL URLWithString: value]  ) {
                        return [NSString stringWithFormat: NSLocalizedString(@"Value '%@' for '%@' is not a valid URL in %@", @"Window text - First %@ is the value of a key, second %@ is the name of the key, third %@ is the path to the Info.plist file containing the key/value pair"), value, key, path];
                    }
                } // Don't test values for the other string keys; as long as they are strings we will install the .plist
            } else if (  [booleanKeys containsObject: key]  ) {
                id obj = [dict objectForKey: key];
                if (  ! [obj respondsToSelector: @selector(boolValue)]  ) {
                    return [NSString stringWithFormat: NSLocalizedString(@"Non-boolean value for '%@' in %@", @"Window text - First %@ is the name of a Key, second %@ is the path to an Info.plist file"), key, path];
                }
			} else if (  [numberKeys containsObject: key]  ) {
				id obj = [dict objectForKey: key];
				if (  ! [obj respondsToSelector: @selector(intValue)]  ) {
					return [NSString stringWithFormat: NSLocalizedString(@"Non-integer value for '%@' in %@", @"Window text - First %@ is the name of a Key, second %@ is the path to an Info.plist file"), key, path];
				}
			} else if (  [arrayKeys containsObject: key]  ) {
				id obj = [dict objectForKey: key];
				if (  obj  ) {
                    if (  ! [obj respondsToSelector: @selector(objectEnumerator)]  ) {
						return [NSString stringWithFormat: NSLocalizedString(@"Non-array value for '%@' in %@", @"Window text - First %@ is the name of a Key, second %@ is the path to an Info.plist file"), key, path];
					}
					id item;
					NSEnumerator * itemEnum = [obj objectEnumerator];
					while (  (item = [itemEnum nextObject])  ) {
						if (  ! [[item class] isSubclassOfClass: [NSString class]] ) {
							return [NSString stringWithFormat: NSLocalizedString(@"Non-string value for an item in '%@' in %@", @"Window text - First %@ is the name of a Key, second %@ is the path to an Info.plist file"), key, path];
						}
					}
				}
			} else if (  [key hasPrefix: @"TBPreference"]  ) {
				NSString * pref = [key substringFromIndex: [@"TBPreference" length]];
				if (  ! [gConfigurationPreferences containsObject: pref]  ) {
					return [NSString stringWithFormat: NSLocalizedString(@"A TBPreference or TBAlwaysSetPreference key refers to an unknown preference '%@' in %@", @"Window text"), pref, path];
				}
			} else if (  [key hasPrefix: @"TBAlwaysSetPreference"]  ) {
				NSString * pref = [key substringFromIndex: [@"TBAlwaysSetPreference" length]];
				if (  ! [gConfigurationPreferences containsObject: pref]  ) {
					return [NSString stringWithFormat: NSLocalizedString(@"A TBPreference or TBAlwaysSetPreference key refers to an unknown preference '%@' in %@", @"Window text"), pref, path];
				}
			} else if (  ! [key isEqualToString: @"TBUninstall"]  ) {
                return [NSString stringWithFormat: NSLocalizedString(@"Unknown key '%@' in %@", @"Window text"), key, path];
            }
        }
		
		if (  ! hasTBPackageVersion  ) {
			return [NSString stringWithFormat: NSLocalizedString(@"No 'TBPackageVersion' in %@", @"Window text"), path];
		}
    }
	
    return nil;
}

+(id) plistOrErrorMessageInTblkAtPath: (NSString *) path {
    
    // Returns an NSDictionary with the contents of the .plist
    // or     an NSString with an error message, or
    // or      nil if there is no .plist, or
    
    NSString * directPath     = [path stringByAppendingPathComponent: @"Info.plist"];
    NSString * inContentsPath = [path stringByAppendingPathComponent: @"Contents/Info.plist"];
    BOOL       haveDirect     = [gFileMgr fileExistsAtPath: directPath];
    BOOL       haveInContents = [gFileMgr fileExistsAtPath: inContentsPath];
    
    NSString * plistPath;
    if (  haveDirect  ) {
        if (  haveInContents  ) {
            return [NSString stringWithFormat: @"Conflict: Both %@ and .../Contents/Info.plist exist", directPath];
        }
        plistPath = directPath;
    } else {
        if (  haveInContents  ) {
            plistPath = inContentsPath;
        } else {
            return nil;
        }
    }
    
    NSDictionary * dict = [NSDictionary dictionaryWithContentsOfFile: plistPath];
    if (  ! dict  ) {
        return [NSString stringWithFormat: @"%@ is corrupted and cannot be processed", plistPath];
    }
    
    NSString * result = [ConfigurationManager checkPlistEntries: dict fromPath: plistPath];
    if (  result  ) {
        return result;
    }
    
    return dict;
}

+(NSDictionary *) plistInTblkAtPath: (NSString *) path {
    
    // Returns an NSDictionary with the contents of the plist
    // or nil if there is a problem (an error message was logged)
    
    id obj = [ConfigurationManager plistOrErrorMessageInTblkAtPath: path];
    if (   ( ! obj)
        || [[obj class] isSubclassOfClass: [NSDictionary class]]  ) {
        return (NSDictionary *) obj;
    }
    
    NSLog(@"Ignoring Info.plist:\n%@", obj);
    return nil;
}

+(void) renameConfigurationFromPath: (NSString *)         sourcePath
                             toPath: (NSString *)         targetPath
                   authorizationPtr: (AuthorizationRef *) authorizationPtr {
    
    NSString * sourceName = [lastPartOfPath(sourcePath) stringByDeletingPathExtension];
    NSString * targetName = [lastPartOfPath(targetPath) stringByDeletingPathExtension];
    
    VPNConnection * connection = [[((MenuController *)[NSApp delegate]) myVPNConnectionDictionary] objectForKey: sourceName];
    if (  ! connection  ) {
        NSLog(@"renameConfigurationMenuItemWasClicked or name change on leftNav list but no configuration has been selected");
        return;
    }
    
    if (  ! [connection isDisconnected]  ) {
        TBShowAlertWindow(NSLocalizedString(@"Active connection", @"Window title"),
                          NSLocalizedString(@"You cannot rename a configuration unless it is disconnected.", @"Window text"));
        return;
    }
    
    NSString * autoConnectKey = [sourceName stringByAppendingString: @"autoConnect"];
    NSString * onSystemStartKey = [sourceName stringByAppendingString: @"-onSystemStart"];
    if (   [gTbDefaults boolForKey: autoConnectKey]
        && [gTbDefaults boolForKey: onSystemStartKey]  ) {
        TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                          NSLocalizedString(@"You may not rename a configuration which is set to start when the computer starts.", @"Window text"));
        return;
    }
    
    if (  [sourcePath hasPrefix: [gDeployPath stringByAppendingString: @"/"]]  ) {
        TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                          NSLocalizedString(@"You may not rename a Deployed configuration.", @"Window text"));
        return;
    }
    
    AuthorizationRef  localAuthorization = NULL;
	
	AuthorizationRef *authPtrToUse = (  authorizationPtr
									   ? authorizationPtr
									   : &localAuthorization);
	
	if (  ! *authPtrToUse  ) {
		NSString * msg = [NSString stringWithFormat: NSLocalizedString(@"You have asked to rename '%@' to '%@'.", @"Window text"), sourceName, targetName];
		*authPtrToUse = [NSApplication getAuthorizationRef: msg];
		if ( *authPtrToUse   == NULL ) {
			return;
		}
	}

    if (  [[ConfigurationManager manager] copyConfigPath: sourcePath
                                                  toPath: targetPath
                                         usingAuthRefPtr: authPtrToUse
                                              warnDialog: YES
                                             moveNotCopy: YES]  ) {
        
        // Save status of "-keychainHasUsernameAndPassword" and "-keychainHasPrivateKey" because they are deleted by moveCredentials
        BOOL havePwCredentials = [gTbDefaults boolForKey: [sourceName stringByAppendingString: @"-keychainHasUsernameAndPassword"]];
        BOOL haveUnCredentials = [gTbDefaults boolForKey: [sourceName stringByAppendingString: @"-keychainHasUsername"]];
	    BOOL havePkCredentials = [gTbDefaults boolForKey: [sourceName stringByAppendingString: @"-keychainHasPrivateKey"]];
        
        moveCredentials(sourceName, targetName);
        
        if (  ! [gTbDefaults movePreferencesFrom: sourceName to: targetName]  ) {
            TBShowAlertWindow(NSLocalizedString(@"Warning", @"Window title"),
                              NSLocalizedString(@"Warning: One or more preferences could not be renamed. See the Console Log for details.", @"Window text"));
        }
        
        // Restore "-keychainHasUsernameAndPassword" and "-keychainHasPrivateKey" to the new configuration's preferences because they were not transferred by moveCredentials
        [gTbDefaults setBool: havePwCredentials forKey: [targetName stringByAppendingString: @"-keychainHasUsernameAndPassword"]];
        [gTbDefaults setBool: haveUnCredentials forKey: [targetName stringByAppendingString: @"-keychainHasUsername"]];
		[gTbDefaults setBool: havePkCredentials forKey: [targetName stringByAppendingString: @"-keychainHasPrivateKey"]];
        
		// We also need to change the name of the configuration that is selected
		NSString * pref = [gTbDefaults stringForKey: @"leftNavSelectedDisplayName"];
		if (  [pref isEqualToString: sourceName]  ) {
			[gTbDefaults setObject: targetName forKey: @"leftNavSelectedDisplayName"];
		}
		
		[[((MenuController *)[NSApp delegate]) logScreen] setPreviouslySelectedNameOnLeftNavList: targetName];
		
		[((MenuController *)[NSApp delegate]) updateMenuAndDetailsWindow];
		
    }
    
    if (  authPtrToUse == &localAuthorization  ) {
        AuthorizationFree(localAuthorization, kAuthorizationFlagDefaults);
        localAuthorization = NULL;
    }
}

-(BOOL)  addConfigsFromPath: (NSString *)               folderPath
            thatArePackages: (BOOL)                     onlyPkgs
                     toDict: (NSMutableDictionary *)    dict
               searchDeeply: (BOOL)                     deep {
    
    // Adds configurations to a dictionary based on input parameters
    // Returns TRUE if succeeded, FALSE if one or more configurations were ignored.
    //
    // If searching L_AS_T_SHARED, looks for .ovpn and .conf and ignores them even if searching for packages (so we can complain to the user)
    
    if (  ! [gConfigDirs containsObject: folderPath]  ) {
        return TRUE;
    }
    
    BOOL ignored = FALSE;
    NSString * file;
    
    NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: folderPath];
	
    if (  deep  ) {
        // Search directory and subdirectories
        while (  (file = [dirEnum nextObject])  ) {
            BOOL addIt = FALSE;
            NSString * fullPath = [folderPath stringByAppendingPathComponent: file];
            NSString * dispName = [lastPartOfPath(fullPath) stringByDeletingPathExtension];
            if (  itemIsVisible(fullPath)  ) {
                NSString * ext = [file pathExtension];
                if (  onlyPkgs  ) {
                    if (  [ext isEqualToString: @"tblk"]  ) {
                        NSString * tbPath = tblkPathFromConfigPath(fullPath);
                        if (  ! tbPath  ) {
                            NSLog(@"Tunnelblick VPN Configuration ignored: No .conf or .ovpn file in %@", fullPath);
							ignored = TRUE;
                        } else {
                            addIt = TRUE;
                        }
                    }
                } else {
                    if (  [fullPath rangeOfString: @".tblk/"].length == 0  ) {  // Ignore .ovpn and .conf in a .tblk
                        if (  [ext isEqualToString: @"ovpn"] || [ext isEqualToString: @"conf"]  ) {
                            addIt = TRUE;
                        }
                    }
                }
            }
            
            if (  addIt  ) {
                if (  invalidConfigurationName(dispName, PROHIBITED_DISPLAY_NAME_CHARACTERS_CSTRING)  ) {
                    TBShowAlertWindow(NSLocalizedString(@"Name not allowed", @"Window title"),
                                      [NSString stringWithFormat: NSLocalizedString(@"Configuration '%@' will be ignored because its"
                                                                                    @" name contains characters that are not allowed.\n\n"
																			        @"Characters that are not allowed: '%s'\n\n", @"Window text"),
									   dispName, PROHIBITED_DISPLAY_NAME_CHARACTERS_CSTRING]);
                } else {
                    if (  [dict objectForKey: dispName]  ) {
                        NSLog(@"Tunnelblick Configuration ignored: The name is already being used: %@", fullPath);
                        ignored = TRUE;
                    } else {
                        [dict setObject: fullPath forKey: dispName];
                    }
                    
                }
            }
        }
    } else {
        // Search directory only, not subdirectories.
        while (  (file = [dirEnum nextObject])  ) {
            [dirEnum skipDescendents];
            BOOL addIt = FALSE;
            NSString * fullPath = [folderPath stringByAppendingPathComponent: file];
            NSString * dispName = [file stringByDeletingPathExtension];
            if (  itemIsVisible(fullPath)  ) {
                NSString * ext = [file pathExtension];
                if (  onlyPkgs  ) {
                    if (  [ext isEqualToString: @"tblk"]  ) {
                        NSString * tbPath = configPathFromTblkPath(fullPath);
                        if (  ! tbPath  ) {
                            NSLog(@"Tunnelblick VPN Configuration ignored: No .conf or .ovpn file. Try reinstalling %@", fullPath);
							ignored = TRUE;
                        } else {
                            addIt = TRUE;
                        }
                    }
                } else {
                    if (  [ext isEqualToString: @"ovpn"] || [ext isEqualToString: @"conf"]  ) {
                        addIt = TRUE;
                    }
                }
                if (   [folderPath isEqualToString: L_AS_T_SHARED]
                    && ([ext isEqualToString: @"ovpn"] || [ext isEqualToString: @"conf"])  ) {
                    NSLog(@"Tunnelblick VPN Configuration ignored: Only Tunnelblick VPN Configurations (.tblk packages) may be shared %@", fullPath);
					ignored = TRUE;
                }
            }
            
            if (  addIt  ) {
                if (  [dict objectForKey: dispName]  ) {
                    NSLog(@"Tunnelblick Configuration ignored: The name is already being used: %@", fullPath);
					ignored = TRUE;
                } else {
                    [dict setObject: fullPath forKey: dispName];
                }
            }
        }
    }
    
    return  ! ignored;
}            

-(NSMutableDictionary *) getConfigurations {
    
    // Returns a dictionary with information about the configuration files in gConfigDirs.
    // The key for each entry is the display name for the configuration; the object is the path to the configuration file
    // (which may be a .tblk package or a .ovpn or .conf file) for the configuration
    //
    // Only searches folders that are in gConfigDirs.
    //
    // First, it goes through gDeploy looking for packages,
    //           then through gDeploy looking for configs NOT in packages,
    //           then through L_AS_T_SHARED looking for packages (does not look for configs that are not in packages in L_AS_T_SHARED)
    //           then through gPrivatePath looking for packages,
    //           then through gPrivatePath looking for configs NOT in packages
    
    NSMutableDictionary * dict = [[[NSMutableDictionary alloc] init] autorelease];
    BOOL noneIgnored = TRUE;
    
    noneIgnored = [self addConfigsFromPath: gDeployPath  thatArePackages: YES toDict: dict searchDeeply: YES ] && noneIgnored;
    noneIgnored = [self addConfigsFromPath: gDeployPath  thatArePackages:  NO toDict: dict searchDeeply: YES ] && noneIgnored;
    noneIgnored = [self addConfigsFromPath: L_AS_T_SHARED  thatArePackages: YES toDict: dict searchDeeply: YES ] && noneIgnored;
    noneIgnored = [self addConfigsFromPath: gPrivatePath thatArePackages:   YES toDict: dict searchDeeply: YES ] && noneIgnored;
    
    if (  ! noneIgnored  ) {
        TBRunAlertPanelExtended(NSLocalizedString(@"Configuration(s) Ignored", @"Window title"),
                                NSLocalizedString(@"One or more configurations are being ignored. See the Console Log for details.", @"Window text"),
                                nil, nil, nil,
                                @"skipWarningAboutIgnoredConfigurations",          // Preference about seeing this message again
                                NSLocalizedString(@"Do not warn about this again", @"Checkbox name"),
                                nil,
								NSAlertDefaultReturn);
    }
    return dict;
}

-(NSString *) extractTblkNameFromPath: (NSString *) path {
    
    // Given a path, returns the name of the .tblk that encloses it (without the .tblk)
    // If path is a .tblk, returns the path (without the .tblk)
    // If path is not a .tblk and is not enclosed in a .tblk, returns the path
    
    // Find ".tblk" so we can ignore it and everything after it
    NSRange rng1 = [path rangeOfString: @".tblk" options: NSBackwardsSearch];
    if (  rng1.location == NSNotFound  ) { // if no ".tblk", don't ignore anything
        rng1.location = [path length];
    }
    
    // Then find the "/" before that so we can include everything after it
    NSRange rng2 = [path rangeOfString: @"/" options: NSBackwardsSearch range: NSMakeRange(0, rng1.location)];
	if (  rng2.location == NSNotFound  ) {
		rng2.location = 0;  // No "/", so include from start of string
	} else {
		rng2.location += 1; // Otherwise, don't include the "/" itself
	}
	
    NSString * returnString = [path substringWithRange: NSMakeRange(rng2.location, rng1.location - rng2.location)];
    return returnString;
}

-(BOOL) userCanEditConfiguration: (NSString *) filePath {
    
    NSString * extension = [filePath pathExtension];
    if (  ! (   [extension isEqualToString: @"tblk"]
             || [extension isEqualToString: @"ovpn"]
             || [extension isEqualToString: @"conf"]
             )  ) {
        NSLog(@"Internal error: %@ is not a .tblk, .conf, or .ovpn", filePath);
        return NO;
    }
    
    NSString * realPath = (  [extension isEqualToString: @"tblk"]
						   ? [filePath stringByAppendingPathComponent: @"Contents/Resources/config.ovpn"]
						   : [[filePath retain] autorelease]);
    
    // File must exist and we must be able to write to the file and its parent directory
    if (   [gFileMgr fileExistsAtPath:     realPath]
		&& [gFileMgr isWritableFileAtPath: realPath]
        && [gFileMgr isWritableFileAtPath: [realPath stringByDeletingLastPathComponent]]  ) {
        return YES;
    }
    
    return NO;
}

-(void) examineConfigFileForConnection: (VPNConnection *) connection {
    
    // Display the sanitized contents of the configuration file in a window
    
    NSString * configFileContents = [connection sanitizedConfigurationFileContents];
    if (  configFileContents  ) {
        NSString * heading = [NSString stringWithFormat: NSLocalizedString(@"%@ OpenVPN Configuration - Tunnelblick", @"Window title"),[connection localizedName]];
        
        // NOTE: The window controller is allocated here, but releases itself when the window is closed.
        //       So _we_ don't release it, and we can overwrite listingWindow with impunity.
        //       (The class variable 'listingWindow' is used to avoid an analyzer warning about a leak.)
        listingWindow = [[ListingWindowController alloc] initWithHeading: heading
                                                                    text: configFileContents];
        [listingWindow showWindow: self];
    } else {
        TBShowAlertWindow(NSLocalizedString(@"Warning", @"Window title"),
                          NSLocalizedString(@"Tunnelblick could not find the configuration file or the configuration file could not be sanitized. See the Console Log for details.", @"Window text"));
    }
}

-(void) editOrExamineConfigurationForConnection: (VPNConnection *) connection {
    
    NSString * targetPath = [connection configPath];
    if ( ! targetPath  ) {
        NSLog(@"editOrExamineConfigurationForConnection: No path for configuration %@", [connection displayName]);
        return;
    }
    
    if (  [self userCanEditConfiguration: targetPath]  ) {
		if (  [[targetPath pathExtension] isEqualToString: @"tblk"]  ) {
			targetPath = [targetPath stringByAppendingPathComponent: @"Contents/Resources/config.ovpn"];
		}
        [connection invalidateConfigurationParse];
        [[NSWorkspace sharedWorkspace] openFile: targetPath withApplication: @"TextEdit"];
    } else {
        [self examineConfigFileForConnection: connection];
    }
}

-(void) shareOrPrivatizeAtPath: (NSString *) path {
    
    // Make a private configuration shared, or a shared configuration private
    
    NSString * source;
    NSString * target;
    NSString * msg;
	
    if (  [[path pathExtension] isEqualToString: @"tblk"]  ) {
        NSString * last = lastPartOfPath(path);
        NSString * name = [last stringByDeletingPathExtension];
        if (  [path hasPrefix: [L_AS_T_SHARED stringByAppendingString: @"/"]]  ) {
            NSString * lastButOvpn = [name stringByAppendingPathExtension: @"ovpn"];
            NSString * lastButConf = [name stringByAppendingPathExtension: @"conf"];
            if (   [gFileMgr fileExistsAtPath: [gPrivatePath stringByAppendingPathComponent: last]]
                || [gFileMgr fileExistsAtPath: [gPrivatePath stringByAppendingPathComponent: lastButOvpn]]
                || [gFileMgr fileExistsAtPath: [gPrivatePath stringByAppendingPathComponent: lastButConf]]  ) {
                int result = TBRunAlertPanel(NSLocalizedString(@"Replace VPN Configuration?", @"Window title"),
                                             [NSString stringWithFormat: NSLocalizedString(@"A private configuration named '%@' already exists.\n\nDo you wish to replace it with the shared configuration?", @"Window text"), name],
                                             NSLocalizedString(@"Replace", @"Button"),
                                             NSLocalizedString(@"Cancel" , @"Button"),
                                             nil);
                if (  result != NSAlertDefaultReturn  ) {   // No action if cancelled or error occurred
                    return;
                }
            }
            
            source = [[path copy] autorelease];
            target = [gPrivatePath stringByAppendingPathComponent: last];
            msg = [NSString stringWithFormat: NSLocalizedString(@"You have asked to make the '%@' configuration private, instead of shared.", @"Window text"), name];
        } else if (  [path hasPrefix: [gPrivatePath stringByAppendingString: @"/"]]  ) {
            source = [[path copy] autorelease];
            target = [L_AS_T_SHARED stringByAppendingPathComponent: last];
            msg = [NSString stringWithFormat: NSLocalizedString(@"You have asked to make the '%@' configuration shared, instead of private.", @"Window text"), name];
        } else {
            NSLog(@"shareOrPrivatizeAtPath: Internal error: path is not private or shared at %@", path);
            return;
        }
        
        AuthorizationRef authRef = [NSApplication getAuthorizationRef: msg];
        if ( authRef == NULL ) {
            return;
        }
        
        [self copyConfigPath: source
                      toPath: target
             usingAuthRefPtr: &authRef
                  warnDialog: YES
                 moveNotCopy: YES];
        
        AuthorizationFree(authRef, kAuthorizationFlagDefaults);
    }
}

-(NSString *) parseString: (NSString *) cfgContents
                forOption: (NSString *) option {
    
    // Returns nil if the option is not found in the string that contains the contents of the configuration file
    // Returns an empty string if the option is found but has no parameters
    // Otherwise, returns the first parameter
    
    NSCharacterSet * notWhitespace = [[NSCharacterSet whitespaceCharacterSet] invertedSet];
    NSCharacterSet * notWhitespaceNotNewline = [[NSCharacterSet whitespaceAndNewlineCharacterSet] invertedSet];
    NSCharacterSet * newline = [NSCharacterSet characterSetWithCharactersInString: @"(\n\r"];
    NSRange mainRng = NSMakeRange(0, [cfgContents length]);
    unsigned int mainEnd = mainRng.length;
    
    unsigned int curPos = 0;
    while (  curPos < mainEnd  ) {
        mainRng.location = curPos;
        mainRng.length = mainEnd - curPos;
        
        // Skip whitespace, including newlines
        NSRange restRng = [cfgContents rangeOfCharacterFromSet: notWhitespaceNotNewline
                                                       options: 0
                                                         range: mainRng];
        if (  restRng.length == 0  ) {
            break;
        } else {
            curPos = restRng.location;
            mainRng.location = restRng.location;
            mainRng.length   = mainEnd - mainRng.location;
        }
		
		NSUInteger startOfLine = mainRng.location;
        
        // If option is next
        NSRange optRng = NSMakeRange(curPos, [option length]);
        if (   (  (optRng.location + optRng.length) <= mainEnd  )
            && [[cfgContents substringWithRange: optRng] caseInsensitiveCompare: option] == NSOrderedSame  ) {
            
            // Skip mandatory whitespace between option and rest of line
            mainRng.location = optRng.location + optRng.length;
            mainRng.length = mainEnd - mainRng.location;
            restRng = [cfgContents rangeOfCharacterFromSet: notWhitespace
                                                   options: 0
                                                     range: mainRng];
			
			// If first thing after whitespace is a LF, then return an empty string
			if (  [[cfgContents substringWithRange: restRng] isEqualToString: @"\n"]  ) {
				return @"";
			}
			
            if (  restRng.location != mainRng.location  ) {
				
				// Whitespace found, so "value" for option is the next token
                mainRng.location = restRng.location;
                mainRng.length = mainEnd - mainRng.location;
                NSRange nlRng = [cfgContents rangeOfCharacterFromSet: newline
                                                             options: 0
                                                               range: mainRng];
				NSRange rolRng; // range of rest of line
                if (  nlRng.length == 0  ) {
                    rolRng = NSMakeRange(mainRng.location, mainEnd - mainRng.location);
                } else {
                    rolRng = NSMakeRange( mainRng.location, nlRng.location - mainRng.location);
                }
				
				NSString * firstCh = [cfgContents substringWithRange: NSMakeRange(rolRng.location, 1)];
				if (   [firstCh isEqualToString: @"\""]
					|| [firstCh isEqualToString: @"'"]  ) {
					
					// quoted token is everything after first quote up to but not including last quote in line
					NSRange endQuoteRng = [cfgContents rangeOfString: firstCh
															 options: NSBackwardsSearch
															   range: rolRng];
					if (  endQuoteRng.location != rolRng.location  ) {
						return [cfgContents substringWithRange: NSMakeRange(rolRng.location + 1, endQuoteRng.location - rolRng.location - 1)];
					}
					
					NSLog(@"Error; unterminated %@ in '%@'",
						  firstCh,
						  [cfgContents substringWithRange:
						   NSMakeRange(startOfLine, rolRng.location + rolRng.length - startOfLine)]);
				}
				
				// normal; token is everything to first whitespace
				NSRange wsRng = [cfgContents rangeOfCharacterFromSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]
															 options: 0
															   range: rolRng];
				if (  wsRng.length == 0  ) {
					return [cfgContents substringWithRange: rolRng];
				} else {
					return [cfgContents substringWithRange:
							NSMakeRange(rolRng.location, wsRng.location - rolRng.location)];
				}
				
				return [cfgContents substringWithRange: rolRng];
            }
            // No whitespace after option, so it is no good (optionXXX)
        }
        
        // Skip to next \n
        restRng = [cfgContents rangeOfCharacterFromSet: newline
                                               options: 0
                                                 range: mainRng];
        if (  restRng.length == 0 ) {
            curPos = mainEnd;
        } else {
            curPos = restRng.location + restRng.length;
        }
    }
	
    return nil;
}

-(NSString *)parseConfigurationPath: (NSString *)      cfgPath
                      forConnection: (VPNConnection *) connection
                        hasScramble: (BOOL *)          hasScramble
                    hasAuthUserPass: (BOOL *)          hasAuthUserPass {
    
    // Parses the configuration file.
    // Sets 'hasScramble' TRUE if configuration has a 'scramble' option; FALSE otherwise
    // Sets 'hasAuthUserPass' TRUE if configuration has a 'auth-user-pass' option with no arguments; FALSE otherwise
    // Gives user the option of adding the down-root plugin if appropriate
    // Returns with device type: "tun", "tap", "utun", "tunOrUtun", or nil if it can't be determined
    // Returns with string "Cancel" if user cancelled
	
    NSString * doNotParseKey = [[connection displayName] stringByAppendingString: @"-doNotParseConfigurationFile"];
    if (  [gTbDefaults boolForKey: doNotParseKey]  ) {
        return nil;
    }
    
    NSString * cfgFile = lastPartOfPath(cfgPath);
    NSString * configLocString = configLocCodeStringForPath(cfgPath);
    NSArray * arguments = [NSArray arrayWithObjects: @"printSanitizedConfigurationFile", cfgFile, configLocString, nil];
    NSString * stdOut = nil;
    NSString * stdErrOut = nil;
    OSStatus status = runOpenvpnstart(arguments, &stdOut, &stdErrOut);
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"Internal failure (%lu) of openvpnstart printSanitizedConfigurationFile %@ %@", (unsigned long)status, cfgFile, configLocString);
        return nil;
    }
    
    NSString * cfgContents = condensedConfigFileContentsFromString(stdOut);
    
    NSString * scrambleOption = [self parseString: cfgContents forOption: @"scramble" ];
    *hasScramble = scrambleOption != nil;
    
    // Set hasAuthUserPass TRUE if auth-user-pass appears and has no parameters
    NSString * authUserPassOption = [self parseString: cfgContents forOption: @"auth-user-pass" ];
    *hasAuthUserPass = (  authUserPassOption
                        ? ([authUserPassOption length] == 0)
                        : NO);
                           

    NSString * userOption  = [self parseString: cfgContents forOption: @"user" ];
    if (  [userOption length] == 0  ) {
        userOption = nil;
    }
    NSString * groupOption = [self parseString: cfgContents forOption: @"group"];
    if (  [groupOption length] == 0  ) {
        groupOption = nil;
    }
    NSString * useDownRootPluginKey = [[connection displayName] stringByAppendingString: @"-useDownRootPlugin"];
    NSString * skipWarningKey = [[connection displayName] stringByAppendingString: @"-skipWarningAboutDownroot"];
    if (   ( ! [gTbDefaults boolForKey: useDownRootPluginKey] )
        &&     [gTbDefaults canChangeValueForKey: useDownRootPluginKey]
        && ( ! [gTbDefaults boolForKey: skipWarningKey] )  ) {
        
        NSString * downOption  = [self parseString: cfgContents forOption: @"down" ];
        if (  [downOption length] == 0  ) {
            downOption = nil;
        }
        
        if (   (userOption || groupOption)
            && (   downOption
                || ([connection useDNSStatus] != 0)  )  ) {
                
                NSString * msg = [NSString stringWithFormat: NSLocalizedString(@"The configuration file for '%@' appears to use the 'user' and/or 'group' options and is using a down script ('Do not set nameserver' not selected, or there is a 'down' option in the configuration file).\n\nIt is likely that restarting the connection (done automatically when the connection is lost) will fail unless the 'openvpn-down-root.so' plugin for OpenVPN is used.\n\nDo you wish to use the plugin?", @"Window text"),
                                  [connection localizedName]];
                
                int result = TBRunAlertPanelExtended(NSLocalizedString(@"Use 'down-root' plugin for OpenVPN?", @"Window title"),
                                                     msg,
                                                     NSLocalizedString(@"Do not use the plugin", @"Button"),
                                                     NSLocalizedString(@"Always use the plugin", @"Button"),
                                                     NSLocalizedString(@"Cancel", @"Button"),
                                                     skipWarningKey,
                                                     NSLocalizedString(@"Do not warn about this again for this configuration", @"Checkbox name"),
                                                     nil,
													 NSAlertDefaultReturn);
                if (  result == NSAlertAlternateReturn  ) {
                    [gTbDefaults setBool: TRUE forKey: useDownRootPluginKey];
                } else if (  result != NSAlertDefaultReturn  ) {   // No action if cancelled or error occurred
                    return @"Cancel";
                }
            }
    }
    
    if (   (   [gTbDefaults boolForKey: useDownRootPluginKey]
            && [gTbDefaults canChangeValueForKey: useDownRootPluginKey] )
        && (! (userOption || groupOption))  ) {
        [gTbDefaults removeObjectForKey: useDownRootPluginKey];
        NSLog(@"Removed '%@' preference", useDownRootPluginKey);
    }
    
    NSArray * reservedOptions = OPENVPN_OPTIONS_THAT_CAN_ONLY_BE_USED_BY_TUNNELBLICK;
    NSString * option;
    NSEnumerator * e = [reservedOptions objectEnumerator];
    while (  (option = [e nextObject])  ) {
        NSString * optionValue = [self parseString: cfgContents forOption: option];
        if (  optionValue  ) {
            NSLog(@"The configuration file for '%@' contains an OpenVPN '%@' option. That option is reserved for use by Tunnelblick. The option will be ignored", [connection displayName], option);
		}
    }
    
    NSArray * windowsOnlyOptions = OPENVPN_OPTIONS_THAT_ARE_WINDOWS_ONLY;
    e = [windowsOnlyOptions objectEnumerator];
    while (  (option = [e nextObject])  ) {
        NSString * optionValue = [self parseString: cfgContents forOption: option];
        if (  optionValue  ) {
            NSLog(@"The OpenVPN configuration file in %@ contains a '%@' option, which is a Windows-only option. It cannot be used on OS X.", [connection displayName], option);
            NSString * msg = [NSString stringWithFormat:
                              NSLocalizedString(@"The OpenVPN configuration file in %@ contains a '%@' option, which is a Windows-only option. It cannot be used on OS X.", @"Window text"),
                              [connection localizedName], option];
            TBShowAlertWindow(NSLocalizedString(@"Tunnelblick Error", @"Window title"),
                              msg);
		}
    }
    
    // If there is a "dev-node" entry, return that device type (tun, utun, tap)
	NSString * devNodeOption = [self parseString: cfgContents forOption: @"dev-node"];
	if (  devNodeOption  ) {
		if (  [devNodeOption hasPrefix: @"tun"]  ) {
			return @"tun";
		}
		if (  [devNodeOption hasPrefix: @"utun"]  ) {
			return @"utun";
		}
		NSLog(@"The configuration file for '%@' contains a 'dev-node' option, but the argument does not begin with 'tun' or 'utun'. It has been ignored", [connection displayName]);
	}
    
    // If there is a "dev-type" entry, return that device type (tun, utun, tap)
    NSString * devTypeOption = [self parseString: cfgContents forOption: @"dev-type"];
    if (  devTypeOption  ) {
        if (  [devTypeOption isEqualToString: @"tun"]  ) {
            return @"tun";
        }
        if (  [devTypeOption isEqualToString: @"utun"]  ) {
            return @"utun";
        }

        NSLog(@"The configuration file for '%@' contains a 'dev-type' option, but the argument is not 'tun'. It has been ignored", [connection displayName]);
    }
    
    // If there is a "dev" entry, return that device type for 'tap' or 'utun' but for 'tun', return 'tunOrUtun' so that will be decided when connecting (depends on OS X version and OpenVPN version)
    NSString * devOption = [self parseString: cfgContents forOption: @"dev"];
    if (  devOption  ) {
		if (  [devOption hasPrefix: @"tun"]  ) {
			return @"tunOrUtun";                    // Uses utun if available (OS X 10.6.8+ and OpenVPN 2.3.3+)
		}
		if (  [devOption hasPrefix: @"utun"]  ) {
			return @"utun";
		}

        
        NSLog(@"The configuration file for '%@' contains a 'dev' option, but the argument does not begin with 'tun', 'tap', or 'utun'. It has been ignored", [connection displayName]);
        NSString * msg = [NSString stringWithFormat: NSLocalizedString(@"The configuration file for '%@' does not appear to contain a 'dev utun'' option. This option may be needed for proper AxionVPN operation. Consult with your network administrator or the OpenVPN documentation.", @"Window text"),
                          [connection localizedName]];
        TBRunAlertPanelExtended(NSLocalizedString(@"No 'dev tun', 'dev utun', or 'dev tap' found", @"Window title"),
                                msg,
                                nil, nil, nil,
                                skipWarningKey,
                                NSLocalizedString(@"Do not warn about this again for this configuration", @"Checkbox name"),
                                nil,
                                NSAlertDefaultReturn);
    }
    
    return nil;
}

-(BOOL) copyConfigPath: (NSString *) sourcePath
                toPath: (NSString *) targetPath
       usingAuthRefPtr: (AuthorizationRef *) authRefPtr
            warnDialog: (BOOL) warn
           moveNotCopy: (BOOL) moveInstead {
    
    // Copies or moves a config file or package and sets ownership and permissions on the target
    // Returns TRUE if succeeded in the copy or move -- EVEN IF THE CONFIG WAS NOT SECURED (an error message was output to the console log).
    // Returns FALSE if failed, having already output an error message to the console log
    
    NSLog(@"[copyConfigPath] Copy %@ to %@",sourcePath,targetPath);
    
    if (  [sourcePath isEqualToString: targetPath]  ) {
        NSLog(@"You cannot copy or move a configuration to itself. Trying to do that with %@", sourcePath);
        return FALSE;
    }
    
	NSString * errMsg = allFilesAreReasonableIn(sourcePath);
	if (  errMsg  ) {
		NSLog(@"%@", errMsg);
		return FALSE;
	}
    
    unsigned firstArg = (moveInstead
                         ? INSTALLER_MOVE_NOT_COPY
                         : 0);
    NSArray * arguments = [NSArray arrayWithObjects: targetPath, sourcePath, nil];
    
    NSError *error;
    [[NSFileManager defaultManager] copyItemAtPath:sourcePath toPath:targetPath error:&error];
    
    NSInteger installerResult = 0;
    NSLog(@"Running installer with %@",arguments);
   // NSInteger installerResult = [((MenuController *)[NSApp delegate]) runInstallerAxion:firstArg
	//											extraArguments: arguments
	//										   usingAuthRefPtr: authRefPtr
	//												   message: nil
	//										 installTblksFirst: nil];
	if (  installerResult == 0  ) {
        NSLog(@"[copyConfigPath] returning TRUE");

        return TRUE;
    }
	
	if (  installerResult == 1  ) {
        NSLog(@"[copyConfigPath] returning FALSE");

		return FALSE;
	}
    
	NSString * name = lastPartOfPath(targetPath);
    if (  ! moveInstead  ) {
        NSLog(@"Could not copy configuration file %@ to %@", sourcePath, targetPath);
        if (  warn  ) {
            NSString * title = NSLocalizedString(@"Could Not Copy Configuration", @"Window title");
            NSString * msg = [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick could not copy the '%@' configuration. See the Console Log for details.", @"Window text"), name];
            TBShowAlertWindow(title, msg);
        }
        
        return FALSE;
        
    } else {
        NSLog(@"Could not move configuration file %@ to %@", sourcePath, targetPath);
        if (  warn  ) {
            NSString * title = NSLocalizedString(@"Could Not Move Configuration", @"Window title");
            NSString * msg = [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick could not move the '%@' configuration. See the Console Log for details.", @"Window text"), name];
            TBShowAlertWindow(title, msg);
        }
        
        return FALSE;
    }
}

-(BOOL) deleteConfigPath: (NSString *) targetPath
         usingAuthRefPtr: (AuthorizationRef *) authRefPtr
              warnDialog: (BOOL) warn {
    
    // Deletes a config file or package
    // Returns TRUE if succeeded
    // Returns FALSE if failed, having already output an error message to the console log
    
    // If it is a .tblk and has a SUFeedURL, CFBundleVersion, and CFBundleIdentifier Info.plist entries, remember the CFBundleIdentifier for later
    NSString * bundleId = nil;
    if (  [targetPath hasSuffix: @".tblk"]  ) {
        NSDictionary * infoDict = [ConfigurationManager plistInTblkAtPath: targetPath];
        if (   [infoDict objectForKey: @"SUFeedURL"]
            && [infoDict objectForKey: @"CFBundleVersion"]  ) {
            bundleId = [infoDict objectForKey: @"CFBundleIdentifier"];
        }
    }
    
    NSArray * arguments = [NSArray arrayWithObjects: targetPath, nil];
    
    [((MenuController *)[NSApp delegate]) runInstaller: INSTALLER_DELETE extraArguments: arguments usingAuthRefPtr: authRefPtr message: nil installTblksFirst: nil];
    
    if ( [gFileMgr fileExistsAtPath: targetPath]  ) {
        NSString * name = [[targetPath lastPathComponent] stringByDeletingPathExtension];
        NSLog(@"Could not uninstall configuration file %@", targetPath);
        if (  warn  ) {
            NSString * title = NSLocalizedString(@"Could Not Uninstall Configuration", @"Window title");
            NSString * msg = [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick could not uninstall the '%@' configuration. See the Console Log for details.", @"Window text"), name];
            TBShowAlertWindow(title, msg);
        }
        return FALSE;
    }
	
    NSLog(@"Uninstalled configuration file %@", targetPath);
    
    if (  bundleId  ) {
        
          // Stop updating any configurations with this bundleId
		[[((MenuController *)[NSApp delegate]) myConfigMultiUpdater] stopUpdateCheckingForAllStubTblksWithBundleIdentifier: bundleId];
		
        // Delete all master stub .tblk containers with this bundleId
        NSArray * stubTblkPaths = [ConfigurationMultiUpdater pathsForMasterStubTblkContainersWithBundleIdentifier: bundleId];
        NSString * containerPath;
        NSEnumerator * e = [stubTblkPaths objectEnumerator];
        while (  (containerPath = [e nextObject])) {
            arguments = [NSArray arrayWithObjects: containerPath, nil];
            [((MenuController *)[NSApp delegate]) runInstaller: INSTALLER_DELETE
                            extraArguments: arguments
                           usingAuthRefPtr: authRefPtr
                                   message: nil
                         installTblksFirst: nil];
            if (  [gFileMgr fileExistsAtPath: containerPath]  ) {
                NSLog(@"Could not delete \"stub\" .tblk container %@", containerPath);
                if (  warn  ) {
                    NSString * title = NSLocalizedString(@"Could Not Uninstall Configuration", @"Window title");
                    NSString * msg = [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick could not completely uninstall the '%@' configuration. See the Console Log for details.", @"Window text"), lastPartOfPath(targetPath)];
                    TBShowAlertWindow(title, msg);
                }
                return FALSE;
            } else {
                NSLog(@"Uninstalled master \"stub\" .tblk for %@", bundleId);
            }
        }
    }
    
    return TRUE;
}






// *********************************************************************************************
// Configuration installation methods

-(NSString *) confirmReplace: (NSString *) localizedName
                          in: (NSString *) sharedOrPrivate {
    
    // Returns "skip" if user want to skip this one configuration
    // Returns "cancel" if user cancelled
    // Returns "shared" or "private" to indicate where the configuration should be replaced
    // Otherwise, returns a localized error message
    
    if (  [[self applyToAllSharedPrivate] isEqualToString: sharedOrPrivate]  ) {
        return sharedOrPrivate;
    }
    
    int result = TBRunAlertPanel(NSLocalizedString(@"Replace VPN Configuration?", @"Window title"),
                                 [NSString stringWithFormat: NSLocalizedString(@"Do you wish to replace the '%@' configuration?\n\n", @"Window text"), localizedName],
                                 NSLocalizedString(@"Replace"  , @"Button"),    // Default button
                                 NSLocalizedString(@"Skip"     , @"Button"),    // Alternate button
                                 NSLocalizedString(@"Cancel"   , @"Button"));   // Other button
    switch (  result  ) {
            
        case NSAlertDefaultReturn:
            return sharedOrPrivate;
            
        case NSAlertAlternateReturn:
            return @"skip";
            
        case NSAlertOtherReturn:
            return @"cancel";
            
        default:
            return NSLocalizedString(@"TBRunAlertPanel returned an error", @"Window text");
    }
}

-(NSString *) askSharedOrPrivateForConfig: (NSString *) localizedName {
    
    // Returns "cancel" if user cancelled
    // Returns "shared" or "private" to indicate user's choice of where to install
    // Anything else is a localized error message
    //
    // Sets *shareAllPtr or *privateAllPtr if the user checked the corresponding checkbox
    
    NSString * allSharedPrivate = [self applyToAllSharedPrivate];
    if (  allSharedPrivate  ) {
        return allSharedPrivate;
    }
    
    BOOL applyToAllCheckboxChecked = FALSE;
    
    NSString * applyToAllCheckboxLabel = (  ! [self inhibitCheckbox]
                                          ? NSLocalizedString(@"Apply to all", @"Checkbox name")
                                          : nil);
    
    BOOL * applyToAllCheckboxCheckedPtr = (  ! [self inhibitCheckbox]
                                           ? &applyToAllCheckboxChecked
                                           : nil);
    
    int result = TBRunAlertPanelExtended(NSLocalizedString(@"Install Configuration For All Users?", @"Window title"),
                                         [NSString stringWithFormat: NSLocalizedString(@"Do you wish to install the '%@' configuration so that all users can use it, or so that only you can use it?\n\n", @"Window text"), localizedName],
                                         NSLocalizedString(@"Only Me"  , @"Button"),    // Default button
                                         NSLocalizedString(@"All Users", @"Button"),    // Alternate button
                                         NSLocalizedString(@"Cancel"   , @"Button"),    // Other button
                                         nil,
                                         applyToAllCheckboxLabel,
                                         applyToAllCheckboxCheckedPtr,
                                         NSAlertDefaultReturn);
    
    switch (  result  ) {
            
        case NSAlertDefaultReturn:
            if (  applyToAllCheckboxChecked  ) {
                [self setApplyToAllSharedPrivate: @"private"];
            }
            return @"private";
            
        case NSAlertAlternateReturn:
            if (  applyToAllCheckboxChecked  ) {
                [self setApplyToAllSharedPrivate: @"shared"];
            }
            return @"shared";
            
        case NSAlertOtherReturn:
            return @"cancel";
            
        default:
            return NSLocalizedString(@"TBRunAlertPanel returned an error", @"Window text");
    }
}

-(NSString *) pathOfTblkToReplaceWithBundleIdentifier: (NSString *) bundleIdentifier {
    
    
    NSArray * dirList = [NSArray arrayWithObjects: gDeployPath, L_AS_T_SHARED, gPrivatePath, nil];
    
    NSString * folderPath;
    NSEnumerator * e = [dirList objectEnumerator];
    while (  (folderPath = [e nextObject])  ) {
        
        NSString * filename;
        NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: folderPath];
        while (  (filename = [dirEnum nextObject])  ) {
            if (  [filename hasSuffix: @".tblk"]  ) {
				[dirEnum skipDescendents];
				NSString * fullPath = [folderPath stringByAppendingPathComponent: filename];
                NSDictionary * fileInfoPlist = [ConfigurationManager plistInTblkAtPath: fullPath];
                NSString * fileCfBundleIdentifier = [fileInfoPlist objectForKey: @"CFBundleIdentifier"];
                if (  [fileCfBundleIdentifier isEqualToString: bundleIdentifier]  ) {
                    return fullPath;
                }
            }
        }
    }
    
    return nil;
}

-(NSString *) targetPathToReplaceForDisplayName: (NSString *)     displayName
                                       inFolder: (NSString *)     folder
                                  infoPlistDict: (NSDictionary *) infoPlistDict
                              replacingTblkPath: (NSString *)     replacingTblkPath
                             cfBundleIdentifier: (NSString *)     cfBundleIdentifier
                                cfBundleVersion: (NSString *)     cfBundleVersion {
    
    // Uses cfBundleIdentifier and cfBundleVersion to check for a configuration that should be replaced.
    //
    // Returns nil if should decide replacement some other way
    // Returns "skip" to skip this one configuration
    // Returns "cancel" if user cancelled
    // Returns a string beginning with "/" containing the path to which the .tblk should be installed
    // Anything else that is returned is a localized error message
    
    if (  ! (   cfBundleIdentifier
             && cfBundleVersion)  ) {
        return nil;
    }
    
    NSString * file;
    NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: folder];
    while (  (file = [dirEnum nextObject])  ) {
        NSString * ext = [file pathExtension];
        if (  [ext isEqualToString: @"tblk"]  ) {
            
            [dirEnum skipDescendents];
            
            NSString * fullPath = [folder stringByAppendingPathComponent: file];
            
            NSDictionary * plist = [ConfigurationManager plistOrErrorMessageInTblkAtPath: fullPath];
            if (  [[plist class] isSubclassOfClass: [NSString class]]  ) {
                return (NSString *)plist;
            }
            if (  ! plist  ) {
                return nil;
            }
            
            NSString * cfBI   = [plist objectForKey: @"CFBundleIdentifier"];
            NSString * cfBV   = [plist objectForKey: @"CFBundleVersion"];
            if (  ! (   cfBI
                     && cfBV)  ) {
                continue;
            }
            
            if (  [cfBI isNotEqualTo: cfBundleIdentifier]  ) {
                continue;
            }
            
            BOOL doUninstall = (nil != [infoPlistDict objectForKey: @"TBUninstall"]);
            
			if (  doUninstall  ) {
				return fullPath;
			}
			
            NSString * localName = [((MenuController *)[NSApp delegate]) localizedNameforDisplayName: displayName tblkPath: fullPath];

			NSString * tbReplaceIdentical = [infoPlistDict objectForKey: @"TBReplaceIdentical"];
			
			if (  [tbReplaceIdentical isEqualToString: @"no"]  ) {
				NSLog(@"Tunnelblick VPN Configuration %@ will NOT be installed: TBReplaceOption=NO.", displayName);
				TBShowAlertWindow(@"Tunnelblick", 
								  [NSString stringWithFormat: NSLocalizedString(@"VPN Configuration %@ will NOT be installed because the configuration already exists and should not be replaced.", @"Window text"), localName]);
				return @"skip";
				
			}
			
			if (  [tbReplaceIdentical isEqualToString: @"yes"]  ) {
				if (  [cfBV compare: cfBundleVersion options: NSNumericSearch] == NSOrderedDescending  ) {
					NSLog(@"VPN Configuration %@ will NOT be installed: it has a lower version number.", displayName);
					TBShowAlertWindow(@"Tunnelblick", 
									  [NSString stringWithFormat: NSLocalizedString(@"VPN Configuration %@ will NOT be installed because it has a lower version number.", @"Window text"), localName]);
					return @"skip";
				}
			}
			
            if (   replacingTblkPath
                && ( ! [replacingTblkPath isEqualToString: fullPath] )  ) {
                return [NSString stringWithFormat:
                         NSLocalizedString(@"targetPathToReplaceForDisplayName: %@ was found to replace the configuration with CFBundleIdentifer %@, but earlier, %@ was found to replace it.", @"Window text"),
                        fullPath, cfBundleIdentifier, replacingTblkPath];
            }
            
            if (  [tbReplaceIdentical isEqualToString: @"ask"]  ) {
                
                NSString * msg;
                NSString * buttonName;
                if (  [cfBV compare: cfBundleVersion options: NSNumericSearch] == NSOrderedSame  ) {
					msg = [NSString stringWithFormat: NSLocalizedString(@"Do you wish to reinstall '%@' version %@?", @"Window text"),
						   localName,
						   cfBundleVersion];
					buttonName = NSLocalizedString(@"Reinstall", @"Button");
				} else {
					msg = [NSString stringWithFormat: NSLocalizedString(@"Do you wish to replace '%@' version %@ with version %@?", @"Window text"),
						   localName,
						   cfBundleVersion,
						   cfBV];
					buttonName = NSLocalizedString(@"Replace", @"Button");
				}
                
                int result = TBRunAlertPanel(NSLocalizedString(@"VPN Configuration Installation", @"Window title"),
                                             msg,
                                             buttonName,                                    // Default button
                                             NSLocalizedString(@"Skip"     , @"Button"),    // Alternate button
                                             NSLocalizedString(@"Cancel"   , @"Button"));   // Other button
                switch (  result  ) {
                        
                    case NSAlertDefaultReturn:
                        return fullPath;
                        
                    case NSAlertAlternateReturn:
                        return @"skip";
                        
                    case NSAlertOtherReturn:
                        return @"cancel";
                        
                    default:
                        return NSLocalizedString(@"TBRunAlertPanel returned an error", @"Window text");
                }
            }
			
            // Fell through, so tbReplaceIdentical == "force", so do the (un)install
            return fullPath;
        }
    }
    
    return nil;
}

-(NSString *) targetPathForDisplayName: (NSString *)     displayName
                         infoPlistDict: (NSDictionary *) infoPlistDict
                     replacingTblkPath: (NSString *)     replacingTblkPath
                    cfBundleIdentifier: (NSString *)     cfBundleIdentifier
                       cfBundleVersion: (NSString *)     cfBundleVersion {
    
    // Uses cfBundleIdentifier and cfBundleVersion to check for a configuration that should be replaced.
    //
    // Returns nil if should decide replacement using the displayName
    // Returns "skip" to skip this one configuration
    // Returns "cancel" if user cancelled
    // Returns a string beginning with "/" containing the path to which the .tblk should be installed
    // Anything else that is returned is a localized error message
    
    NSString * path;
	
	BOOL doUninstall = (nil != [infoPlistDict objectForKey: @"TBUninstall"]);

	if (  ! doUninstall  ) {
		path = [self targetPathToReplaceForDisplayName: displayName
											  inFolder: gDeployPath
										 infoPlistDict: infoPlistDict
									 replacingTblkPath: replacingTblkPath
									cfBundleIdentifier: cfBundleIdentifier
									   cfBundleVersion: cfBundleVersion];
		if (  path  ) {
			return path;
		}
	}
	
    path = [self targetPathToReplaceForDisplayName: displayName
                                          inFolder: L_AS_T_SHARED
                                     infoPlistDict: infoPlistDict
                                 replacingTblkPath: replacingTblkPath
                                cfBundleIdentifier: cfBundleIdentifier
                                   cfBundleVersion: cfBundleVersion];
    if (  path  ) {
        return path;
    }
    
    path = [self targetPathToReplaceForDisplayName: displayName
                                          inFolder: gPrivatePath
                                     infoPlistDict: infoPlistDict
                                 replacingTblkPath: replacingTblkPath
                                cfBundleIdentifier: cfBundleIdentifier
                                   cfBundleVersion: cfBundleVersion];
    return path;
}

-(NSString *) targetPathForDisplayName: (NSString *)     displayName
                         infoPlistDict: (NSDictionary *) infoPlistDict
                     replacingTblkPath: (NSString *)     replacingTblkPath
							  fromPath: (NSString *)     replacementTblkPath {
    
    // Returns "skip" if user want to skip this one configuration
    // Returns "cancel" if user cancelled
    // Returns a string beginning with "/" containing the path to which the .tblk should be installed
    // Anything else that is returned is a localized error message
    //
    // Note: infoPlistDict can be nil
    
    // If the Info.plist for this .tblk has CFBundleIdentifier and CFBundleVersion entries
    //    then see if we should replace based on them
    NSString * cfBundleIdentifier = [infoPlistDict objectForKey: @"CFBundleIdentifier"];
    NSString * cfBundleVersion    = [infoPlistDict objectForKey: @"CFBundleVersion"];
    if (   cfBundleIdentifier
        && cfBundleVersion  ) {
        NSString * result = [self targetPathForDisplayName: displayName
                                             infoPlistDict: infoPlistDict
                                         replacingTblkPath: replacingTblkPath
                                        cfBundleIdentifier: cfBundleIdentifier
                                           cfBundleVersion: cfBundleVersion];
        if (  result  ) {
            return result;
        }
    }
    
    // Otherwise, see if we should replace based on the displayName
    NSString * nameWithTblkExtension = [displayName stringByAppendingPathExtension: @"tblk"];
    NSString * fileInSharedPath      = [L_AS_T_SHARED stringByAppendingPathComponent: nameWithTblkExtension];
    NSString * fileInPrivatePath     = [gPrivatePath  stringByAppendingPathComponent: nameWithTblkExtension];
    
    BOOL replaceShared  = [gFileMgr fileExistsAtPath: fileInSharedPath];
    BOOL replacePrivate = [gFileMgr fileExistsAtPath: fileInPrivatePath];
    
    if (   replacePrivate
        && ( ! [self installToPrivateOK])  ) {
        return NSLocalizedString(@"You are not allowed to replace a private configuration", @"Window text");
    }
    if (   replaceShared
        && ( ! [self installToSharedOK])  ) {
        return NSLocalizedString(@"You are not allowed to replace a shared configuration", @"Window text");
    }
    
    NSString * tbSharePackage     = [infoPlistDict objectForKey: @"TBSharePackage"];
    NSString * tbReplaceIdentical = [infoPlistDict objectForKey: @"TBReplaceIdentical"];
    
	NSString * localizedName = [((MenuController *)[NSApp delegate]) localizedNameforDisplayName: displayName tblkPath: replacementTblkPath];
	
    NSString * sharedOrPrivate = @"private";
    
#ifdef AXION_DONT_BUILD
    if (   replaceShared
        && replacePrivate  ) {
        if (   (   [tbSharePackage isEqualToString: @"shared"]
                || [tbSharePackage isEqualToString: @"private"] )
            && (  ! [tbReplaceIdentical isEqualToString: @"ask"] )
            ) {
            sharedOrPrivate = tbSharePackage;
        } else {
            sharedOrPrivate =  [self askSharedOrPrivateForConfig: localizedName];
        }
    } else  if (  replacePrivate  ) {
        if (  ! [tbReplaceIdentical isEqualToString: @"ask"]  ) {
            sharedOrPrivate = @"private";
        } else {
            sharedOrPrivate = [self confirmReplace: localizedName in: @"private"];
        }
    } else if (  replaceShared  ) {
        if (  ! [tbReplaceIdentical isEqualToString: @"ask"]  ) {
            sharedOrPrivate = @"shared";
        } else {
            sharedOrPrivate = [self confirmReplace: localizedName in: @"shared"];
        }
    } else {
		id obj = [infoPlistDict objectForKey: @"TBUninstall"];
		if (  obj  ) {
			return nil;	// Uninstalling but no such configuration
		}
        if (  [self installToPrivateOK]  ) {
            if (  [self installToSharedOK]  ) {
                if (   [tbSharePackage isEqualToString: @"private"]
                    || [tbSharePackage isEqualToString: @"shared"] ) {
                    sharedOrPrivate = tbSharePackage;
                } else {
                    sharedOrPrivate =  [self askSharedOrPrivateForConfig: localizedName];
                }
            } else {
                sharedOrPrivate = @"private";
            }
        } else {
            if (  [self installToSharedOK]  ) {
                sharedOrPrivate =  @"shared";
            } else {
                sharedOrPrivate =  NSLocalizedString(@"Cannot install configurations to either shared or private locations", @"Window text");
            }
        }
    }
#endif
    
    NSString * displayNameWithTblkExtension = [displayName stringByAppendingPathExtension: @"tblk"];
    NSString * targetPath = nil;
    if (  [sharedOrPrivate isEqualToString: @"private"]  ) {
        targetPath = [gPrivatePath  stringByAppendingPathComponent: displayNameWithTblkExtension];
    } else if (  [sharedOrPrivate isEqualToString: @"shared"]  ) {
        targetPath = [L_AS_T_SHARED stringByAppendingPathComponent: displayNameWithTblkExtension];
    } else {
        targetPath = sharedOrPrivate; // Error or user cancelled or said to skip
    }
    
    return targetPath;
}

-(NSString *) convertOvpnOrConfAtPath: (NSString *) path
                         toTblkAtPath: (NSString *) toPath
                    replacingTblkPath: (NSString *) replacingTblkPath
                          displayName: (NSString *) theDisplayName
				 nameForErrorMessages: (NSString *) nameForErrorMessages
                     useExistingFiles: (NSArray *)  useExistingFiles
							 fromTblk: (BOOL)       fromTblk {
    
    // Returns nil or a localized string with an error message or the conversion log
    
    NSString * result = [ConfigurationManager checkForSampleConfigurationAtPath: path];
    if (  result  ) {
        return result;
    }
    
    NSString * ext  = [path pathExtension];
    if (   [ext isEqualToString: @"ovpn"]
        || [ext isEqualToString: @"conf"]  ) {
        
        // Convert the .ovpn or .conf to a .tblk
        ConfigurationConverter * converter = [[ConfigurationConverter alloc] init];
        NSString * result = [converter convertConfigPath: path
                                              outputPath: toPath
                                       replacingTblkPath: replacingTblkPath
                                             displayName: theDisplayName
                                    nameForErrorMessages: nameForErrorMessages
                                        useExistingFiles: useExistingFiles
                                                 logFile: NULL
                                                fromTblk: fromTblk];
        [converter release];
        
		return result;
    } else {
        return [NSString stringWithFormat: NSLocalizedString(@"Not a .ovpn or .conf: %@", @"Window text"), path];
    }
}

-(NSString *) convertInnerTblkAtPath: (NSString *)     innerFilePath
                       outerTblkPath: (NSString *)     outerTblkPath
                  outerTblkInfoPlist: (NSDictionary *) outerTblkInfoPlist
                         displayName: (NSString *)     displayName
                 isInAnUpdatableTblk: (BOOL)           isInAnUpdatableTblk {
    
    // Converts a .tblk or .ovpn/.conf at outerTblkPath/innerFilePath to a .tblk
    //
    // Returns nil, "cancel" or "skip" to indicate the user cancelled or wants to skip this configuration, or a string with a localized error message.
    
    
    NSString * fullPath = [outerTblkPath stringByAppendingPathComponent: innerFilePath];
    
    NSDictionary * mergedInfoPlist = [NSDictionary dictionaryWithDictionary: outerTblkInfoPlist];
    NSString * configPath = [NSString stringWithString: fullPath];
    
    if (  [[fullPath pathExtension] isEqualToString: @"tblk" ]  ) {
        
        // Get the inner .tblk's .plist (if any)
        id obj = [ConfigurationManager plistOrErrorMessageInTblkAtPath: fullPath];
        if (  [[obj class] isSubclassOfClass: [NSString class]]  ) {
            return (NSString *) obj;
        }
        if (  isInAnUpdatableTblk  ) {
            if (  ! obj  ) {
                return [NSString stringWithFormat: NSLocalizedString(@"Missing Info.plist for\n\n%@\n\n"
                                                                     @"This VPN Configuration is enclosed in an updatable outer VPN Configuration, so it must include an Info.plist.", @"Window text"), fullPath];
            }
        }
        NSDictionary * innerTblkInfoPlist = (NSDictionary *)obj;
        
        // Create a merged .plist -- outer with entries replaced by inner
        if (  outerTblkInfoPlist  ) {
			NSArray * allowedInnerPlistReplacementKeys = [NSArray arrayWithObjects:
														  @"CFBundleIdentifier",
														  @"CFBundleVersion",
														  @"CFBundleShortVersionString",
                                                          @"TBPackageVersion",
                                                          @"TBReplaceIdentical",
                                                          @"TBSharePackage",
                                                          @"TBKeepExistingFilesList",
                                                          @"TBUninstall",
                                                          nil];
            
            NSString * innerBundleIdentifier = nil;
            NSString * innerBundleVersion    = nil;
            NSMutableDictionary * mDict = [[outerTblkInfoPlist mutableCopy] autorelease];
            NSEnumerator * e = [innerTblkInfoPlist keyEnumerator];
            NSString * key;
            while (  (key = [e nextObject])  ) {
				id obj = [innerTblkInfoPlist objectForKey: key];
                if (  [key isEqualToString: @"CFBundleIdentifier"]  ) {
                    innerBundleIdentifier = (NSString *)obj;
					[mDict setObject: obj forKey: key];
                } else if (  [key isEqualToString: @"CFBundleVersion"]  ) {
                    innerBundleVersion    = (NSString *)obj;
					[mDict setObject: obj forKey: key];
				} else if (  [key hasPrefix: @"SU"]  ) {
					return [NSString stringWithFormat: NSLocalizedString(@"\"%@\" in the Info.plist for\n\n%@\n\nis not allowed because the Info.plist for an \"inner\" .tblk may not contain \"updatable\" .tblk entries.", @"Window text"), key, fullPath];
				} else 	if (   [allowedInnerPlistReplacementKeys containsObject: key]
							|| [key hasPrefix: @"TBPreference"]
							|| [key hasPrefix: @"TBAlwaysSetPreference"]  ) {
					[mDict setObject: obj forKey: key];
				} else if (  ! [[mDict objectForKey: key] isEqualTo: obj ]) {
					return [NSString stringWithFormat: NSLocalizedString(@"\"%@\" in the Info.plist for\n\n%@\n\nis not allowed in an \"inner\" .tblk or conflicts with the same entry in an \"outer\" .tblk.", @"Window text"), key, fullPath];
				}
			}
            
            if ( isInAnUpdatableTblk  ) {
                if (  ! (   innerBundleIdentifier
                         && innerBundleVersion)  )  {
                    return [NSString stringWithFormat: NSLocalizedString(@"Missing CFBundleIdentifier or CFBundleVersion in Info.plist for\n\n%@\n\n"
                                                                         @"This VPN Configuration is enclosed in an updatable outer VPN Configuration, so it must include its own CFBundleIdentifier and CFBundleVersion.", @"Window text"), fullPath];
                }
            }
            
            mergedInfoPlist = [NSDictionary dictionaryWithDictionary: mDict];
        } else {
            mergedInfoPlist = innerTblkInfoPlist;
        }
        
        // Get a relative path to the configuration file. If both a ".ovpn" and a ".conf" file exist, use the ".ovpn" file
        
        // (Put all the config files in a list, then look at the list)
        NSMutableArray * configFiles = [NSMutableArray arrayWithCapacity: 2];
        NSString * file;
        NSDirectoryEnumerator * innerEnum = [gFileMgr enumeratorAtPath: fullPath];
        while (  (file = [innerEnum nextObject])  ) {
            NSString * ext = [file pathExtension];
            if (   [ext isEqualToString: @"ovpn"]
                || [ext isEqualToString: @"conf"]
                ) {
                [configFiles addObject: file];
            } else if (  [ext isEqualToString: @"tblk"]  ) {
                return [NSString stringWithFormat: NSLocalizedString(@"A Tunnelblick VPN Configuration is nested too deeply in '%@'", @"Window text"), fullPath];
            }
        }
        
        NSString * configFile;
        if (  [configFiles count] == 0  ) {
            return [NSString stringWithFormat: NSLocalizedString(@"There is not an OpenVPN configuration file in '%@'", @"Window text"), fullPath];
        }
        if (  [configFiles count] == 1  ) {
            configFile = [configFiles objectAtIndex: 0];
            
        } else if (  [configFiles count] == 2  ) {
            NSString * first  = [configFiles objectAtIndex: 0];
            NSString * second = [configFiles objectAtIndex: 1];
            if (  [[first stringByDeletingPathExtension] isEqualToString: [second stringByDeletingPathExtension]]  ) {
                configFile = (  [[first pathExtension] isEqualToString: @"ovpn"]
                              ? first
                              : second);
            } else {
                return [NSString stringWithFormat: NSLocalizedString(@"Too many configuration files in '%@'", @"Window text"), fullPath];
            }
            
        } else {
            return [NSString stringWithFormat: NSLocalizedString(@"Too many configuration files in '%@'", @"Window text"), fullPath];
        }
        
        configPath = [fullPath stringByAppendingPathComponent: configFile];
    }
    
    // Do the conversion
    NSString * displayNameWithTblkExtension = [displayName stringByAppendingPathExtension: @"tblk"];
    NSString * outTblkPath = [[self tempDirPath] stringByAppendingPathComponent: displayNameWithTblkExtension];
    NSArray * useExistingFiles = [mergedInfoPlist objectForKey: @"TBKeepExistingFilesList"];
    
    NSString  * replacingTblkPath = [self pathOfTblkToReplaceWithBundleIdentifier: [mergedInfoPlist objectForKey: @"CFBundleIdentifier"]];
    
    // Warn if the configuration is connected and contains scripts. If the scripts are replaced with new ones, that could cause problems.
    if (  replacingTblkPath  ) {
        BOOL warnConfigurationIsConnected = FALSE;
        NSDictionary * configDict = [((MenuController *)[NSApp delegate]) myConfigDictionary];
        NSEnumerator * keyEnum = [configDict keyEnumerator];
        NSString * key;
        while (  (key = [keyEnum nextObject])  ) {
            if (  [key isEqualToString: replacingTblkPath]  ) {
                VPNConnection * connection = [configDict objectForKey: key];
                if (  ! [connection isDisconnected]  ) {
                    
                    NSString * file;
                    NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: replacingTblkPath];
                    while (  (file = [dirEnum nextObject])  ) {
                        if (  [file hasSuffix: @".sh"]) {
                            warnConfigurationIsConnected = TRUE;
                            break;
                        }
                    }
                }
                
                break;
            }
        }
        
        if (  warnConfigurationIsConnected  ) {
            NSString * localName = [((MenuController *)[NSApp delegate]) localizedNameforDisplayName: displayName tblkPath: replacingTblkPath];
            int result = TBRunAlertPanel(NSLocalizedString(@"VPN Configuration Installation", @"Window title"),
                                         [NSString stringWithFormat:
                                          NSLocalizedString(@"Configuration '%@' contains one or more scripts which may cause problems if you replace or uninstall the configuration while it is connected.\n\n"
                                                            @"Do you wish to replace the configuration?",
                                                            @"Window text"),
                                          localName],
                                         NSLocalizedString(@"Replace", @"Button"),   // Default button
                                         NSLocalizedString(@"Cancel",  @"Button"),   // Alternate button
                                         nil);                                       // Other button
            if (  result == NSAlertAlternateReturn  ) {
				return @"cancel";
            }
        }
    }
    
    NSString * result = [self convertOvpnOrConfAtPath: configPath
                                         toTblkAtPath: outTblkPath
                                    replacingTblkPath: replacingTblkPath
                                          displayName: displayName
								 nameForErrorMessages: (  [self multipleConfigurations]
                                                        ? displayName
                                                        : nil)
                                     useExistingFiles: useExistingFiles
											 fromTblk: YES];
    if (  result  ) {
        return result;
    }
    
    NSString * targetPath = [self targetPathForDisplayName: displayName
                                             infoPlistDict: mergedInfoPlist
                                         replacingTblkPath: replacingTblkPath
												  fromPath: fullPath];
	
	BOOL uninstall = (  [mergedInfoPlist objectForKey: @"TBUninstall"]
					  ? TRUE
					  : FALSE);
    if (  targetPath  ) {
        if (  [targetPath hasPrefix: @"/"]  ) {
            // It is a path
			if (  uninstall  ) {
				[[self deletions] addObject: targetPath];
			} else {
				if (  [gFileMgr fileExistsAtPath: targetPath]  ) {
					[[self replaceSources] addObject: outTblkPath];
					[[self replaceTargets] addObject: targetPath];
				} else {
					[[self installSources] addObject: outTblkPath];
					[[self installTargets] addObject: targetPath];
				}
			}
			
        } else {
            return  targetPath; // Error or user cancelled or said to skip this one
        }
	} else {
		if (  uninstall  ) {
            NSString * localName = [((MenuController *)[NSApp delegate]) localizedNameforDisplayName: displayName tblkPath: fullPath];
			return [NSString stringWithFormat: NSLocalizedString(@"Cannot uninstall configuration '%@' because it is not installed.", @"Window text"), localName];
		}
    }
    
    return nil;
}

-(id) updatablePlistIn: (NSString *) path {
	
	// Returns nil or, if the .tblk at path is updatable, its .plist, or if there is an error in the .plist, a string with the localized error message
	
	id obj = [ConfigurationManager plistOrErrorMessageInTblkAtPath: path];
	
	// Not updatable if no .plist
	if (  ! obj  ) {
		return nil;
	}
	
	// Not updatable if .plist contains errors
	if (  ! [[obj class] isSubclassOfClass: [NSDictionary class]]  ) {
		return obj;
	}
	
	NSDictionary * plist = (NSDictionary *)obj;
	
	// Not updatable if doesn't have CFBundleIdentifier, CFBundleVersion, and SUFeedURL
    if (  ! (   [plist objectForKey: @"CFBundleIdentifier"]
             && [plist objectForKey: @"CFBundleVersion"]
             && [plist objectForKey: @"SUFeedURL"]
             )  ) {
        return nil;
    }
    
	// It is updatable; return its .plist
	return plist;
}

-(NSString *) convertOuterTblk: (NSString *) outerTblkPath
			   haveOvpnOrConfs: (BOOL)       haveOvpnOrConfs {
    
    // Returns nil, or "cancel" if the user cancelled, or a string with a localized error message.
    
    // A .tblk (or a subfolder within it) can have both a .conf and a .ovpn file, in which case we ignore the .conf and only process the .ovpn
    // We do that by building a list of all of the .conf and .ovpn files as we iterate through the outer .tblk's directory structure
    // Then, after we've finished that, we create a new list without any .conf files that have corresponding .ovpn files.
    // Finally, we iterate over that array processing the .tblk, .ovpn, and .conf files.
    
	
	BOOL thisIsTheLastTblk = [self inhibitCheckbox];  // This outer .tblk is the last .tblk in the tblkPaths array
	
    // Get, and check, the .plist for this outer .tblk if there is one
    id obj = [ConfigurationManager plistOrErrorMessageInTblkAtPath: outerTblkPath];
    if (  [[obj class] isSubclassOfClass: [NSString class]]  ) {
        return (NSString *) obj;
    }
    NSDictionary * outerTblkPlist = (NSDictionary *)obj;
    
	obj = [self updatablePlistIn: outerTblkPath];
	if (  obj  ) {
		if (  ! [[obj class] isSubclassOfClass: [NSDictionary class]]  ) {
			return (NSString *)obj; // An error message
		}
    }
	NSDictionary * outerUpdatablePlist = (NSDictionary *)obj;
		
    // Build lists of .tblks and of .ovpn/.conf files
    NSMutableArray * ovpnAndConfInnerFilePartialPaths = [NSMutableArray arrayWithCapacity: 100];
    NSMutableArray * tblkInnerFilePartialPaths        = [NSMutableArray arrayWithCapacity: 100];
    
    NSString * innerFilePartialPath;
    NSDirectoryEnumerator * outerEnum = [gFileMgr enumeratorAtPath: outerTblkPath];
    while (  (innerFilePartialPath = [outerEnum nextObject])  ) {
        NSString * ext = [innerFilePartialPath pathExtension];
        if (  [ext isEqualToString: @"tblk"]  ) {
            [outerEnum skipDescendents]; // Don't look inside the .tblk
            [tblkInnerFilePartialPaths addObject: innerFilePartialPath];
            
        } else if (   [ext isEqualToString: @"ovpn"]
                   || [ext isEqualToString: @"conf"]  ) {
            [ovpnAndConfInnerFilePartialPaths addObject: innerFilePartialPath];
        }
    }
    
    // Remove .conf files from the list if the corresponding .ovpn file is on the list
    NSEnumerator * e = [ovpnAndConfInnerFilePartialPaths objectEnumerator];
    while (  (innerFilePartialPath = [e nextObject])  ) {
        NSString * withoutExt = [innerFilePartialPath stringByDeletingPathExtension];
        NSString * ovpnFilePath = [withoutExt stringByAppendingPathExtension: @"ovpn"];
        NSString * confFilePath = [withoutExt stringByAppendingPathExtension: @"conf"];
        if (   [ovpnAndConfInnerFilePartialPaths containsObject: ovpnFilePath]
            && [ovpnAndConfInnerFilePartialPaths containsObject: confFilePath]  ) {
            [ovpnAndConfInnerFilePartialPaths removeObject: confFilePath];
        }
    }
    
    // Complain if nothing to convert
	if (   ([tblkInnerFilePartialPaths       count] == 0)
		&& ([ovpnAndConfInnerFilePartialPaths count] == 0)  ) {
		if (  [self multipleConfigurations]  ) {
			return [NSString stringWithFormat: NSLocalizedString(@"In %@:\n\nThere are no OpenVPN configurations to install.", @"Window text"), outerTblkPath];
		} else {
			return NSLocalizedString(@"There are no OpenVPN configurations to install.", @"Window text");
		}
	}
	
    // Convert .ovpn/.conf files
    NSUInteger ix;
    for (  ix=0; ix<[ovpnAndConfInnerFilePartialPaths count]; ix++  ) {
        
        [self setInhibitCheckbox: (   thisIsTheLastTblk
								   && ( ! haveOvpnOrConfs)
                                   && ( ix == [ovpnAndConfInnerFilePartialPaths count] - 1)
								   && ( [tblkInnerFilePartialPaths count] == 0)   )];
		
        NSString * configPartialPath = [ovpnAndConfInnerFilePartialPaths objectAtIndex: ix];
        
		NSString * result =[self convertInnerTblkAtPath: configPartialPath
										  outerTblkPath: outerTblkPath
									 outerTblkInfoPlist: outerTblkPlist
                                            displayName: (  ([ovpnAndConfInnerFilePartialPaths count] > 1)
                                                          ? [configPartialPath stringByDeletingPathExtension]
                                                          : [[outerTblkPath lastPathComponent] stringByDeletingPathExtension])
                                    isInAnUpdatableTblk: (outerUpdatablePlist != nil)];
        if (   result  ) {
            if (  [result isEqualToString: @"skip"]  ) {
                return nil;
            }
            return result;
        }
    }
    
	// Convert .tblks
    for (  ix=0; ix<[tblkInnerFilePartialPaths count]; ix++  ) {
        
        [self setInhibitCheckbox: (   thisIsTheLastTblk
								   && ( ! haveOvpnOrConfs)
								   && (ix == [tblkInnerFilePartialPaths count] - 1)  )];
		
        innerFilePartialPath   = [tblkInnerFilePartialPaths objectAtIndex: ix];
        NSString * displayName = [innerFilePartialPath stringByDeletingPathExtension];
		if (  [displayName hasPrefix: @"Contents/Resources"]  ) {
			displayName = [displayName substringFromIndex: [@"Contents/Resources" length]];
		}
        
        NSString * result = [self convertInnerTblkAtPath: innerFilePartialPath
                                           outerTblkPath: outerTblkPath
                                      outerTblkInfoPlist: outerTblkPlist
                                             displayName: displayName
                                     isInAnUpdatableTblk: (outerUpdatablePlist != nil)];
        if (   result  ) {
            if (  [result isEqualToString: @"skip"]  ) {
                continue;
            }
            return result;
        }
    }
	
	// If this outer .tblk is an updatable .tblk, create a "stub" .tblk and add it to 'updateSources' and 'updateTargets'
    if (  outerUpdatablePlist  ) {
		// Create a stub .tblk in the temporary folder's "Updatables" subfolder.
		// A stub consists of an Info.plist file and a "uninstalled" file inside a "Contents" folder inside a .tblk.
        // A "Resources" folder inside the "Contents" folder may contain a DSA key file if there is one.
        
        // Get the path at which to create the stub .tblk.
		NSString * cfBI = [outerUpdatablePlist objectForKey: @"CFBundleIdentifier"];
		NSString * tblkName = [cfBI stringByAppendingPathExtension: @"tblk"];
		NSString * tblkStubPath = [[[self tempDirPath] stringByAppendingPathComponent: @"Updatables"]
								   stringByAppendingPathComponent: tblkName];
        
        // Make sure we haven't processed a configuration with that CFBundleIdentifier already
		if (  [gFileMgr fileExistsAtPath: tblkStubPath]  ) {
            return [NSString stringWithFormat: NSLocalizedString(@"Updatable configuration '%@' was not stored as updatable because that CFBundleIdentifier has already been processed\n", @"Window text"), cfBI];
		}
		
        // Create the Contents directory
		NSString * contentsPath = [tblkStubPath stringByAppendingPathComponent: @"Contents"];
		if (  createDir(contentsPath, PERMS_SECURED_FOLDER) == -1 ) {
            return [NSString stringWithFormat: NSLocalizedString(@"Updatable configuration '%@' was not stored as updatable because 'Contents' in the stub .tblk could not be created\n", @"Window text"), cfBI];
		}
		
        // Copy the Info.plist into the Contents directory and set its permissions
		NSString * plistPath = [contentsPath stringByAppendingPathComponent: @"Info.plist"];
		if (  ! [outerUpdatablePlist writeToFile: plistPath atomically: YES]  ) {
            return [NSString stringWithFormat: NSLocalizedString(@"Updatable configuration '%@' was not stored as updatable because its Info.plist could not be stored in the stub .tblk\n", @"Window text"), cfBI];
		}
        NSDictionary * attributes = [NSDictionary dictionaryWithObject: [NSNumber numberWithInt: PERMS_SECURED_READABLE] forKey: NSFilePosixPermissions];
		if (  ! [gFileMgr tbChangeFileAttributes: attributes atPath: plistPath]  ) {
            return [NSString stringWithFormat: NSLocalizedString(@"Failed to set permissions on %@\n", @"Window text"), plistPath];
        }
		
		// Create the "uninstalled" file in the Contents directory
		NSString * uninstalledFilePath = [contentsPath stringByAppendingPathComponent: @"installed"];
		if (  ! [gFileMgr createFileAtPath: uninstalledFilePath contents: [NSData data] attributes: attributes]  ) {
            return [NSString stringWithFormat: NSLocalizedString(@"Configuration '%@' is not updatable because it could not be marked as 'updatable'.\n", @"Window text"), cfBI];
		}
		
        /*
        // If there is a DSA key file, copy that, too, but into "Contents/Resources", and set its permissions
        id obj = [outerUpdatablePlist objectForKey: @"SUPublicDSAKeyFile"];
        if (  obj  ) {
			if (  ! [[obj class] isSubclassOfClass: [NSString class]]  ) {
                return [NSString stringWithFormat: NSLocalizedString(@"Updatable configuration '%@' was not stored as updatable because 'SUPublicDSAKeyFile' was not a string\n", @"Window text"), cfBI];
			}
            NSString * suDSAKeyFileName = (NSString *)obj;
            if (  ! [suDSAKeyFileName isEqualToString: [suDSAKeyFileName lastPathComponent]]  ) {
                return [NSString stringWithFormat: NSLocalizedString(@"Updatable configuration '%@' was not stored as updatable because 'SUPublicDSAKeyFile' was not a file name with optional extension\n", @"Window text"), cfBI];
            }
            // Look for the key file first in the outer .tblk, then in the outer .tblk's Contents/Resources folder
            NSString * dsaKeyFilePath = [outerTblkPath stringByAppendingPathComponent: suDSAKeyFileName];
            if (  ! [gFileMgr fileExistsAtPath: dsaKeyFilePath]  ) {
                dsaKeyFilePath = [[[outerTblkPath stringByAppendingPathComponent: @"Contents"]
                                   stringByAppendingPathComponent: @"Resources"]
                                  stringByAppendingPathComponent: suDSAKeyFileName];
                if (  ! [gFileMgr fileExistsAtPath: dsaKeyFilePath]  ) {
                    return [NSString stringWithFormat: NSLocalizedString(@"Updatable configuration '%@' was not stored as updatable because %@ could not be found\n", @"Window text"), cfBI, suDSAKeyFileName];
                }
            }
            
            NSString * resourcesPath = [contentsPath stringByAppendingPathComponent: @"Resources"];
            if (  createDir(resourcesPath, PERMS_SECURED_FOLDER) == -1 ) {
                return [NSString stringWithFormat: NSLocalizedString(@"Updatable configuration '%@' was not stored as updatable because 'Contents/Resources' in the stub .tblk could not be created\n", @"Window text"), cfBI];
            }
            NSString * targetDSAKeyPath = [resourcesPath stringByAppendingPathComponent: suDSAKeyFileName];
            if (  ! [gFileMgr tbCopyPath: dsaKeyFilePath toPath: targetDSAKeyPath handler: nil]  ) {
                return [NSString stringWithFormat: NSLocalizedString(@"Updatable configuration '%@' was not stored as updatable because '%@' could not be copied to '%@'\n", @"Window text"), cfBI, dsaKeyFilePath, targetDSAKeyPath];
            }
            if (  ! [gFileMgr tbChangeFileAttributes: attributes atPath: targetDSAKeyPath]  ) {
                return [NSString stringWithFormat: NSLocalizedString(@"Failed to set permissions on %@\n", @"Window text"), targetDSAKeyPath];
            }
        } else {
            // No DSA key file. SUFeedURL must be https://
            id obj = [outerUpdatablePlist objectForKey: @"SUFeedURL"];
            if (   ( ! obj)
                || ( ! [[obj class] isSubclassOfClass: [NSString class]] )
                || ( ! [(NSString *)obj hasPrefix: @"https://"]  )  ) {
                return [NSString stringWithFormat: NSLocalizedString(@"Updatable configuration '%@' was not stored as updatable because its Info.plist 'SUFeedURL' did not start with 'https://' and there was no 'SUPublicDSAKeyFile' entry\n", @"Window text"), cfBI];
            }
        }
        
        */ ///AXION

		NSString * targetPath = [[L_AS_T_TBLKS stringByAppendingPathComponent: cfBI]
                                 stringByAppendingPathComponent: [outerTblkPath lastPathComponent]];
		[[self updateSources] addObject: tblkStubPath];
		[[self updateTargets] addObject: targetPath];
	}
    
    return nil;
}

-(NSString *) setupToInstallTblks: (NSArray *)  tblkPaths
				  haveOvpnOrConfs: (BOOL)       haveOvpnOrConfs {
    
    // Converts non-normalized .tblks to normalized .tblks (with Contents/Resources) in the temporary folder at tempDirPath
    // Adds paths of .tblks that are to be UNinstalled to the 'deletions' array
    // Adds paths of .tblks that are to be installed   to the 'installSources' or 'replaceSources' array and targets (in private or shared) to the 'installTargets' or 'replaceTargets' array
    //
    // Returns nil      if converted with no problem
    // Returns "cancel" if the user cancelled
    // Returns "skip"   if the user skipped the last configuration
    // Otherwise returns a string with a localized error message
    
    NSUInteger ix;
    for (  ix=0; ix<[tblkPaths count]; ix++  ) {
        
        // If there are no more configurations to set up, don't show the 'Apply to all' checkbox
        [self setInhibitCheckbox: (ix == [tblkPaths count] - 1)];
        
        NSString * path = [tblkPaths objectAtIndex: ix];
        
        NSString * result = [self convertOuterTblk: path haveOvpnOrConfs: haveOvpnOrConfs];
        if (   result
            && [result isNotEqualTo: @"skip"]  ) {
			return result;
        }
    }
    
    return nil;
}

-(NSString *) setupToInstallOvpnsAndConfs: (NSArray *)  ovpnPaths {
    
    // Converts .ovpns and/or .confs to normalized .tblks (with Contents/Resources) in the temporary folder at tempDirPath
    // Adds paths of .tblks that are to be installed   to the 'installSources' or 'replaceSources' array and targets (in private or shared) to the 'installTargets' or 'replaceTargets' array
    //
    // Returns nil      if converted with no problem
    // Returns "cancel" if the user cancelled
    // Returns "skip"   if the user skipped the last configuration
    // Otherwise returns a string with a localized error message
    
    NSUInteger ix;
    for (  ix=0; ix<[ovpnPaths count]; ix++  ) {
        
        // If there are no more configurations to set up, don't show the 'Apply to all' checkbox
        [self setInhibitCheckbox: (ix == [ovpnPaths count] - 1)];
        
        NSString * path = [ovpnPaths objectAtIndex: ix];
		NSString * fileName = [path lastPathComponent];
		NSString * displayName = [fileName stringByDeletingPathExtension];
		NSString * displayNameWithTblkExtension = [displayName stringByAppendingPathExtension: @"tblk"];
		NSString * outTblkPath = [[self tempDirPath] stringByAppendingPathComponent: displayNameWithTblkExtension];
		
		// Do the conversion
        NSString * result = [self convertOvpnOrConfAtPath: path
                                             toTblkAtPath: outTblkPath
                                        replacingTblkPath: nil
                                              displayName: nil
                                     nameForErrorMessages: (  [self multipleConfigurations]
                                                            ? displayName
                                                            : nil)
                                         useExistingFiles: nil
                                                 fromTblk: NO];
        
        if (  result  ) {
			return result;
        }
		
        NSString * targetPath = [self targetPathForDisplayName: displayName
                                                 infoPlistDict: nil
                                             replacingTblkPath: nil
													  fromPath: outTblkPath];
        NSLog(@"Installing to: %@",targetPath);
        if (  targetPath  ) {
            if (  [targetPath hasPrefix: @"/"]  ) {
                // It is a path
				if (  [gFileMgr fileExistsAtPath: targetPath]  ) {
					[[self replaceSources] addObject: outTblkPath];
					[[self replaceTargets] addObject: targetPath];
				} else {
					[[self installSources] addObject: outTblkPath];
					[[self installTargets] addObject: targetPath];
				}
            } else if (  [targetPath isNotEqualTo: @"skip"]  ) {
                return targetPath; // Error or user cancelled
            }
        }
    }
    
 	return nil;
}

-(NSString *) setupToInstallOvpnsAndConfsAxion: (NSArray *)  ovpnPaths {
    
    // Converts .ovpns and/or .confs to normalized .tblks (with Contents/Resources) in the temporary folder at tempDirPath
    // Adds paths of .tblks that are to be installed   to the 'installSources' or 'replaceSources' array and targets (in private or shared) to the 'installTargets' or 'replaceTargets' array
    //
    // Returns nil      if converted with no problem
    // Returns "cancel" if the user cancelled
    // Returns "skip"   if the user skipped the last configuration
    // Otherwise returns a string with a localized error message
    NSLog(@"[setupToInstallOvpnsAndConfsAxion] Called");
    
    NSUInteger ix;
    for (  ix=0; ix<[ovpnPaths count]; ix++  ) {
        
        // If there are no more configurations to set up, don't show the 'Apply to all' checkbox
        [self setInhibitCheckbox: (ix == [ovpnPaths count] - 1)];
        
        NSString * path = [ovpnPaths objectAtIndex: ix];
        NSString * fileName = [path lastPathComponent];
        NSString * displayName = [fileName stringByDeletingPathExtension];
        NSString * displayNameWithTblkExtension = [displayName stringByAppendingPathExtension: @"tblk"];
        NSString * outTblkPath = [[self tempDirPath] stringByAppendingPathComponent: displayNameWithTblkExtension];
        
        
        NSLog(@"path: %@",path);
        NSLog(@"outTblkPath: %@",outTblkPath);
        
        // Do the conversion
        NSString * result = [self convertOvpnOrConfAtPath: path
                                             toTblkAtPath: outTblkPath
                                        replacingTblkPath: nil
                                              displayName: nil
                                     nameForErrorMessages: (  [self multipleConfigurations]
                                                            ? displayName
                                                            : nil)
                                         useExistingFiles: nil
                                                 fromTblk: NO];
        
        if (  result  ) {
            return result;
        }
        
        NSLog(@"[setupToInstall] Checkpoint 1");
        NSString * targetPath = [self targetPathForDisplayName: displayName
                                                 infoPlistDict: nil
                                             replacingTblkPath: nil
                                                      fromPath: outTblkPath];
        NSLog(@"[setupToInstall] Installing to: %@",targetPath);
        if (  targetPath  ) {
            if (  [targetPath hasPrefix: @"/"]  ) {
                // It is a path
                if (  [gFileMgr fileExistsAtPath: targetPath]  ) {
                    [[self replaceSources] addObject: outTblkPath];
                    [[self replaceTargets] addObject: targetPath];
                } else {
                    [[self installSources] addObject: outTblkPath];
                    [[self installTargets] addObject: targetPath];
                }
            } else if (  [targetPath isNotEqualTo: @"skip"]  ) {
                return targetPath; // Error or user cancelled
            }
        }
    }
    
    return nil;
}

-(BOOL) checkFilesAreReasonable: (NSArray *) paths {
    
    NSString * tooBigMsg = nil;
    NSString * path;
    NSEnumerator * e = [paths objectEnumerator];
    while (  (path = [e nextObject])  ) {
		tooBigMsg = allFilesAreReasonableIn(path);
        if (  tooBigMsg  ) {
			break;
        }
    }
    if (  tooBigMsg  ) {
        TBShowAlertWindow(NSLocalizedString(@"VPN Configuration Installation Error", @"Window title"),
                          [NSString stringWithFormat:
						   NSLocalizedString(@"There was a problem:\n\n"
										     @"%@", "Window text"),
						   tooBigMsg]);
        return FALSE;
    }
    
    return TRUE;
}

-(void) cleanupInstallAndNotifyDelegate: (BOOL)                       notifyDelegate
                    delegateNotifyValue: (NSApplicationDelegateReply) delegateNotifyValue {
    
    if (   [self authWasNull]
        && (gAuthorization != NULL)  ) {
        AuthorizationFree(gAuthorization, kAuthorizationFlagDefaults);
        gAuthorization = NULL;
    }
    
    NSString * path = [self tempDirPath];
	if (  [gFileMgr fileExistsAtPath: path]  ) {
		if (  ! [gFileMgr tbRemoveFileAtPath: path handler: nil]  ) {
			NSLog(@"Unable to delete directory %@", path);
		}
	}
    
    if (  notifyDelegate  ) {
        [NSApp replyToOpenOrPrint: delegateNotifyValue];
    }
}

-(NSApplicationDelegateReply) doUninstallslReplacementsInstallsSkipConfirmMsg: (BOOL) skipConfirmMsg
                                                                skipResultMsg: (BOOL) skipResultMsg {
    
    // Does the work to uninstall, replace, and/or install configurations from the 'deletions', 'installSource', 'replaceSource', etc. arrays
    //
    // Returns the value that the delegate should use as an argument to '[NSApp replyToOpenOrPrint:]' (whether or not it will be needed)
    
    NSUInteger nToUninstall = [[self deletions]      count];
    NSUInteger nToInstall   = [[self installSources] count];
    NSUInteger nToReplace   = [[self replaceSources] count];
    
    // If there's nothing to do, just return as if the user cancelled
    if (  (nToUninstall + nToInstall + nToReplace) == 0  ) {
        return NSApplicationDelegateReplyCancel;
    }
    
    // If there is no gAuthorization currently, get one (it is release by cleanupInstall:); otherwise confirm what we are about to do
    
    NSString * uninstallMsg = (  (nToUninstall == 0)
                               ? @""
                               : (  (nToUninstall == 1)
                                  ? NSLocalizedString(@"    • Uninstall one configuration\n", @"Window text: 'AxionVPN needs to: *'")
                                  : [NSString stringWithFormat: NSLocalizedString(@"    • Uninstall %lu configurations\n\n", @"Window text: 'AxionVPN needs to: *'"), (unsigned long)nToUninstall]));
    NSString * replaceMsg   = (  (nToReplace == 0)
                               ? @""
                               : (  (nToReplace == 1)
                                  ? NSLocalizedString(@"    • Replace one configuration\n", @"Window text: 'AxionVPN needs to: *'")
                                  : [NSString stringWithFormat: NSLocalizedString(@"    • Replace %lu configurations\n\n", @"Window text: 'AxionVPN needs to: *'"), (unsigned long)nToReplace]));
    NSString * installMsg   = (  (nToInstall == 0)
                               ? @""
                               : (  (nToInstall == 1)
                                  ? NSLocalizedString(@"    • Install one configuration\n", @"Window text: 'AxionVPN needs to: *'")
                                  : [NSString stringWithFormat: NSLocalizedString(@"    • Install %lu configurations\n\n", @"Window text: 'AxionVPN needs to: *'"), (unsigned long)nToInstall]));
    NSString * authMsg = [NSString stringWithFormat: @"AxionVPN needs to:\n\n%@%@%@", uninstallMsg, replaceMsg, installMsg];
  
#ifdef AXION_DONT_BUILD
    
    if ( gAuthorization == NULL  ) {
        
        gAuthorization = [NSApplication getAuthorizationRef: authMsg];
        if (  gAuthorization == NULL  ) {
            return NSApplicationDelegateReplyCancel;
        }
    } else {
        
        if (  ! skipConfirmMsg  ) {
            int result = TBRunAlertPanel(NSLocalizedString(@"VPN Configuration Installation", @"Window title"),
                                         authMsg,
                                         NSLocalizedString(@"OK",      @"Button"),   // Default button
                                         NSLocalizedString(@"Cancel",  @"Button"),   // Alternate button
                                         nil);                                       // Other button
            if (  result == NSAlertAlternateReturn  ) {
                return NSApplicationDelegateReplyCancel;
            }
        }
    }
#endif
    // Do the actual installs and uninstalls
    
    NSUInteger nUninstallErrors = 0;
    NSUInteger nInstallErrors   = 0;
    NSUInteger nReplaceErrors   = 0;
    NSUInteger nUpdateErrors    = 0;
    
    NSMutableString * installerErrorMessages = [NSMutableString stringWithCapacity: 1000];
    
    NSUInteger ix;
    
    // Un-install .tblks in 'deletions'
    for (  ix=0; ix<[[self deletions] count]; ix++  ) {
        
        NSString * target = [[self deletions] objectAtIndex: ix];
        
        if (  ! [self deleteConfigPath: target
                       usingAuthRefPtr: &gAuthorization
                            warnDialog: NO]  ) {
            nUninstallErrors++;
            NSString * targetDisplayName   = [lastPartOfPath(target) stringByDeletingPathExtension];
            NSString * targetLocalizedName = [((MenuController *)[NSApp delegate]) localizedNameforDisplayName: targetDisplayName tblkPath: target];
            [installerErrorMessages appendString: [NSString stringWithFormat: NSLocalizedString(@"Unable to uninstall the '%@' configuration\n", @"Window text"), targetLocalizedName]];
        }
    }
    
    // Install .tblks in 'installSources' to 'installTargets'
    for (  ix=0; ix<[[self installSources] count]; ix++  ) {
        
        NSString * source = [[self installSources] objectAtIndex: ix];
        NSString * target = [[self installTargets] objectAtIndex: ix];
        NSString * targetDisplayName = [lastPartOfPath(target) stringByDeletingPathExtension];
        
        if (  [self copyConfigPath: source
                            toPath: target
                   usingAuthRefPtr: &gAuthorization
                        warnDialog: NO
                       moveNotCopy: NO]  ) {
            
            NSDictionary * connDict = [((MenuController *)[NSApp delegate]) myVPNConnectionDictionary];
            BOOL replacedTblk = (nil != [connDict objectForKey: targetDisplayName]);
            if (  replacedTblk  ) {
                // Force a reload of the configuration's preferences using any new TBPreference and TBAlwaysSetPreference items in its Info.plist
                [((MenuController *)[NSApp delegate]) deleteExistingConfig: targetDisplayName ];
                [((MenuController *)[NSApp delegate]) addNewConfig: target withDisplayName: targetDisplayName];
                [[((MenuController *)[NSApp delegate]) logScreen] update];
            }
            
        } else {
            nInstallErrors++;
            NSString * targetDisplayName = [lastPartOfPath(target) stringByDeletingPathExtension];
            NSString * targetLocalizedName = [((MenuController *)[NSApp delegate]) localizedNameforDisplayName: targetDisplayName tblkPath: target];
            [installerErrorMessages appendString: [NSString stringWithFormat: NSLocalizedString(@"Unable to install the '%@' configuration\n", @"Window text"), targetLocalizedName]];
        }
    }
    
    // Install .tblks in 'replaceSources' to 'replaceTargets'
    for (  ix=0; ix<[[self replaceSources] count]; ix++  ) {
        
        NSString * source = [[self replaceSources] objectAtIndex: ix];
        NSString * target = [[self replaceTargets] objectAtIndex: ix];
        NSString * targetDisplayName = [lastPartOfPath(target) stringByDeletingPathExtension];
        
        if (  [self copyConfigPath: source
                            toPath: target
                   usingAuthRefPtr: &gAuthorization
                        warnDialog: NO
                       moveNotCopy: NO]  ) {
            
            NSDictionary * connDict = [((MenuController *)[NSApp delegate]) myVPNConnectionDictionary];
            VPNConnection * connection = [connDict objectForKey: targetDisplayName];
            if (  connection  ) {
                // Force a reload of the configuration's preferences using any new TBPreference and TBAlwaysSetPreference items in its Info.plist
                [connection reloadPreferencesFromTblk];
                [[((MenuController *)[NSApp delegate]) logScreen] update];
            }
            
        } else {
            nReplaceErrors++;
            NSString * targetDisplayName = [lastPartOfPath(target) stringByDeletingPathExtension];
            NSString * targetLocalizedName = [((MenuController *)[NSApp delegate]) localizedNameforDisplayName: targetDisplayName tblkPath: target];
            [installerErrorMessages appendString: [NSString stringWithFormat: NSLocalizedString(@"Unable to replace the '%@' configuration\n", @"Window text"), targetLocalizedName]];
        }
    }
    
    // Copy updatable stub .tblks into L_AS_T_TBLKS
    
    // We need to modify target paths to insert the edition number (a unique integer).
    // So it changes from   /something/.../com.example.something/something
    //                 to   /something/.../com.example.something_EDITION/something
    // We set each new edition number to one more than the highest existing edition number
    
    // So first, we find the highest existing edition number
    NSString * highestEdition = nil;
    NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: L_AS_T_TBLKS];
    NSString * file;
    while (  (file = [dirEnum nextObject])  ) {
        [dirEnum skipDescendents];
        if (   ( ! [file hasPrefix: @"."] )
            && ( ! [file hasSuffix: @".tblk"] )  ) {
            NSString * edition = [file pathEdition];
            if (   ( [edition length] != 0 )
                && (   ( ! highestEdition )
                    || [edition caseInsensitiveNumericCompare: highestEdition] == NSOrderedDescending )  ) {
                    highestEdition = edition;
                }
        }
    }
    if (  ! highestEdition  ) {
        highestEdition = @"-1";
    }
    
    // Now go through and copy the stub .tblks, modifying each target path as we go
    
    for (  ix=0; ix<[[self updateSources] count]; ix++  ) {
        
        NSString * source = [[self updateSources] objectAtIndex: ix];
        NSString * target = [[self updateTargets] objectAtIndex: ix];
        
        // Insert the new edition into the target path as a suffix to the next-to-last path component
        
        NSString * targetLast        = [target lastPathComponent];
        NSString * targetWithoutLast = [target stringByDeletingLastPathComponent];
        NSString * bundleId          = [targetWithoutLast lastPathComponent];
        
        highestEdition = [NSString stringWithFormat: @"%u", (unsigned)[highestEdition intValue] + 1];
        
        target = [[targetWithoutLast
                   stringByAppendingFormat: @"_%@", highestEdition]
                  stringByAppendingPathComponent: targetLast];
        
        NSArray * arguments = [NSArray arrayWithObjects: target, source, nil];
        NSInteger installerResult = [((MenuController *)[NSApp delegate]) runInstaller: 0
                                                                        extraArguments: arguments];
        if (  installerResult == 0  ) {
            [[((MenuController *)[NSApp delegate]) myConfigMultiUpdater] stopUpdateCheckingForAllStubTblksWithBundleIdentifier: bundleId];
            [[((MenuController *)[NSApp delegate]) myConfigMultiUpdater] addUpdateCheckingForStubTblkAtPath: target];
        } else {
            nUpdateErrors++;
            [installerErrorMessages appendString: [NSString stringWithFormat: NSLocalizedString(@"Unable to store updatable configuration stub at %@\n", @"Window text"), target]];
        }
    }
    
    // Construct and display a window with the results of the uninstalls/replacements/installs
    
    NSUInteger nTotalErrors = nUninstallErrors + nInstallErrors + nReplaceErrors + nUpdateErrors;
    
    if (   (nTotalErrors != 0)
        || ( ! skipResultMsg )  ) {
        
        NSString * msg = nil;
        
        NSUInteger nNetUninstalls   = nToUninstall - nUninstallErrors;
        NSUInteger nNetInstalls     = nToInstall   - nInstallErrors;
        NSUInteger nNetReplacements = nToReplace   - nReplaceErrors;
        
        uninstallMsg = (  (nNetUninstalls == 0)
                        ? @""
                        : (  (nNetUninstalls == 1)
                           ? NSLocalizedString(@"     • Uninstalled one configuration\n\n", @"Window text: 'Tunnelblick succesfully: *'")
                           : [NSString stringWithFormat: NSLocalizedString(@"     • Uninstalled %lu configurations\n\n", @"Window text: 'Tunnelblick succesfully: *'"), (unsigned long)nNetUninstalls]));
        replaceMsg   = (  (nNetReplacements == 0)
                        ? @""
                        : (  (nNetReplacements == 1)
                           ? NSLocalizedString(@"     • Replaced one configuration\n\n", @"Window text: 'Tunnelblick succesfully: *'")
                           : [NSString stringWithFormat: NSLocalizedString(@"     • Replaced %lu configurations\n\n", @"Window text: 'Tunnelblick succesfully: *'"), (unsigned long)nNetReplacements]));
        installMsg   = (  (nNetInstalls == 0)
                        ? @""
                        : (  (nNetInstalls == 1)
                           ? NSLocalizedString(@"     • Installed one configuration\n\n", @"Window text: 'Tunnelblick succesfully: *'")
                           : [NSString stringWithFormat: NSLocalizedString(@"     • Installed %lu configurations\n\n", @"Window text: 'Tunnelblick succesfully: *'"), (unsigned long)nNetInstalls]));
        
        NSString * headerMsg  = (  ([uninstallMsg length] + [replaceMsg length] + [installMsg length]) == 0
                                 ? @""
                                 : NSLocalizedString(@"Tunnelblick successfully:\n\n", @"Window text: '* Installed/Replaced/Uninstalled'"));
        
        if (  nTotalErrors == 0  ) {
            msg = [NSString stringWithFormat: @"%@%@%@%@", headerMsg, uninstallMsg, replaceMsg, installMsg];
        } else {
            msg = [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick encountered errors with %lu configurations:\n\n%@%@%@%@", @"Window text"),
                   (unsigned long)nTotalErrors, installerErrorMessages, headerMsg, uninstallMsg, replaceMsg, installMsg];
        }
        
        TBShowAlertWindow(NSLocalizedString(@"VPN Configuration Installation", @"Window title"), msg);
    }
    
    return (  nTotalErrors == 0
            ? NSApplicationDelegateReplySuccess
            : NSApplicationDelegateReplyFailure);
}


-(NSApplicationDelegateReply) doUninstallslReplacementsInstallsAxionSkipConfirmMsg: (BOOL) skipConfirmMsg
																skipResultMsg: (BOOL) skipResultMsg {
    
	// Does the work to uninstall, replace, and/or install configurations from the 'deletions', 'installSource', 'replaceSource', etc. arrays
    
    NSLog(@"[doInstallsetc] Called");
	//
	// Returns the value that the delegate should use as an argument to '[NSApp replyToOpenOrPrint:]' (whether or not it will be needed)
	
    NSUInteger nToUninstall = [[self deletions]      count];
    NSUInteger nToInstall   = [[self installSources] count];
	NSUInteger nToReplace   = [[self replaceSources] count];
    
    // If there's nothing to do, just return as if the user cancelled
	if (  (nToUninstall + nToInstall + nToReplace) == 0  ) {
		return NSApplicationDelegateReplyCancel;
	}
    
    // If there is no gAuthorization currently, get one (it is release by cleanupInstall:); otherwise confirm what we are about to do
	
    NSString * uninstallMsg = (  (nToUninstall == 0)
                               ? @""
                               : (  (nToUninstall == 1)
                                  ? NSLocalizedString(@"    • Uninstall one configuration\n", @"Window text: 'AxionVPN needs to: *'")
                                  : [NSString stringWithFormat: NSLocalizedString(@"    • Uninstall %lu configurations\n\n", @"Window text: 'AxionVPN needs to: *'"), (unsigned long)nToUninstall]));
    NSString * replaceMsg   = (  (nToReplace == 0)
                               ? @""
                               : (  (nToReplace == 1)
                                  ? NSLocalizedString(@"    • Replace one configuration\n", @"Window text: 'AxionVPN needs to: *'")
                                  : [NSString stringWithFormat: NSLocalizedString(@"    • Replace %lu configurations\n\n", @"Window text: 'AxionVPN needs to: *'"), (unsigned long)nToReplace]));
    NSString * installMsg   = (  (nToInstall == 0)
                               ? @""
                               : (  (nToInstall == 1)
                                  ? NSLocalizedString(@"    • Install one configuration\n", @"Window text: 'AxionVPN needs to: *'")
                                  : [NSString stringWithFormat: NSLocalizedString(@"    • Install %lu configurations\n\n", @"Window text: 'AxionVPN needs to: *'"), (unsigned long)nToInstall]));
    NSString * authMsg = [NSString stringWithFormat: @"AxionVPN needs to:\n\n%@%@%@", uninstallMsg, replaceMsg, installMsg];

#ifdef AXION_DONT_BUILD
 	if ( gAuthorization == NULL  ) {
        
        gAuthorization = [NSApplication getAuthorizationRef: authMsg];
        if (  gAuthorization == NULL  ) {
			return NSApplicationDelegateReplyCancel;
        }
	} else {
        
        if (  ! skipConfirmMsg  ) {
            int result = TBRunAlertPanel(NSLocalizedString(@"VPN Configuration Installation", @"Window title"),
                                         authMsg,
                                         NSLocalizedString(@"OK",      @"Button"),   // Default button
                                         NSLocalizedString(@"Cancel",  @"Button"),   // Alternate button
                                         nil);                                       // Other button
            if (  result == NSAlertAlternateReturn  ) {
				return NSApplicationDelegateReplyCancel;
            }
        }
    }
    
#endif
    
    // Do the actual installs and uninstalls
    
    NSUInteger nUninstallErrors = 0;
    NSUInteger nInstallErrors   = 0;
	NSUInteger nReplaceErrors   = 0;
	NSUInteger nUpdateErrors    = 0;
    
	NSMutableString * installerErrorMessages = [NSMutableString stringWithCapacity: 1000];
    
	NSUInteger ix;
	
    // Un-install .tblks in 'deletions'
	for (  ix=0; ix<[[self deletions] count]; ix++  ) {
		
		NSString * target = [[self deletions] objectAtIndex: ix];
		
		if (  ! [self deleteConfigPath: target
					   usingAuthRefPtr: &gAuthorization
							warnDialog: NO]  ) {
			nUninstallErrors++;
			NSString * targetDisplayName   = [lastPartOfPath(target) stringByDeletingPathExtension];
            NSString * targetLocalizedName = [((MenuController *)[NSApp delegate]) localizedNameforDisplayName: targetDisplayName tblkPath: target];
			[installerErrorMessages appendString: [NSString stringWithFormat: NSLocalizedString(@"Unable to uninstall the '%@' configuration\n", @"Window text"), targetLocalizedName]];
		}
	}
    
    // Install .tblks in 'installSources' to 'installTargets'
    for (  ix=0; ix<[[self installSources] count]; ix++  ) {
        
        NSString * source = [[self installSources] objectAtIndex: ix];
        NSString * target = [[self installTargets] objectAtIndex: ix];
        NSString * targetDisplayName = [lastPartOfPath(target) stringByDeletingPathExtension];
        
        if (  [self copyConfigPath: source
                            toPath: target
                   usingAuthRefPtr: &gAuthorization
                        warnDialog: NO
                       moveNotCopy: NO]  ) {
			
            NSDictionary * connDict = [((MenuController *)[NSApp delegate]) myVPNConnectionDictionary];
            BOOL replacedTblk = (nil != [connDict objectForKey: targetDisplayName]);
            if (  replacedTblk  ) {
                // Force a reload of the configuration's preferences using any new TBPreference and TBAlwaysSetPreference items in its Info.plist
                [((MenuController *)[NSApp delegate]) deleteExistingConfig: targetDisplayName ];
                [((MenuController *)[NSApp delegate]) addNewConfig: target withDisplayName: targetDisplayName];
                [[((MenuController *)[NSApp delegate]) logScreen] update];
            }
            
        } else {
            nInstallErrors++;
            NSString * targetDisplayName = [lastPartOfPath(target) stringByDeletingPathExtension];
            NSString * targetLocalizedName = [((MenuController *)[NSApp delegate]) localizedNameforDisplayName: targetDisplayName tblkPath: target];
            [installerErrorMessages appendString: [NSString stringWithFormat: NSLocalizedString(@"Unable to install the '%@' configuration\n", @"Window text"), targetLocalizedName]];
        }
    }
    
    // Install .tblks in 'replaceSources' to 'replaceTargets'
    for (  ix=0; ix<[[self replaceSources] count]; ix++  ) {
        
        NSString * source = [[self replaceSources] objectAtIndex: ix];
        NSString * target = [[self replaceTargets] objectAtIndex: ix];
        NSString * targetDisplayName = [lastPartOfPath(target) stringByDeletingPathExtension];
        
        if (  [self copyConfigPath: source
                            toPath: target
                   usingAuthRefPtr: &gAuthorization
                        warnDialog: NO
                       moveNotCopy: NO]  ) {
			
            NSDictionary * connDict = [((MenuController *)[NSApp delegate]) myVPNConnectionDictionary];
            VPNConnection * connection = [connDict objectForKey: targetDisplayName];
            if (  connection  ) {
                // Force a reload of the configuration's preferences using any new TBPreference and TBAlwaysSetPreference items in its Info.plist
				[connection reloadPreferencesFromTblk];
                [[((MenuController *)[NSApp delegate]) logScreen] update];
            }
            
        } else {
            nReplaceErrors++;
            NSString * targetDisplayName = [lastPartOfPath(target) stringByDeletingPathExtension];
            NSString * targetLocalizedName = [((MenuController *)[NSApp delegate]) localizedNameforDisplayName: targetDisplayName tblkPath: target];
            [installerErrorMessages appendString: [NSString stringWithFormat: NSLocalizedString(@"Unable to replace the '%@' configuration\n", @"Window text"), targetLocalizedName]];
        }
    }
	
    
#ifdef AXION_DONT_BUILD
	// Copy updatable stub .tblks into L_AS_T_TBLKS
    
    // We need to modify target paths to insert the edition number (a unique integer).
    // So it changes from   /something/.../com.example.something/something
    //                 to   /something/.../com.example.something_EDITION/something
    // We set each new edition number to one more than the highest existing edition number
    
    // So first, we find the highest existing edition number
    NSString * highestEdition = nil;
    NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: L_AS_T_TBLKS];
    NSString * file;
    while (  (file = [dirEnum nextObject])  ) {
        [dirEnum skipDescendents];
        if (   ( ! [file hasPrefix: @"."] )
            && ( ! [file hasSuffix: @".tblk"] )  ) {
            NSString * edition = [file pathEdition];
            if (   ( [edition length] != 0 )
                && (   ( ! highestEdition )
                    || [edition caseInsensitiveNumericCompare: highestEdition] == NSOrderedDescending )  ) {
                    highestEdition = edition;
                }
        }
    }
	if (  ! highestEdition  ) {
		highestEdition = @"-1";
	}
    
    // Now go through and copy the stub .tblks, modifying each target path as we go
    
    for (  ix=0; ix<[[self updateSources] count]; ix++  ) {
        
        NSString * source = [[self updateSources] objectAtIndex: ix];
        NSString * target = [[self updateTargets] objectAtIndex: ix];
        
        // Insert the new edition into the target path as a suffix to the next-to-last path component
        
        NSString * targetLast        = [target lastPathComponent];
        NSString * targetWithoutLast = [target stringByDeletingLastPathComponent];
        NSString * bundleId          = [targetWithoutLast lastPathComponent];
        
        highestEdition = [NSString stringWithFormat: @"%u", (unsigned)[highestEdition intValue] + 1];
        
        target = [[targetWithoutLast
                   stringByAppendingFormat: @"_%@", highestEdition]
                  stringByAppendingPathComponent: targetLast];
        
		NSArray * arguments = [NSArray arrayWithObjects: target, source, nil];
		NSInteger installerResult = [((MenuController *)[NSApp delegate]) runInstaller: 0
													extraArguments: arguments];
		if (  installerResult == 0  ) {
 			[[((MenuController *)[NSApp delegate]) myConfigMultiUpdater] stopUpdateCheckingForAllStubTblksWithBundleIdentifier: bundleId];
            [[((MenuController *)[NSApp delegate]) myConfigMultiUpdater] addUpdateCheckingForStubTblkAtPath: target];
        } else {
            nUpdateErrors++;
            [installerErrorMessages appendString: [NSString stringWithFormat: NSLocalizedString(@"Unable to store updatable configuration stub at %@\n", @"Window text"), target]];
        }
	}
#endif
	
	// Construct and display a window with the results of the uninstalls/replacements/installs
	
	NSUInteger nTotalErrors = nUninstallErrors + nInstallErrors + nReplaceErrors + nUpdateErrors;
	
	if (   (nTotalErrors != 0)
		|| ( ! skipResultMsg )  ) {
		
		NSString * msg = nil;
		
		NSUInteger nNetUninstalls   = nToUninstall - nUninstallErrors;
		NSUInteger nNetInstalls     = nToInstall   - nInstallErrors;
		NSUInteger nNetReplacements = nToReplace   - nReplaceErrors;
		
		uninstallMsg = (  (nNetUninstalls == 0)
						? @""
						: (  (nNetUninstalls == 1)
						   ? NSLocalizedString(@"     • Uninstalled one configuration\n\n", @"Window text: 'Tunnelblick succesfully: *'")
						   : [NSString stringWithFormat: NSLocalizedString(@"     • Uninstalled %lu configurations\n\n", @"Window text: 'Tunnelblick succesfully: *'"), (unsigned long)nNetUninstalls]));
		replaceMsg   = (  (nNetReplacements == 0)
						? @""
						: (  (nNetReplacements == 1)
						   ? NSLocalizedString(@"     • Replaced one configuration\n\n", @"Window text: 'Tunnelblick succesfully: *'")
						   : [NSString stringWithFormat: NSLocalizedString(@"     • Replaced %lu configurations\n\n", @"Window text: 'Tunnelblick succesfully: *'"), (unsigned long)nNetReplacements]));
		installMsg   = (  (nNetInstalls == 0)
						? @""
						: (  (nNetInstalls == 1)
						   ? NSLocalizedString(@"     • Installed one configuration\n\n", @"Window text: 'Tunnelblick succesfully: *'")
						   : [NSString stringWithFormat: NSLocalizedString(@"     • Installed %lu configurations\n\n", @"Window text: 'Tunnelblick succesfully: *'"), (unsigned long)nNetInstalls]));
		
		NSString * headerMsg  = (  ([uninstallMsg length] + [replaceMsg length] + [installMsg length]) == 0
								 ? @""
								 : NSLocalizedString(@"Tunnelblick successfully:\n\n", @"Window text: '* Installed/Replaced/Uninstalled'"));
		
		if (  nTotalErrors == 0  ) {
			msg = [NSString stringWithFormat: @"%@%@%@%@", headerMsg, uninstallMsg, replaceMsg, installMsg];
		} else {
			msg = [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick encountered errors with %lu configurations:\n\n%@%@%@%@", @"Window text"),
				   (unsigned long)nTotalErrors, installerErrorMessages, headerMsg, uninstallMsg, replaceMsg, installMsg];
		}
		
		TBShowAlertWindow(NSLocalizedString(@"VPN Configuration Installation", @"Window title"), msg);
	}
	
    return (  nTotalErrors == 0
			? NSApplicationDelegateReplySuccess
			: NSApplicationDelegateReplyFailure);
}

-(BOOL) multipleInstallableConfigurations: (NSArray *) filePaths {
	
	// Returns TRUE if there are multiple configurations to be installed from paths in filePaths
	// Returns FALSE if there is only one configuration to be installed.
	//
	// Note: if there is a .conf and a .ovpn in the same folder, only one will be installed; this method takes that into account
	
	NSString * firstConfigPath = nil;
	NSString * mainPath;
	NSEnumerator * e = [filePaths objectEnumerator];
	while (  (mainPath = [e nextObject])  ) {
		
		NSString * ext = [mainPath pathExtension];
		
		if (   [ext isEqualToString: @"ovpn"]
			|| [ext isEqualToString: @"conf"]  ) {
			NSString * fullPathWithoutExtension = [mainPath stringByDeletingPathExtension];
			if (  firstConfigPath  ) {
				if (  ! [firstConfigPath isEqualToString: fullPathWithoutExtension]  ) {
					return TRUE;
				}
			} else {
				firstConfigPath = fullPathWithoutExtension;
			}
		}
		
		NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: mainPath];
		NSString * file;
		while (  (file = [dirEnum nextObject])  ) {
			
			ext = [file pathExtension];
			
			if (   [ext isEqualToString: @"ovpn"]
				|| [ext isEqualToString: @"conf"]  ) {
				NSString * fullPathWithoutExtension = [[mainPath stringByAppendingPathComponent: file] stringByDeletingPathExtension];
				if (  firstConfigPath  ) {
					if (  ! [firstConfigPath isEqualToString: fullPathWithoutExtension]  ) {
						return TRUE;
					}
				} else {
					firstConfigPath = fullPathWithoutExtension;
				}
				
			}
		}
	}
	
	return FALSE;
}
		   
// *********************************************************************************************
// EXTERNAL ENTRY for .tblk, .ovpn, and .conf installation

-(void) installConfigurations: (NSArray *) filePaths
      skipConfirmationMessage: (BOOL)      skipConfirmMsg
            skipResultMessage: (BOOL)      skipResultMsg
               notifyDelegate: (BOOL)      notifyDelegate {
    
    // The filePaths array entries are paths to a .tblk, .ovpn, or .conf to install.
    
    if (  [filePaths count] == 0) {
        if (  notifyDelegate  ) {
            [NSApp replyToOpenOrPrint: NSApplicationDelegateReplySuccess];
        }
        
        return;
    }
    
    if (  ! [self checkFilesAreReasonable: filePaths]  ) {
        if (  notifyDelegate  ) {
            [NSApp replyToOpenOrPrint: NSApplicationDelegateReplyFailure];
        }
        
        return;
    }
    
    // Set up instance variables that we use
    
    BOOL isDeployed = [gFileMgr fileExistsAtPath: gDeployPath];
    [self setInstallToPrivateOK: (   (! isDeployed)
                                  || (   [gTbDefaults boolForKey: @"usePrivateConfigurationsWithDeployedOnes"]
                                      && ( ! [gTbDefaults canChangeValueForKey: @"usePrivateConfigurationsWithDeployedOnes"])
                                      )
                                  )];
    [self setInstallToSharedOK: (   (! isDeployed)
                                 || (   [gTbDefaults boolForKey: @"useSharedConfigurationsWithDeployedOnes"]
                                     && ( ! [gTbDefaults canChangeValueForKey: @"useSharedConfigurationsWithDeployedOnes"])
                                     )
                                 )];
    if (   [gTbDefaults boolForKey: @"doNotOpenDotTblkFiles"]
        || (   ( ! [self installToPrivateOK] )
            && ( ! [self installToSharedOK]  )
            )
        ) {
        TBShowAlertWindow(NSLocalizedString(@"VPN Configuration Installation Error", @"Window title"),
                          NSLocalizedString(@"Installing configurations is not allowed", "Window text"));
        if (  notifyDelegate  ) {
            [NSApp replyToOpenOrPrint: NSApplicationDelegateReplyFailure];
        }
        return;
    }
    
    installSources =   [[NSMutableArray alloc]  initWithCapacity: 100];
    installTargets =   [[NSMutableArray alloc]  initWithCapacity: 100];
    replaceSources =   [[NSMutableArray alloc]  initWithCapacity: 100];
    replaceTargets =   [[NSMutableArray alloc]  initWithCapacity: 100];
    updateSources  =   [[NSMutableArray alloc]  initWithCapacity: 100];
    updateTargets  =   [[NSMutableArray alloc]  initWithCapacity: 100];
    deletions      =   [[NSMutableArray alloc]  initWithCapacity: 100];
    
    errorLog       =   [[NSMutableString alloc] initWithCapacity: 1000];
    
    [self setInhibitCheckbox:        FALSE];
    [self setAuthWasNull:            (gAuthorization == NULL) ];
    [self setMultipleConfigurations: [self multipleInstallableConfigurations: filePaths]];
	
    NSString * path = [newTemporaryDirectoryPath() autorelease];
    if (  ! [gFileMgr tbRemoveFileAtPath: path handler: nil]  ) {
        NSLog(@"Unable to delete %@", path);
        if (  notifyDelegate  ) {
            [NSApp replyToOpenOrPrint: NSApplicationDelegateReplyFailure];
        }
        return;
    }
    if (  createDir(path, PERMS_PRIVATE_FOLDER) == -1  ) {
        NSLog(@"Unable to create %@", path);
        if (  notifyDelegate  ) {
            [NSApp replyToOpenOrPrint: NSApplicationDelegateReplyFailure];
        }
        return;
    }
    [self setTempDirPath: path];
    
    //
    //
    // From here on, we need to use cleanupInstallAndNotifyDelegate: so the temporary directory is removed
    //
    //
    
    // Separate the file list into .tblks and .ovpn/.conf
    NSMutableArray * tblkPaths = [NSMutableArray arrayWithCapacity: [filePaths count]];
    NSMutableArray * ovpnPaths = [NSMutableArray arrayWithCapacity: [filePaths count]];
	NSString * file;
	NSEnumerator * e = [filePaths objectEnumerator];
	while (  (file = [e nextObject])  ) {
		NSString * ext = [file pathExtension];
		if (  [ext isEqualToString: @"tblk"]  ) {
            [tblkPaths addObject: file];
		} else if (   [ext isEqualToString: @"ovpn"]
				   || [ext isEqualToString: @"conf"]  ) {
			[ovpnPaths addObject: file];
		}  // Ignore anything else
	}
    
    // Set up to install .tblk packages
    if (  [tblkPaths count] != 0  ) {
        NSString * result = [self setupToInstallTblks: tblkPaths haveOvpnOrConfs: ([ovpnPaths count] != 0)];
        if (  result  ) {
            if ( [result isEqualToString: @"cancel"]  ) {
				[self cleanupInstallAndNotifyDelegate: notifyDelegate delegateNotifyValue: NSApplicationDelegateReplyCancel];
				return;
			} else if (  [result isNotEqualTo: @"skip"]  ) {
				TBShowAlertWindow(NSLocalizedString(@"VPN Configuration Installation Error", @"Window title"),
								  [NSString stringWithFormat:
								   NSLocalizedString(@"Installation failed:\n\n%@", "Window text"),
								   result]);
				[self cleanupInstallAndNotifyDelegate: notifyDelegate delegateNotifyValue: NSApplicationDelegateReplyFailure];
				return;
			}
        }
    }
    
    // Set up to install .ovpn and .conf files
	if (  [ovpnPaths count] != 0  ) {
        NSString * result = [self setupToInstallOvpnsAndConfs: ovpnPaths];
        if (  result  ) {
            if ( [result isEqualToString: @"cancel"]  ) {
				[self cleanupInstallAndNotifyDelegate: notifyDelegate delegateNotifyValue: NSApplicationDelegateReplyCancel];
				return;
			} else if (  [result isNotEqualTo: @"skip"]  ) {
				TBShowAlertWindow(NSLocalizedString(@"VPN Configuration Installation Error", @"Window title"),
								  [NSString stringWithFormat:
								   NSLocalizedString(@"Installation failed:\n\n%@", "Window text"),
								   result]);
				[self cleanupInstallAndNotifyDelegate: notifyDelegate delegateNotifyValue: NSApplicationDelegateReplyFailure];
				return;
			}
        }
    }
	
	// Do the uninstalls/replacements/uninstalls
	NSApplicationDelegateReply reply = [self doUninstallslReplacementsInstallsSkipConfirmMsg: skipConfirmMsg
																			   skipResultMsg: skipResultMsg];
	
    [self cleanupInstallAndNotifyDelegate: notifyDelegate delegateNotifyValue: reply];
	
    return;
}


-(void)CleanConfigurationsAxion{
    
     NSLog(@"[CleanConfigurationsAxion] Called");
    
    //first we need to disconnect any connections
    
    VPNConnection * connection;
    NSEnumerator* e = [[((MenuController *)[NSApp delegate]) myVPNConnectionDictionary] objectEnumerator];
    while (  (connection = [e nextObject])  ) {
        if (  ! [[connection state] isEqualToString:@"EXITING"]  ) {
            
            NSLog(@"[connect] Closing old connection %@",[connection displayName]);
            [connection startDisconnectingUserKnows:YES];
        }
    }
    
    
    
    //Now clean all the VPN configurations
    
    
    
    NSMutableString *path = gPrivatePath;
    
    NSError *error = nil;
    for (NSString *file in [gFileMgr contentsOfDirectoryAtPath:gPrivatePath error:&error]) {
        NSString *tmpPath = [NSString stringWithFormat:@"%@/%@",gPrivatePath,file];
        NSLog(@"[CleanConfigurationsAxion] Attempting to renive %@",tmpPath);
        BOOL success = [gFileMgr removeItemAtPath:tmpPath error:&error];
        if (!success || error) {
            NSLog(@"[CleanConfigurationsAxion] Removed %@",tmpPath);
        }
        else{
            NSLog(@"[CleanConfigurationsAxion] Failed to remove %@",tmpPath);
        }
    }
    
    //return [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    
}


-(void) installConfigurationsAxion: (NSArray *) filePaths
      skipConfirmationMessage: (BOOL)      skipConfirmMsg
            skipResultMessage: (BOOL)      skipResultMsg
               notifyDelegate: (BOOL)      notifyDelegate {
    
    
    
    
    //Clean any pre-existing configs before we go on
    [self CleanConfigurationsAxion];
    
    // The filePaths array entries are paths to a .tblk, .ovpn, or .conf to install.
    
    if (  [filePaths count] == 0) {
        if (  notifyDelegate  ) {
            [NSApp replyToOpenOrPrint: NSApplicationDelegateReplySuccess];
        }
        
        return;
    }
    
    if (  ! [self checkFilesAreReasonable: filePaths]  ) {
        if (  notifyDelegate  ) {
            [NSApp replyToOpenOrPrint: NSApplicationDelegateReplyFailure];
        }
        
        return;
    }
    
    // Set up instance variables that we use
    
    BOOL isDeployed = [gFileMgr fileExistsAtPath: gDeployPath];
    [self setInstallToPrivateOK: (   (! isDeployed)
                                  || (   [gTbDefaults boolForKey: @"usePrivateConfigurationsWithDeployedOnes"]
                                      && ( ! [gTbDefaults canChangeValueForKey: @"usePrivateConfigurationsWithDeployedOnes"])
                                      )
                                  )];
    [self setInstallToSharedOK: (   (! isDeployed)
                                 || (   [gTbDefaults boolForKey: @"useSharedConfigurationsWithDeployedOnes"]
                                     && ( ! [gTbDefaults canChangeValueForKey: @"useSharedConfigurationsWithDeployedOnes"])
                                     )
                                 )];
    if (   [gTbDefaults boolForKey: @"doNotOpenDotTblkFiles"]
        || (   ( ! [self installToPrivateOK] )
            && ( ! [self installToSharedOK]  )
            )
        ) {
        TBShowAlertWindow(NSLocalizedString(@"VPN Configuration Installation Error", @"Window title"),
                          NSLocalizedString(@"Installing configurations is not allowed", "Window text"));
        if (  notifyDelegate  ) {
            [NSApp replyToOpenOrPrint: NSApplicationDelegateReplyFailure];
        }
        return;
    }
    
    installSources =   [[NSMutableArray alloc]  initWithCapacity: 100];
    installTargets =   [[NSMutableArray alloc]  initWithCapacity: 100];
    replaceSources =   [[NSMutableArray alloc]  initWithCapacity: 100];
    replaceTargets =   [[NSMutableArray alloc]  initWithCapacity: 100];
    updateSources  =   [[NSMutableArray alloc]  initWithCapacity: 100];
    updateTargets  =   [[NSMutableArray alloc]  initWithCapacity: 100];
    deletions      =   [[NSMutableArray alloc]  initWithCapacity: 100];
    
    errorLog       =   [[NSMutableString alloc] initWithCapacity: 1000];
    
    [self setInhibitCheckbox:        FALSE];
    [self setAuthWasNull:            (gAuthorization == NULL) ];
    [self setMultipleConfigurations: [self multipleInstallableConfigurations: filePaths]];
    
    NSString * path = [newTemporaryDirectoryPath() autorelease];
    if (  ! [gFileMgr tbRemoveFileAtPath: path handler: nil]  ) {
        NSLog(@"Unable to delete %@", path);
        if (  notifyDelegate  ) {
            [NSApp replyToOpenOrPrint: NSApplicationDelegateReplyFailure];
        }
        return;
    }
    if (  createDir(path, PERMS_PRIVATE_FOLDER) == -1  ) {
        NSLog(@"Unable to create %@", path);
        if (  notifyDelegate  ) {
            [NSApp replyToOpenOrPrint: NSApplicationDelegateReplyFailure];
        }
        return;
    }
    [self setTempDirPath: path];
    
    //
    //
    // From here on, we need to use cleanupInstallAndNotifyDelegate: so the temporary directory is removed
    //
    //
    
    // Separate the file list into .tblks and .ovpn/.conf
    NSMutableArray * tblkPaths = [NSMutableArray arrayWithCapacity: [filePaths count]];
    NSMutableArray * ovpnPaths = [NSMutableArray arrayWithCapacity: [filePaths count]];
    NSString * file;
    NSEnumerator * e = [filePaths objectEnumerator];
    while (  (file = [e nextObject])  ) {
        NSString * ext = [file pathExtension];
        if (  [ext isEqualToString: @"tblk"]  ) {
            [tblkPaths addObject: file];
        } else if (   [ext isEqualToString: @"ovpn"]
                   || [ext isEqualToString: @"conf"]  ) {
            [ovpnPaths addObject: file];
        }  // Ignore anything else
    }
    
    // Set up to install .tblk packages
    if (  [tblkPaths count] != 0  ) {
        NSString * result = [self setupToInstallTblks: tblkPaths haveOvpnOrConfs: ([ovpnPaths count] != 0)];
        if (  result  ) {
            if ( [result isEqualToString: @"cancel"]  ) {
                [self cleanupInstallAndNotifyDelegate: notifyDelegate delegateNotifyValue: NSApplicationDelegateReplyCancel];
                return;
            } else if (  [result isNotEqualTo: @"skip"]  ) {
                TBShowAlertWindow(NSLocalizedString(@"VPN Configuration Installation Error", @"Window title"),
                                  [NSString stringWithFormat:
                                   NSLocalizedString(@"Installation failed:\n\n%@", "Window text"),
                                   result]);
                [self cleanupInstallAndNotifyDelegate: notifyDelegate delegateNotifyValue: NSApplicationDelegateReplyFailure];
                return;
            }
        }
    }
    
    // Set up to install .ovpn and .conf files
    if (  [ovpnPaths count] != 0  ) {
        NSLog(@"about to install ovpn file");
        NSString * result = [self setupToInstallOvpnsAndConfsAxion: ovpnPaths];
        if (  result  ) {
            if ( [result isEqualToString: @"cancel"]  ) {
                [self cleanupInstallAndNotifyDelegate: notifyDelegate delegateNotifyValue: NSApplicationDelegateReplyCancel];
                return;
            } else if (  [result isNotEqualTo: @"skip"]  ) {
                TBShowAlertWindow(NSLocalizedString(@"VPN Configuration Installation Error", @"Window title"),
                                  [NSString stringWithFormat:
                                   NSLocalizedString(@"Installation failed:\n\n%@", "Window text"),
                                   result]);
                [self cleanupInstallAndNotifyDelegate: notifyDelegate delegateNotifyValue: NSApplicationDelegateReplyFailure];
                return;
            }
        }
    }
    
    // Do the uninstalls/replacements/uninstalls
    NSApplicationDelegateReply reply = [self doUninstallslReplacementsInstallsAxionSkipConfirmMsg: skipConfirmMsg
                                                                               skipResultMsg: skipResultMsg];
    NSLog(@"Done installing");
    
    [self cleanupInstallAndNotifyDelegate: notifyDelegate delegateNotifyValue: reply];
    
    return;
}


@end
