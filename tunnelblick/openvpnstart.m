/*
 * Copyright 2014 by Jonathan K. Bullard. All rights reserved.
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

#import "sharedRoutines.h"


NSAutoreleasePool * pool        = nil;

NSString          * gDeployPath = nil;


// Set up appendLog routine (required to link to sharedRoutines, even though it is not used by anything in sharedRoutines that we call)
void appendLog(NSString * msg) {
    fprintf(stderr, "Tunnelblick: %s\n", [msg UTF8String]);
}


BOOL runningOnLeopardOrNewer(void)
{
    unsigned major, minor, bugFix;
    OSStatus status = getSystemVersion(&major, &minor, &bugFix);
    if (  status != 0) {
        fprintf(stderr, "getSystemVersion() failed");
        return FALSE;
    }
    
    return ( (major > 10) || (minor > 4) );

}


int main(int argc, char * argv[]) {
    
    pool = [[NSAutoreleasePool alloc] init];
	
	// Set up gDeployPath (required to link to sharedRoutines, even though it is not used by anything in sharedRoutines that we call)
	gDeployPath = [[[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent: @"Deploy"] copy];
	
    // Create a tab-separated, newline-terminated command for tunnelblickd
    
    NSMutableString * command = [NSMutableString stringWithCapacity: 2000];
    BOOL errFound = FALSE;
    int i;
    
    for (  i=1; i<argc; i++  ) {
        NSString * arg = [NSString stringWithCString: argv[i] encoding: NSUTF8StringEncoding];
        
        if (  [arg length] == 0  ) {
            
            fprintf(stderr, "Argument %lu is empty. Empty arguments are not allowed.", (unsigned long)i);
            errFound = TRUE;
            
        } else if (  [arg length] >= 1000  ) {
            
            fprintf(stderr, "Argument %lu is too long. Arguments must be less than 1000 characters long.", (unsigned long)i);
            errFound = TRUE;
            
        } else {
            
            if (  [arg rangeOfString: @"\t"].length != 0  ) {
                fprintf(stderr, "Argument %lu contains one or more HTAB characters (ASCII 0x09). They are not allowed in arguments", (unsigned long)i);
                errFound = TRUE;
            }
            
            if (  [command length] == 0  ) {
                [command appendString: arg];
            } else {
                [command appendFormat: @"\t%@", arg];
            }
        }
    }
    
    if (  errFound  ) {
        [pool drain];
		fprintf(stderr, "Exiting openvpnstart before any processing");
        exit(-1);
    }
    
    [command appendString: @"\n"];
    
    // Send the command to tunnelblickd (or run tunnelblick-helper directly if on Tiger; it is SUID) and return the results
    
    OSStatus status = -1;
    NSString * stdoutString = nil;
    NSString * stderrString = nil;
    
    if (  runningOnLeopardOrNewer()  ) {
        status = runTunnelblickd(command, &stdoutString, &stderrString);
    } else {
        NSString * tunnelblickHelperPath = [[NSBundle mainBundle] pathForResource: @"tunnelblick-helper" ofType: nil];
        status = runTool(tunnelblickHelperPath, [NSArray arrayWithObject: command], &stdoutString, &stderrString);
    }
	if (  stdoutString  ) {
		fprintf(stdout, "%s", [stdoutString UTF8String]);
	}
	if (  stderrString  ) {
		fprintf(stderr, "%s", [stderrString UTF8String]);
	}
	[pool drain];
	exit(status);
}
