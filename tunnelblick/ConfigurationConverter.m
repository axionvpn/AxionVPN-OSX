/*
 * Copyright 2012, 2013, 2014 Jonathan K. Bullard. All rights reserved.
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

#import "ConfigurationConverter.h"

#import <stdio.h>

#import "helper.h"
#import "sharedRoutines.h"

#import "ConfigurationToken.h"
#import "NSFileManager+TB.h"


extern NSFileManager * gFileMgr;
extern NSString      * gPrivatePath;

@implementation ConfigurationConverter

-(NSString *) localizedLogString {
	
	return [NSString stringWithString: localizedLogString];
}

TBSYNTHESIZE_OBJECT_GET(retain, NSString *, nameForErrorMessages)

-(id) init {
	self = [super init];
	if (  self  ) {
		logFile    = NULL;
		logString          = [[NSMutableString alloc] initWithCapacity: 1000];
		localizedLogString = [[NSMutableString alloc] initWithCapacity: 1000];
	}
	
	return self;	
}

-(void) dealloc {
    
    [outputPath           release]; outputPath           = nil;
    [configPath           release]; configPath           = nil;
    [replacingTblkPath    release]; replacingTblkPath    = nil;
    [displayName          release]; displayName          = nil;
    [nameForErrorMessages release]; nameForErrorMessages = nil;
    [useExistingFiles     release]; useExistingFiles     = nil;
    
    [logString            release]; logString            = nil;
    [localizedLogString   release]; localizedLogString   = nil;
    [configString         release]; configString         = nil;
    [tokens               release]; tokens               = nil;
    [tokensToReplace      release]; tokensToReplace      = nil;
    [replacementStrings   release]; replacementStrings   = nil;
    [pathsAlreadyCopied   release]; pathsAlreadyCopied   = nil;
    [logString            release]; logString            = nil;
    
    [super dealloc];
}

-(NSString *) logMessage: (NSString *) msg localized: (NSString *) localizedMsg {
    
    // Logs the message and returns the localized version of the message.
	// The "msg" arguement may be nil.
    
	// Create the English full message for the NSLog
	NSString * fullMsg = (  msg
						  ? (  (inputLineNumber == 0)
							 ? [NSString stringWithFormat: @"Converting/Installing %@: %@", configPath, msg]
							 : [NSString stringWithFormat: @"Converting/Installing %@ at line %lu: %@", configPath, (long)inputLineNumber, msg]
							 )
						  : nil);
	
	// Create the localized version of the full message for presenting to the user or putting in the log file
    BOOL ovpnOrConf = (   [nameForErrorMessages hasSuffix: @".conf"]	// Only when converting .ovpn/.conf, not when installing
                       || [nameForErrorMessages hasSuffix: @".ovpn"]);
    NSString * fullLocalizedMsg = (  nameForErrorMessages
								   ? (  (inputLineNumber == 0)
									  ? (  ovpnOrConf
										 ? [NSString stringWithFormat: NSLocalizedString(@"Converting %@: %@", @"Window text"), [self nameForErrorMessages], localizedMsg]
										 : [NSString stringWithFormat: NSLocalizedString(@"In the OpenVPN configuration file for '%@': %@", @"Window text"), [self nameForErrorMessages], localizedMsg]
										 )
									  : (  ovpnOrConf
										 ? [NSString stringWithFormat: NSLocalizedString(@"Converting %@ at line %lu: %@", @"Window text"), [self nameForErrorMessages], (long)inputLineNumber, localizedMsg]
										 : [NSString stringWithFormat: NSLocalizedString(@"In the OpenVPN configuration file for '%@' at line %lu: %@", @"Window text"), [self nameForErrorMessages], (long)inputLineNumber, localizedMsg]
										 )
									  )
								   :  (  (inputLineNumber == 0)
									   ? localizedMsg
									   : [NSString stringWithFormat: NSLocalizedString(@"At line %lu of the OpenVPN configuration file: %@", @"Window text"), (long)inputLineNumber, localizedMsg]
									   )
								   );
	
	if (  fullMsg  ) {
		[logString appendString: fullMsg];
	}
	
	[localizedLogString appendString: fullLocalizedMsg];
	
	if (  logFile == NULL  ) {
		if (  fullMsg  ) {
			NSLog(@"%@", fullMsg);
		}
	} else {
		fprintf(logFile, "%s\n", [fullLocalizedMsg UTF8String]);
	}
    
    return fullLocalizedMsg;
}

-(NSRange) nextTokenInLine: (unsigned) lineNumber {
	
	// Returns the range of the next token in a line,
	//      or a range of (0,0) if an error occurred (a message has already been logged)
	//      or NSNotFound if there are no more tokens in the line
	
    BOOL inSingleQuote = FALSE;
    BOOL inDoubleQuote = FALSE;
    BOOL inBackslash   = FALSE;
    BOOL inToken       = FALSE;
    
    // Assume no token
	NSRange returnRange = NSMakeRange(NSNotFound, 0);
    
	while (  inputIx < [configString length]  ) {
        
		unichar c = [configString characterAtIndex: inputIx];
        
        // If have started token, mark the end of the token as the current position -- before this character (for now)
        if (  returnRange.location != NSNotFound  ) {
            returnRange.length = inputIx - returnRange.location;
        }
        
        inputIx++;
        
        if ( inBackslash  ) {
			if (  c == UNICHAR_LF  ) {
				[self logMessage: [NSString stringWithFormat: @"Backslash at end of line %u is not allowed", lineNumber]
                       localized: [NSString stringWithFormat: NSLocalizedString(@"Backslash at end of line %u is not allowed", @"Window text"), lineNumber]];
				inputIx--;				  // back up so newline will be processed by skipToNextLine
				return NSMakeRange(0, 0); // newline marks end of token but is not part of the token
			}
			inBackslash = FALSE;
            continue;
        }
        
		if (  inDoubleQuote  ) {
			if (  c == '"'  ) {
                return returnRange;		// double-quote marks end of token but is not part of the token
            }
            if (  c == UNICHAR_LF  ) {
				inputIx--;				// back up so newline will be processed by skipToNextLine
				break;
            }
            
            continue;
        }
        
        if (  inSingleQuote  ) {
            if (  c == '\''  ) {
                return returnRange;  // single-quote marks end of token but is not part of the token
            }
            if (  c == UNICHAR_LF  ) {
				inputIx--;				// back up so newline will be processed by skipToNextLine
				break;
            }
            
            continue;
        }
		
		if (  c == UNICHAR_LF  ) {
			inputIx--;				// back up so newline will be processed by skipToNextLine
			return returnRange;     // newline marks end of token but is not part of the token
		}
		
		if (  [[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember: c]  ) {
			if (  returnRange.location == NSNotFound  ) {
				continue;           // whitespace comes before token, so just skip past it
			} else {
				return returnRange; // whitespace marks end of token but is not part of the token
			}
		}
		
		if (   (c == '#')
			|| (c == ';')  ) {
			inputIx--;		// Skip to, but not over, the next newline (if any)
			do {
				inputIx++;
				if (  inputIx >= [configString length]  ) {
					break;
				}
				c = [configString characterAtIndex: inputIx];
			} while (  c != UNICHAR_LF  );
			return returnRange;         // comment marks end of token (if any) but is not part of the token
		}
		
        if (  c == '"'  ) {
            if (  inToken  ) {
                inputIx--;              // next time through, start with double-quote
                return returnRange;     // double-quote marks end of token but is not part of the token
            }
            
            inDoubleQuote = TRUE;       // processing a double-quote string
            inToken = TRUE;
			// If haven't started token, whatever is next is the start of the token
			if (  returnRange.location == NSNotFound  ) {
				returnRange.location = inputIx;
				returnRange.length   = 0;
			}
            continue;
            
        } else if (  c == '\''  ) {
            if (   inToken  ) {
                inputIx--;                  // next time through, start with single-quote
                return returnRange;     // single-quote marks end of token
            }
            
            inSingleQuote = TRUE;       // processing a single-quote string
            inToken       = TRUE;
			// If haven't started token, whatever is next is the start of the token
			if (  returnRange.location == NSNotFound  ) {
				returnRange.location = inputIx;
				returnRange.length   = 0;
			}
            continue;
            
        } else if (  c == '\\'  ) {
            inBackslash = TRUE;
			continue;
        }
        
        inToken = TRUE;
        
        // If haven't started token, this is the start of the token
        if (  returnRange.location == NSNotFound  ) {
            returnRange.location = inputIx - 1;
            returnRange.length   = 1;
        }
    }
    
    if (  inSingleQuote  ) {
        [self logMessage: [NSString stringWithFormat: @"Single-quote missing in line %u", lineNumber]
               localized: [NSString stringWithFormat: NSLocalizedString(@"Single-quote missing in line %u", @"Window text"), lineNumber]];
		return NSMakeRange(0, 0);
    }
    if (  inDoubleQuote  ) {
        [self logMessage: [NSString stringWithFormat: @"Double-quote missing in line %u", lineNumber]
               localized: [NSString stringWithFormat: NSLocalizedString(@"Double-quote missing in line %u", @"Window text"), lineNumber]];
		return NSMakeRange(0, 0);
	}
    return returnRange;
}

-(NSMutableArray *) getTokens {
	NSMutableArray * arr = [NSMutableArray arrayWithCapacity: 300];
	
	inputIx = 0;
	unsigned lineNum = 1;
	
	while (  inputIx < [configString length]  ) {
		NSRange r = [self nextTokenInLine: lineNum];
		if (  r.location == NSNotFound  ) {
			while (  inputIx++ < [configString length]  ) {
				if (  [[configString substringWithRange: NSMakeRange(inputIx - 1, 1)] isEqualToString: @"\n"]  ) {
					lineNum++;
					break;
				}
			}
			[arr addObject: [[[ConfigurationToken alloc] initWithRange:NSMakeRange(inputIx - 1, 1)
                                                              inString: configString
                                                            lineNumber: lineNum] autorelease]];
		} else if (   (r.location == 0)
				   && (r.length == 0)  ) {
			return nil; // An error occurred and has already been logged
		} else {
			[arr addObject: [[[ConfigurationToken alloc] initWithRange: r
                                                              inString: configString
                                                            lineNumber: lineNum] autorelease]];
		}
	}
	
	return arr;
}

-(NSArray *) getTokensFromPath: (NSString *) theConfigPath
                    lineNumber: (unsigned)   theLineNumber
                        string: (NSString *) theString
                    outputPath: (NSString *) theOutputPath
                       logFile: (FILE *)     theLogFile {

    configPath      = [theConfigPath copy];
    inputLineNumber = theLineNumber;
    configString    = [theString copy];
    outputPath      = [theOutputPath copy];
    logFile         = theLogFile;
    
    inputIx         = 0;
    
	tokensToReplace    = [[NSMutableArray alloc] initWithCapacity: 8];
	replacementStrings = [[NSMutableArray alloc] initWithCapacity: 8];

    NSMutableArray * tokensToReturn = [self getTokens];
	
    return tokensToReturn;
}

-(NSString *) fileIsReasonableSize: (NSString *) path {
    
    // Returns nil if a regular file and 10MB or smaller, otherwise returns a localized string with an error messsage
    // after logMessage-ing an error message
    
    if (  ! path  ) {
        return [self logMessage: @"An Internal AxionVPN error occurred: fileIsReasonableSize: path is nil"
                      localized: NSLocalizedString(@"An Internal AxionVPN error occurred: fileIsReasonableSize: path is nil", @"Window text")];
    }
    
    NSDictionary * atts = [[NSFileManager defaultManager] tbFileAttributesAtPath: path traverseLink: YES];
    if (  ! atts  ) {
        return [self logMessage: [NSString stringWithFormat: @"An Internal AxionVPN error occurred: fileIsReasonableSize: Cannot get attributes: %@", path]
                      localized: [NSString stringWithFormat: NSLocalizedString(@"An Internal AxionVPN error occurred: fileIsReasonableSize: Cannot get attributes: %@", @"Window text"), path]];
    }
    
    NSString * fileType = [atts objectForKey: NSFileType];
    if (  ! fileType  ) {
        return [self logMessage: [NSString stringWithFormat: @"An Internal AxionVPN error occurred: fileIsReasonableSize: Cannot get type: %@", path]
                      localized: [NSString stringWithFormat: NSLocalizedString(@"An Internal AxionVPN error occurred: fileIsReasonableSize: Cannot get type: %@", @"Window text"), path]];
    }
    if (  ! [fileType isEqualToString: NSFileTypeRegular]  ) {
        return [self logMessage: [NSString stringWithFormat: @"An Internal AxionVPN error occurred: fileIsReasonableSize: invalid file type: %@", path]
                      localized: [NSString stringWithFormat: NSLocalizedString(@"An Internal AxionVPN error occurred: fileIsReasonableSize: invalid file type: %@", @"Window text"), path]];
    }
    
    NSNumber * sizeAsNumber = [atts objectForKey: NSFileSize];
    if (  ! sizeAsNumber  ) {
        return [self logMessage: [NSString stringWithFormat: @"An Internal AxionVPN error occurred: fileIsReasonableSize: Cannot get size: %@", path]
                      localized: [NSString stringWithFormat: NSLocalizedString(@"An Internal AxionVPN error occurred: fileIsReasonableSize: Cannot get size: %@", @"Window text"), path]];
    }
    
    unsigned long long size = [sizeAsNumber unsignedLongLongValue];
    if (  size > 10485760ull  ) {
        return [self logMessage: [NSString stringWithFormat: @"File is too large: %@", path]
                      localized: [NSString stringWithFormat: NSLocalizedString(@"File is too large: %@", @"Window text"), path]];
    }
    
    return nil;
}

-(NSString *) errorIfBadCharactersInFileAtPath: (NSString *) path {
    
    // Returns nil if the file at path is OK, or a localized string describing the error if it contains "bad" characters (after logMessage-ing an error message)
    // Which characters are "bad" depends on what type of file it is:
    //
    //      No file may be empty
    //
    //      Binary files can contain anything
    //
    //      Other files
    //            * Cannot start with "{" (which indicates a "rich text format" file
    //            * Script files (extension "sh") cannot contain CR characters
    //            * Key/certificate files cannot contain non-ASCII characters
    
    NSString * ext = [path pathExtension];
    
    // Get the contents of the file
    NSData * data = [[NSFileManager defaultManager] contentsAtPath: path];
	if (  ! data  ) {
		return [self logMessage: [NSString stringWithFormat: @"File '%@' is missing.", path]
                      localized: [NSString stringWithFormat: NSLocalizedString(@"File '%@' is missing", @"Window text"), [path lastPathComponent]]];
	}
	if (  [data length] == 0  ) {
		return [self logMessage: [NSString stringWithFormat: @"File '%@' is empty.", path]
                      localized: [NSString stringWithFormat: NSLocalizedString(@"File '%@' is empty", @"Window text"), [path lastPathComponent]]];
	}
    
    // If it is a binary key/cert file, allow any characters
    if (  [KEY_AND_CRT_EXTENSIONS containsObject: ext]  ) {
        if (  ! [NONBINARY_CONTENTS_EXTENSIONS containsObject: ext]  ) {
            return nil;
        }
    }
    
    // Check for RTF files
    const char * chars = [data bytes];
    if (   chars[0] == '{'  ) {
        return [self logMessage: [NSString stringWithFormat: @"File '%@' appears to be in 'rich text' format because it starts with a '{' character. All OpenVPN-related files must be 'plain text' or 'UTF-8' files.", path]
                      localized: [NSString stringWithFormat: NSLocalizedString(@"File '%@' appears to be in 'rich text' format because it starts with a '{' character. All OpenVPN-related files must be 'plain text' or 'UTF-8' files.", @"Window text"), [path lastPathComponent]]];
    }
    
    // Set up variables that control what we look for
    BOOL isConfigurationFile = FALSE;
    BOOL isScriptFile        = FALSE;
    
    if (   [ext isEqualToString: @"ovpn"]
        || [ext isEqualToString: @"conf"]  ) {
        isConfigurationFile  = TRUE;
    } else if (  [ext isEqualToString: @"sh"]  ) {
        isScriptFile = TRUE;
    } else if (  ! [KEY_AND_CRT_EXTENSIONS containsObject: ext]  ) {
        return [self logMessage: [NSString stringWithFormat: @"File '%@' has an extension which is not known to Tunnelblick.", path]
                      localized: [NSString stringWithFormat: NSLocalizedString(@"File '%@' has an extension which is not known to Tunnelblick.", @"Window text"), [path lastPathComponent]]];
    }
    
    // Don't test anything else in a configuration file because it can contain UTF8 characters pretty much anywhere
	// Don't test anything else in a script file because that is checked elsewhere for CR characters, which are the only characters that are not allowed
    if (  isConfigurationFile
		|| isScriptFile  ) {
        return nil;
    }
    
    // It is a key or certificate file
    BOOL inBackslash = FALSE;
    unsigned i;
    unsigned lineNumber = 1;
    for (  i=0; i<[data length]; i++  ) {
        unsigned char c = chars[i];
        if (  ! inBackslash  ) {
            if (   ((c & 0x80) != 0)   // If high bit set
                || (c == 0x7F)         // Or DEL
                || (   (c < 0x20)      // Or a control character
                    && (c != '\t')     //    but not an HTAB
                    && (c != '\n')     //            or LF
                    && (c != '\r')     //            or CR
                    )
                ) {
                return [self logMessage: [NSString stringWithFormat: @"Line %d of file '%@' contains a non-printable character (0x%02X) which is not allowed.", lineNumber, path, (unsigned int)c]
                              localized: [NSString stringWithFormat: NSLocalizedString(@"Line %d of file '%@' contains a non-printable character (0x%02X) which is not allowed.\n\n", @"Window text"), lineNumber, [path lastPathComponent], (unsigned int)c]];
            }
            if (  c == '\n'  ) {
                lineNumber++;
            } else if (  c == '\\'  ) {
                inBackslash = TRUE;
            }
        } else if (  inBackslash  ) {
            inBackslash = FALSE;
        }
    }
    
    if (  inBackslash  ) {
        return [self logMessage: [NSString stringWithFormat: @"File '%@' ends with a backslash, which is not allowed.", path]
                      localized: [NSString stringWithFormat: NSLocalizedString(@"File '%@' ends with a backslash, which is not allowed.", @"Window text"), [path lastPathComponent]]];
    }
    
    return nil;
}

-(NSString *) duplicateFileFrom: (NSString *) source
				 		 toPath: (NSString *) target {
	
	// Copies a file. If it is a ".sh" file, CR characters are removed from the copy
	
	if (  [[target pathExtension] isEqualToString: @"sh"]  ) {
		NSData * data = [[NSFileManager defaultManager] contentsAtPath: source];
		if (  ! data  ) {
			return [self logMessage: [NSString stringWithFormat: @"The file %@ is missing.", source]
						  localized: [NSString stringWithFormat: NSLocalizedString(@"The file %@ is missing", @"Window text"), [source lastPathComponent]]];
		}
		if (  [data length] == 0  ) {
			return [self logMessage: [NSString stringWithFormat: @"The file %@ is empty.", source]
						  localized: [NSString stringWithFormat: NSLocalizedString(@"The file %@ is empty", @"Window text"), [source lastPathComponent]]];
		}
		
		NSMutableString * contents = [[[NSMutableString alloc] initWithData: data encoding: NSUTF8StringEncoding] autorelease];
		BOOL crCharactersRemoved = FALSE;
		
		NSUInteger ix;
		for ( ix=0; ix<[contents length]; ix++  ) {
			unichar ch = [contents characterAtIndex: ix];
			if (  ch == '\r'  ) {
				crCharactersRemoved = TRUE;
				[contents deleteCharactersInRange: NSMakeRange(ix, 1)];
				ix--;
			}
		}
		if (  crCharactersRemoved  ) {
			if (  [contents writeToFile: target atomically: YES encoding: NSUTF8StringEncoding error: NULL]  ) {
				[self logMessage: [NSString stringWithFormat: @"Copied %@, removing CR characters", [target lastPathComponent]]
					   localized: [NSString stringWithFormat: NSLocalizedString(@"Copied %@, removing CR characters", @"Window text"), [target lastPathComponent]]];
				return nil;
			} else {
				return [self logMessage: [NSString stringWithFormat: @"Failed to copy %@ to %@", source, target]
							  localized: [NSString stringWithFormat: NSLocalizedString(@"Failed to copy %@ to %@", @"Window text"), source, target]];
			}
		} else {
			if (  [contents writeToFile: target atomically: YES encoding: NSUTF8StringEncoding error: NULL]  ) {
				[self logMessage: [NSString stringWithFormat: @"Copied %@", [target lastPathComponent]]
					   localized: [NSString stringWithFormat: NSLocalizedString(@"Copied %@", @"Window text"), [target lastPathComponent]]];
				return nil;
			} else {
				return [self logMessage: [NSString stringWithFormat: @"Failed to copy %@ to %@", source, target]
							  localized: [NSString stringWithFormat: NSLocalizedString(@"Failed to copy %@ to %@", @"Window text"), source, target]];
			}
		}
	} else {
		if (  [gFileMgr tbCopyPath: source toPath: target handler: nil]  ) {
			[self logMessage: [NSString stringWithFormat: @"Copied %@", [target lastPathComponent]]
				   localized: [NSString stringWithFormat: NSLocalizedString(@"Copied %@", @"Window text"), [target lastPathComponent]]];
			return nil;
		} else {
			return [self logMessage: [NSString stringWithFormat: @"Failed to copy %@ to %@", source, target]
						  localized: [NSString stringWithFormat: NSLocalizedString(@"Failed to copy %@ to %@", @"Window text"), source, target]];
		}
	}
	
	return nil;	// Make the analyzer happy
}

-(BOOL) existingFilesList: (NSArray *)  list
             hasAMatchFor: (NSString *) name {
    
    if (  ! list  ) {
        return NO;
    }
    
    if (  [list containsObject: name]  ) {
        return YES;
    }
    
    NSString * entry;
    NSEnumerator * e = [list objectEnumerator];
    while (  (entry = [e nextObject])  ) {
        NSRange rng = [entry rangeOfString: @"*"];
        if (  rng.length != 0  ) {
            NSString * prefix = [entry substringToIndex:   rng.location];
            NSString * suffix = [entry substringFromIndex: rng.location + 1];
            NSString * restOfName = [name substringFromIndex: [prefix length]];
            if (   (   ([prefix length] == 0 )
                    || [name hasPrefix: prefix] )
                && (   ([suffix length] == 0 )
                    || [restOfName hasSuffix: suffix] )
                ) {
                return YES;
            }
        }
    }
    
    return NO;
}

-(NSString *) processPathRange: (NSRange) rng
	   removeBackslashes: (BOOL) removeBackslashes
        needsShExtension: (BOOL) needsShExtension
              okIfNoFile: (BOOL) okIfNoFile
          ignorePathInfo: (BOOL) ignorePathInfo {
    
	// If this is a  _CONVERSION_ of an existing configuration:
    // Then call with ignorePathInfo FALSE
    //      -- To use the path as it appears in the configuration file when accessing .ca, .cert, .key, etc. files
    //
	// If this is an _INSTALLATION_ of a .tblk
    // Then call with ignorePathInfo FALSE
    //      -- To use only the last path component of paths in the configuration file when accessing .ca, .cert, .key, etc. files
    //        (Because the files have already been copied to the same folder as the configuration file.)
    //
    // Returns nil if OK, otherwise a localized error message (having already logMessage-ed an error)
    
    // Get raw path from the configuration file itself
	NSString * inPathString = [configString substringWithRange: rng];
	if (  removeBackslashes  ) {
		NSMutableString * path = [inPathString mutableCopy];
		[path replaceOccurrencesOfString: @"\\" withString: @"" options: 0 range: NSMakeRange(0, [path length])];
		inPathString = [NSString stringWithString: path];
		[path release];
	}
	
    // Process that pathString into an absolute path to access the file right now
	NSString * inPath = [[inPathString copy] autorelease];
    BOOL pathIsAbsolute         = [inPath hasPrefix: @"/"];
    BOOL pathIsInHomeFolder     = [inPath hasPrefix: @"~"];
    BOOL pathIsRelativeToTblk = ! (pathIsAbsolute || pathIsInHomeFolder);
	if (  ! pathIsAbsolute  ) {
		if (  pathIsInHomeFolder  ) {
			inPath = [inPath stringByExpandingTildeInPath];
		} else {
			NSString * baseFolder = [configPath stringByDeletingLastPathComponent];
			NSString * restOfPath = (  ignorePathInfo
                                     ? [inPath lastPathComponent] // INSTALLATION, ignore path info in the configuration file
                                     : inPath);                   // CONVERSION,   use the PATH as it appears in the configuration file
			inPath = [baseFolder stringByAppendingPathComponent: restOfPath];
		}
	}
	
    BOOL fileExists = [gFileMgr fileExistsAtPath: inPath];
    
    if (  ! fileExists  ) {
        if (  ! okIfNoFile  ) {
            // Deal with TBKeepExistingFilesList -- see if the file exists in the existing unsecured .tblk/Contents/Resources
            NSString * fileName = [inPath lastPathComponent];
            if (   useExistingFiles
                && [self existingFilesList: useExistingFiles hasAMatchFor: fileName]
                && ( ! [fileName hasSuffix: @".sh"] )
                && pathIsRelativeToTblk  ) {
                NSString * existingPrivatePath = [[[replacingTblkPath stringByAppendingPathComponent: @"Contents"]
                                                   stringByAppendingPathComponent: @"Resources"]
                                                  stringByAppendingPathComponent: fileName];
                fileExists = [gFileMgr fileExistsAtPath: existingPrivatePath];
                if (  fileExists  ) {
                    // Yes, so use the existing file as the inPath
                    inPath = existingPrivatePath;
                    [self logMessage: [NSString stringWithFormat: @"The configuration file refers to a file '%@', which does not exist in the new configuration, so the existing unsecured file has been used.", inPathString]
                           localized: [NSString stringWithFormat: NSLocalizedString(@"The configuration file refers to a file\n\n%@\n\nwhich does not exist in the new configuration, so the existing unsecured file has been used.", @"Window text"), inPathString]];
                } else {
                    if (  pathIsRelativeToTblk  ) {
                        return [self logMessage: [NSString stringWithFormat: @"The configuration file refers to a file '%@', which does not exist (even in the configuration being replaced).", inPathString]
                                      localized: [NSString stringWithFormat: NSLocalizedString(@"The configuration file refers to a file\n\n%@\n\nwhich does not exist (even in the configuration being replaced).", @"Window text"), inPathString]];
                    } else {
                        return [self logMessage: [NSString stringWithFormat: @"The configuration file refers to a file '%@' which should be located at '%@' but the file does not exist (even in the configuration being replaced).", inPathString, inPath]
                                      localized: [NSString stringWithFormat: NSLocalizedString(@"The configuration file refers to a file\n\n%@\n\nwhich should be located at\n\n%@\n\nbut the file does not exist (even in the configuration being replaced).", @"Window text"), inPathString, inPath]];
                    }
                }
            } else {
                if (  [inPath isEqualToString: inPathString]  ) {
                    return [self logMessage: [NSString stringWithFormat: @"The configuration file refers to a file '%@', which does not exist.", inPathString]
                                  localized: [NSString stringWithFormat: NSLocalizedString(@"The configuration file refers to a file\n\n%@\n\nwhich does not exist.", @"Window text"), inPathString]];
                } else {
                    return [self logMessage: [NSString stringWithFormat: @"The configuration file refers to a file '%@' which should be located at '%@' but the file does not exist.", inPathString, inPath]
                                  localized: [NSString stringWithFormat: NSLocalizedString(@"The configuration file refers to a file\n\n%@\n\nwhich should be located at\n\n%@\n\nbut the file does not exist.", @"Window text"), inPathString, inPath]];
                }
            }
        }
    }
    
    NSString * file                     = [inPath lastPathComponent];
    NSString * fileWithNeededExtension  = [NSString stringWithString: inPath];
	NSString * inPathWithAddedExtension = [NSString stringWithString: inPath];
	
    if (  fileExists) {
    
        NSString * errMsg = [self fileIsReasonableSize: inPath ];
        if (  errMsg  ) {
            return errMsg;
        }
        
        // Make sure the file has an extension that Tunnelblick can secure properly
        fileWithNeededExtension = [[file copy] autorelease];
        NSString * extension = [file pathExtension];
        if (   needsShExtension  ) {
            if (  ! [extension isEqualToString: @"sh"]  ) {
                fileWithNeededExtension = [file stringByAppendingPathExtension: @"sh"];
                inPathWithAddedExtension = [inPath stringByAppendingPathExtension: @"sh"];
                [self logMessage: [NSString stringWithFormat: @"Added '.sh' extension to %@ so it will be secured properly", file]
                       localized: [NSString stringWithFormat: NSLocalizedString(@"Added '.sh' extension to %@ so it will be secured properly", @"Window text"), file]];
            }
        } else {
            if (   ( ! extension)
                || ( ! [KEY_AND_CRT_EXTENSIONS containsObject: extension] )  ) {
                fileWithNeededExtension = [file stringByAppendingPathExtension: @"key"];
                inPathWithAddedExtension = [inPath stringByAppendingPathExtension: @"sh"];
                [self logMessage: [NSString stringWithFormat: @"Added a '.key' extension to %@ so it will be secured properly", file]
                       localized: [NSString stringWithFormat: NSLocalizedString(@"Added a '.key' extension to %@ so it will be secured properly", @"Window text"), file]];
            }
        }
		
		extension = [inPathWithAddedExtension pathExtension];
		if (  ! [extension isEqualToString: @"sh"]  ) {
			errMsg = [self errorIfBadCharactersInFileAtPath: inPath];
			if (  errMsg  ) {
				return errMsg;
			}
		}
	}
    
    if (   fileExists
		&& outputPath  ) {

        NSString * outPath = [[[outputPath stringByAppendingPathComponent: @"Contents"]
                               stringByAppendingPathComponent: @"Resources"]
                              stringByAppendingPathComponent: fileWithNeededExtension];
        
		unsigned linkCounter = 0;
        while (   [[[gFileMgr tbFileAttributesAtPath: inPath traverseLink: NO] objectForKey: NSFileType] isEqualToString: NSFileTypeSymbolicLink]
			   && (linkCounter++ < 20)  ) {
            NSString * newInPath = [gFileMgr tbPathContentOfSymbolicLinkAtPath: inPath];
            if (  newInPath  ) {
				if (  ! [newInPath hasPrefix: @"/"]  ) {
					newInPath = [[inPath stringByDeletingLastPathComponent] stringByAppendingPathComponent: newInPath];
                }
                [self logMessage: [NSString stringWithFormat: @"Resolved symbolic link at '%@' to '%@'", inPath, newInPath]
                       localized: [NSString stringWithFormat: NSLocalizedString(@"Resolved symbolic link at '%@' to '%@'", @"Window text"), inPath, newInPath]];
				inPath = [[newInPath retain] autorelease];
            } else {
                return [self logMessage: [NSString stringWithFormat: @"Could not resolve symbolic link at %@", inPath]
                              localized: [NSString stringWithFormat: NSLocalizedString(@"Could not resolve symbolic link at %@", @"Window text"), inPath]];
            }
		}
		
		if (  [[[gFileMgr tbFileAttributesAtPath: inPath traverseLink: NO] objectForKey: NSFileType] isEqualToString: NSFileTypeSymbolicLink]  ) {
			return [self logMessage: [NSString stringWithFormat: @"Symbolic links nested too deeply. Gave up at %@", inPath]
                          localized: [NSString stringWithFormat: NSLocalizedString(@"Symbolic links nested too deeply. Gave up at %@", @"Window text"), inPath]];
		}

		if (  ! [gFileMgr fileExistsAtPath: outPath]  ) {
			NSString * result = [self duplicateFileFrom: inPath toPath: outPath];
			if (  result  ) {
				return result;
			}
		} else if (  [gFileMgr contentsEqualAtPath: inPath andPath: outPath ]) {
			NSString * name = [outPath lastPathComponent];
			[self logMessage: [NSString stringWithFormat: @"Skipped copying '%@' because a file with that name and contents has already been copied.", inPath]
                   localized: [NSString stringWithFormat: NSLocalizedString(@"Skipped copying %@ because a file with that name and contents has already been copied.", @"Window text"), name]];
		} else {
			return [self logMessage: [NSString stringWithFormat: @"Unable to copy file at '%@' to '%@' because the same name is used for different contents", inPath, outPath]
                          localized: [NSString stringWithFormat: NSLocalizedString(@"Unable to copy file at '%@' to '%@' because the same name is used for different contents", @"Window text"), inPath, outPath]];
		}
		
        mode_t perms = (  [[outPath pathExtension] isEqualToString: @"sh"]
                        ? PERMS_PRIVATE_SCRIPT
                        : PERMS_PRIVATE_OTHER);
		if (  ! checkSetPermissions(outPath, perms, YES)  ) {
			return [self logMessage: [NSString stringWithFormat: @"Unable to set permissions on '%@'", outPath]
                          localized: [NSString stringWithFormat: NSLocalizedString(@"Unable to set permissions on '%@'", @"Window text"), outPath]];
        }
		
		[pathsAlreadyCopied addObject: inPath];
    }
	
	if (   fileExists
		&& ( ! [inPathString isEqualToString: fileWithNeededExtension])  ) {
		[tokensToReplace  addObject: [[[ConfigurationToken alloc]
                                       initWithRange: rng
                                       inString:      configString
                                       lineNumber:    inputLineNumber] autorelease]];
		NSMutableString * temp = [fileWithNeededExtension mutableCopy];
		[temp replaceOccurrencesOfString: @" " withString: @"\\ " options: 0 range: NSMakeRange(0, [temp length])];
		[replacementStrings addObject: [NSString stringWithString: temp]];
		[temp release];
    }
	
    return nil;
}

-(NSString *) duplicateOtherFiles {
    
    // Copy siblings of the config file into the final .tblk
    // (But only copy files that have not already been copied, and only copy files whose type we know)
    
    NSArray * extensionsToCopy = TBLK_INSTALL_EXTENSIONS;
    NSArray * extensionsToIgnore = [NSArray arrayWithObjects: @"ovpn", @"conf", @"tblk", nil];
	
    // Get a list of files in the .tblk already
    NSMutableArray * filesAlreadyInTblk = [NSMutableArray arrayWithCapacity: 10];
    NSString * resourcesPath = [outputPath stringByAppendingPathComponent: @"Contents/Resources"];
    NSString * file;
    NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: resourcesPath];
    while (  (file = [dirEnum nextObject])  ) {
        [dirEnum skipDescendents];
        NSString * ext = [file pathExtension];
        if  (  [extensionsToCopy containsObject: ext]  ) {
            [filesAlreadyInTblk addObject: file];
        }
    }
    
    // Go through the folder that contains the config file, looking for more files to copy into the final .tblk
    NSString * container = [configPath stringByDeletingLastPathComponent];
	
	// If the config file is in Resources, and there is an Info.plist file in the folder that contains Resources (presumably Contents),
	// then remember that path and copy it ino the final .tblk if we don't copy a different one from the same folder as the config file
	NSString * infoPlistPath = nil;
	if (  [[container lastPathComponent] isEqualToString: @"Resources"]  ) {
		infoPlistPath = [[container stringByDeletingLastPathComponent] stringByAppendingPathComponent: @"Info.plist"];
		if (  ! [gFileMgr fileExistsAtPath: infoPlistPath]  ) {
			infoPlistPath = nil;
		}
	}
	
    dirEnum = [gFileMgr enumeratorAtPath: container];
	BOOL isDir;
    while (  (file = [dirEnum nextObject])  ) {
		[dirEnum skipDescendents];
        NSString * ext = [file pathExtension];
		NSString * fullPath = [container stringByAppendingPathComponent: file];
		if (  ! [pathsAlreadyCopied containsObject: fullPath]  ) {
			if  (  [extensionsToCopy containsObject: ext]  ) {
				NSString * fileName = [file lastPathComponent];
				if (  ! [filesAlreadyInTblk containsObject: fileName]  ) {
					NSString * source = [container stringByAppendingPathComponent: file];
					NSString * target = [resourcesPath stringByAppendingPathComponent: file];
					NSString * result = [self duplicateFileFrom: source toPath: target];
					if (  result  ) {
						return [self logMessage: [NSString stringWithFormat: @"The file in which the error occurred was %@", source] 
									  localized: [NSString stringWithFormat: NSLocalizedString(@"There was a problem with\n\n%@:\n\n%@", @"Window text"), source, result]];
					}
				}
			} else if (  [[fullPath lastPathComponent] isEqualToString: @"Info.plist"]  ) {
				NSString * fileName = [file lastPathComponent];
				if (  ! [filesAlreadyInTblk containsObject: fileName]  ) {
					NSString * source = [container stringByAppendingPathComponent: file];
					NSString * target = [[resourcesPath stringByDeletingLastPathComponent] stringByAppendingPathComponent: file];
					NSString * result = [self duplicateFileFrom: source toPath: target];
					if (  result  ) {
						return [self logMessage: [NSString stringWithFormat: @"The file in which the error occurred was %@", source] 
									  localized: [NSString stringWithFormat: NSLocalizedString(@"There was a problem with\n\n%@:\n\n%@", @"Window text"), source, result]];
					}
				}
				
			} else if (   itemIsVisible(fullPath)
					   && ( ! [extensionsToIgnore containsObject: ext] )
					   && [gFileMgr fileExistsAtPath: fullPath isDirectory: &isDir]
					   && ( ! isDir )  ) {
				return [self logMessage: [NSString stringWithFormat: @"Unknown file type '%@' for %@", ext, fullPath]
							  localized: [NSString stringWithFormat: NSLocalizedString(@"Unknown extension '%@' for %@", @"Window text"), ext, fullPath]];
			}
		}
	}
	
	// If there is an Info.plist in Resources (one level up in the path), and there isn't an Info.plist from the same folder as the config file
	// Then copy the one from Resources into the .tblk
	if (  infoPlistPath  ) {
		NSString * target = [[resourcesPath stringByDeletingLastPathComponent] stringByAppendingPathComponent: @"Info.plist"];
		if (   [filesAlreadyInTblk containsObject: @"Info.plist"]
			|| [gFileMgr fileExistsAtPath: target]
			) {
			NSLog(@"Ignoring Info.plist in %@ because we have already copied the Info.plist in Resources", [[target stringByDeletingLastPathComponent] lastPathComponent]);
		} else {
			NSString * result = [self duplicateFileFrom: infoPlistPath toPath: target];
			if (  result  ) {
				return [self logMessage: [NSString stringWithFormat: @"The file in which the error occurred was %@", infoPlistPath] 
							  localized: [NSString stringWithFormat: NSLocalizedString(@"There was a problem with\n\n%@:\n\n%@", @"Window text"), infoPlistPath, result]];
			}
		}
	}
	
	return nil;
}

-(NSString *) processNonReadableConfiguration {
    
    // Create the .tblk structure in the output file
	NSString * contentsPath  = [outputPath stringByAppendingPathComponent: @"Contents"];
	NSString * resourcesPath = [contentsPath stringByAppendingPathComponent: @"Resources"];
	if (  ! createDir(resourcesPath, PERMS_SECURED_FOLDER)  ) {
		appendLog([NSString stringWithFormat: @"Failed to create folder at %@", resourcesPath]);
		return [NSString stringWithFormat: NSLocalizedString(@"Failed to create folder at %@", @"Window text"), resourcesPath];
	}
	
	// Create symlinks to everything in the .tblk
	NSString * configContainer = [configPath stringByDeletingLastPathComponent];
	NSString * file;
	NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: configContainer];
	while (  (file = [dirEnum nextObject])  ) {
		NSString * fullPath = [configContainer stringByAppendingPathComponent: file];
		BOOL isDir;
		if (   [gFileMgr fileExistsAtPath: fullPath isDirectory: &isDir]
			&& ( ! isDir)
			&& ( ! [file hasPrefix: @"."])  ) {
			NSString * sourcePath = [configContainer stringByAppendingPathComponent: file];
			NSString * targetPath = (  [file isEqualToString: @"Info.plist"]
									 ? [contentsPath    stringByAppendingPathComponent: file]
									 : [resourcesPath   stringByAppendingPathComponent: file]);
			if (  [gFileMgr tbCreateSymbolicLinkAtPath: targetPath pathContent: sourcePath]  ) {
				appendLog([NSString stringWithFormat: @"Created symlink\n  to %@\n  at %@", sourcePath, targetPath]);
			} else {
				appendLog([NSString stringWithFormat: @"Failed to create symlink\n  to %@\n  at %@", sourcePath, targetPath]);
				return [NSString stringWithFormat: NSLocalizedString(@"Failed to create symlink\n  to %@\n  at %@", @"Window text"), sourcePath, targetPath];
			}
		}
	}
	
	// Create symlinks to files in useExistingFiles from the existing configuration
	NSString * existingConfigContainer = [[replacingTblkPath stringByAppendingPathComponent: @"Contents"]
										  stringByAppendingPathComponent: @"Resources"];
	if (   existingConfigContainer
		&& ([useExistingFiles count] != 0)) {
		NSString * file;
		NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: existingConfigContainer];
		while (  (file = [dirEnum nextObject])  ) {
			NSString * fullPath = [existingConfigContainer stringByAppendingPathComponent: file];
			BOOL isDir;
			if (   [gFileMgr fileExistsAtPath: fullPath isDirectory: &isDir]
				&& ( ! isDir)
				&& ( ! [file hasPrefix: @"."] )
				&&  [self existingFilesList: useExistingFiles hasAMatchFor: file]  ) {
				NSString * sourcePath = [existingConfigContainer stringByAppendingPathComponent: file];
				NSString * targetPath = [resourcesPath           stringByAppendingPathComponent: [file lastPathComponent]];
				if (  [gFileMgr tbCreateSymbolicLinkAtPath: targetPath pathContent: sourcePath]  ) {
					appendLog([NSString stringWithFormat: @"Created symlink\n  to %@\n  at %@", sourcePath, targetPath]);
				} else {
					appendLog([NSString stringWithFormat: @"Failed to create symlink\n  to %@\n  at %@", sourcePath, targetPath]);
					return [NSString stringWithFormat: NSLocalizedString(@"Failed to create symlink\n  to %@\n  at %@", @"Window text"), sourcePath, targetPath];
				}
			}
		}
	} else {
		if (  [useExistingFiles count] != 0  ) {
			appendLog([NSString stringWithFormat: @"Not replacing an existing configuration, so configuration '%@' cannot use 'TBKeepExistingFilesList'", nameForErrorMessages]);
			return [NSString stringWithFormat: NSLocalizedString(@"Not replacing an existing configuration, so configuration '%@' cannot use 'TBKeepExistingFilesList'", @"Window text"), nameForErrorMessages];
		}
	}
	
	return nil;
}

-(NSString *) convertConfigPath: (NSString *) theConfigPath
					 outputPath: (NSString *) theOutputPath
              replacingTblkPath: (NSString *) theReplacingTblkPath
                    displayName: (NSString *) theDisplayName
		   nameForErrorMessages: (NSString *) theNameForErrorMessages
               useExistingFiles: (NSArray *)  theUseExistingFiles
						logFile: (FILE *)     theLogFile
					   fromTblk: (BOOL)       theFromTblk {
    
    // Converts a configuration file for use in a .tblk by removing all path information from ca, cert, etc. options.
    //
	// If outputPath is specified, it is created as a .tblk and the configuration file and keys and certificates are copied into it.
    // If outputPath is nil, the configuration file's contents are replaced after removing path information.
    //
    // If displayName is specified and is in useExistingFiles, files referenced in the OpenVPN config that do not exist in the
    // configuration being installed are copied from the secured (alternate, shadow copy) of the existing private configuration.
    // If any files in the new configuration exist and are in useExistingFiles, that is an error.
    //
	// If logFile is NULL, NSLog is used
	//   * When invoked from installer to convert existing .ovpn/.conf files to .tblks,
	//     this will be a FILE reference to a file to be used for logging. The contents of
	//     this file will be included in installer's NSLog entry.
    //   * When invoked from ConfigurationManager to install a .ovpn/.conf/.tblk, this
	//     will be NULL and ConfigurationConverter will output to NSLog directly.
    //
	// If fromTblk is true, all non-config files that are siblings of the configuration file, and any files in non-.tblk folders that are
	// siblings of the configuration file, are copied into the .tblk.
	//
	//   * When invoked to convert a configuration file inside a .tblk being installed, this should be TRUE
	//     Otherwise, it should be FALSE.
	//
    // Notwithstanding the foregoing, if we are installing from L_AS_T/Tblks, a symlink is created for all files in the source .tblk and all
	// files referenced in "TBKeepExistingFilesList".
    //
    // Returns nil if no error; otherwise returns a localized error message
	
    configPath           = [theConfigPath           copy];
    outputPath           = [theOutputPath           copy];
    replacingTblkPath    = [theReplacingTblkPath    copy];
    displayName          = [theDisplayName          copy];
    nameForErrorMessages = [theNameForErrorMessages copy];
    useExistingFiles     = [theUseExistingFiles     copy];
    logFile    = theLogFile;
	fromTblk = theFromTblk;
    
    logString          = [[NSMutableString alloc] init];
    localizedLogString = [[NSMutableString alloc] init];
    
    NSString * errMsg = [self fileIsReasonableSize: theConfigPath];
    if (  errMsg  ) {
        return errMsg;
    }
    
    if (  [theConfigPath hasPrefix: L_AS_T_TBLKS]  ) {
        return [self processNonReadableConfiguration];
    }
    
    errMsg = [self errorIfBadCharactersInFileAtPath: theConfigPath ];
    if (  errMsg  ) {
        return errMsg;
    }
    
    configString = [[[[NSString alloc] initWithContentsOfFile: configPath encoding: NSUTF8StringEncoding error: NULL] autorelease] mutableCopy];
    
    // Append newline to file if it doesn't aleady end in one (simplifies parsing)
    if (  ! [configString hasSuffix: @"\n"]  ) {
        [configString appendString: @"\n"];
    }
    
    tokens = [[self getTokens] copy];
	if (  ! tokens  ) {
		return [self logMessage: nil
                      localized: [NSString stringWithFormat: NSLocalizedString(@"One or more problems were detected:\n\n%@", @"Window text"), [self localizedLogString]]];
	}
	
    tokensToReplace    = [[NSMutableArray alloc] initWithCapacity: 8];
	replacementStrings = [[NSMutableArray alloc] initWithCapacity: 8];
	pathsAlreadyCopied = [[NSMutableArray alloc] initWithCapacity: 8];
    inputIx         = 0;
    inputLineNumber = 0;
    
    // List of OpenVPN options that cannot appear in a Tunnelblick VPN Configuration
    NSArray * optionsThatAreNotAllowedWithTunnelblick = OPENVPN_OPTIONS_THAT_CAN_ONLY_BE_USED_BY_TUNNELBLICK;
    NSArray * optionsThatAreNotAllowedOnOSX = OPENVPN_OPTIONS_THAT_ARE_WINDOWS_ONLY;
    
    // List of OpenVPN options that take a file path
    NSArray * optionsWithPath = [NSArray arrayWithObjects:
//					             @"askpass",                       // askpass        'file' not supported since we don't compile with --enable-password-save
//								 @"auth-user-pass",				   // auth-user-pass 'file' not supported since we don't compile with --enable-password-save
								 @"ca",
								 @"cert",
								 @"dh",
								 @"extra-certs",
								 @"key",
								 @"pkcs12",
								 @"crl-verify",                    // Optional 'direction' argument
								 @"secret",                        // Optional 'direction' argument
								 @"tls-auth",                      // Optional 'direction' argument
								 nil];
    
    // List of OpenVPN options that take a command
	NSArray * optionsWithCommand = [NSArray arrayWithObjects:
									@"tls-verify",
									@"auth-user-pass-verify",
									@"client-connect",
									@"client-disconnect",
									@"up",
									@"down",
									@"ipchange",
									@"route-up",
									@"route-pre-down",
									@"learn-address",
									nil];
	
	NSArray * optionsWithArgsThatAreOptional = [NSArray arrayWithObjects:
									            @"auth-user-pass",                // Optional 'file' argument not supported since we don't compile with --enable-password-save
												@"crl-verify",                    // Optional 'direction' argument
												@"secret",                        // Optional 'direction' argument
												@"tls-auth",                      // Optional 'direction' argument after 'file' argument
												nil];
    
    NSArray * beginInlineKeys = [NSArray arrayWithObjects:
                                 @"<ca>",
                                 @"<cert>",
                                 @"<dh>",
                                 @"<extra-certs>",
                                 @"<key>",
                                 @"<pkcs12>",
                                 @"<secret>",
                                 @"<tls-auth>",
                                 nil];
    
    NSArray * endInlineKeys = [NSArray arrayWithObjects:
                               @"</ca>",
                               @"</cert>",
                               @"</dh>",
                               @"</extra-certs>",
                               @"</key>",
                               @"</pkcs12>",
                               @"</secret>",
                               @"</tls-auth>",
                               nil];
    
    // List of OpenVPN options that cannot appear in a Tunnelblick VPN Configuration unless the file they reference has an absolute path
    NSArray * optionsThatRequireAnAbsolutePath = [NSArray arrayWithObjects:
                                                  @"status",
                                                  @"write-pid",
                                                  @"replay-persist",
                                                  nil];
    
    // Create the .tblk/Contents/Resources folder
    if (  outputPath  ) {
		NSString * tblkResourcesPath = [[outputPath stringByAppendingPathComponent: @"Contents"]
                                        stringByAppendingPathComponent: @"Resources"];
        if (  createDir(tblkResourcesPath, PERMS_PRIVATE_FOLDER) == -1  ) {
            return [self logMessage: [NSString stringWithFormat: @"Unable to create %@ owned by %ld:%ld with %lo permissions",
                                      tblkResourcesPath, (long) getuid(), (long) ADMIN_GROUP_ID, (long) PERMS_PRIVATE_OTHER]
                          localized: [NSString stringWithFormat: NSLocalizedString(@"Unable to create %@ owned by %ld:%ld with %lo permissions", @"Window text"),
                                       tblkResourcesPath, (long) getuid(), (long) ADMIN_GROUP_ID, (long) PERMS_PRIVATE_OTHER]];
        }
    }
    
    unsigned tokenIx = 0;
    while (  tokenIx < [tokens count]  ) {
        
        ConfigurationToken * firstToken = [tokens objectAtIndex: tokenIx++];
        inputLineNumber = [firstToken lineNumber];
        
        if (  ! [firstToken isLinefeed]  ) {
            ConfigurationToken * secondToken = nil;
            if (  tokenIx < [tokens count]  ) {
                secondToken = [tokens objectAtIndex: tokenIx];
                if (  [secondToken isLinefeed]  ) {
                    secondToken = nil;
                }
            }
            
			if (  [optionsThatAreNotAllowedWithTunnelblick containsObject: [firstToken stringValue]]  ) {
				return [self logMessage: [NSString stringWithFormat: @"The '%@' OpenVPN option is not allowed when using Tunnelblick.", [firstToken stringValue]]
                              localized: [NSString stringWithFormat: NSLocalizedString(@"The '%@' OpenVPN option is not allowed when using Tunnelblick.", @"Window text"), [firstToken stringValue]]];
			}
            
            if (  [optionsThatAreNotAllowedOnOSX containsObject: [firstToken stringValue]]  ) {
				return [self logMessage: [NSString stringWithFormat: @"The '%@' OpenVPN option is not allowed on OS X. It is a 'Windows only' option.", [firstToken stringValue]]
                              localized: [NSString stringWithFormat: NSLocalizedString(@"The '%@' OpenVPN option is not allowed on OS X. It is a 'Windows only' option.", @"Window text"), [firstToken stringValue]]];
			}
            
            if (  [optionsWithPath containsObject: [firstToken stringValue]]  ) {
                if (  secondToken  ) {
                    // remove leading/trailing single- or double-quotes
					NSRange r2 = [secondToken range];
                    if (   (   [[configString substringWithRange: NSMakeRange(r2.location, 1)] isEqualToString: @"\""]
                            && [[configString substringWithRange: NSMakeRange(r2.location + r2.length - 1, 1)] isEqualToString: @"\""]  )
                        || (   [[configString substringWithRange: NSMakeRange(r2.location, 1)] isEqualToString: @"'"]
                            && [[configString substringWithRange: NSMakeRange(r2.location + r2.length - 1, 1)] isEqualToString: @"'"]  )  )
                    {
                        r2.location++;
                        r2.length -= 2;
                    }
                    
                    // copy the file and change the path in the configuration string if necessary
                    if (  ! [[configString substringWithRange: r2] isEqualToString: @"[inline]"]  ) {
                        NSString * errMsg = [self processPathRange: r2 removeBackslashes: YES needsShExtension: NO okIfNoFile: NO ignorePathInfo: (! outputPath)];
                        if (  errMsg  ) {
                            return errMsg;
                        }
                    }
                    tokenIx++;
                } else {
                    if (  ! [optionsWithArgsThatAreOptional containsObject: [firstToken stringValue]]  ) {
                        return [self logMessage: [NSString stringWithFormat: @"Expected path not found for '%@'", [firstToken stringValue]]
                                      localized: [NSString stringWithFormat: NSLocalizedString(@"Expected path not found for '%@'", @"Window text"), [firstToken stringValue]]];
                    }
                }
            } else if (  [optionsWithCommand containsObject: [firstToken stringValue]]  ) {
                if (  secondToken  ) {
					NSRange r2 = [secondToken range];
                    
                    // The second token is a command, which consists of a path and arguments, so we must parse the command
                    // to extract the path, then use that extracted path
                    NSString * command = [[configString substringWithRange: [secondToken range]] stringByAppendingString: @"\n"];
                    ConfigurationConverter * converter = [[ConfigurationConverter alloc] init];
                    NSArray * commandTokens = [converter getTokensFromPath: configPath lineNumber: inputLineNumber string: command outputPath: outputPath logFile: logFile];
					if (  ! commandTokens  ) {
                        NSString * log = [converter localizedLogString];
						[converter release];
						return [self logMessage: nil
                                      localized: [NSString stringWithFormat: NSLocalizedString(@"One or more problems were detected:\n\n%@", @"Window text"), log]];
					}
                    [converter release];
                    
                    // Set the length of the path of the command
                    NSRange r3 = [[commandTokens objectAtIndex: 0] range];
                    r2.length = r3.length;
                    
                    // copy the file and change the path in the configuration string if necessary
                    NSString * errMsg = [self processPathRange: r2 removeBackslashes: YES needsShExtension: YES okIfNoFile: YES ignorePathInfo: (! outputPath)];
                    if (  errMsg  ) {
                        return errMsg;
                    }
                    
                    tokenIx++;
                    
                } else {
                    if (  ! [optionsWithArgsThatAreOptional containsObject: [firstToken stringValue]]  ) {
                        return [self logMessage: [NSString stringWithFormat: @"Expected command not found for '%@'", [firstToken stringValue]]
                                      localized: [NSString stringWithFormat: NSLocalizedString(@"Expected command not found for '%@'", @"Window text"), [firstToken stringValue]]];
                    }
                }
            } else if (  [beginInlineKeys containsObject: [firstToken stringValue]]  ) {
                NSString * startTokenStringValue = [firstToken stringValue];
                BOOL foundEnd = FALSE;
                ConfigurationToken * token;
				while (  tokenIx < [tokens count]  ) {
                    token = [tokens objectAtIndex: tokenIx++];
                    if (  [token isLinefeed]  ) {
                        if (  tokenIx < [tokens count]  ) {
                            token = [tokens objectAtIndex: tokenIx];
                            if (  [endInlineKeys containsObject: [token stringValue]] ) {
                                foundEnd = TRUE;
                                break;
                            }
                        }
                    }
                }
                
                if (  ! foundEnd ) {
                    return [self logMessage: [NSString stringWithFormat: @"'%@' was not terminated", startTokenStringValue]
                                  localized: [NSString stringWithFormat: NSLocalizedString(@"'%@' was not terminated.", @"Window text"), startTokenStringValue]];
                }
            } else if (  [optionsThatRequireAnAbsolutePath containsObject: [firstToken stringValue]]  ) {
                if (  ! [[secondToken stringValue] hasPrefix: @"/" ]  ) {
                    return [self logMessage: [NSString stringWithFormat: @"The '%@' option is not allowed in an OpenVPN configuration file that is in a Tunnelblick VPN Configuration unless the file it references is specified with an absolute path.", [firstToken stringValue]]
                                  localized: [NSString stringWithFormat: NSLocalizedString(@"The '%@' option is not allowed in an OpenVPN configuration file that is in a Tunnelblick VPN Configuration unless the file it references is specified with an absolute path.", @"Window text"), [firstToken stringValue]]];
                }
            }
            
            // Skip to end of line
            while (  tokenIx < [tokens count]  ) {
                if (  [[tokens objectAtIndex: tokenIx++] isLinefeed]  ) {
                    break;
                }
            }
		}
	}
	
	// Modify the configuration file string, from the end to the start (earlier ranges aren't affected by later changes)
    unsigned i;
    for (  i=[tokensToReplace count]; i > 0; i--  ) {
        [configString replaceCharactersInRange: [[tokensToReplace objectAtIndex: i - 1] range] withString: [replacementStrings objectAtIndex: i - 1]];
    }
	
	// Inhibit display of line number
	inputLineNumber = 0;
    
    if (  fromTblk  ) {
        // Installing a .tblk (not installing a .ovpn/.conf or converting an existing .ovpn/.conf),
		// so need to include any other files in the .tblk (pre-connect.sh, etc. -- whatever there is, we include it)
        NSString * result = [self duplicateOtherFiles];
        if (  result  ) {
            return result;
        }
    }

	// Write out the (possibly modified) configuration file
    if (  outputPath  ) {
        NSString * outputConfigPath= [[[outputPath stringByAppendingPathComponent: @"Contents"]
                                       stringByAppendingPathComponent: @"Resources"]
                                      stringByAppendingPathComponent: @"config.ovpn"];
        NSDictionary * attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                     [NSNumber numberWithUnsignedLong: (unsigned long) getuid()],            NSFileOwnerAccountID,
                                     [NSNumber numberWithUnsignedLong: (unsigned long) ADMIN_GROUP_ID],      NSFileGroupOwnerAccountID,
                                     [NSNumber numberWithUnsignedLong: (unsigned long) PERMS_PRIVATE_OTHER], NSFilePosixPermissions,
                                     nil];
        if (  [gFileMgr createFileAtPath: outputConfigPath
                                contents: [NSData dataWithBytes: [configString UTF8String]
                                                         length: [configString length]]
                              attributes: attributes]  ) {
            [self logMessage: @"Converted OpenVPN configuration"
                   localized: NSLocalizedString(@"Converted OpenVPN configuration", @"Window text")];
        } else {
            return [self logMessage: @"Unable to convert OpenVPN configuration"
                          localized: NSLocalizedString(@"Unable to convert OpenVPN configuration", @"Window text")];
        }
    } else if (  [tokensToReplace count] != 0  ) {
        FILE * outFile = fopen([configPath fileSystemRepresentation], "w");
        if (  outFile  ) {
			if (  fwrite([configString UTF8String], [configString length], 1, outFile) != 1  ) {
				return [self logMessage: @"Unable to write to configuration file for modification"
                              localized: NSLocalizedString(@"Unable to write to configuration file for modification", @"Window text")];
			}
			
			fclose(outFile);
			[self logMessage: @"Modified configuration file to remove path information"
                   localized: NSLocalizedString(@"Modified configuration file to remove path information", @"Window text")];
		} else {
            return [self logMessage: @"Unable to open configuration file for modification"
                          localized: NSLocalizedString(@"Unable to open configuration file for modification", @"Window text")];
		}
	} else {
		[self logMessage: @"Did not need to modify configuration file; no path information to remove"
               localized: NSLocalizedString(@"Did not need to modify configuration file; no path information to remove", @"Window text")];
	}
	
	return nil;
}

@end
