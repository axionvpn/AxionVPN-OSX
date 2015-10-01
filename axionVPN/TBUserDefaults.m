/*
 * Copyright 2009, 2010, 2011, 2012, 2013, 2014 Jonathan K. Bullard. All rights reserved.
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

#import "TBUserDefaults.h"

#import "helper.h"

#import "MenuController.h"


NSArray * gProgramPreferences;
NSArray * gConfigurationPreferences;

@implementation TBUserDefaults

-(TBUserDefaults *) initWithForcedDictionary: (NSDictionary *) inForced
                      andSecondaryDictionary: (NSDictionary *) inSecondary
                           usingUserDefaults: (BOOL)           inUseUserDefaults {
    self = [super init];
    if ( ! self  ) {
        return nil;
    }
    
    forcedDefaults = [inForced copy];
    
    secondaryDefaults = [inSecondary copy];
    
    if (  inUseUserDefaults  ) {
        userDefaults = [[NSUserDefaults standardUserDefaults] retain];
        [userDefaults registerDefaults: [NSMutableDictionary dictionary]];
    } else {
        userDefaults = nil;
    }
    
    return self;
}

-(void) dealloc {
    
    [forcedDefaults    release]; forcedDefaults    = nil;
    [secondaryDefaults release]; secondaryDefaults = nil;
    [userDefaults      release]; userDefaults      = nil;
    
    [super dealloc];
}

-(id) forcedObjectForKey: (NSString *) key {
    // Checks for a forced object for a key, implementing wildcard matches

    id value = [forcedDefaults objectForKey: key];
    if (  value == nil  ) {
        // No key for XYZABCDE, so try for a wildcard match
        // If have a *ABCDE key, returns it's value
        NSEnumerator * e = [forcedDefaults keyEnumerator];
        NSString * forcedKey;
        while (  (forcedKey = [e nextObject])  ) {
            if (   [forcedKey hasPrefix: @"*"]
                && ( [forcedKey length] != 1)  ) {
                if (  [key hasSuffix: [forcedKey substringFromIndex: 1]]  ) {
                    return [forcedDefaults objectForKey: forcedKey];
                }
            }
        }
    }
    
    return value;
}

-(id) defaultsObjectForKey: (NSString *) key {
    // Checks for a defaults object for a key, implementing wildcard matches

    id value = [userDefaults objectForKey: key];
    if (  value == nil  ) {
        // No key for XYZABCDE, so try for a wildcard match
        // If have a *ABCDE key, returns it's value
        NSDictionary * userDefaultsDictionary = [userDefaults dictionaryRepresentation];
        NSEnumerator * e = [userDefaultsDictionary keyEnumerator];
        NSString * defaultsKey;
        while (  (defaultsKey = [e nextObject])  ) {
            if (   [defaultsKey hasPrefix: @"*"]
                && ( [defaultsKey length] != 1)  ) {
                if (  [key hasSuffix: [defaultsKey substringFromIndex: 1]]  ) {
                    return [userDefaults objectForKey: defaultsKey];
                }
            }
        }
    }
    
    return value;
}

-(id) objectForKey: (NSString *) key {
    id value = [self forcedObjectForKey: key];
    if (  value == nil  ) {
        value = [secondaryDefaults objectForKey: key];
        if (  value == nil  ) {
            value = [self defaultsObjectForKey: key];
        }
    }
    
    return value;
}

-(BOOL) boolForKey: (NSString *) key
           default: (BOOL)       defaultValue {
    
    id obj = [self objectForKey: key];
    
    if (  obj  ) {
        if (  [obj respondsToSelector: @selector(boolValue)]  ) {
            return [obj boolValue];
        }
        
        NSLog(@"boolForKey: Preference '%@' must be a boolean (i.e., an NSNumber), but it is a %@; using a value of %@", key,
              [[obj class] description], (defaultValue ? @"YES" : @"NO"));
    }
    
    return defaultValue;
}

-(BOOL) boolForKey: (NSString *) key {
    
    return [self boolForKey: key default: NO];
}

-(BOOL) boolWithDefaultYesForKey: (NSString *) key {
    
    return [self boolForKey: key default: YES];
}

-(BOOL) preferenceExistsForKey: (NSString * ) key {
    return ([self objectForKey: key] != nil);
}

-(NSTimeInterval) timeIntervalForKey: (NSString *)     key
                             default: (NSTimeInterval) defaultValue
                                 min: (NSTimeInterval) minValue
                                 max: (NSTimeInterval) maxValue {
    
    id obj = [self objectForKey: key];
    
    if (  obj  ) {
        if (  [obj respondsToSelector: @selector(doubleValue)]  ) {
            double objDoubleValue = [obj doubleValue];
            if (  objDoubleValue < minValue  ) {
                NSLog(@"'%@' preference ignored because it is less than %f. Using %f", key, minValue, defaultValue);
            } else if (  objDoubleValue > maxValue  ) {
                NSLog(@"'%@' preference ignored because it is greater than %f. Using %f", key, maxValue, defaultValue);
            } else {
                return (NSTimeInterval)objDoubleValue;
            }
        } else {
            NSLog(@"'%@' preference ignored because it is not a number, it is a %@. Using %f", key, [[obj class] description], defaultValue);
        }
    }
    
    return defaultValue;
}

-(NSString *) stringForKey: (NSString *) key {
    
    // Returns the NSString object associated with a key, or nil if no object exists for the key or the object is not an NSString OR IT IS AN EMPTY STRING.
    
    id obj = [self objectForKey: key];
	
	if (  obj  ) {
		if (  [[obj class] isSubclassOfClass: [NSString class]]  ) {
			if (  [obj length] != 0  ) {
				return (NSString *)obj;
			}
		} else {
			NSLog(@"Preference '%@' must be a string; it is a %@ and will be ignored", key, [[obj class] description]);
		}
	}
	
    return nil;
}

-(unsigned) unsignedIntForKey: (NSString *) key
                      default: (unsigned)   defaultValue
                          min: (unsigned)   minValue
                          max: (unsigned)   maxValue {
    
    id obj = [self objectForKey: key];
    
    if (  obj  ) {
        if (  [obj respondsToSelector: @selector(intValue)]  ) {
            int intObValue = [obj intValue];
            if (  intObValue < 0  ) {
                NSLog(@"'%@' preference ignored because it is less than 0. Using %u", key, defaultValue);
            } else {
                unsigned obValue = (unsigned) intObValue;
                if (  obValue < minValue  ) {
                    NSLog(@"'%@' preference ignored because it is less than %u. Using %u", key, minValue, defaultValue);
                } else if (  obValue > maxValue  ) {
                    NSLog(@"'%@' preference ignored because it is greater than %u. Using %u", key, maxValue, defaultValue);
                } else {
                    return obValue;
                }
            }
        } else {
            NSLog(@"'%@' preference ignored because it is not a number, it is a %@. Using %u", key, [[obj class] description], defaultValue);
        }
    }
    
    return defaultValue;
}

-(NSArray *) arrayForKey:    (NSString *) key {
    
    // Returns the NSArray object associated with a key, or nil if no object exists for the key or the object is not an NSArray.
    
    id obj = [self objectForKey: key];
	
	if (  obj  ) {
		if (  [[obj class] isSubclassOfClass: [NSArray class]]  ) {
            return (NSArray *)obj;
		} else {
			NSLog(@"Preference '%@' must be an array; it is a %@. It will be ignored", key, [[obj class] description]);
		}
	}
	
    return nil;
}

-(NSDate *) dateForKey: (NSString *) key {
    
    // Returns the NSDate object associated with a key, or nil if no object exists for the key or the object is not an NSDate.
    
    id obj = [self objectForKey: key];
	
	if (  obj  ) {
		if (  [[obj class] isSubclassOfClass: [NSDate class]]  ) {
            return (NSDate *)obj;
		} else {
			NSLog(@"Preference '%@' must be an date; it is a %@. It will be ignored", key, [[obj class] description]);
		}
	}
	
    return nil;
}

-(float) floatForKey: (NSString *) key
             default: (float)      defaultValue
                 min: (float)      minValue
                 max: (float)      maxValue {
    
    id obj = [self objectForKey: key];
    
    if (  obj  ) {
        if (  [obj respondsToSelector: @selector(floatValue)]  ) {
            float obValue = [obj floatValue];
            if (  obValue < minValue  ) {
                NSLog(@"'%@' preference ignored because it is less than %f. Using %f", key, minValue, defaultValue);
            } else if (  obValue > maxValue  ) {
                NSLog(@"'%@' preference ignored because it is greater than %f. Using %f", key, maxValue, defaultValue);
            } else {
                return obValue;
            }
        } else {
            NSLog(@"'%@' preference ignored because it is not a number, it is a %@. Using %f", key, [[obj class] description], defaultValue);
        }
    }
    
    return defaultValue;
}

-(BOOL) canChangeValueForKey: (NSString *) key {
    // Returns YES if key's value can be modified, NO if it can't
    if (   ( ! userDefaults )
        || ([secondaryDefaults objectForKey:  key] != nil)
        || ([self forcedObjectForKey: key] != nil)  ) {
        return NO;
    }
    
    return YES;
}

-(void) setBool: (BOOL) value forKey: (NSString *) key {
	id forcedValue = [self forcedObjectForKey: key];
    if (  forcedValue  ) {
		if (   ( ! [forcedValue respondsToSelector: @selector(boolValue)])
			|| ( [forcedValue boolValue] != value )  ) {
			NSLog(@"setBool: %@ forKey: '%@': ignored because the preference is being forced to %@", (value ? @"YES" : @"NO"), key, forcedValue);
		}
	} else if (  [secondaryDefaults objectForKey: key] != nil  ) {
        NSLog(@"setBool: forKey: '%@': ignored because the preference is being forced by the secondary dictionary", key);
    } else if (  ! userDefaults  ) {
        NSLog(@"setBool: forKey: '%@': ignored because user preferences are not available", key);
    } else {
        [userDefaults setBool: value forKey: key];
        [self synchronize];
    }
}

-(void) setObject: (id) value forKey: (NSString *) key {
	id forcedValue = [self forcedObjectForKey: key];
    if (  forcedValue  ) {
		if (  [forcedValue isNotEqualTo: value]  ) {
			NSLog(@"setObject: %@ forKey: '%@': ignored because the preference is being forced to %@", value, key, forcedValue);
		}
    } else if (  [secondaryDefaults objectForKey: key] != nil  ) {
        NSLog(@"setObject: forKey: '%@': ignored because the preference is being forced by the secondary dictionary", key);
    } else if (  ! userDefaults  ) {
        NSLog(@"setObject: forKey: '%@': ignored because user preferences are not available", key);
    } else {
        [userDefaults setObject: value forKey: key];
        [self synchronize];
    }
}

-(void) removeObjectForKey: (NSString *) key {
    if (  [self forcedObjectForKey: key] != nil  ) {
        NSLog(@"removeObjectForKey: '%@': ignored because the preference is being forced", key);
    } else if (  [secondaryDefaults objectForKey: key] != nil  ) {
        NSLog(@"removeObjectForKey: '%@': ignored because the preference is being forced by the secondary dictionary", key);
    } else if (  ! userDefaults  ) {
        NSLog(@"removeObjectForKey: '%@': ignored because user preferences are not available", key);
    } else {
        [userDefaults removeObjectForKey: key];
        [self synchronize];
    }
}

-(void) removeAllObjectsWithSuffix: (NSString *) key {
    // Brute force -- try to remove key ending with the suffix for all configurations
    NSEnumerator * dictEnum = [[((MenuController *)[NSApp delegate]) myConfigDictionary] keyEnumerator];
    NSString * displayName;
    while (  (displayName = [dictEnum nextObject])  ) {
        NSString * fullKey = [displayName stringByAppendingString: key];
        if (  [self forcedObjectForKey: fullKey] != nil  ) {
            NSLog(@"removeAllObjectsWithSuffix: Not removing '%@' because the preference is being forced by", fullKey);
        } else if (  [secondaryDefaults objectForKey: fullKey] != nil  ) {
            NSLog(@"removeAllObjectsWithSuffix: Not removing '%@' because the preference is being forced by the secondary dictionary", fullKey);
        } else if (  ! userDefaults  ) {
            NSLog(@"removeAllObjectsWithSuffix: Not removing '%@' because user preferences are not available", fullKey);
        } else {
            [userDefaults removeObjectForKey: fullKey];
        }
    }
    
    [self synchronize];

}

-(void) addToDictionary: (NSMutableDictionary *) targetDict
			 withSuffix: (NSString *)            keySuffix
				   from: (NSDictionary *)        fromDict {
	
	NSString * key;
	NSEnumerator * e = [fromDict keyEnumerator];
	while (  (key = [e nextObject])  ) {
		if (  [key hasSuffix: keySuffix]  ) {
			[targetDict setObject: [fromDict objectForKey: key] forKey: key];
		}
	}
}

-(NSArray *) valuesForPreferencesSuffixedWith:(NSString *) key {
    
    // Returns an array of the objects for all preferences with keys that have a particular suffix.
    
    // Get all key/value pairs
	NSMutableDictionary * namesAndValues = [[NSMutableDictionary alloc] initWithCapacity: 100];
	[self addToDictionary: namesAndValues withSuffix: key from: forcedDefaults];
	[self addToDictionary: namesAndValues withSuffix: key from: secondaryDefaults];
	[self addToDictionary: namesAndValues withSuffix: key from: [userDefaults dictionaryRepresentation]];
	
    // Extract all distinct values
	NSMutableArray * values = [[[NSMutableArray alloc] initWithCapacity: 10] autorelease];
	NSString * dictKey;
	NSEnumerator * e = [namesAndValues keyEnumerator];
	while (  (dictKey = [e nextObject])  ) {
		NSString * value = [namesAndValues objectForKey: dictKey];
		if (  ! [values containsObject: value]  ) {
			[values addObject: value];
		}
	}
	
	[namesAndValues release];
	return values;
}

-(void) synchronize {
    if (  ! [userDefaults synchronize]  ) { // If fails, try again after sleeping for one second
        sleep(1);
        if (  ! [userDefaults synchronize]  ) {
            NSLog(@"Failed to synchronize preferences in 2 tries");
            TBShowAlertWindow(NSLocalizedString(@"Warning", @"Window title"),
							  [NSString stringWithFormat:
							   NSLocalizedString(@"Tunnelblick was unable to save its preferences because OS X refused to save them.\n\n"
												 @"The preferences may have become corrupt; if so you may need to delete the file that contains them. The preferences are in\n\n"
												 @"%@/Library/Preferences/net.tunnelblick.tunnelblick.plist.\n\n"
                                                 @"If they are corrupt, the preferences will be automatically cleared the next time you launch Tunnelblick (after making a backup of them).", @"Window text"), NSHomeDirectory()]);
        } else {
            NSLog(@"Failed to synchronize preferences on first attempt but the retry succeeded");
        }
    }
}

-(BOOL) movePreferencesFrom: (NSString *) sourceDisplayName
                         to: (NSString *) targetDisplayName {
    if (  ! userDefaults  ) {
        return TRUE;
    }
    
    if (  [sourceDisplayName isEqualToString: targetDisplayName]  ) {
        NSLog(@"copyPreferencesFrom:to: ignored because target '%@' is the same as source", targetDisplayName);
        return FALSE;
    }
    
    BOOL problemsFound = FALSE;
    
    // First, remove all preferences for the target configuration
    if (  ! [self removePreferencesFor: targetDisplayName]  ) {
        problemsFound = TRUE;
    }
    
    // Then, add the non-forced preferences from the source configuration
    NSEnumerator * arrayEnum = [gConfigurationPreferences objectEnumerator];
    NSString * preferenceSuffix;
    while (  (preferenceSuffix = [arrayEnum nextObject])  ) {
        NSString * sourceKey = [sourceDisplayName stringByAppendingString: preferenceSuffix];
        NSString * targetKey = [targetDisplayName stringByAppendingString: preferenceSuffix];
        id obj;
        if (  (obj = [userDefaults objectForKey: sourceKey])  ) {
            if (  [self canChangeValueForKey: targetKey]  ) {
                [userDefaults setObject: obj forKey: targetKey];
            } else {
                NSLog(@"Preference '%@' is forced and cannot be set.", targetKey);
                problemsFound = TRUE;
            }
        }
    }
    
    // Then, remove all preferences for the source configuration
    if (  ! [self removePreferencesFor: sourceDisplayName]  ) {
        problemsFound = TRUE;
    }
    
    return ! problemsFound;
}

-(BOOL) copyPreferencesFrom: (NSString *) sourceDisplayName
                         to: (NSString *) targetDisplayName {
    if (  ! userDefaults  ) {
        return TRUE;
    }

    if (  [sourceDisplayName isEqualToString: targetDisplayName]  ) {
        NSLog(@"copyPreferencesFrom:to: ignored because target '%@' is the same as source", targetDisplayName);
        return FALSE;
    }
    
    BOOL problemsFound = FALSE;
    
    // First, remove all preferences for the target configuration
    if (  ! [self removePreferencesFor: targetDisplayName]  ) {
        problemsFound = TRUE;
    }
    
    // Then, add the non-forced preferences from the source configuration
    NSEnumerator * arrayEnum = [gConfigurationPreferences objectEnumerator];
    NSString * preferenceSuffix;
    while (  (preferenceSuffix = [arrayEnum nextObject])  ) {
        NSString * sourceKey = [sourceDisplayName stringByAppendingString: preferenceSuffix];
        NSString * targetKey = [targetDisplayName stringByAppendingString: preferenceSuffix];
        id obj;
        if (  (obj = [userDefaults objectForKey: sourceKey])  ) {
            if (  [self canChangeValueForKey: targetKey]  ) {
                [userDefaults setObject: obj forKey: targetKey];
            } else {
                NSLog(@"Preference '%@' is forced and cannot be set.", targetKey);
                problemsFound = TRUE;
            }
        }
    }
    
    return ! problemsFound;
}

-(BOOL) removePreferencesFor: (NSString *) displayName {
    BOOL problemsFound = FALSE;
    NSEnumerator * arrayEnum = [gConfigurationPreferences objectEnumerator];
    NSString * preferenceSuffix;
    while (  (preferenceSuffix = [arrayEnum nextObject])  ) {
        NSString * key = [displayName stringByAppendingString: preferenceSuffix];
        if (  [userDefaults objectForKey: key]  ) {
            if (  [self canChangeValueForKey: key]  ) {
                [userDefaults removeObjectForKey: key];
            } else {
                NSLog(@"Preference '%@' is forced and cannot be removed.", key);
                problemsFound = TRUE;
            }
        }
    }
    
    return ! problemsFound;
}

-(void) scanForUnknownPreferencesInDictionary: (NSDictionary *) dict
                                  displayName: (NSString *)     dictName {
    NSEnumerator * dictEnum = [dict keyEnumerator];
    NSString * preferenceKey;
    while (  (preferenceKey = [dictEnum nextObject])  ) {
        if (  ! [gProgramPreferences containsObject: preferenceKey]  ) {
            NSEnumerator * prefEnum = [gConfigurationPreferences objectEnumerator];
            NSString * knownKey;
            BOOL found = FALSE;
            while (  (knownKey = [prefEnum nextObject])  ) {
                if (  [preferenceKey hasSuffix: knownKey]  ) {
                    found = TRUE;
                    break;
                }
            }
            if (  ! found  ) {
                NSLog(@"Warning: %@ contain unknown preference '%@'", dictName, preferenceKey);
            }
        }
    }
}

-(unsigned) numberOfConfigsInCredentialsGroup: (NSString *)     groupName
                                 inDictionary: (NSDictionary *) dict {
    unsigned n = 0;
    NSString * prefKey = @"-credentialsGroup";
    if (  ! dict  ) {
        NSEnumerator * e = [forcedDefaults keyEnumerator];
        NSString * key;
        while (  (key = [e nextObject])  ) {
            if (  [key hasSuffix: prefKey]  ) {
                if (  [[forcedDefaults objectForKey: key] isEqualToString: groupName]  ) {
                    n++;
                }
            }
        }
    }

    return n;
}

-(unsigned) numberOfConfigsInCredentialsGroup: (NSString *) groupName {
    unsigned nForced = [self numberOfConfigsInCredentialsGroup: groupName
                                                  inDictionary: forcedDefaults];
    unsigned nNormal = [self numberOfConfigsInCredentialsGroup: groupName
                                                  inDictionary: [userDefaults dictionaryRepresentation]];
    return nForced + nNormal;
}

-(NSString *) removeNamedCredentialsGroup: (NSString *) groupName {
    // Make sure the list of groups are not forced
	NSString * groupsKey = @"namedCredentialsNames";
    if (  ! [self canChangeValueForKey: groupsKey]  ) {
        return [NSString stringWithFormat: NSLocalizedString(@"The '%@' credentials may not be deleted because the list of named credentials is being forced.", @"Window text"), groupName];
    }
    
    // Make sure there are no forced preferences with this group
    unsigned n = [self numberOfConfigsInCredentialsGroup: groupName inDictionary: forcedDefaults];
    if (  n != 0  ) {
        return [NSString stringWithFormat: NSLocalizedString(@"The '%@' credentials may not be deleted because one or more configurations are being forced to use them.", @"Window text"), groupName];
    }
    
    // Remove all non-forced preferences with this group
    unsigned nRemoved = 0;
    NSString * prefKey = @"-credentialsGroup";
    if (  ! userDefaults  ) {
        NSDictionary * dict = [userDefaults dictionaryRepresentation];
        NSEnumerator * e = [dict keyEnumerator];
        NSString * key;
        while (  (key = [e nextObject])  ) {
            if (  [key hasSuffix: prefKey]  ) {
                if (  [[dict objectForKey: key] isEqualToString: groupName]  ) {
                    [userDefaults removeObjectForKey: key];
                    nRemoved++;
                }
            }
        }
    }
    
    if (  nRemoved == 0  ) {
        NSLog(@"Warning: No configurations use the '%@' credentials.", groupName);
    }
    
    // Remove the group itself
    NSMutableArray * groups = [[[self objectForKey: groupsKey] mutableCopy] autorelease];
    if (  groups  ) {
        if (  [[groups class] isSubclassOfClass: [NSArray class]]  ) {
            NSUInteger ix = [groups indexOfObject: groupName];
            if (  ix != NSNotFound  ) {
                [groups removeObjectAtIndex: ix];
				if (  [groups count] == 0  ) {
					[self removeObjectForKey: groupsKey];
				} else {
					[self setObject: groups forKey: groupsKey];
				}
            } else {
                NSLog(@"Warning: '%@' does not appear in the list of named credentials.", groupName);
            }
        } else {
            return NSLocalizedString(@"The 'namedCredentialsNames' preference must be an array of strings", @"Window text");
        }
    }
    
	return nil;
}

-(NSString *) addNamedCredentialsGroup: (NSString *) groupName {
	NSString * groupsKey = @"namedCredentialsNames";
    if (  [self canChangeValueForKey: groupsKey]  ) {
        NSMutableArray * groups = [[[self objectForKey: groupsKey] mutableCopy] autorelease];
        if (  groups  ) {
            if (  [[groups class] isSubclassOfClass: [NSArray class]]  ) {
                NSUInteger ix = [groups indexOfObject: groupName];
                if (  ix == NSNotFound  ) {
                    [groups addObject: groupName];
                    [self setObject: groups forKey: groupsKey];
                } else {
                    return [NSString stringWithFormat:
							NSLocalizedString(@"Warning: '%@' is already a named credential.", @"Window text"),
											  groupName];
                }
            } else {
                return NSLocalizedString(@"The 'credentialsNames' preference must be an array of strings.", @"Window text");
            }
        } else {
            NSArray * newGroups = [NSArray arrayWithObject: groupName];
            [self setObject: newGroups forKey: groupsKey];
        }
        
        return nil;
    } else {
        return [NSString stringWithFormat: NSLocalizedString(@"The '%@' credentials may not be added because the list of named credentials is being forced.", @"Window text"), groupName];
    }
}

-(NSArray *) sortedCredentialsGroups {
	NSArray * groups = [self objectForKey: @"namedCredentialsNames"];
	if (  groups  ) {
		groups = [groups sortedArrayUsingSelector: @selector(caseInsensitiveNumericCompare:)];
	} else {
		groups = [NSArray arrayWithObject: NSLocalizedString(@"Common", @"Credentials name")];
	}
	
	return groups;
}

@end
