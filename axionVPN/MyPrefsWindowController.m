/*
 * Copyright 2011, 2012, 2013, 2014 Jonathan K. Bullard. All rights reserved.
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


#import "MyPrefsWindowController.h"

#import <asl.h>

#import "easyRsa.h"
#import "helper.h"
#import "sharedRoutines.h"

#import "AppearanceView.h"
#import "AuthAgent.h"
#import "ConfigurationManager.h"
#import "ConfigurationsView.h"
#import "GeneralView.h"
#import "InfoView.h"
#import "LeftNavDataSource.h"
#import "LeftNavItem.h"
#import "LeftNavViewController.h"
#import "MainIconView.h"
#import "MenuController.h"
#import "NSApplication+LoginItem.h"
#import "NSFileManager+TB.h"
#import "NSString+TB.h"
#import "SettingsSheetWindowController.h"
#import "Sparkle/SUUpdater.h"
#import "TBUserDefaults.h"
#import "UtilitiesView.h"
#import "VPNConnection.h"

extern NSFileManager  * gFileMgr;
extern TBUserDefaults * gTbDefaults;
extern NSString       * gPrivatePath;
extern NSString       * gDeployPath;
extern unsigned         gMaximumLogSize;
extern NSArray        * gProgramPreferences;
extern NSArray        * gConfigurationPreferences;

@interface MyPrefsWindowController()

-(void) setupViews;
-(void) setupConfigurationsView;
-(void) setupGeneralView;
-(void) setupAppearanceView;
-(void) setupUtilitiesView;
-(void) setupInfoView;

-(unsigned) firstDifferentComponent: (NSArray *) a
                                and: (NSArray *) b;

-(NSString *) indent: (NSString *) s
                  by: (unsigned)   n;

-(void) setCurrentViewName: (NSString *) newName;

-(void) setSelectedWhenToConnectIndex: (NSUInteger) newValue;

-(void) setupPerConfigurationCheckbox: (NSButton *) checkbox
                                  key: (NSString *) key
                             inverted: (BOOL)       inverted
                            defaultTo: (BOOL)       defaultsTo;

-(void) setupLeftNavigationToDisplayName: (NSString *) displayNameToSelect;

-(void) setupSetNameserver:           (VPNConnection *) connection;
-(void) setupRouteAllTraffic:         (VPNConnection *) connection;
-(void) setupCheckIPAddress:          (VPNConnection *) connection;
-(void) setupResetPrimaryInterface:   (VPNConnection *) connection;
-(void) setupDisableIpv6OnTun:                    (VPNConnection *) connection;
-(void) setupPerConfigOpenvpnVersion: (VPNConnection *) connection;
-(void) setupNetworkMonitoring:       (VPNConnection *) connection;

-(void) setValueForCheckbox: (NSButton *) checkbox
              preferenceKey: (NSString *) preferenceKey
                   inverted: (BOOL)       inverted
                 defaultsTo: (BOOL)       defaultsTo;

-(void) updateConnectionStatusAndTime;

-(void) updateLastCheckedDate;

-(void) validateWhenToConnect: (VPNConnection *) connection;

@end

@implementation MyPrefsWindowController

TBSYNTHESIZE_OBJECT_GET(retain, NSMutableArray *, leftNavDisplayNames)

TBSYNTHESIZE_OBJECT(retain, NSString *, previouslySelectedNameOnLeftNavList, setPreviouslySelectedNameOnLeftNavList)

TBSYNTHESIZE_OBJECT_GET(retain, ConfigurationsView *, configurationsPrefsView)

TBSYNTHESIZE_OBJECT_GET(retain, SettingsSheetWindowController *, settingsSheetWindowController)

TBSYNTHESIZE_OBJECT_SET(NSString *, currentViewName, setCurrentViewName)

// Synthesize getters and direct setters:
TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedSetNameserverIndex,           setSelectedSetNameserverIndexDirect)
TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedPerConfigOpenvpnVersionIndex, setSelectedPerConfigOpenvpnVersionIndexDirect)

TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedKeyboardShortcutIndex,        setSelectedKeyboardShortcutIndexDirect)
TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedMaximumLogSizeIndex,          setSelectedMaximumLogSizeIndexDirect)

TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedAppearanceIconSetIndex,       setSelectedAppearanceIconSetIndexDirect)
TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedAppearanceConnectionWindowDisplayCriteriaIndex, setSelectedAppearanceConnectionWindowDisplayCriteriaIndexDirect)
TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedAppearanceConnectionWindowScreenIndex, setSelectedAppearanceConnectionWindowScreenIndexDirect)

TBSYNTHESIZE_NONOBJECT_GET(NSUInteger, selectedWhenToConnectIndex)
TBSYNTHESIZE_NONOBJECT_GET(NSUInteger, selectedLeftNavListIndex)

-(void) dealloc {
	
    [currentViewName                     release]; currentViewName                     = nil;
	[previouslySelectedNameOnLeftNavList release]; previouslySelectedNameOnLeftNavList = nil;
	[leftNavList                         release]; leftNavList = nil;
	[leftNavDisplayNames                 release]; leftNavDisplayNames = nil;
    [settingsSheetWindowController       release]; settingsSheetWindowController = nil;
	
    [super dealloc];
}

+ (NSString *)nibName
// Overrides DBPrefsWindowController method
{
	if (   runningOnSnowLeopardOrNewer()  // 10.5 and lower don't have setDelegate and setDataSource
		&& ( ! [gTbDefaults boolForKey: @"doNotShowOutlineViewOfConfigurations"] )  ) {
		return @"Preferences";
	} else {
		return @"Preferences-pre-10.6";
	}

}


-(void) setupToolbar
{
    [self addView: configurationsPrefsView  label: NSLocalizedString(@"Configurations", @"Window title") image: [NSImage imageNamed: @"Configurations"]];
    [self addView: appearancePrefsView      label: NSLocalizedString(@"Appearance",     @"Window title") image: [NSImage imageNamed: @"Appearance"    ]];
    [self addView: generalPrefsView         label: NSLocalizedString(@"Preferences",    @"Window title") image: [NSImage imageNamed: @"Preferences"   ]];
    [self addView: utilitiesPrefsView       label: NSLocalizedString(@"Utilities",      @"Window title") image: [NSImage imageNamed: @"Utilities"     ]];
    [self addView: infoPrefsView            label: NSLocalizedString(@"Info",           @"Window title") image: [NSImage imageNamed: @"Info"          ]];
    
    [self setupViews];
    
    [[self window] setDelegate: self];
}

static BOOL firstTimeShowingWindow = TRUE;

-(void) setupViews
{
    
    currentFrame = NSMakeRect(0.0, 0.0, 920.0, 390.0);
    
    currentViewName = NSLocalizedString(@"Configurations", @"Window title");
    
    [self setSelectedPerConfigOpenvpnVersionIndexDirect:                   tbNumberWithInteger(NSNotFound)];
    [self setSelectedKeyboardShortcutIndexDirect:                          tbNumberWithInteger(NSNotFound)];
    [self setSelectedMaximumLogSizeIndexDirect:                            tbNumberWithInteger(NSNotFound)];
    [self setSelectedAppearanceIconSetIndexDirect:                         tbNumberWithInteger(NSNotFound)];
    [self setSelectedAppearanceConnectionWindowDisplayCriteriaIndexDirect: tbNumberWithInteger(NSNotFound)];
    [self setSelectedAppearanceConnectionWindowScreenIndexDirect:          tbNumberWithInteger(NSNotFound)];
    
    [self setupConfigurationsView];
    [self setupGeneralView];
    [self setupAppearanceView];
    [self setupUtilitiesView];
    [self setupInfoView];
}


- (IBAction)showWindow:(id)sender 
{
    [super showWindow: sender];
    
    if (  firstTimeShowingWindow  ) {
        // Set the window's position from preferences (saved when window is closed)
        // But only if the preference's version matches the TB version (since window size could be different in different versions of TB)
        NSString * tbVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
        if (  [tbVersion isEqualToString: [gTbDefaults stringForKey:@"detailsWindowFrameVersion"]]    ) {
            NSString * mainFrameString  = [gTbDefaults stringForKey: @"detailsWindowFrame"];
            NSString * leftFrameString  = [gTbDefaults stringForKey: @"detailsWindowLeftFrame"];
            if (   mainFrameString != nil  ) {
                NSRect mainFrame = NSRectFromString(mainFrameString);
                [[self window] setFrame: mainFrame display: YES];  // display: YES so stretches properly
            }
            
            if (  leftFrameString != nil  ) {
                NSRect leftFrame = NSRectFromString(leftFrameString);
                if (  leftFrame.size.width < LEFT_NAV_AREA_MINIMUM_SIZE  ) {
                    leftFrame.size.width = LEFT_NAV_AREA_MINIMUM_SIZE;
                }
                [[configurationsPrefsView leftSplitView] setFrame: leftFrame];
            }
        } else {
			[[self window] center];
            [[self window] setReleasedWhenClosed: NO];
		}

        firstTimeShowingWindow = FALSE;
    }
}


-(void) windowWillClose:(NSNotification *)notification
{
	(void) notification;
	
    if (  [currentViewName isEqualToString: @"Info"]  ) {
        [infoPrefsView oldViewWillDisappear: infoPrefsView identifier: @"Info"];
    }
    
    [[self selectedConnection] stopMonitoringLogFiles];
    
    // Save the window's frame and the splitView's frame and the TB version in the preferences
    NSString * mainFrameString = NSStringFromRect([[self window] frame]);
    NSString * leftFrameString = nil;
    if (  [[configurationsPrefsView leftSplitView] frame].size.width > (LEFT_NAV_AREA_MINIMAL_SIZE + 5.0)  ) {
        leftFrameString = NSStringFromRect([[configurationsPrefsView leftSplitView] frame]);
    }
    NSString * tbVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
    BOOL saveIt = TRUE;
    if (  [tbVersion isEqualToString: [gTbDefaults stringForKey:@"detailsWindowFrameVersion"]]    ) {
        if (   [mainFrameString isEqualToString: [gTbDefaults stringForKey:@"detailsWindowFrame"]]
            && [leftFrameString isEqualToString: [gTbDefaults stringForKey:@"detailsWindowLeftFrame"]]  ) {
            saveIt = FALSE;
        }
    }
    
    if (saveIt) {
        [gTbDefaults setObject: mainFrameString forKey: @"detailsWindowFrame"];
        if (  leftFrameString ) {
            [gTbDefaults setObject: leftFrameString forKey: @"detailsWindowLeftFrame"];
        }
        [gTbDefaults setObject: [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"]
                        forKey: @"detailsWindowFrameVersion"];
    }
}


// oldViewWillDisappear and newViewWillAppear do two things:
//
//      1) They fiddle frames to ignore resizing except of Configurations
//      2) They notify infoPrefsView it is appearing/disappearing so it can start/stop its animation

// Overrides superclass
-(void) oldViewWillDisappear: (NSView *) view identifier: (NSString *) identifier
{
    if (  [view respondsToSelector: @selector(oldViewWillDisappear:identifier:)]  ) {
        [(id) view oldViewWillDisappear: view identifier: identifier];
    }
    
    [self setCurrentViewName: nil];
    
    // If switching FROM Configurations, save the frame for later and remove resizing indicator
    //                                   and stop monitoring the log
    if (   [identifier isEqualToString: @"Configurations"]  ) {
        currentFrame = [view frame];
		NSWindow * w = [view window];
        [w setShowsResizeIndicator: NO];
		windowContentMinSize = [w contentMinSize];	// Don't allow size changes except in 'Configurations' view
		windowContentMaxSize = [w contentMaxSize];	// But remember min & max for when we restore 'Configurations' view
		NSRect f = [w frame];
		NSSize s = [w contentRectForFrameRect: f].size;
        [w setContentMinSize: s];
		[w setContentMaxSize: s];
		
        [[self selectedConnection] stopMonitoringLogFiles];
    }
}


// Overrides superclass
-(void) newViewWillAppear: (NSView *) view identifier: (NSString *) identifier
{
    if (  [view respondsToSelector: @selector(newViewWillAppear:identifier:)]  ) {
        [(id) view newViewWillAppear: view identifier: identifier];
    }
    
    [self setCurrentViewName: identifier];
    
    // If switching TO Configurations, restore its last frame (even if user resized the window)
    //                                 and start monitoring the log
    // Otherwise, restore all other views' frames to the Configurations frame
    if (   [identifier isEqualToString: @"Configurations"]  ) {
        [view setFrame: currentFrame];
		NSWindow * w = [view window];
        [w setShowsResizeIndicator: YES];
		[w setContentMinSize: windowContentMinSize];
		[w setContentMaxSize: windowContentMaxSize];        
        [[self selectedConnection] startMonitoringLogFiles];
    } else {
        [appearancePrefsView setFrame: currentFrame];
        [generalPrefsView    setFrame: currentFrame];        
        [utilitiesPrefsView  setFrame: currentFrame];
        [infoPrefsView       setFrame: currentFrame];
    }
	
	if (  [identifier isEqualToString: @"Preferences"]) {
		// Update our preferences from Sparkle's whenever we show the view
		// (Would be better if Sparkle told us when they changed, but it doesn't)
		[((MenuController *)[NSApp delegate]) setOurPreferencesFromSparkles];
		[self setupGeneralView];
	}
}

// Overrides superclass
-(void) newViewDidAppear: (NSView *) view
{
    if        (   view == configurationsPrefsView  ) {
        [[self window] makeFirstResponder: [configurationsPrefsView leftNavTableView]];
    } else if (   view == generalPrefsView  ) {
        [[self window] makeFirstResponder: [generalPrefsView keyboardShortcutButton]];
    } else if (   view == appearancePrefsView  ) {
        [[self window] makeFirstResponder: [appearancePrefsView appearanceIconSetButton]];
    } else if (   view == utilitiesPrefsView  ) {
        [[self window] makeFirstResponder: [utilitiesPrefsView utilitiesHelpButton]];
    } else if (   view == infoPrefsView  ) {
        [[self window] makeFirstResponder: [infoPrefsView infoHelpButton]];
        NSString * deployedString = (  gDeployPath && [gFileMgr fileExistsAtPath: gDeployPath]
                                     ? NSLocalizedString(@" (Deployed)", @"Window title")
                                     : @"");
        NSString * version = [NSString stringWithFormat: @"%@%@", tunnelblickVersion([NSBundle mainBundle]), deployedString];
        [[infoPrefsView infoVersionTFC] setTitle: version];
    } else {
        NSLog(@"newViewDidAppear:identifier: invoked with unknown view");
    }
}

-(BOOL) tabView: (NSTabView *) inTabView shouldSelectTabViewItem: (NSTabViewItem *) tabViewItem
{
	(void) inTabView;
	(void) tabViewItem;
		
    if (  [self selectedConnection]  ) {
        return YES;
    }
    
    return NO;
}

-(void) tabView: (NSTabView *) inTabView didSelectTabViewItem: (NSTabViewItem *) tabViewItem
{
    if (  inTabView == [configurationsPrefsView configurationsTabView]  ) {
        if (  tabViewItem == [configurationsPrefsView logTabViewItem]  ) {
            [[self selectedConnection] startMonitoringLogFiles];
        } else {
            [[self selectedConnection] stopMonitoringLogFiles];
        }
    }
}

//***************************************************************************************************************


-(BOOL) oneConfigurationIsSelected {
	
	if (   runningOnSnowLeopardOrNewer()
		&& ( ! [gTbDefaults boolForKey: @"doNotShowOutlineViewOfConfigurations"] )  ) {
		LeftNavViewController   * ovc    = [configurationsPrefsView outlineViewController];
		NSOutlineView           * ov     = [ovc outlineView];
		NSIndexSet              * idxSet = [ov selectedRowIndexes];
		return [idxSet count] == 1;
	}
	
	return TRUE;
}

-(void) setupShowHideOnTbMenuMenuItem: (VPNConnection *) connection {
    
    if (connection  ) {
        NSString * key = [[connection displayName] stringByAppendingString: @"-doNotShowOnTunnelblickMenu"];
        if (  [gTbDefaults boolForKey: key]  ) {
            [[configurationsPrefsView showHideOnTbMenuMenuItem] setTitle: NSLocalizedString(@"Show Configuration on Tunnelblick Menu",        @"Menu Item")];
        } else {
            [[configurationsPrefsView showHideOnTbMenuMenuItem] setTitle: NSLocalizedString(@"Do Not Show Configuration on Tunnelblick Menu", @"Menu Item")];
        }
        [((MenuController *)[NSApp delegate]) changedDisplayConnectionSubmenusSettings];
    }
}

-(void) setupConfigurationsView
{
	
	BOOL savedDoingSetupOfUI = [((MenuController *)[NSApp delegate]) doingSetupOfUI];
	[((MenuController *)[NSApp delegate]) setDoingSetupOfUI: TRUE];

    [self setSelectedSetNameserverIndexDirect:           tbNumberWithInteger(NSNotFound)];   // Force a change when first set
    [self setSelectedPerConfigOpenvpnVersionIndexDirect: tbNumberWithInteger(NSNotFound)];
    selectedWhenToConnectIndex     = NSNotFound;

    selectedLeftNavListIndex = 0;
    
    [leftNavList                          release];
    leftNavList                         = nil;
    [leftNavDisplayNames                  release];
    leftNavDisplayNames                 = nil;
    [settingsSheetWindowController        release];
    settingsSheetWindowController       = nil;
    [previouslySelectedNameOnLeftNavList  release];
    previouslySelectedNameOnLeftNavList = [[gTbDefaults stringForKey: @"leftNavSelectedDisplayName"] retain];

    authorization = 0;
    
	[self setupLeftNavigationToDisplayName: previouslySelectedNameOnLeftNavList];
	
    // Right split view
    
    [[configurationsPrefsView configurationsTabView] setDelegate: self];
    
    VPNConnection * connection = [self selectedConnection];
    
    // Right split view - Settings tab

    if (  connection  ) {
    
        [self updateConnectionStatusAndTime];
        
        [self indicateNotWaitingForConnection: [self selectedConnection]];
        [self validateWhenToConnect: [self selectedConnection]];
        
        [self setupSetNameserver:           [self selectedConnection]];
        [self setupRouteAllTraffic:         [self selectedConnection]];
        [self setupCheckIPAddress:          [self selectedConnection]];
        [self setupResetPrimaryInterface:   [self selectedConnection]];
        [self setupDisableIpv6OnTun:                    [self selectedConnection]];
        [self setupNetworkMonitoring:       [self selectedConnection]];
        [self setupPerConfigOpenvpnVersion: [self selectedConnection]];
        
        // Set up a timer to update connection times
        [((MenuController *)[NSApp delegate]) startOrStopUiUpdater];
    }
    
    [self validateDetailsWindowControls];   // Set windows enabled/disabled
	
	[((MenuController *)[NSApp delegate]) setDoingSetupOfUI: savedDoingSetupOfUI];
}


-(BOOL) usingSetNameserver {
    NSString * name = [[self selectedConnection] displayName];
	if (  ! name  ) {
		return NO;
	}
	
    NSString * key = [name stringByAppendingString: @"useDNS"];
    unsigned ix = [gTbDefaults unsignedIntForKey: key
                                         default: 1
                                             min: 0
                                             max: MAX_SET_DNS_WINS_INDEX];
    return (ix == 1);
}

-(void) setupSetNameserver: (VPNConnection *) connection
{
    
    if (  ! connection  ) {
        return;
    }
    
    if (  ! configurationsPrefsView  ) {
        return;
    }
    
    // Set up setNameserverPopUpButton with localized content that varies with the connection
    NSArray * content = [connection modifyNameserverOptionList];
    [[configurationsPrefsView setNameserverArrayController] setContent: content];
    [[configurationsPrefsView setNameserverPopUpButton] sizeToFit];
	[configurationsPrefsView normalizeWidthOfPopDownButtons];
    
    // Select the appropriate Set nameserver entry
    NSString * key = [[connection displayName] stringByAppendingString: @"useDNS"];

    unsigned arrayCount = [[[configurationsPrefsView setNameserverArrayController] content] count];
    if (  (arrayCount - 1) > MAX_SET_DNS_WINS_INDEX) {
        NSLog(@"MAX_SET_DNS_WINS_INDEX = %u but there are %u entries in the array", (unsigned)MAX_SET_DNS_WINS_INDEX, arrayCount);
        [((MenuController *)[NSApp delegate]) terminateBecause: terminatingBecauseOfError];
    }
    
    NSInteger ix = [gTbDefaults unsignedIntForKey: key
                                default: 1
                                    min: 0
                                    max: MAX_SET_DNS_WINS_INDEX];
    
    
    [[configurationsPrefsView setNameserverPopUpButton] selectItemAtIndex: ix];
    [self setSelectedSetNameserverIndex: tbNumberWithInteger(ix)];
    [[configurationsPrefsView setNameserverPopUpButton] setEnabled: [gTbDefaults canChangeValueForKey: key]];
    [settingsSheetWindowController setupSettingsFromPreferences];
}

-(void) setupNetworkMonitoring: (VPNConnection *) connection
{
 	(void) connection;
	
   if (  [self forceDisableOfNetworkMonitoring]  ) {
        [[configurationsPrefsView monitorNetworkForChangesCheckbox] setState: NSOffState];
        [[configurationsPrefsView monitorNetworkForChangesCheckbox] setEnabled: NO];
    } else {
        [self setupPerConfigurationCheckbox: [configurationsPrefsView monitorNetworkForChangesCheckbox]
                                        key: @"-notMonitoringConnection"
                                   inverted: YES
                                  defaultTo: NO];
    }
}

-(void) setupRouteAllTraffic: (VPNConnection *) connection
{
    (void) connection;
    
    [self setupPerConfigurationCheckbox: [configurationsPrefsView routeAllTrafficThroughVpnCheckbox]
                                    key: @"-routeAllTrafficThroughVpn"
                               inverted: NO
                              defaultTo: NO];
}

-(void) setupCheckIPAddress: (VPNConnection *) connection
{
    (void) connection;
    
    if (  [gTbDefaults boolForKey: @"inhibitOutboundTunneblickTraffic"]  ) {
        [[configurationsPrefsView checkIPAddressAfterConnectOnAdvancedCheckbox] setState:   NSOffState];
        [[configurationsPrefsView checkIPAddressAfterConnectOnAdvancedCheckbox] setEnabled: NO];
    } else {
        [self setupPerConfigurationCheckbox: [configurationsPrefsView checkIPAddressAfterConnectOnAdvancedCheckbox]
                                        key: @"-notOKToCheckThatIPAddressDidNotChangeAfterConnection"
                                   inverted: YES
                                  defaultTo: NO];
    }
}

-(void) setupResetPrimaryInterface: (VPNConnection *) connection
{
    (void) connection;
    
    if (  [self usingSetNameserver]  ) {
        [self setupPerConfigurationCheckbox: [configurationsPrefsView resetPrimaryInterfaceAfterDisconnectCheckbox]
                                        key: @"-resetPrimaryInterfaceAfterDisconnect"
                                   inverted: NO
                                  defaultTo: NO];
    } else {
        [[configurationsPrefsView resetPrimaryInterfaceAfterDisconnectCheckbox] setState:   NSOffState];
        [[configurationsPrefsView resetPrimaryInterfaceAfterDisconnectCheckbox] setEnabled: NO];
    }
}

-(void) setupDisableIpv6OnTun: (VPNConnection *) connection
{
    (void) connection;
    
	NSString * type = [connection tapOrTun];
    if (   ( ! [type isEqualToString: @"tap"] )
		&& [self usingSetNameserver]  ) {
        [self setupPerConfigurationCheckbox: [configurationsPrefsView disableIpv6OnTunCheckbox]
                                        key: @"-doNotDisableIpv6onTun"
                                   inverted: YES
                                  defaultTo: NO];
		
	} else {
		[[configurationsPrefsView disableIpv6OnTunCheckbox] setState:   NSOffState];
		[[configurationsPrefsView disableIpv6OnTunCheckbox] setEnabled: NO];
	}
}

-(void) setupPerConfigOpenvpnVersion: (VPNConnection *) connection
{
    
	if (  ! connection  ) {
        return;
    }
    
    NSArrayController * ac = [configurationsPrefsView perConfigOpenvpnVersionArrayController];
    NSArray * list = [ac content];
    
    if (  [list count] < 3  ) {
        return; // Have not set up the list yet
    }
    
    NSUInteger versionIx    = [connection getOpenVPNVersionIxToUseAdjustForScramble: NO];
    
    NSString * key = [[connection displayName] stringByAppendingString: @"-openvpnVersion"];
    NSString * prefVersion = [gTbDefaults stringForKey: key];
    NSUInteger listIx = 0;                              // Default to the first entry -- "Default (x.y.z)"

    if (  [prefVersion length] == 0  ) {
        // Use default; if actually using it, show we are using default (1st entry), otherwise show what we are using
        if (  versionIx == 0  ) {
            listIx = 0;
        } else {
            listIx = versionIx + 1; // + 1 to skip over the 1st entry (default)
        }
    } else if (  [prefVersion isEqualToString: @"-"]  ) {
        // Use latest. If we are actually using it, show we are using latest (last entry), otherwise show what we are using
        NSArray  * versionNames = [((MenuController *)[NSApp delegate]) openvpnVersionNames];
        if (  versionIx == [versionNames count] - 1  ) {
            listIx = versionIx + 2; // + 2 to skip over the 1st entry (default) and the specific entry, to get to "Latest (version)"
        } else {
            listIx = versionIx + 1; // + 1 to skip over the 1st entry (default)
        }
    } else {
        // Using a specific version, but show what we are actually using instead
        listIx = versionIx + 1; // + 1 to skip over the 1st entry (default)
    }
    
    [self setSelectedPerConfigOpenvpnVersionIndex: tbNumberWithInteger(listIx)];
    
    [[configurationsPrefsView perConfigOpenvpnVersionButton] setEnabled: [gTbDefaults canChangeValueForKey: key]];
}

-(void) setupLeftNavigationToDisplayName: (NSString *) displayNameToSelect
{
    NSUInteger leftNavIndexToSelect = NSNotFound;
    
    NSMutableArray * currentFolders = [NSMutableArray array]; // Components of folder enclosing most-recent leftNavList/leftNavDisplayNames entry
    NSArray * allConfigsSorted = [[[((MenuController *)[NSApp delegate]) myVPNConnectionDictionary] allKeys] sortedArrayUsingSelector: @selector(caseInsensitiveNumericCompare:)];
    
    // If the configuration we want to select is gone, don't try to select it
    if (  displayNameToSelect  ) {
        if (  ! [allConfigsSorted containsObject: displayNameToSelect]  ) {
            displayNameToSelect = nil;
        }
	}
	
    // If no display name to select and there are any names, select the first one
	if (  ! displayNameToSelect  ) {
        if (  [allConfigsSorted count] > 0  ) {
            displayNameToSelect = [allConfigsSorted objectAtIndex: 0];
        }
    }
	
	[leftNavList         release];
	[leftNavDisplayNames release];
	leftNavList         = [[NSMutableArray alloc] initWithCapacity: [[((MenuController *)[NSApp delegate]) myVPNConnectionDictionary] count]];
	leftNavDisplayNames = [[NSMutableArray alloc] initWithCapacity: [[((MenuController *)[NSApp delegate]) myVPNConnectionDictionary] count]];
	int currentLeftNavIndex = 0;
	
	NSEnumerator* configEnum = [allConfigsSorted objectEnumerator];
    NSString * dispNm;
    while (  (dispNm = [configEnum nextObject])  ) {
        VPNConnection * connection = [[((MenuController *)[NSApp delegate]) myVPNConnectionDictionary] objectForKey: dispNm];
		NSArray * currentConfig = [dispNm componentsSeparatedByString: @"/"];
		unsigned firstDiff = [self firstDifferentComponent: currentConfig and: currentFolders];
		
		// Track any necessary "outdenting"
		if (  firstDiff < [currentFolders count]  ) {
			// Remove components from the end of currentFolders until we have a match
			unsigned i;
			for (  i=0; i < ([currentFolders count]-firstDiff); i++  ) {
				[currentFolders removeLastObject];
			}
		}
		
		// currentFolders and currentConfig now match, up to but not including the firstDiff-th entry
		
		// Add a "folder" line for each folder in currentConfig starting with the first-Diff-th entry (if any)
		unsigned i;
		for (  i=firstDiff; i < [currentConfig count]-1; i++  ) {
			[leftNavDisplayNames addObject: @""];
			NSString * folderName = [currentConfig objectAtIndex: i];
			[leftNavList         addObject: [self indent: folderName by: i]];
			[currentFolders addObject: folderName];
			++currentLeftNavIndex;
		}
		
		// Add a "configuration" line
		[leftNavDisplayNames addObject: [connection displayName]];
		[leftNavList         addObject: [self indent: [currentConfig lastObject] by: [currentConfig count]-1u]];
		
		if (  displayNameToSelect  ) {
			if (  [displayNameToSelect isEqualToString: [connection displayName]]  ) {
				leftNavIndexToSelect = currentLeftNavIndex;
			}
		} else if (   ( leftNavIndexToSelect == NSNotFound )
				   && ( ! [connection isDisconnected] )  ) {
			leftNavIndexToSelect = currentLeftNavIndex;
		}
		++currentLeftNavIndex;
	}
	
	[[configurationsPrefsView leftNavTableView] reloadData];
	
	if (   runningOnSnowLeopardOrNewer()  // 10.5 and lower don't have setDelegate and setDataSource
		&& ( ! [gTbDefaults boolForKey: @"doNotShowOutlineViewOfConfigurations"] )  ) {
		
		LeftNavViewController * oVC = [[self configurationsPrefsView] outlineViewController];
        NSOutlineView         * oView = [oVC outlineView];
        LeftNavDataSource     * oDS = [[self configurationsPrefsView] leftNavDataSrc];
        [oDS reload];
		[oView reloadData];
		
		// Expand items that were left expanded previously and get row # we should select (that matches displayNameToSelect)
		
		NSInteger ix = 0;	// Track row # of name we are to display

		NSArray * expandedDisplayNames = [gTbDefaults arrayForKey: @"leftNavOutlineViewExpandedDisplayNames"];
        LeftNavViewController * outlineViewController = [configurationsPrefsView outlineViewController];
        NSOutlineView * outlineView = [outlineViewController outlineView];
        [outlineView expandItem: [outlineView itemAtRow: 0]];
        NSInteger r;
        id item;
        for (  r=0; r<[outlineView numberOfRows]; r++) {
            item = [outlineView itemAtRow: r];
            NSString * itemDisplayName = [item displayName];
            if (  [itemDisplayName hasSuffix: @"/"]  ) {
                if (   [expandedDisplayNames containsObject: itemDisplayName]
                    || [displayNameToSelect hasPrefix: itemDisplayName]  ) {
                    [outlineView expandItem: item];
                }
            }
            if (  [displayNameToSelect isEqualToString: itemDisplayName]  ) {
                ix = r;
            }
        }
		
		if (  displayNameToSelect  ) {
			[oView selectRowIndexes: [NSIndexSet indexSetWithIndex: ix] byExtendingSelection: NO];
            [[[configurationsPrefsView outlineViewController] outlineView] scrollRowToVisible: ix];
		}
	}
	
    // If there are any entries in the list
    // Select the entry that was selected previously, or the first that was not disconnected, or the first
    if (  currentLeftNavIndex > 0  ) {
        if (  leftNavIndexToSelect == NSNotFound  ) {
            if (  [leftNavList count]  ) {
                leftNavIndexToSelect = 0;
            }
        }
        if (  leftNavIndexToSelect != NSNotFound  ) {
            selectedLeftNavListIndex = NSNotFound;  // Force a change
            [self setSelectedLeftNavListIndex: (unsigned)leftNavIndexToSelect];
            [[configurationsPrefsView leftNavTableView] scrollRowToVisible: leftNavIndexToSelect];
        }
    } else {
        [self setupSetNameserver:            nil];
        [self setupRouteAllTraffic:          nil];
        [self setupCheckIPAddress:           nil];
        [self setupResetPrimaryInterface:    nil];
        [self setupDisableIpv6OnTun:                     nil];
        [self setupNetworkMonitoring:        nil];
		[self setupPerConfigOpenvpnVersion:  nil];
        [self validateDetailsWindowControls];
        [settingsSheetWindowController setConfigurationName: nil];
        
    }
}

// Call this when a configuration was added or deleted
-(void) update
{
    [self setupLeftNavigationToDisplayName: previouslySelectedNameOnLeftNavList];
    
    VPNConnection * connection = [self selectedConnection];
    if (  connection  ) {
        NSString * newDisplayName = [connection displayName];
        [settingsSheetWindowController setConfigurationName: newDisplayName];
    } else {
        [[settingsSheetWindowController window] close];
    }
}


-(void) updateConnectionStatusAndTime
{
	if (  [super windowHasLoaded]  ) {
		[[self window] setTitle: [self windowTitle: NSLocalizedString(@"Configurations", @"Window title")]];
	}
}

-(void) indicateWaitingForConnection: (VPNConnection *) theConnection
{
    if (  theConnection == [self selectedConnection]  ) {
        [[configurationsPrefsView progressIndicator] startAnimation: self];
        [[configurationsPrefsView progressIndicator] setHidden: NO];
    }
}


-(void) indicateNotWaitingForConnection: (VPNConnection *) theConnection
{
    if (  theConnection == [self selectedConnection]  ) {
        [[configurationsPrefsView progressIndicator] stopAnimation: self];
        [[configurationsPrefsView progressIndicator] setHidden: YES];
    }
}

// Set a checkbox from preferences
-(void) setupPerConfigurationCheckbox: (NSButton *) checkbox
                                  key: (NSString *) key
                             inverted: (BOOL)       inverted
                            defaultTo: (BOOL)       defaultsTo
{
    if (  checkbox  ) {
        VPNConnection * connection = [self selectedConnection];
        if (  connection  ) {
            NSString * actualKey = [[connection displayName] stringByAppendingString: key];
            BOOL state = (  defaultsTo
						  ? [gTbDefaults boolWithDefaultYesForKey: actualKey]
						  : [gTbDefaults boolForKey: actualKey]);
            if (  inverted  ) {
                state = ! state;
            }
            if (  state  ) {
                [checkbox setState: NSOnState];
            } else {
                [checkbox setState: NSOffState];
            }
            
            BOOL enable = [gTbDefaults canChangeValueForKey: actualKey];
            [checkbox setEnabled: enable];
        }
    }
}


-(void) validateDetailsWindowControls
{
    VPNConnection * connection = [self selectedConnection];
    
	[self updateConnectionStatusAndTime];
	
    if (  connection  ) {
        
        [self validateConnectAndDisconnectButtonsForConnection: connection];
        
        // Left split view
        
		[[configurationsPrefsView addConfigurationButton]    setEnabled: [self oneConfigurationIsSelected]];
        [[configurationsPrefsView removeConfigurationButton] setEnabled: [self oneConfigurationIsSelected]];

		
		[self setupShowHideOnTbMenuMenuItem: connection];
		
        [[configurationsPrefsView workOnConfigurationPopUpButton] setEnabled: ([self oneConfigurationIsSelected]
																				&& (! [gTbDefaults boolForKey: @"disableWorkOnConfigurationButton"]))];
		[[configurationsPrefsView workOnConfigurationPopUpButton] setAutoenablesItems: YES];
        
        NSString * configurationPath = [connection configPath];
        if (  [configurationPath hasPrefix: [L_AS_T_SHARED stringByAppendingString: @"/"]]  ) {
            [[configurationsPrefsView makePrivateOrSharedMenuItem] setTitle: NSLocalizedString(@"Make Configuration Private..."  , @"Menu Item")];
        } else if (  [configurationPath hasPrefix: [gPrivatePath stringByAppendingString: @"/"]]  ) {
            [[configurationsPrefsView makePrivateOrSharedMenuItem] setTitle: NSLocalizedString(@"Make Configuration Shared..."  , @"Menu Item")];
        } else {
            [[configurationsPrefsView makePrivateOrSharedMenuItem] setTitle: NSLocalizedString(@"Make Configuration Shared..."  , @"Menu Item")];
        }
        
        if (  [[ConfigurationManager manager] userCanEditConfiguration: [connection configPath]]  ) {
            [[configurationsPrefsView editOpenVPNConfigurationFileMenuItem] setTitle: NSLocalizedString(@"Edit OpenVPN Configuration File...", @"Menu Item")];
        } else {
            [[configurationsPrefsView editOpenVPNConfigurationFileMenuItem] setTitle: NSLocalizedString(@"Examine OpenVPN Configuration File...", @"Menu Item")];
        }
		
        
        // right split view
        
        // Right split view - log tab
        
        [[configurationsPrefsView logToClipboardButton]             setEnabled: ([self oneConfigurationIsSelected]
																				 && (! [gTbDefaults boolForKey: @"disableCopyLogToClipboardButton"]))];
        
        
        // Right split view - settings tab
        
        [[configurationsPrefsView advancedButton]                   setEnabled: YES];
        
        [self validateWhenToConnect: [self selectedConnection]];
        
    } else {
        
        // There is not a connection selected. Don't let the user do anything except add a connection.

		[[configurationsPrefsView addConfigurationButton]           setEnabled: YES];
        [[configurationsPrefsView removeConfigurationButton]        setEnabled: NO];
        [[configurationsPrefsView workOnConfigurationPopUpButton]   setEnabled: NO];
        
        // The "Log" and "Settings" items can't be selected because tabView:shouldSelectTabViewItem: will return NO if there is no selected connection
        
        [[configurationsPrefsView progressIndicator]                setHidden: YES];
        [[configurationsPrefsView logToClipboardButton]             setEnabled: NO];
        
        [[configurationsPrefsView connectButton]                    setEnabled: NO];
        [[configurationsPrefsView disconnectButton]                 setEnabled: NO];
        
        [[configurationsPrefsView whenToConnectPopUpButton]         setEnabled: NO];
        
        [[configurationsPrefsView setNameserverPopUpButton]         setEnabled: NO];
        
        [[configurationsPrefsView monitorNetworkForChangesCheckbox]             setEnabled: NO];
        [[configurationsPrefsView routeAllTrafficThroughVpnCheckbox]            setEnabled: NO];
        [[configurationsPrefsView checkIPAddressAfterConnectOnAdvancedCheckbox] setEnabled: NO];
        [[configurationsPrefsView resetPrimaryInterfaceAfterDisconnectCheckbox] setEnabled: NO];
        [[configurationsPrefsView disableIpv6OnTunCheckbox]                     setEnabled: NO];
        
        [[configurationsPrefsView perConfigOpenvpnVersionButton]    setEnabled: NO];
        
        [[configurationsPrefsView advancedButton]                   setEnabled: NO];

    }
}

- (BOOL)validateMenuItem:(NSMenuItem *) anItem
{
	VPNConnection * connection = [self selectedConnection];
	
	if (  [anItem action] == @selector(addConfigurationButtonWasClicked:)  ) {
		return ! [gTbDefaults boolForKey: @"disableAddConfigurationButton"];
		
	} else if (  [anItem action] == @selector(removeConfigurationButtonWasClicked:)  ) {
		return [gTbDefaults boolForKey: @"disableRemoveConfigurationButton"];
		
	} else if (  [anItem action] == @selector(renameConfigurationMenuItemWasClicked:)  ) {
		return ! [gTbDefaults boolForKey: @"disableRenameConfigurationMenuItem"];
		
	} else if (  [anItem action] == @selector(duplicateConfigurationMenuItemWasClicked:)  ) {
		return ! [gTbDefaults boolForKey: @"disableDuplicateConfigurationMenuItem"];
		
	} else if (  [anItem action] == @selector(revertToShadowMenuItemWasClicked:)  ) {
		return (   ( ! [gTbDefaults boolForKey: @"disableRevertToShadowMenuItem"] )
				&& (   [[connection configPath] hasPrefix: [gPrivatePath stringByAppendingString: @"/"]])
				&& ( ! [connection shadowIsIdenticalMakeItSo: NO] )
				);
		
	} else if (  [anItem action] == @selector(showHideOnTbMenuMenuItemWasClicked:)  ) {
		return ! [gTbDefaults boolForKey: @"disableShowHideOnTbMenuItem"];
		
	} else if (  [anItem action] == @selector(makePrivateOrSharedMenuItemWasClicked:)  ) {
		NSString * configurationPath = [connection configPath];
		if (  [configurationPath hasPrefix: [L_AS_T_SHARED stringByAppendingString: @"/"]]  ) {
			[[configurationsPrefsView makePrivateOrSharedMenuItem] setTitle: NSLocalizedString(@"Make Configuration Private..."  , @"Menu Item")];
			return ! [gTbDefaults boolForKey: @"disableMakeConfigurationPrivateOrSharedMenuItem"];
		} else if (  [configurationPath hasPrefix: [gPrivatePath stringByAppendingString: @"/"]]  ) {
			[[configurationsPrefsView makePrivateOrSharedMenuItem] setTitle: NSLocalizedString(@"Make Configuration Shared..."  , @"Menu Item")];
			return ! [gTbDefaults boolForKey: @"disableMakeConfigurationPrivateOrSharedMenuItem"];
		} else {
			[[configurationsPrefsView makePrivateOrSharedMenuItem] setTitle: NSLocalizedString(@"Make Configuration Shared..."  , @"Menu Item")];
			return NO;
		}
		
	} else if (  [anItem action] == @selector(editOpenVPNConfigurationFileMenuItemWasClicked:)  ) {
		return ! [gTbDefaults boolForKey: @"disableExamineOpenVpnConfigurationFileMenuItem"];
		
	} else if (  [anItem action] == @selector(showOpenvpnLogMenuItemWasClicked:)  ) {
		return (   ( ! [gTbDefaults boolForKey: @"disableShowOpenVpnLogInFinderMenuItem"] )
				&& [[connection configPath] hasPrefix: [gPrivatePath stringByAppendingString: @"/"]]
				);
		
	} else if (  [anItem action] == @selector(removeCredentialsMenuItemWasClicked:)  ) {
		return  ! [gTbDefaults boolForKey: @"disableDeleteConfigurationCredentialsInKeychainMenuItem"];
	
	} else if (  [anItem action] == @selector(whenToConnectManuallyMenuItemWasClicked:)  ) {
		return TRUE;
	
	} else if (  [anItem action] == @selector(whenToConnectTunnelBlickLaunchMenuItemWasClicked:)  ) {
		return TRUE;
	
	} else if (  [anItem action] == @selector(whenToConnectOnComputerStartMenuItemWasClicked:)  ) {
		return [[self selectedConnection] mayConnectWhenComputerStarts];
	}

	NSLog(@"MyPrefsWindowController:validateMenuItem: Unknown menuItem %@", [anItem description]);
	return NO;
}


// Overrides superclass method
// If showing the Configurations tab, window title is:
//      configname (Shared/Private/Deployed): Status (hh:mm:ss) - Tunnelblick
// Otherwise, window title is:
//      tabname - Tunnelblick
-(NSString *) windowTitle: (NSString *) currentItemLabel
{
	(void) currentItemLabel;
	
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    NSString *appName = [[NSFileManager defaultManager] displayNameAtPath: bundlePath];
    if (  [appName hasSuffix: @".app"]  ) {
        appName = [appName substringToIndex: [appName length] - 4];
    }
    
    NSString * windowLabel = [NSString stringWithFormat: @"%@ - Tunnelblick", localizeNonLiteral(currentViewName, @"Window title")];

    if (  [currentViewName isEqualToString: NSLocalizedString(@"Configurations", @"Window title")]  ) {
        VPNConnection * connection = [self selectedConnection];
        if (  connection  ) {
            NSString * status = localizeNonLiteral([connection state], @"Connection status");
            NSString * connectionTimeString = @"";
            if (   [connection isConnected]
                && [gTbDefaults boolWithDefaultYesForKey: @"showConnectedDurations"]  ) {
				connectionTimeString = [connection connectTimeString];
            }
            windowLabel = [NSString stringWithFormat: @"%@%@: %@%@ - %@", [connection localizedName], [connection displayLocation], status, connectionTimeString, appName];
        }
    }
    
    return windowLabel;
}


-(void) hookedUpOrStartedConnection: (VPNConnection *) theConnection
{
    if (   theConnection
        && ( theConnection == [self selectedConnection] )  ) {
        [theConnection startMonitoringLogFiles];
    }
}


-(void) validateWhenConnectingForConnection: (VPNConnection *) theConnection
{
    if (  theConnection  ) {
        [self validateWhenToConnect: theConnection];
    }
}


-(void) validateConnectAndDisconnectButtonsForConnection: (VPNConnection *) theConnection
{
    if (   ( ! theConnection)
		|| ( ! [self oneConfigurationIsSelected])  )  {
        [[configurationsPrefsView connectButton]    setEnabled: NO];
        [[configurationsPrefsView disconnectButton] setEnabled: NO];
        return;
    }
    
    if ( theConnection != [self selectedConnection]  ) {
        return;
    }
    
    NSString * displayName = [theConnection displayName];
    NSString * disableConnectButtonKey    = [displayName stringByAppendingString: @"-disableConnectButton"];
    NSString * disableDisconnectButtonKey = [displayName stringByAppendingString: @"-disableDisconnectButton"];
    BOOL disconnected = [theConnection isDisconnected];
    [[configurationsPrefsView connectButton]    setEnabled: (   disconnected
                                   && ( ! [gTbDefaults boolForKey: disableConnectButtonKey] )  )];
    [[configurationsPrefsView disconnectButton] setEnabled: (   ( ! disconnected )
                                   && ( ! [gTbDefaults boolForKey: disableDisconnectButtonKey] )  )];
}

-(unsigned) firstDifferentComponent: (NSArray *) a and: (NSArray *) b
{
    unsigned retVal = 0;
    unsigned i;
    for (i=0;
         (i < [a count]) 
         && (i < [b count])
         && [[a objectAtIndex: i] isEqual: [b objectAtIndex: i]];
         i++  ) {
        ++retVal;
    }
    
    return retVal;
}


-(NSString *) indent: (NSString *) s by: (unsigned) n
{
    NSString * retVal = [NSString stringWithFormat:@"%*s%@", 3*n, "", s];
    return retVal;
}


-(BOOL) forceDisableOfNetworkMonitoring
{
    NSArray * content = [[configurationsPrefsView setNameserverArrayController] content];
    NSUInteger ix = tbUnsignedIntegerValue(selectedSetNameserverIndex);
    if (   ([content count] < 4)
        || (ix > 2)
        || (ix == 0)  ) {
        return TRUE;
    } else {
        return FALSE;
    }
}

-(int)numberOfRowsInTableView:(NSTableView *)aTableView
{
    if (  aTableView == [configurationsPrefsView leftNavTableView]  ) {
        unsigned n = [leftNavList count];
        return (int)n;
    }
    
    return 0;
}

-(id) tableView:(NSTableView *) aTableView objectValueForTableColumn:(NSTableColumn *) aTableColumn row: (int) rowIndex
{
    (void) aTableColumn;
    
    if (  aTableView == [configurationsPrefsView leftNavTableView]  ) {
        NSString * s = [leftNavList objectAtIndex: (unsigned)rowIndex];
        return s;
    }
    
    return nil;
}

- (VPNConnection*) selectedConnection
// Returns the connection associated with the currently selected connection or nil on error.
{
    if (  selectedLeftNavListIndex != NSNotFound  ) {
        if (  selectedLeftNavListIndex < [leftNavDisplayNames count]  ) {
            NSString * dispNm = [leftNavDisplayNames objectAtIndex: selectedLeftNavListIndex];
            if (  dispNm != nil) {
                VPNConnection* connection = [[((MenuController *)[NSApp delegate]) myVPNConnectionDictionary] objectForKey: dispNm];
                if (  connection  ) {
                    return connection;
                }
                NSArray *allConnections = [[((MenuController *)[NSApp delegate]) myVPNConnectionDictionary] allValues];
                if (  [allConnections count]  ) {
                    return [allConnections objectAtIndex:0];
                }
                else return nil;
            }
        }
    }
    
    return nil;
}

// User Interface

// Window

-(IBAction) connectButtonWasClicked: (id) sender
{
    VPNConnection * connection = [self selectedConnection];
    if (  connection  ) {
        [connection addToLog: @"*Tunnelblick: Disconnecting; VPN Details… window connect button pressed"];
        [connection connect: sender userKnows: YES];
    } else {
        NSLog(@"connectButtonWasClicked but no configuration selected");
    }
}


-(IBAction) disconnectButtonWasClicked: (id) sender
{
	(void) sender;
	
    VPNConnection * connection = [self selectedConnection];
    if (  connection  ) {
        [connection addToLog: @"*Tunnelblick: Disconnecting; VPN Details… window disconnect button pressed"];
		NSString * oldRequestedState = [connection requestedState];
        [connection startDisconnectingUserKnows: [NSNumber numberWithBool: YES]];
        if (  [oldRequestedState isEqualToString: @"EXITING"]  ) {
			[connection displaySlowDisconnectionDialogLater];
        }
    } else {
        NSLog(@"disconnectButtonWasClicked but no configuration selected");
    }
}


-(IBAction) configurationsHelpButtonWasClicked: (id) sender
{
	(void) sender;
	
    MyGotoHelpPage(@"vpn-details.html", nil);
}


// Left side -- navigation and configuration manipulation

-(IBAction) addConfigurationButtonWasClicked: (id) sender
{
	(void) sender;
	
    [[ConfigurationManager manager] addConfigurationGuide];
}


-(IBAction) removeConfigurationButtonWasClicked: (id) sender
{
	(void) sender;
	
    VPNConnection * connection = [self selectedConnection];
    
    if (  ! connection  ) {
        NSLog(@"removeConfigurationButtonWasClicked but no configuration selected");
        return;
    }
    
    NSString * displayName = [connection displayName];
    NSString * autoConnectKey = [displayName stringByAppendingString: @"autoConnect"];
    NSString * onSystemStartKey = [displayName stringByAppendingString: @"-onSystemStart"];
    if (   [gTbDefaults boolForKey: autoConnectKey]
        && [gTbDefaults boolForKey: onSystemStartKey]  ) {
        TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                          NSLocalizedString(@"You may not delete a configuration which is set to start when the computer starts.", @"Window text"));
        return;
    }
    
    if (  ! [connection isDisconnected]  ) {
        TBShowAlertWindow(NSLocalizedString(@"Active connection", @"Window title"),
                          NSLocalizedString(@"You may not delete a configuration unless it is disconnected.", @"Window text"));
        return;
    }
    
    NSString * configurationPath = [connection configPath];
    
    if (  [configurationPath hasPrefix: [gDeployPath stringByAppendingString: @"/"]]  ) {
        TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                          NSLocalizedString(@"You may not delete a Deployed configuration.", @"Window text"));
        return;
    }
    
	NSString * group = credentialsGroupFromDisplayName(displayName);

	BOOL removeCredentials = TRUE;
	NSString * credentialsNote = @"";
	if (  group  ) {
		if (  1 != [gTbDefaults numberOfConfigsInCredentialsGroup: group]  ) {
			credentialsNote = NSLocalizedString(@"\n\nNote: The configuration's group credentials will not be deleted because other configurations use them.", @"Window text");
			removeCredentials = FALSE;
		}
	}
	
    NSString * notDeletingOtherFilesMsg;
    NSString * ext = [configurationPath pathExtension];
    if (  [ext isEqualToString: @"tblk"]  ) {
        notDeletingOtherFilesMsg = @"";
    } else {
        notDeletingOtherFilesMsg = NSLocalizedString(@"\n\n Note: Files associated with the configuration, such as key or certificate files, will not be deleted.", @"Window text");
    }
    
    BOOL localAuthorization = FALSE;
    if (  authorization == nil  ) {
        // Get an AuthorizationRef and use executeAuthorized to run the installer to delete the file
        NSString * msg = [NSString stringWithFormat: 
                          NSLocalizedString(@" Configurations may be deleted only by a computer administrator.\n\n Deletion is immediate and permanent. All settings for '%@' will also be deleted permanently.%@%@", @"Window text"),
                          displayName,
						  credentialsNote,
                          notDeletingOtherFilesMsg];
        authorization = [NSApplication getAuthorizationRef: msg];
        if (  authorization == nil) {
            return;
        }
        localAuthorization = TRUE;
    } else {
        int button = TBRunAlertPanel(NSLocalizedString(@"Please Confirm", @"Window title"),
                                     [NSString stringWithFormat:
                                      NSLocalizedString(@"Deleting a configuration is permanent and cannot be undone.\n\nAll settings for the configuration will also be deleted permanently.\n\n%@%@\n\nAre you sure you wish to delete configuration '%@'?", @"Window text"),
                                      credentialsNote,
									  notDeletingOtherFilesMsg,
                                      displayName],
                                     NSLocalizedString(@"Cancel", @"Button"),    // Default button
                                     NSLocalizedString(@"Delete", @"Button"),    // Alternate button
                                     nil);
        if (  button != NSAlertAlternateReturn) {
            if (  localAuthorization  ) {
                AuthorizationFree(authorization, kAuthorizationFlagDefaults);
                authorization = nil;
            }
            return;
        }
    }
    
    if (  [[ConfigurationManager manager] deleteConfigPath: configurationPath
                                           usingAuthRefPtr: &authorization
                                                warnDialog: YES]  ) {
        //Remove credentials
		if (  removeCredentials  ) {
			AuthAgent * myAuthAgent = [[[AuthAgent alloc] initWithConfigName: group credentialsGroup: group] autorelease];
			
			[myAuthAgent setAuthMode: @"privateKey"];
			if (  [myAuthAgent keychainHasAnyCredentials]  ) {
				[myAuthAgent deleteCredentialsFromKeychainIncludingUsername: YES];
			}
			[myAuthAgent setAuthMode: @"password"];
			if (  [myAuthAgent keychainHasAnyCredentials]  ) {
				[myAuthAgent deleteCredentialsFromKeychainIncludingUsername: YES];
			}
		}
		
        [gTbDefaults removePreferencesFor: displayName];
    }
    
    if (  localAuthorization  ) {
        AuthorizationFree(authorization, kAuthorizationFlagDefaults);
        authorization = nil;
    }
}


-(IBAction) renameConfigurationMenuItemWasClicked: (id) sender
{
	(void) sender;
	
    VPNConnection * connection = [self selectedConnection];
    if (  ! connection  ) {
        NSLog(@"renameConfigurationMenuItemWasClicked but no configuration has been selected");
        return;
    }
    
    NSString * sourceDisplayName = [connection displayName];
    NSString * sourcePath = [connection configPath];
    
    // Get the new name
    NSString * prompt = [NSString stringWithFormat: NSLocalizedString(@"Please enter a new name for '%@'.", @"Window text"), [sourceDisplayName lastPathComponent]];
    NSString * newName = TBGetDisplayName(prompt, sourcePath);
    
    if (  ! newName  ) {
        return;             // User cancelled
    }
    
    NSString * sourceFolder = [sourcePath stringByDeletingLastPathComponent];
    NSString * targetPath = [sourceFolder stringByAppendingPathComponent: newName];
    NSString * newExtension = [newName pathExtension];
    if (  ! [newExtension isEqualToString: @"tblk"]  ) {
        targetPath = [targetPath stringByAppendingPathExtension: @"tblk"];
    }
    
    [ConfigurationManager renameConfigurationFromPath: sourcePath
                                               toPath: targetPath
                                     authorizationPtr: &authorization];
}

-(IBAction) duplicateConfigurationMenuItemWasClicked: (id) sender
{
	(void) sender;
	
    VPNConnection * connection = [self selectedConnection];
    if (  ! connection  ) {
        NSLog(@"duplicateConfigurationMenuItemWasClicked but no configuration has been selected");
        return;
    }
    
    NSString * displayName = [connection displayName];
    NSString * autoConnectKey = [displayName stringByAppendingString: @"autoConnect"];
    NSString * onSystemStartKey = [displayName stringByAppendingString: @"-onSystemStart"];
    if (   [gTbDefaults boolForKey: autoConnectKey]
        && [gTbDefaults boolForKey: onSystemStartKey]  ) {
        TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                          NSLocalizedString(@"You may not duplicate a configuration which is set to start when the computer starts.", @"Window text"));
        return;
    }
    
    NSString * source = [connection configPath];
    if (  [source hasPrefix: [gDeployPath stringByAppendingString: @"/"]]  ) {
        TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                          NSLocalizedString(@"You may not duplicate a Deployed configuration.", @"Window text"));
        return;
    }
    
    // Get a target path like the finder: "xxx copy.ext", "xxx copy 2.ext", "xxx copy 3.ext", etc.
    NSString * sourceFolder = [source stringByDeletingLastPathComponent];
    NSString * sourceLast = [source lastPathComponent];
    NSString * sourceLastName = [sourceLast stringByDeletingPathExtension];
    NSString * sourceExtension = [sourceLast pathExtension];
    NSString * targetName;
    NSString * target;
    int copyNumber;
    for (  copyNumber=1; copyNumber<100; copyNumber++  ) {
        if (  copyNumber == 1) {
            targetName = [sourceLastName stringByAppendingString: NSLocalizedString(@" copy", @"Suffix for a duplicate of a file")];
        } else {
            targetName = [sourceLastName stringByAppendingFormat: NSLocalizedString(@" copy %d", @"Suffix for a duplicate of a file"), copyNumber];
        }
        
        target = [[sourceFolder stringByAppendingPathComponent: targetName] stringByAppendingPathExtension: sourceExtension];
        if (  ! [gFileMgr fileExistsAtPath: target]  ) {
            break;
        }
    }
    
    if (  copyNumber > 99  ) {
        TBShowAlertWindow(NSLocalizedString(@"Warning", @"Window title"),
                          NSLocalizedString(@"Too many duplicate configurations already exist.", @"Window text"));
        return;
    }
    
    BOOL localAuthorization = FALSE;
    if (  authorization == nil  ) {
        NSString * msg = [NSString stringWithFormat: NSLocalizedString(@"You have asked to duplicate '%@'.", @"Window text"), displayName];
        authorization = [NSApplication getAuthorizationRef: msg];
        if ( authorization == nil ) {
            return;
        }
        localAuthorization = TRUE;
    }
    
    if (  [[ConfigurationManager manager] copyConfigPath: source
                                                  toPath: target
                                         usingAuthRefPtr: &authorization
                                              warnDialog: YES
                                             moveNotCopy: NO]  ) {
        
        NSString * targetDisplayName = [lastPartOfPath(target) stringByDeletingPathExtension];
        if (  ! [gTbDefaults copyPreferencesFrom: displayName to: targetDisplayName]  ) {
            TBShowAlertWindow(NSLocalizedString(@"Warning", @"Window title"),
                              NSLocalizedString(@"Warning: One or more preferences could not be duplicated. See the Console Log for details.", @"Window text"));
        }
        
        copyCredentials([connection displayName], targetDisplayName);
    }
    
    if (  localAuthorization  ) {
        AuthorizationFree(authorization, kAuthorizationFlagDefaults);
        authorization = nil;
    }
}


-(IBAction) makePrivateOrSharedMenuItemWasClicked: (id) sender
{
	(void) sender;
	
    VPNConnection * connection = [self selectedConnection];
    if (  ! connection  ) {
        NSLog(@"makePrivateOrSharedMenuItemWasClicked but no configuration has been selected");
        return;
    }
    
    NSString * displayName = [connection displayName];
    NSString * autoConnectKey = [displayName stringByAppendingString: @"autoConnect"];
    NSString * onSystemStartKey = [displayName stringByAppendingString: @"-onSystemStart"];
    if (   [gTbDefaults boolForKey: autoConnectKey]
        && [gTbDefaults boolForKey: onSystemStartKey]  ) {
        TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                          NSLocalizedString(@"You cannot make a configuration private if it is set to start when the computer starts.", @"Window text"));
        return;
    }
    
    NSString * path = [connection configPath];
    if (  ! [[path pathExtension] isEqualToString: @"tblk"]  ) {
        TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                          NSLocalizedString(@"You cannot make a configuration shared if it is not a Tunnelblick VPN Configuration (.tblk).", @"Window text"));
        return;
    }
    
    NSString * infoPlistPath = [[path stringByAppendingPathComponent: @"Contents"] stringByAppendingPathComponent: @"Info.plist"];
	NSString * fileName = [[[NSDictionary dictionaryWithContentsOfFile: infoPlistPath] objectForKey: @"CFBundleIdentifier"] stringByAppendingPathExtension: @"tblk"];
	if (  fileName  ) {
		BOOL isUpdatable = FALSE;
        BOOL isDir;
		NSString * bundleIdAndEdition;
		NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: L_AS_T_TBLKS];
		while (  (bundleIdAndEdition = [dirEnum nextObject])  ) {
			[dirEnum skipDescendents];
            NSString * containerPath = [L_AS_T_TBLKS stringByAppendingPathComponent: bundleIdAndEdition];
            if (   ( ! [bundleIdAndEdition hasPrefix: @"."] )
                && ( ! [bundleIdAndEdition hasSuffix: @".tblk"] )
                && [[NSFileManager defaultManager] fileExistsAtPath: containerPath isDirectory: &isDir]
                && isDir  ) {
                NSString * name;
                NSDirectoryEnumerator * innerEnum = [gFileMgr enumeratorAtPath: containerPath];
                while (  (name = [innerEnum nextObject] )  ) {
                    if (  [name isEqualToString: fileName]  ) {
                        isUpdatable = TRUE;
                        break;
                    }
                }
            }
        }
		if (  isUpdatable  ) {
			TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
							  NSLocalizedString(@"You cannot make a configuration shared if it is itself an updatable configuration.\n\n"
                                                @"Note that a Tunnelblick VPN Configuration that is inside an updatable Tunnelblick VPN Configuration can be shared.", @"Window text"));
			return;
		}
	}
    
    if (  ! [connection isDisconnected]  ) {
        NSString * msg = (  [path hasPrefix: [L_AS_T_SHARED stringByAppendingString: @"/"]]
                          ? NSLocalizedString(@"You cannot make a configuration private unless it is disconnected.", @"Window text")
                          : NSLocalizedString(@"You cannot make a configuration shared unless it is disconnected.", @"Window text")
                          );
        TBShowAlertWindow(NSLocalizedString(@"Active connection", @"Window title"),
                          msg);
        return;
    }
    
    [[ConfigurationManager manager] shareOrPrivatizeAtPath: path];
    [connection invalidateConfigurationParse];
}


-(IBAction) revertToShadowMenuItemWasClicked: (id) sender
{
	(void) sender;
	
    VPNConnection * connection = [self selectedConnection];
    if (  ! connection  ) {
        NSLog(@"revertToShadowMenuItemWasClicked but no configuration has been selected");
        return;
    }
    
	NSString * source = [connection configPath];

    if (  ! [source hasPrefix: [gPrivatePath stringByAppendingString: @"/"]]  ) {
        TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                          NSLocalizedString(@"You may only revert a private configuration.", @"Window text"));
        return;
    }
	
	if ( [connection shadowIsIdenticalMakeItSo: NO]  ) {
		TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
						  [NSString stringWithFormat:
						   NSLocalizedString(@"%@ is already identical to its last secured (shadow) copy.\n\n", @"Window text"),
						   [connection displayName]]);
        return;
	}
    
	int result = TBRunAlertPanel(NSLocalizedString(@"Tunnelblick", @"Window title"),
								 [NSString stringWithFormat:
								  NSLocalizedString(@"Do you wish to revert the '%@' configuration to its last secured (shadow) copy?\n\n", @"Window text"),
								  [connection displayName]],
								 NSLocalizedString(@"Revert", @"Button"),
								 NSLocalizedString(@"Cancel", @"Button"), nil);
	
	if (  result != NSAlertDefaultReturn  ) {
		return;
	}
    
	NSString * fileName = lastPartOfPath(source);
	NSArray * arguments = [NSArray arrayWithObjects: @"revertToShadow", fileName, nil];
	result = runOpenvpnstart(arguments, nil, nil);
	switch (  result  ) {
			
		case OPENVPNSTART_REVERT_CONFIG_OK:
			TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
							  [NSString stringWithFormat:
							   NSLocalizedString(@"%@ has been reverted to its last secured (shadow) copy.\n\n", @"Window text"),
							   [connection displayName]]);
			break;
			
		case OPENVPNSTART_REVERT_CONFIG_MISSING:
			TBShowAlertWindow(NSLocalizedString(@"VPN Configuration Installation Error", @"Window title"),
							  NSLocalizedString(@"The private configuration has never been secured, so you cannot revert to the secured (shadow) copy.", @"Window text"));
			break;
			
		default:
			TBShowAlertWindow(NSLocalizedString(@"VPN Configuration Installation Error", @"Window title"),
							  NSLocalizedString(@"An error occurred while trying to revert to the secured (shadow) copy. See the Console Log for details.\n\n", @"Window text"));
			break;
	}
    
    [connection invalidateConfigurationParse];
	[self setupDisableIpv6OnTun: connection];
	
}

-(IBAction) showHideOnTbMenuMenuItemWasClicked: (id) sender
{
    (void) sender;
    
    VPNConnection * connection = [self selectedConnection];
    if (connection  ) {
        NSString * key = [[connection displayName] stringByAppendingString: @"-doNotShowOnTunnelblickMenu"];
        BOOL value = [gTbDefaults boolForKey: key];
        [gTbDefaults setBool: ! value forKey: key];
        [self setupShowHideOnTbMenuMenuItem: [self selectedConnection]];
    }
}

-(IBAction) editOpenVPNConfigurationFileMenuItemWasClicked: (id) sender
{
	(void) sender;
	
    VPNConnection * connection = [self selectedConnection];
    if (connection  ) {
        [[ConfigurationManager manager] editOrExamineConfigurationForConnection: connection];
    } else {
        NSLog(@"editOpenVPNConfigurationFileMenuItemWasClicked but no configuration selected");
    }
    
    [connection invalidateConfigurationParse];
}


-(IBAction) showOpenvpnLogMenuItemWasClicked: (id) sender
{
	(void) sender;
	
    VPNConnection * connection = [self selectedConnection];
    if (  connection  ) {
        NSString * path = [connection openvpnLogPath];
        BOOL result = FALSE;
        if (  path  ) {
            result = [[NSWorkspace sharedWorkspace] selectFile: path inFileViewerRootedAtPath: @""];
        }
        if (  ! result  ) {
            TBShowAlertWindow(NSLocalizedString(@"File not found", @"Window title"),
                              NSLocalizedString(@"The OpenVPN log does not yet exist or has been deleted.", @"Window text"));
        }
    } else {
        NSLog(@"showOpenvpnLogMenuItemWasClicked but no configuration selected");
    }
}


-(IBAction) removeCredentialsMenuItemWasClicked: (id) sender
{
	(void) sender;
	
    VPNConnection * connection = [self selectedConnection];
    if (  connection  ) {
        NSString * name = [connection displayName];
		
		NSString * group = credentialsGroupFromDisplayName(name);
		AuthAgent * myAuthAgent = [[[AuthAgent alloc] initWithConfigName: name credentialsGroup: group] autorelease];
		
        [myAuthAgent setAuthMode: @"privateKey"];
        BOOL havePrivateKeyCredentials = [myAuthAgent keychainHasAnyCredentials];
        
        [myAuthAgent setAuthMode: @"password"];
        BOOL haveUsernameCredentials = [myAuthAgent keychainHasAnyCredentials];
        
        if (   havePrivateKeyCredentials
            || haveUsernameCredentials  ) {
			NSString * msg;
			if (  group  ) {
				msg =[NSString stringWithFormat: NSLocalizedString(@"Are you sure you wish to delete the credentials (private"
																   @" key or username and password) stored in the Keychain for '%@'"
                                                                   @" credentials?", @"Window text"), group];
			} else {
				msg =[NSString stringWithFormat: NSLocalizedString(@"Are you sure you wish to delete the credentials (private key or username and password) for '%@' that are stored in the Keychain?", @"Window text"), name];
			}
			
            int button = TBRunAlertPanel(NSLocalizedString(@"Please Confirm", @"Window title"),
                                         msg,
                                         NSLocalizedString(@"Cancel", @"Button"),             // Default button
                                         NSLocalizedString(@"Delete Credentials", @"Button"), // Alternate button
                                         nil);
            
            if (  button == NSAlertAlternateReturn  ) {
                if (  havePrivateKeyCredentials  ) {
                    [myAuthAgent setAuthMode: @"privateKey"];
                    [myAuthAgent deleteCredentialsFromKeychainIncludingUsername: YES];
                }
                if (  haveUsernameCredentials  ) {
                    [myAuthAgent setAuthMode: @"password"];
                    [myAuthAgent deleteCredentialsFromKeychainIncludingUsername: YES];
                }
            }
        } else {
            TBShowAlertWindow(NSLocalizedString(@"No Credentials", @"Window title"),
                             [NSString stringWithFormat:
                              NSLocalizedString(@"'%@' does not have any credentials (private key or username and password) stored in the Keychain.", @"Window text"),
                             name]);
        }
        
    } else {
        NSLog(@"removeCredentialsMenuItemWasClicked but no configuration selected");
    }
}


// Log tab

-(NSString *) listOfFilesInTblkForConnection: (VPNConnection *) connection {
    
    NSString * configPath = [connection configPath];
    NSString * configPathTail = [configPath lastPathComponent];
    
    if (  [configPath hasSuffix: @".tblk"]  ) {
        NSMutableString * fileListString = [[[NSMutableString alloc] initWithCapacity: 500] autorelease];
        NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: configPath];
        NSString * filename;
        while (  (filename = [dirEnum nextObject])  ) {
            if (  ! [filename hasPrefix: @"."]  ) {
                NSString * extension = [filename pathExtension];
                NSString * nameOnly = [filename lastPathComponent];
                NSArray * extensionsToSkip = KEY_AND_CRT_EXTENSIONS;
                if (   ( ! [extensionsToSkip containsObject: extension])
                    && ( ! [extension isEqualToString: @"ovpn"])
                    && ( ! [extension isEqualToString: @"lproj"])
                    && ( ! [extension isEqualToString: @"strings"])
                    && ( ! [nameOnly  isEqualToString: @"Info.plist"])
                    && ( ! [nameOnly  isEqualToString: @".DS_Store"])
                    ) {
                    NSString * fullPath = [configPath stringByAppendingPathComponent: filename];
                    BOOL isDir;
                    if (  ! (   [gFileMgr fileExistsAtPath: fullPath isDirectory: &isDir]
                             && isDir)  ) {
                        [fileListString appendFormat: @"      %@\n", filename];
                    }
                }
            }
        }
        
        return (  ([fileListString length] == 0)
                ? [NSString stringWithFormat: @"There are no unusual files in %@\n", configPathTail]
                : [NSString stringWithFormat: @"Unusual files in %@:\n%@", configPathTail, fileListString]);
    } else {
        return [NSString stringWithFormat: @"Cannot list unusual files in %@; not a .tblk\n", configPathTail];
    }
}

-(NSString *) tigerConsoleContents {
    
    // Tiger doesn't implement the asl API (or not enough of it). So we get the console log from the file if we are running as an admin
	NSString * consoleRawContents = @""; // stdout (ignore stderr)
	
	if (  isUserAnAdmin()  ) {
		runTool(TOOL_PATH_FOR_BASH,
                [NSArray arrayWithObjects:
                 @"-c",
                 [NSString stringWithFormat: @"cat /Library/Logs/Console/%d/console.log | grep -i -E 'tunnelblick|openvpn' | tail -n 100", getuid()],
                 nil],
                &consoleRawContents,
                nil);
	} else {
		consoleRawContents = (@"The Console log cannot be obtained because you are not\n"
							  @"logged in as an administrator. To view the Console log,\n"
							  @"please use the Console application in /Applications/Utilities.\n");
	}
	    
    // Replace backslash-n with newline and indent the continuation lines
    NSMutableString * consoleContents = [[consoleRawContents mutableCopy] autorelease];
    [consoleContents replaceOccurrencesOfString: @"\\n"
                                     withString: @"\n                                       " // Note all the spaces in the string
                                        options: 0
                                          range: NSMakeRange(0, [consoleContents length])];

    return consoleContents;
}

-(NSString *) stringFromLogEntry: (NSDictionary *) dict {
    
    // Returns a string with a console log entry, terminated with a LF
    
    NSString * timestampS = [dict objectForKey: [NSString stringWithUTF8String: ASL_KEY_TIME]];
    NSString * senderS    = [dict objectForKey: [NSString stringWithUTF8String: ASL_KEY_SENDER]];
    NSString * pidS       = [dict objectForKey: [NSString stringWithUTF8String: ASL_KEY_PID]];
    NSString * msgS       = [dict objectForKey: [NSString stringWithUTF8String: ASL_KEY_MSG]];
    
    NSDate * dateTime = [NSDate dateWithTimeIntervalSince1970: (NSTimeInterval) [timestampS doubleValue]];
    NSDateFormatter * formatter = [[[NSDateFormatter alloc] init] autorelease];
    [formatter setDateFormat: @"yyyy-MM-dd HH:mm:ss"];

    NSString * timeString = [formatter stringFromDate: dateTime];
    NSString * senderString = [NSString stringWithFormat: @"%@[%@]", senderS, pidS];
    
	// Set up to indent continuation lines by converting newlines to \n (i.e., "backslash n")
	NSMutableString * msgWithBackslashN = [[msgS mutableCopy] autorelease];
	[msgWithBackslashN replaceOccurrencesOfString: @"\n"
									   withString: @"\\n"
										  options: 0
											range: NSMakeRange(0, [msgWithBackslashN length])];
	
    return [NSString stringWithFormat: @"%@ %21@ %@\n", timeString, senderString, msgWithBackslashN];
}

-(NSString *) stringContainingRelevantConsoleLogEntries {
    
    // Returns a string with relevant entries from the Console log
    
	// First, search the log for all entries fewer than six hours old from Tunnelblick or openvpnstart
    // And append them to tmpString
	
	NSMutableString * tmpString = [NSMutableString string];
    
    aslmsg q = asl_new(ASL_TYPE_QUERY);
	time_t sixHoursAgoTimeT = time(NULL) - 6 * 60 * 60;
	const char * sixHoursAgo = [[NSString stringWithFormat: @"%ld", (long) sixHoursAgoTimeT] UTF8String];
    asl_set_query(q, ASL_KEY_TIME, sixHoursAgo, ASL_QUERY_OP_GREATER_EQUAL | ASL_QUERY_OP_NUMERIC);
    aslresponse r = asl_search(NULL, q);
    
    aslmsg m;
    while (NULL != (m = aslresponse_next(r))) {
        
        NSMutableDictionary *tmpDict = [NSMutableDictionary dictionary];
        
        BOOL includeDict = FALSE;
        const char * key;
        const char * val;
        unsigned i;
        for (  i = 0; (NULL != (key = asl_key(m, i))); i++  ) {
            val = asl_get(m, key);
            if (  val  ) {
                NSString * string    = [NSString stringWithUTF8String: val];
                NSString * keyString = [NSString stringWithUTF8String: key];
                [tmpDict setObject: string forKey: keyString];
                
                if (  ! ASL_KEY_SENDER  ) {
                    NSLog(@"stringContainingRelevantConsoleLogEntries: ASL_KEY_SENDER = NULL");
                }
                if (  ! ASL_KEY_MSG  ) {
                    NSLog(@"stringContainingRelevantConsoleLogEntries: ASL_KEY_MSG = NULL");
                }
                if (  [keyString isEqualToString: [NSString stringWithUTF8String: ASL_KEY_SENDER]]  ) {
                    if (   [string isEqualToString: @"Tunnelblick"]
                        || [string isEqualToString: @"atsystemstart"]
                        || [string isEqualToString: @"installer"]
                        || [string isEqualToString: @"openvpnstart"]
                        || [string isEqualToString: @"process-network-changes"]
                        || [string isEqualToString: @"standardize-scutil-output"]
                        || [string isEqualToString: @"tunnelblickd"]
                        || [string isEqualToString: @"tunnelblick-helper"]
                        ) {
                        includeDict = TRUE;
                    }
                } else if (  [keyString isEqualToString: [NSString stringWithUTF8String: ASL_KEY_MSG]]  ) {
                    if (   ([string rangeOfString: @"Tunnelblick"].length != 0)
                        || ([string rangeOfString: @"tunnelblick"].length != 0)
                        || ([string rangeOfString: @"Tunnel" "blick"].length != 0)      // Include non-rebranded references to Tunnelblick
                        || ([string rangeOfString: @"atsystemstart"].length != 0)
                        || ([string rangeOfString: @"installer"].length != 0)
                        || ([string rangeOfString: @"openvpnstart"].length != 0)
                        || ([string rangeOfString: @"Saved crash report for openvpn"].length != 0)
                        || ([string rangeOfString: @"process-network-changes"].length != 0)
                        || ([string rangeOfString: @"standardize-scutil-output"].length != 0)
                        ) {
                        includeDict = TRUE;
                    }
                }
            }
		}
		
		if (  includeDict  ) {
			[tmpString appendString: [self stringFromLogEntry: tmpDict]];
		}
	}
		
	aslresponse_free(r);
	
	// Next, extract the tail of the entries -- the last 200 lines of them
	// (The loop test is "i<201" because we look for the 201-th newline from the end of the string; just after that is the
	//  start of the 200th entry from the end of the string.)
    
	NSRange tsRng = NSMakeRange(0, [tmpString length]);	// range we are looking at currently; start with entire string
    unsigned i;
	unsigned offset = 2;
    BOOL fewerThan200LinesInLog = FALSE;
	for (  i=0; i<201; i++  ) {
		NSRange nlRng = [tmpString rangeOfString: @"\n"	// range of last newline at end of part we are looking at
										 options: NSBackwardsSearch
										   range: tsRng];
		
		if (  nlRng.length == 0  ) {    // newline not found (fewer than 200 lines in tmpString);  set up to start at start of string
			offset = 0;
            fewerThan200LinesInLog = TRUE;
			break;
		}
		
        if (  nlRng.location == 0  ) {  // newline at start of string (shouldn't happen, but...)
			offset = 1;					// set up to start _after_ the newline
            fewerThan200LinesInLog = TRUE;
            break;
        }
        
		tsRng.length = nlRng.location - 1; // change so looking before that newline 
	}
    
    if (  fewerThan200LinesInLog  ) {
        tsRng.length = 0;
    }
    
	NSString * tail = [tmpString substringFromIndex: tsRng.length + offset];
	
	// Finally, indent continuation lines
	NSMutableString * indentedMsg = [[tail mutableCopy] autorelease];
	[indentedMsg replaceOccurrencesOfString: @"\\n"
								 withString: @"\n                                       " // Note all the spaces in the string
									options: 0
									  range: NSMakeRange(0, [indentedMsg length])];
	return indentedMsg;	
}

-(NSString *) getPreferences: (NSArray *) prefsArray prefix: (NSString *) prefix {
    
    NSMutableString * string = [[[NSMutableString alloc] initWithCapacity: 1000] autorelease];
    
    NSEnumerator * e = [prefsArray objectEnumerator];
    NSString * keySuffix;
    while (  (keySuffix = [e nextObject])  ) {
        NSString * key = [prefix stringByAppendingString: keySuffix];
		id obj = [gTbDefaults objectForKey: key];
		if (  obj  ) {
			if (  [key isEqualToString: @"installationUID"]  ) {
				[string appendFormat: @"%@ (not shown)\n", key];
			} else {
				[string appendFormat: @"%@ = %@%@\n", keySuffix, obj, (  [gTbDefaults canChangeValueForKey: key]
																	   ? @""
																	   : @" (forced)")];
			}
		}
    }
    
    return [NSString stringWithString: string];
}

-(NSString *) stringWithIfconfigOutput {
    
    NSString * ifconfigOutput = @""; // stdout (ignore stderr)
	
    runTool(TOOL_PATH_FOR_IFCONFIG,
            [NSArray array],
            &ifconfigOutput,
            nil);
    
    return ifconfigOutput;
}

-(NSString *) nonAppleKextContents {
    
    NSString * kextRawContents = @""; // stdout (ignore stderr)
	
    runTool(TOOL_PATH_FOR_BASH,
            [NSArray arrayWithObjects:
             @"-c",
             [TOOL_PATH_FOR_KEXTSTAT stringByAppendingString: @" | grep -v com.apple"],
             nil],
            &kextRawContents,
            nil);
    
    return kextRawContents;
}

-(IBAction) logToClipboardButtonWasClicked: (id) sender {

	(void) sender;
	
    VPNConnection * connection = [self selectedConnection];
    if (  connection  ) {
		
		// Get OS and Tunnelblick version info
		NSString * versionContents = [[((MenuController *)[NSApp delegate]) openVPNLogHeader] stringByAppendingString:
                                      (isUserAnAdmin()
                                       ? @"; Admin user"
                                       : @"; Standard user")];
		
		// Get contents of configuration file
        NSString * configFileContents = [connection sanitizedConfigurationFileContents ];
        if (  ! configFileContents  ) {
            configFileContents = @"(No configuration file found or configuration file could not be sanitized. See the Console Log for details.)";
        }
		
		NSString * condensedConfigFileContents = condensedConfigFileContentsFromString(configFileContents);
		
        // Get list of files in .tblk or message explaining why cannot get list
        NSString * tblkFileList = [self listOfFilesInTblkForConnection: connection];
        
        // Get relevant preferences
        NSString * configurationPreferencesContents = [self getPreferences: gConfigurationPreferences prefix: [connection displayName]];
        
        NSString * wildcardPreferencesContents      = [self getPreferences: gConfigurationPreferences prefix: @"*"];
        
        NSString * programPreferencesContents       = [self getPreferences: gProgramPreferences       prefix: @""];
        
		// Get Tunnelblick log
        NSTextStorage * store = [[configurationsPrefsView logView] textStorage];
        NSString * logContents = [store string];
        
        // Get output of "ifconfig"
        NSString * ifconfigOutput = [self stringWithIfconfigOutput];
        
		// Get tail of Console log
        NSString * consoleContents = (  runningOnLeopardOrNewer()
                                      ? [self stringContainingRelevantConsoleLogEntries]
                                      : [self tigerConsoleContents]);
        
        NSString * kextContents = [self nonAppleKextContents];
        
		NSString * separatorString = @"================================================================================\n\n";
		
        NSString * output = [NSString stringWithFormat:
							 @"%@\n\n"  // Version info
                             @"Configuration %@\n\n"
                             @"\"Sanitized\" condensed configuration file for %@:\n\n%@\n\n%@"
                             @"Non-Apple kexts that are loaded:\n\n%@\n%@"
                             @"%@\n%@"  // List of unusual files in .tblk (or message why not listing them)
                             @"Configuration preferences:\n\n%@\n%@"
                             @"Wildcard preferences:\n\n%@\n%@"
                             @"Program preferences:\n\n%@\n%@"
                             @"Tunnelblick Log:\n\n%@\n%@"
							 @"\"Sanitized\" full configuration file\n\n%@\n\n%@"
                             @"ifconfig output:\n\n%@\n%@"
                             @"Console Log:\n\n%@\n",
                             versionContents,
                             [connection localizedName], [connection configPath], condensedConfigFileContents, separatorString,
                             kextContents, separatorString,
                             tblkFileList, separatorString,
                             configurationPreferencesContents, separatorString,
                             wildcardPreferencesContents, separatorString,
                             programPreferencesContents, separatorString,
                             logContents, separatorString,
							 configFileContents, separatorString,
                             ifconfigOutput, separatorString,
                             consoleContents];
        
        NSPasteboard * pb = [NSPasteboard generalPasteboard];
        [pb declareTypes: [NSArray arrayWithObject: NSStringPboardType] owner: self];
        [pb setString: output forType: NSStringPboardType];
    } else {
        NSLog(@"logToClipboardButtonWasClicked but no configuration selected");
    }
}


// Settings tab

-(IBAction) whenToConnectManuallyMenuItemWasClicked: (id) sender
{
	(void) sender;
	
    if (  [self selectedConnection]  ) {
        [self setSelectedWhenToConnectIndex: 0];
    } else {
        NSLog(@"whenToConnectManuallyMenuItemWasClicked but no configuration selected");
    }
}


-(IBAction) whenToConnectTunnelBlickLaunchMenuItemWasClicked: (id) sender
{
	(void) sender;
	
    if (  [self selectedConnection]  ) {
        [self setSelectedWhenToConnectIndex: 1];
    } else {
        NSLog(@"whenToConnectTunnelBlickLaunchMenuItemWasClicked but no configuration selected");
    }
}


-(IBAction) whenToConnectOnComputerStartMenuItemWasClicked: (id) sender
{
	(void) sender;
	
    if (  [self selectedConnection]  ) {
        NSString * configurationPath = [[self selectedConnection] configPath];
        if (  [configurationPath hasPrefix: [gPrivatePath stringByAppendingString: @"/"]]  ) {
            NSUInteger ix = selectedWhenToConnectIndex;
            selectedWhenToConnectIndex = 2;
            [[configurationsPrefsView whenToConnectPopUpButton] selectItemAtIndex: (int)ix];
            [self setSelectedWhenToConnectIndex: ix];
            TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                              NSLocalizedString(@"Private configurations cannot connect when the computer starts.\n\n"
                                                "First make the configuration shared, then change this setting.", @"Window text"));
        } else if (  ! [[configurationPath pathExtension] isEqualToString: @"tblk"]  ) {
            NSUInteger ix = selectedWhenToConnectIndex;
            selectedWhenToConnectIndex = 2;
            [[configurationsPrefsView whenToConnectPopUpButton] selectItemAtIndex: (int)ix];
            [self setSelectedWhenToConnectIndex: ix];
            TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                              NSLocalizedString(@"Only a Tunnelblick VPN Configuration (.tblk) can start when the computer starts.", @"Window text"));
        } else if (  ! [[self selectedConnection] mayConnectWhenComputerStarts]  ) {
            NSUInteger ix = selectedWhenToConnectIndex;
            selectedWhenToConnectIndex = 2;
            [[configurationsPrefsView whenToConnectPopUpButton] selectItemAtIndex: (int)ix];
            [self setSelectedWhenToConnectIndex: ix];
            TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                              NSLocalizedString(@"A configuration which requires a passphrase (private key) or a username and password cannot start when the computer starts.", @"Window text"));
        } else {
            [self setSelectedWhenToConnectIndex: 2];
        }
    } else {
        NSLog(@"whenToConnectOnComputerStartMenuItemWasClicked but no configuration selected");
    }
}

-(void) setSelectedPerConfigOpenvpnVersionIndex: (NSNumber *) newValue
{
    if (  [newValue isNotEqualTo: [self selectedPerConfigOpenvpnVersionIndex]]  ) {
        NSArrayController * ac = [configurationsPrefsView perConfigOpenvpnVersionArrayController];
        NSArray * list = [ac content];
        if (  tbUnsignedIntegerValue(newValue) < [list count]  ) {
            
            [self setSelectedPerConfigOpenvpnVersionIndexDirect: newValue];
            
            // Set the preference if this isn't just the initialization
            if (  ! [((MenuController *)[NSApp delegate]) doingSetupOfUI]  ) {
                NSString * newPreferenceValue = [[list objectAtIndex: tbUnsignedIntegerValue(newValue)] objectForKey: @"value"];
				NSDictionary * dict = [NSDictionary dictionaryWithObjectsAndKeys:
									   newPreferenceValue, @"NewValue",
									   @"-openvpnVersion", @"PreferenceName",
									   nil];
				[((MenuController *)[NSApp delegate]) performSelectorOnMainThread: @selector(setPreferenceForSelectedConfigurationsWithDict:) withObject: dict waitUntilDone: NO];
			}
        }
    }
}

// Checkbox was changed by another window
-(void) monitorNetworkForChangesCheckboxChangedForConnection: (VPNConnection *) theConnection
{
    VPNConnection * connection = [self selectedConnection];
    if (   connection
        && (connection == theConnection)  ) {
        NSString * displayName = [connection displayName];
        NSString * key = [displayName stringByAppendingString: @"-notMonitoringConnection"];
        BOOL checked = [gTbDefaults boolForKey: key];
        int state = (checked ? NSOffState : NSOnState);
        [[configurationsPrefsView monitorNetworkForChangesCheckbox] setState: state];
    }
}

-(IBAction) monitorNetworkForChangesCheckboxWasClicked: (NSButton *) sender
{
    [((MenuController *)[NSApp delegate]) setBooleanPreferenceForSelectedConnectionsWithKey: @"-notMonitoringConnection"
                                                                                         to: ([sender state] == NSOnState)
                                                                                   inverted: YES];
    
    [settingsSheetWindowController monitorNetworkForChangesCheckboxChangedForConnection: [self selectedConnection]];
}

-(IBAction) routeAllTrafficThroughVpnCheckboxWasClicked: (NSButton *) sender {
    [((MenuController *)[NSApp delegate]) setBooleanPreferenceForSelectedConnectionsWithKey: @"-routeAllTrafficThroughVpn"
                                                                                         to: ([sender state] == NSOnState)
                                                                                   inverted: NO];
}

-(IBAction) checkIPAddressAfterConnectOnAdvancedCheckboxWasClicked: (NSButton *) sender
{
    [((MenuController *)[NSApp delegate]) setBooleanPreferenceForSelectedConnectionsWithKey: @"-notOKToCheckThatIPAddressDidNotChangeAfterConnection"
                                                                                         to: ([sender state] == NSOnState)
                                                                                   inverted: YES];
}

-(IBAction) resetPrimaryInterfaceAfterDisconnectCheckboxWasClicked: (NSButton *) sender {
    [((MenuController *)[NSApp delegate]) setBooleanPreferenceForSelectedConnectionsWithKey: @"-resetPrimaryInterfaceAfterDisconnect"
                                                                                         to: ([sender state] == NSOnState)
                                                                                   inverted: NO];
}

-(IBAction) disableIpv6OnTunCheckboxWasClicked: (NSButton *) sender
{
    [((MenuController *)[NSApp delegate]) setBooleanPreferenceForSelectedConnectionsWithKey: @"-doNotDisableIpv6onTun"
                                                                                         to: ([sender state] == NSOnState)
                                                                                   inverted: YES];
}

-(IBAction) advancedButtonWasClicked: (id) sender
{
	(void) sender;
	
    VPNConnection * connection = [self selectedConnection];
    if (  connection  ) {
        if (  settingsSheetWindowController == nil  ) {
            settingsSheetWindowController = [[SettingsSheetWindowController alloc] init];
        }
        
        NSString * name = [connection displayName];
        [settingsSheetWindowController setConfigurationName: name];
        [settingsSheetWindowController showSettingsSheet: self];
    } else {
        NSLog(@"advancedButtonWasClicked but no configuration selected");
    }
}


// Makes sure that
//       * The autoConnect and -onSystemStart preferences
//       * The configuration location (private/shared/deployed)
//       * Any launchd .plist for the configuration
// are all consistent.
// Does this by creating/deleting a launchd .plist if it can (i.e., if the user authorizes it)
// Otherwise may modify the preferences to reflect the existence of the launchd .plist
-(void) validateWhenToConnect: (VPNConnection *) connection
{
    if (  ! connection  ) {
        return;
    }
    
    NSString * displayName = [connection displayName];
    
    BOOL enableWhenComputerStarts = [connection mayConnectWhenComputerStarts];
    
    NSString * autoConnectKey = [displayName stringByAppendingString: @"autoConnect"];
    BOOL autoConnect   = [gTbDefaults boolForKey: autoConnectKey];
    NSString * ossKey = [displayName stringByAppendingString: @"-onSystemStart"];
    BOOL onSystemStart = [gTbDefaults boolForKey: ossKey];
    
    BOOL launchdPlistWillConnectOnSystemStart = [connection launchdPlistWillConnectOnSystemStart];
    
    NSUInteger ix = NSNotFound;
    
    //Keep track of what we've done for an alert to the user
    BOOL fixedPreferences       = FALSE;
    BOOL failedToFixPreferences = FALSE;
    BOOL fixedPlist             = FALSE;
    BOOL cancelledFixPlist      = FALSE;
    
    if (  autoConnect && onSystemStart  ) {
        if (  enableWhenComputerStarts  ) {
            if (  launchdPlistWillConnectOnSystemStart  ) {
                // All is OK -- prefs say to connect when system starts and launchd .plist agrees and it isn't a private configuration and has no credentials
                ix = 2;
            } else {
                // No launchd .plist -- try to create one
                if (  [connection checkConnectOnSystemStart: TRUE withAuth: nil]  ) {
                    // Made it connect when computer starts
                    fixedPlist = TRUE;
                    ix = 2;
                } else {
                    // User cancelled attempt to make it connect when computer starts
                    cancelledFixPlist = TRUE;
                    NSLog(@"Preferences for '%@' say it should connect when the computer starts but it does not have a launchd .plist and the user did not authorize creating a .plist. Attempting to repair preferences...", displayName);
                    [gTbDefaults setBool: FALSE forKey: autoConnectKey];
                    if (  ! [gTbDefaults boolForKey: autoConnectKey]  ) {
                        NSLog(@"Succesfully set '%@' preference to FALSE", autoConnectKey);
                        fixedPreferences = TRUE;
                    } else {
                        NSLog(@"Unable to set '%@' preference to FALSE", autoConnectKey);
                        failedToFixPreferences = TRUE;
                    }
                    [gTbDefaults setBool: FALSE forKey: ossKey];
                    if (  ! [gTbDefaults boolForKey: ossKey]  ) {
                        NSLog(@"Succesfully set '%@' preference to FALSE", ossKey);
                        fixedPreferences = TRUE;
                    } else {
                        NSLog(@"Unable to set '%@' preference to FALSE", ossKey);
                        failedToFixPreferences = TRUE;
                    }
                    ix = 0;  // It IS going to start when computer starts, so show that to user
                }
            }
        } else {
            // Private configuration or has credentials
            if (  ! launchdPlistWillConnectOnSystemStart  ) {
                // Prefs, but not launchd, says will connnect on system start but it is a private configuration or has credentials
                NSLog(@"Preferences for '%@' say it should connect when the computer starts but it is a private configuration or has credentials. Attempting to repair preferences...", displayName);
                [gTbDefaults setBool: FALSE forKey: autoConnectKey];
                if (  ! [gTbDefaults boolForKey: autoConnectKey]  ) {
                    NSLog(@"Succesfully set '%@' preference to FALSE", autoConnectKey);
                    fixedPreferences = TRUE;
                } else {
                    NSLog(@"Unable to set '%@' preference to FALSE", autoConnectKey);
                    failedToFixPreferences = TRUE;
                }
                [gTbDefaults setBool: FALSE forKey: ossKey];
                if (  ! [gTbDefaults boolForKey: ossKey]  ) {
                    NSLog(@"Succesfully set '%@' preference to FALSE", ossKey);
                    fixedPreferences = TRUE;
                } else {
                    NSLog(@"Unable to set '%@' preference to FALSE", ossKey);
                    failedToFixPreferences = TRUE;
                }
                ix = 0;
            } else {
                // Prefs and launchd says connect on user start but private configuration, so can't. Try to remove the launchd .plist
                if (  [connection checkConnectOnSystemStart: FALSE withAuth: nil]  ) {
                    // User cancelled attempt to make it NOT connect when computer starts
                    cancelledFixPlist = TRUE;
                    NSLog(@"Preferences for '%@' say it should connect when the computer starts and a launchd .plist exists for that, but it is a private configuration or has credentials. User cancelled attempt to repair.", displayName);
                    ix = 2;
                } else {
                    NSLog(@"Preferences for '%@' say it should connect when the computer starts and a launchd .plist exists for that, but it is a private configuration or has credentials. The launchd .plist has been removed. Attempting to repair preferences...", displayName);
                    [gTbDefaults setBool: FALSE forKey: autoConnectKey];
                    if (  ! [gTbDefaults boolForKey: autoConnectKey]  ) {
                        NSLog(@"Succesfully set '%@' preference to FALSE", autoConnectKey);
                        fixedPreferences = TRUE;
                    } else {
                        NSLog(@"Unable to set '%@' preference to FALSE", autoConnectKey);
                        failedToFixPreferences = TRUE;
                    }
                    [gTbDefaults setBool: FALSE forKey: ossKey];
                    if (  ! [gTbDefaults boolForKey: ossKey]  ) {
                        NSLog(@"Succesfully set '%@' preference to FALSE", ossKey);
                        fixedPreferences = TRUE;
                    } else {
                        NSLog(@"Unable to set '%@' preference to FALSE", ossKey);
                        failedToFixPreferences = TRUE;
                    }
                    ix = 0;
                }
            }
        }
    } else {
        // Manual or when Tunnelblick is launched
        if (  launchdPlistWillConnectOnSystemStart  ) {
            // launchd .plist exists but prefs are not connect when computer starts. Attempt to remove .plist
            if (  [connection checkConnectOnSystemStart: FALSE withAuth: nil]  ) {
                // User cancelled attempt to make it NOT connect when computer starts
                cancelledFixPlist = TRUE;
                NSLog(@"Preferences for '%@' say it should NOT connect when the computer starts but a launchd .plist exists for that and the user cancelled an attempt to remove the .plist. Attempting to repair preferences.", displayName);
                if (  ! [gTbDefaults boolForKey: autoConnectKey]  ) {
                    [gTbDefaults setBool: TRUE forKey: autoConnectKey];
                    if (  [gTbDefaults boolForKey: autoConnectKey]  ) {
                        NSLog(@"Succesfully set '%@' preference to TRUE", autoConnectKey);
                        fixedPreferences = TRUE;
                    } else {
                        NSLog(@"Unable to set '%@' preference to TRUE", autoConnectKey);
                        failedToFixPreferences = TRUE;
                    }
                }
                if (  ! [gTbDefaults boolForKey: ossKey]  ) {
                    [gTbDefaults setBool: TRUE forKey: ossKey];
                    if (  [gTbDefaults boolForKey: ossKey]  ) {
                        NSLog(@"Succesfully set '%@' preference to TRUE", ossKey);
                        fixedPreferences = TRUE;
                    } else {
                        NSLog(@"Unable to set '%@' preference to TRUE", ossKey);
                        failedToFixPreferences = TRUE;
                    }
                }
                ix = 2;
            } else {
                NSLog(@"Preferences for '%@' say it should NOT connect when the computer starts and a launchd .plist existed but has been removed.", displayName);
            }
        }
    }
    
    if (  ix == NSNotFound  ) {
        ix = 0;
        if (  [gTbDefaults boolForKey: autoConnectKey]  ) {
            if (  [gTbDefaults boolForKey: ossKey]  ) {
                ix = 2;
            } else {
                ix = 1;
            }
        }
    }
    
    if (  failedToFixPreferences  ) {
        TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                          [NSString stringWithFormat: 
                           NSLocalizedString(@"Tunnelblick failed to repair problems with preferences for '%@'. Details are in the Console Log", @"Window text"),
                           displayName]);
    }
    if (  fixedPreferences || cancelledFixPlist || fixedPlist) {
        ; // Avoid analyzer warnings about unused variables
    }
    
    [[configurationsPrefsView whenToConnectPopUpButton] selectItemAtIndex: (int)ix];
    selectedWhenToConnectIndex = ix;
    [[configurationsPrefsView whenToConnectOnComputerStartMenuItem] setEnabled: enableWhenComputerStarts];
    
    BOOL enable = (   [gTbDefaults canChangeValueForKey: autoConnectKey]
                   && [gTbDefaults canChangeValueForKey: ossKey]
				   && [self oneConfigurationIsSelected]);
    [[configurationsPrefsView whenToConnectPopUpButton] setEnabled: enable];
}

-(void) setSelectedWhenToConnectIndex: (NSUInteger) newValue
{
    NSUInteger oldValue = selectedWhenToConnectIndex;
    if (  newValue != oldValue  ) {
        NSString * configurationName = [[self selectedConnection] displayName];
        NSString * autoConnectKey   = [configurationName stringByAppendingString: @"autoConnect"];
        NSString * onSystemStartKey = [configurationName stringByAppendingString: @"-onSystemStart"];
        switch (  newValue  ) {
            case 0:
                [gTbDefaults setBool: FALSE forKey: autoConnectKey];
                [gTbDefaults setBool: FALSE forKey: onSystemStartKey];
                break;
            case 1:
                [gTbDefaults setBool: TRUE  forKey: autoConnectKey];
                [gTbDefaults setBool: FALSE forKey: onSystemStartKey];
                break;
            case 2:
                [gTbDefaults setBool: TRUE forKey: autoConnectKey];
                [gTbDefaults setBool: TRUE forKey: onSystemStartKey];
                break;
            default:
                NSLog(@"Attempt to set 'when to connect' to %ld ignored", (long) newValue);
                break;
        }
        selectedWhenToConnectIndex = newValue;
        [self validateWhenToConnect: [self selectedConnection]];
        
        NSUInteger ix = 0;
        if (  [gTbDefaults boolForKey: autoConnectKey]  ) {
            if (  [gTbDefaults boolForKey: onSystemStartKey]  ) {
                ix = 2;
            } else {
                ix = 1;
            }
        }
        if (  ix != newValue  ) {   // If weren't able to change it, restore old value
            if (  oldValue == NSNotFound  ) {
                oldValue = 0;
            }
            [self setSelectedWhenToConnectIndex: oldValue];
            selectedWhenToConnectIndex = oldValue;
        }
    }
}


-(void) setSelectedSetNameserverIndex: (NSNumber *) newValue
{
    if (  [newValue isNotEqualTo: [self selectedSetNameserverIndex]]  ) {
        if (  ! [((MenuController *)[NSApp delegate]) doingSetupOfUI]  ) {
			NSDictionary * dict = [NSDictionary dictionaryWithObjectsAndKeys:
                                   newValue, @"NewValue",
								   @"useDNS", @"PreferenceName",
								   nil];
			[((MenuController *)[NSApp delegate]) performSelectorOnMainThread: @selector(setPreferenceForSelectedConfigurationsWithDict:) withObject: dict waitUntilDone: NO];
			
			// Must set the key now (even though setPreferenceForSelectedConfigurationsWithDict: will set it later) so the rest of the code in this method runs with the new setting
            NSString * actualKey = [[[self selectedConnection] displayName] stringByAppendingString: @"useDNS"];
            [gTbDefaults setObject: newValue forKey: actualKey];
        }
		
		// Must set the key above (even though setPreferenceForSelectedConfigurationsWithDict: will set it later) so the following code works with the new setting

        [self setSelectedSetNameserverIndexDirect: newValue];
        
        // If script doesn't support monitoring, indicate it is off and disable it
        if (   (tbUnsignedIntegerValue(newValue) > 2)
            || (tbUnsignedIntegerValue(newValue) == 0)
            || ([[[configurationsPrefsView setNameserverArrayController] content] count] < 4)  ) {
            [[configurationsPrefsView monitorNetworkForChangesCheckbox] setState: NSOffState];
            [[configurationsPrefsView monitorNetworkForChangesCheckbox] setEnabled: NO];
        } else {
            [self setupPerConfigurationCheckbox: [configurationsPrefsView monitorNetworkForChangesCheckbox]
                                            key: @"-notMonitoringConnection"
                                       inverted: YES
                                      defaultTo: NO];
        }
		
		// Set up IPv6 and reset of primary interface
		[self setupDisableIpv6OnTun: [self selectedConnection]];
		[self setupResetPrimaryInterface: [self selectedConnection]];
		
        [settingsSheetWindowController monitorNetworkForChangesCheckboxChangedForConnection: [self selectedConnection]];
        [settingsSheetWindowController setupSettingsFromPreferences];
    }
}

-(void) tableViewSelectionDidChange:(NSNotification *)notification
{
	(void) notification;
	
    [self performSelectorOnMainThread: @selector(selectedLeftNavListIndexChanged) withObject: nil waitUntilDone: NO];
}

-(void) selectedLeftNavListIndexChanged
{
    int n;
	
	if (   runningOnSnowLeopardOrNewer()  // 10.5 and lower don't have setDelegate and setDataSource
		&& ( ! [gTbDefaults boolForKey: @"doNotShowOutlineViewOfConfigurations"] )  ) {
		n = [[[configurationsPrefsView outlineViewController] outlineView] selectedRow];
		NSOutlineView * oV = [[configurationsPrefsView outlineViewController] outlineView];
		LeftNavItem * item = [oV itemAtRow: n];
		LeftNavDataSource * oDS = (LeftNavDataSource *) [oV dataSource];
		NSString * displayName = [oDS outlineView: oV displayNameForTableColumn: nil byItem: item];
		NSDictionary * dict = [oDS rowsByDisplayName];
		NSNumber * ix = [dict objectForKey: displayName];
		if (  ix  ) {
			n = [ix intValue];
		} else {
            return; // No configurations
		}
	} else {
		n = [[configurationsPrefsView leftNavTableView] selectedRow];
	}
		
    [self setSelectedLeftNavListIndex: (unsigned) n];
}

-(void) setSelectedLeftNavListIndex: (NSUInteger) newValue
{
    if (  newValue != selectedLeftNavListIndex  ) {
        
        // Don't allow selection of a "folder" row, only of a "configuration" row
        while (  [[leftNavDisplayNames objectAtIndex: (unsigned) newValue] length] == 0) {
            ++newValue;
        }
        
        if (  selectedLeftNavListIndex != NSNotFound  ) {
            VPNConnection * connection = [self selectedConnection];
            [connection stopMonitoringLogFiles];
        }
        
        selectedLeftNavListIndex = newValue;
        [[configurationsPrefsView leftNavTableView] selectRowIndexes: [NSIndexSet indexSetWithIndex: (unsigned) newValue] byExtendingSelection: NO];
        
		// Set name and status of the new connection in the window title.
		VPNConnection* newConnection = [self selectedConnection];
        NSString * dispNm = [newConnection displayName];
		
		BOOL savedDoingSetupOfUI = [((MenuController *)[NSApp delegate]) doingSetupOfUI];
		[((MenuController *)[NSApp delegate]) setDoingSetupOfUI: TRUE];
		
        [self setupSetNameserver:           newConnection];
        [self setupRouteAllTraffic:         newConnection];
        [self setupCheckIPAddress:          newConnection];
        [self setupResetPrimaryInterface:   newConnection];
        [self setupDisableIpv6OnTun:                    newConnection];
        [self setupNetworkMonitoring:       newConnection];
		[self setupPerConfigOpenvpnVersion: newConnection];
        
        [self validateDetailsWindowControls];
		
		[((MenuController *)[NSApp delegate]) setDoingSetupOfUI: savedDoingSetupOfUI];
                
        [dispNm retain];
        [previouslySelectedNameOnLeftNavList release];
        previouslySelectedNameOnLeftNavList = dispNm;
        [gTbDefaults setObject: dispNm forKey: @"leftNavSelectedDisplayName"];
        
        [settingsSheetWindowController setConfigurationName: dispNm];
        
        [newConnection startMonitoringLogFiles];
    }
}

//***************************************************************************************************************

-(void) setupUpdatesCheckboxes {
	
    // Set values for the update checkboxes
	
	if (  [gTbDefaults boolForKey:@"inhibitOutboundTunneblickTraffic"]  ) {
		NSButton * checkbox = [generalPrefsView updatesCheckAutomaticallyCheckbox];
		[checkbox setState:   NSOffState];
		[checkbox setEnabled: NO];
		
	} else {
		[self setValueForCheckbox: [generalPrefsView updatesCheckAutomaticallyCheckbox]
					preferenceKey: @"updateCheckAutomatically"
						 inverted: NO
					   defaultsTo: FALSE];
    }
	
	[self setValueForCheckbox: [generalPrefsView updatesCheckForBetaUpdatesCheckbox]
				preferenceKey: @"updateCheckBetas"
					 inverted: NO
				   defaultsTo: runningABetaVersion()];
	
	[self setValueForCheckbox: [generalPrefsView updatesSendProfileInfoCheckbox]
				preferenceKey: @"updateSendProfileInfo"
					 inverted: NO
				   defaultsTo: FALSE];
    
    // Set the last update date/time
    [self updateLastCheckedDate];

}

-(void) setupGeneralView
{
	[((MenuController *)[NSApp delegate]) setOurPreferencesFromSparkles]; // Sparkle may have changed it's preferences so we update ours
	
	[self setValueForCheckbox: [generalPrefsView inhibitOutboundTBTrafficCheckbox]
				preferenceKey: @"inhibitOutboundTunneblickTraffic"
					 inverted: NO
				   defaultsTo: FALSE];
	
	[self setupUpdatesCheckboxes];
	
    // Select the keyboard shortcut
    
    unsigned kbsCount = [[[generalPrefsView keyboardShortcutArrayController] content] count];
    unsigned kbsIx = [gTbDefaults unsignedIntForKey: @"keyboardShortcutIndex"
                                            default: 1 /* F1  key */
                                                min: 0 /* (none) */
                                                max: kbsCount];
    
    [self setSelectedKeyboardShortcutIndex: [NSNumber numberWithUnsignedInt: kbsIx]];
    
    [[generalPrefsView keyboardShortcutButton] setEnabled: [gTbDefaults canChangeValueForKey: @"keyboardShortcutIndex"]];
    
    // Select the log size
    
    unsigned prefSize = gMaximumLogSize;
    
    NSUInteger logSizeIx = NSNotFound;
    NSArrayController * ac = [generalPrefsView maximumLogSizeArrayController];
    NSArray * list = [ac content];
    unsigned i;
    for (  i=0; i<[list count]; i++  ) {
        NSDictionary * dict = [list objectAtIndex: i];
        NSString * listValue = [dict objectForKey: @"value"];
        unsigned listValueSize;
        if (  [listValue respondsToSelector:@selector(intValue)]  ) {
            listValueSize = [listValue unsignedIntValue];
        } else {
            NSLog(@"'value' entry in %@ is invalid.", dict);
            listValueSize = NSNotFound;
        }
        
        if (  listValueSize == prefSize  ) {
            logSizeIx = i;
            break;
        }
        
        if (  listValueSize > prefSize  ) {
            logSizeIx = i;
            NSLog(@"'maxLogDisplaySize' preference is invalid.");
            break;
        }
    }
    
    if (  logSizeIx == NSNotFound  ) {
        NSLog(@"'maxLogDisplaySize' preference value of %u is not available", prefSize);
        logSizeIx = 2;  // Second one should be '102400'
    }
    
    if (  logSizeIx < [list count]  ) {
        [self setSelectedMaximumLogSizeIndex: tbNumberWithUnsignedInteger(logSizeIx)];
    } else {
        NSLog(@"Invalid selectedMaximumLogSizeIndex %lu; maximum is %ld", (unsigned long)logSizeIx, (long) [list count]-1);
    }
    
    [[generalPrefsView maximumLogSizeButton] setEnabled: [gTbDefaults canChangeValueForKey: @"maxLogDisplaySize"]];
}

-(void) updateLastCheckedDate
{
    NSDate * lastCheckedDate = [gTbDefaults dateForKey: @"SULastCheckTime"];
    NSString * lastChecked = (  lastCheckedDate
                              ? [lastCheckedDate descriptionWithCalendarFormat: @"%Y-%m-%d %H:%M" timeZone: nil locale: [[NSUserDefaults standardUserDefaults] dictionaryRepresentation]]
                              : NSLocalizedString(@"(Never checked)", @"Window text"));
    [[generalPrefsView updatesLastCheckedTFC] setTitle: [NSString stringWithFormat:
                                                         NSLocalizedString(@"Last checked: %@", @"Window text"),
                                                         lastChecked]];
}


-(IBAction) updatesSendProfileInfoCheckboxWasClicked: (NSButton *) sender
{
    SUUpdater * updater = [((MenuController *)[NSApp delegate]) updater];
    if (  [updater respondsToSelector: @selector(setSendsSystemProfile:)]  ) {
        [((MenuController *)[NSApp delegate]) setOurPreferencesFromSparkles]; // Sparkle may have changed it's preferences so we update ours
        BOOL newValue = [sender state] == NSOnState;
        [gTbDefaults setBool: newValue forKey: @"updateSendProfileInfo"];
        [updater setSendsSystemProfile: newValue];
    } else {
        NSLog(@"'Send anonymous profile information when checking' change ignored because Sparkle Updater does not respond to setSendsSystemProfile:");
    }
}


-(IBAction) inhibitOutboundTBTrafficCheckboxWasClicked: (NSButton *) sender
{
	[gTbDefaults setBool: [sender state] forKey: @"inhibitOutboundTunneblickTraffic"];
	
	[self setupUpdatesCheckboxes];
	[self setupCheckIPAddress: nil];
	
    SUUpdater * updater = [((MenuController *)[NSApp delegate]) updater];
    if (  [updater respondsToSelector: @selector(setAutomaticallyChecksForUpdates:)]  ) {
        [((MenuController *)[NSApp delegate]) setOurPreferencesFromSparkles]; // Sparkle may have changed it's preferences so we update ours
 		[((MenuController *)[NSApp delegate]) setupUpdaterAutomaticChecks];
    } else {
        NSLog(@"'Inhibit automatic update checking and IP address checking' change ignored because the updater does not respond to setAutomaticallyChecksForUpdates:");
	}
}


-(IBAction) updatesCheckAutomaticallyCheckboxWasClicked: (NSButton *) sender
{
    SUUpdater * updater = [((MenuController *)[NSApp delegate]) updater];
    if (  [updater respondsToSelector: @selector(setAutomaticallyChecksForUpdates:)]  ) {
        [((MenuController *)[NSApp delegate]) setOurPreferencesFromSparkles]; // Sparkle may have changed it's preferences so we update ours
		
        [gTbDefaults setBool: [sender state] forKey: @"updateCheckAutomatically"];
		[((MenuController *)[NSApp delegate]) setupUpdaterAutomaticChecks];
    } else {
        NSLog(@"'Automatically Check for Updates' change ignored because the updater does not respond to setAutomaticallyChecksForUpdates:");
    }
}


-(IBAction) updatesCheckForBetaUpdatesCheckboxWasClicked: (NSButton *) sender
{
    [gTbDefaults setBool: [sender state] forKey: @"updateCheckBetas"];
    
    [((MenuController *)[NSApp delegate]) changedCheckForBetaUpdatesSettings];
}


-(IBAction) updatesCheckNowButtonWasClicked: (id) sender
{
	(void) sender;
	
    [((MenuController *)[NSApp delegate]) checkForUpdates: self];
    [self updateLastCheckedDate];
}


-(IBAction) resetDisabledWarningsButtonWasClicked: (id) sender
{
	(void) sender;
	
    NSString * key;
    NSEnumerator * arrayEnum = [gProgramPreferences objectEnumerator];
    while (   (key = [arrayEnum nextObject])  ) {
        if (  [key hasPrefix: @"skipWarning"]  ) {
            if (  [gTbDefaults preferenceExistsForKey: key]  ) {
                if (  [gTbDefaults canChangeValueForKey: key]  ) {
                    [gTbDefaults removeObjectForKey: key];
                }
            }
        }
    }
    
    arrayEnum = [gConfigurationPreferences objectEnumerator];
    while (  (key = [arrayEnum nextObject])  ) {
        if (  [key hasPrefix: @"-skipWarning"]  ) {
            [gTbDefaults removeAllObjectsWithSuffix: key];
        }
    }
}


-(IBAction) generalHelpButtonWasClicked: (id) sender
{
	(void) sender;
	
    MyGotoHelpPage(@"preferences-general.html", nil);
}


-(void) setSelectedKeyboardShortcutIndex: (NSNumber *) newValue
{
    if (  [newValue isNotEqualTo: [self selectedKeyboardShortcutIndex]]  ) {
        NSArrayController * ac = [generalPrefsView keyboardShortcutArrayController];
        NSArray * list = [ac content];
        if (  tbUnsignedIntegerValue(newValue) < [list count]  ) {
            
            [self setSelectedKeyboardShortcutIndexDirect: newValue];
            
            // Select the new size
            [ac setSelectionIndex: tbUnsignedIntegerValue(newValue)];
            
            // Set the preference
            [gTbDefaults setObject: newValue forKey: @"keyboardShortcutIndex"];
            
            // Set the value we use
            [((MenuController *)[NSApp delegate]) setHotKeyIndex: [newValue unsignedIntValue]];
        }
    }
}    

-(void) setSelectedMaximumLogSizeIndex: (NSNumber *) newValue
{
    if (  [newValue isNotEqualTo: [self selectedMaximumLogSizeIndex]]  ) {
        NSArrayController * ac = [generalPrefsView maximumLogSizeArrayController];
        NSArray * list = [ac content];
        if (  tbUnsignedIntegerValue(newValue) < [list count]  ) {
            
            // Set the index
            [self setSelectedMaximumLogSizeIndexDirect: newValue];
            
            // Select the new size
            [ac setSelectionIndex: tbUnsignedIntegerValue(newValue)];
            
            // Set the preference
            NSString * newPref = [[list objectAtIndex: tbUnsignedIntegerValue(newValue)] objectForKey: @"value"];
            [gTbDefaults setObject: newPref forKey: @"maxLogDisplaySize"];
            
            // Set the value we use
            gMaximumLogSize = [newPref unsignedIntValue];
        }
    }
}

//***************************************************************************************************************

-(void) setupAppearanceIconSetButton {
	
    NSString * defaultIconSetName = @"TunnelBlick.TBMenuIcons";
    
    NSString * iconSetToUse = [gTbDefaults stringForKey: @"menuIconSet"];
    if (  ! iconSetToUse  ) {
        iconSetToUse = defaultIconSetName;
    }
    
    // Search popup list for the specified filename and the default
    NSArray * icsContent = [[appearancePrefsView appearanceIconSetArrayController] content];
    unsigned i;
    NSUInteger iconSetIx = NSNotFound;
    unsigned defaultIconSetIx = NSNotFound;
    for (  i=0; i< [icsContent count]; i++  ) {
        NSDictionary * dict = [icsContent objectAtIndex: i];
        NSString * fileName = [dict objectForKey: @"value"];
        if (  [fileName isEqualToString: iconSetToUse]  ) {
            iconSetIx = i;
        }
        if (  [fileName isEqualToString: defaultIconSetName]  ) {
            defaultIconSetIx = i;
        }
    }
	
    if (  iconSetIx == NSNotFound) {
        iconSetIx = defaultIconSetIx;
    }
    
    if (  iconSetIx == NSNotFound  ) {
        if (  [icsContent count] > 0) {
            if (  [iconSetToUse isEqualToString: defaultIconSetName]) {
                NSLog(@"Could not find '%@' icon set or default icon set; using first set found", iconSetToUse);
                iconSetIx = 0;
            } else {
                NSLog(@"Could not find '%@' icon set; using default icon set", iconSetToUse);
                iconSetIx = defaultIconSetIx;
            }
        } else {
            NSLog(@"Could not find any icon sets");
        }
    }
    
    if (  iconSetIx == NSNotFound  ) {
		[NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString(@"(None available)", @"Button"), @"name", @"", @"value", nil];
        [self setSelectedAppearanceIconSetIndex: tbNumberWithUnsignedInteger(0)];
    } else {
        [self setSelectedAppearanceIconSetIndex: tbNumberWithUnsignedInteger(iconSetIx)];
    }
    
    [[appearancePrefsView appearanceIconSetButton] setEnabled: [gTbDefaults canChangeValueForKey: @"menuIconSet"]];
}

-(void) setupAppearanceConnectionWindowDisplayCriteriaButton {
	
    NSString * displayCriteria = [gTbDefaults stringForKey: @"connectionWindowDisplayCriteria"];
    if (  ! displayCriteria  ) {
        displayCriteria = @"showWhenConnecting";
    }
    
    NSUInteger displayCriteriaIx = NSNotFound;
    NSArrayController * ac = [appearancePrefsView appearanceConnectionWindowDisplayCriteriaArrayController];
    NSArray * list = [ac content];
	unsigned i;
    for (  i=0; i<[list count]; i++  ) {
        NSDictionary * dict = [list objectAtIndex: i];
        NSString * preferenceValue = [dict objectForKey: @"value"];
        if (  [preferenceValue isEqualToString: displayCriteria]  ) {
            displayCriteriaIx = i;
            break;
        }
    }
    if (  displayCriteriaIx == NSNotFound  ) {
        NSLog(@"'connectionWindowDisplayCriteria' preference value of '%@' is not available", displayCriteria);
        displayCriteriaIx = 0;  // First one should be 'showWhenConnecting'
    }
    
    if (  displayCriteriaIx < [list count]  ) {
        [self setSelectedAppearanceConnectionWindowDisplayCriteriaIndex: tbNumberWithUnsignedInteger(displayCriteriaIx)];
    } else {
        NSLog(@"Invalid displayCriteriaIx %lu; maximum is %ld", (unsigned long)displayCriteriaIx, (long) [list count]-1);
    }
    
    [[appearancePrefsView appearanceConnectionWindowDisplayCriteriaButton] setEnabled: [gTbDefaults canChangeValueForKey: @"connectionWindowDisplayCriteria"]];
}

-(void) setupDisplayStatisticsWindowCheckbox {
    if (  [[gTbDefaults stringForKey: @"connectionWindowDisplayCriteria"] isEqualToString: @"neverShow"] ) {
        [[appearancePrefsView appearanceDisplayStatisticsWindowsCheckbox] setState: NSOffState];
        [[appearancePrefsView appearanceDisplayStatisticsWindowsCheckbox] setEnabled: NO];
    } else {
        [self setValueForCheckbox: [appearancePrefsView appearanceDisplayStatisticsWindowsCheckbox]
                    preferenceKey: @"doNotShowNotificationWindowOnMouseover"
                         inverted: YES
                       defaultsTo: FALSE];
    }
}    
    
-(void) setupDisplayStatisticsWindowWhenDisconnectedCheckbox {
    if (  [[gTbDefaults stringForKey: @"connectionWindowDisplayCriteria"] isEqualToString: @"neverShow"] ) {
        [[appearancePrefsView appearanceDisplayStatisticsWindowsWhenDisconnectedCheckbox] setState: NSOffState];
        [[appearancePrefsView appearanceDisplayStatisticsWindowsWhenDisconnectedCheckbox] setEnabled: NO];
    } else {
        [self setValueForCheckbox: [appearancePrefsView appearanceDisplayStatisticsWindowsWhenDisconnectedCheckbox]
                    preferenceKey: @"doNotShowDisconnectedNotificationWindows"
                         inverted: YES
                       defaultsTo: FALSE];
    }
}

-(void) setupAppearanceConnectionWindowScreenButton {
	
    [self setSelectedAppearanceConnectionWindowScreenIndexDirect: tbNumberWithUnsignedInteger(NSNotFound)];
	
    NSArray * screens = [((MenuController *)[NSApp delegate]) screenList];
    
    if (   ([screens count] < 2)
		|| ([[self selectedAppearanceConnectionWindowDisplayCriteriaIndex] isEqualTo: tbNumberWithUnsignedInteger(0)]  )  ) {
        
		// Show the default screen, but don't change the preference
		BOOL wereDoingSetupOfUI = [((MenuController *)[NSApp delegate]) doingSetupOfUI];
		[((MenuController *)[NSApp delegate]) setDoingSetupOfUI: TRUE];
        [self setSelectedAppearanceConnectionWindowScreenIndex: tbNumberWithUnsignedInteger(0)];
		[((MenuController *)[NSApp delegate]) setDoingSetupOfUI: wereDoingSetupOfUI];
		
        [[appearancePrefsView appearanceConnectionWindowScreenButton] setEnabled: NO];
		
    } else {
		
        unsigned displayNumberFromPrefs = [gTbDefaults unsignedIntForKey: @"statusDisplayNumber" default: 0 min: 0 max: NSNotFound];
        NSUInteger screenIxToSelect;
        if (  displayNumberFromPrefs == 0 ) {
            screenIxToSelect = 0;   // Screen to use was not specified, use default screen
        } else {
            screenIxToSelect = NSNotFound;
            unsigned i;
            for (  i=0; i<[screens count]; i++) {
                NSDictionary * dict = [screens objectAtIndex: i];
                unsigned displayNumber = [[dict objectForKey: @"DisplayNumber"] unsignedIntValue];
                if (  displayNumber == displayNumberFromPrefs  ) {
                    screenIxToSelect = i+1;
                    break;
                }
            }
            
            if (  screenIxToSelect == NSNotFound) {
                NSLog(@"Display # is not available, using default");
                screenIxToSelect = 0;
            }
        }
        
		NSArrayController * ac = [appearancePrefsView appearanceConnectionWindowScreenArrayController];
		NSArray * list = [ac content];
        if (  screenIxToSelect >= [list count]  ) {
            NSLog(@"Invalid screenIxToSelect %lu; maximum is %ld", (unsigned long)screenIxToSelect, (long) [list count]-1);
            screenIxToSelect = 0;
        }
        
        [self setSelectedAppearanceConnectionWindowScreenIndex: tbNumberWithUnsignedInteger(screenIxToSelect)];
        
        [[appearancePrefsView appearanceConnectionWindowScreenButton] setEnabled: [gTbDefaults canChangeValueForKey: @"statusDisplayNumber"]];
    }
}

-(void) setupAppearancePlaceIconNearSpotlightCheckbox {
    
    if (   mustPlaceIconInStandardPositionInStatusBar()  ) {
        NSButton * checkbox = [appearancePrefsView appearancePlaceIconNearSpotlightCheckbox];
        [checkbox setState:   NO];
        [checkbox setEnabled: NO];
    } else {
        [self setValueForCheckbox: [appearancePrefsView appearancePlaceIconNearSpotlightCheckbox]
                    preferenceKey: @"placeIconInStandardPositionInStatusBar"
                         inverted: YES
                       defaultsTo: FALSE];
    }
    
}

-(void) setupAppearanceView
{
	[self setupAppearanceIconSetButton];
    
    [self setupAppearancePlaceIconNearSpotlightCheckbox];

    [self setValueForCheckbox: [appearancePrefsView appearanceDisplayConnectionSubmenusCheckbox]
                preferenceKey: @"doNotShowConnectionSubmenus"
                     inverted: YES
                   defaultsTo: FALSE];
    
    [self setValueForCheckbox: [appearancePrefsView appearanceDisplayConnectionTimersCheckbox]
                preferenceKey: @"showConnectedDurations"
                     inverted: NO
                   defaultsTo: FALSE];
    
    [self setValueForCheckbox: [appearancePrefsView appearanceDisplaySplashScreenCheckbox]
                preferenceKey: @"doNotShowSplashScreen"
                     inverted: YES
                   defaultsTo: FALSE];
    
	[self setupAppearanceConnectionWindowDisplayCriteriaButton];
    
    // Note: setupAppearanceConnectionWindowScreenButton,
    //       setupDisplayStatisticsWindowCheckbox, and
    //       setupAppearanceDisplayStatisticsWindowsWhenDisconnectedCheckbox
	// are invoked by setSelectedAppearanceConnectionWindowDisplayCriteriaIndex,
	//                which is invoked by setupAppearanceConnectionWindowDisplayCriteriaButton
}

-(IBAction) appearanceDisplayConnectionSubmenusCheckboxWasClicked: (NSButton *) sender
{
    [gTbDefaults setBool: ! [sender state] forKey:@"doNotShowConnectionSubmenus"];
    [((MenuController *)[NSApp delegate]) changedDisplayConnectionSubmenusSettings];
}

-(IBAction) appearanceDisplayConnectionTimersCheckboxWasClicked: (NSButton *) sender
{
    [gTbDefaults setBool: [sender state]  forKey:@"showConnectedDurations"];
    [((MenuController *)[NSApp delegate]) changedDisplayConnectionTimersSettings];
}

-(IBAction) appearanceDisplaySplashScreenCheckboxWasClicked: (NSButton *) sender
{
	[gTbDefaults setBool: ! [sender state] forKey:@"doNotShowSplashScreen"];
}

-(IBAction) appearancePlaceIconNearSpotlightCheckboxWasClicked: (NSButton *) sender
{
	[gTbDefaults setBool: ! [sender state] forKey:@"placeIconInStandardPositionInStatusBar"];
    [((MenuController *)[NSApp delegate]) recreateStatusItemAndMenu];
}

-(IBAction) appearanceDisplayStatisticsWindowsCheckboxWasClicked: (NSButton *) sender
{
	[gTbDefaults setBool: ! [sender state] forKey:@"doNotShowNotificationWindowOnMouseover"];
    [[((MenuController *)[NSApp delegate]) ourMainIconView] changedDoNotShowNotificationWindowOnMouseover];
}

-(IBAction) appearanceDisplayStatisticsWindowWhenDisconnectedCheckboxWasClicked: (NSButton *) sender
{
	[gTbDefaults setBool: ! [sender state] forKey:@"doNotShowDisconnectedNotificationWindows"];
    [[((MenuController *)[NSApp delegate]) ourMainIconView] changedDoNotShowNotificationWindowOnMouseover];
}

-(IBAction) appearanceHelpButtonWasClicked: (id) sender
{
	(void) sender;
	
    MyGotoHelpPage(@"preferences-appearance.html", nil);
}

-(void) setSelectedAppearanceIconSetIndex: (NSNumber *) newValue
{
    if (  [newValue isNotEqualTo: [self selectedAppearanceIconSetIndex]]  ) {
        NSArrayController * ac = [appearancePrefsView appearanceIconSetArrayController];
        NSArray * list = [ac content];
        if (  tbUnsignedIntegerValue(newValue) < [list count]  ) {
            
            [self setSelectedAppearanceIconSetIndexDirect: newValue];
            
            // Select the new index
            [ac setSelectionIndex: tbUnsignedIntegerValue(newValue)];
            
            // Set the preference
            if (  tbUnsignedIntegerValue(newValue) != NSNotFound  ) {
                // Set the preference
                NSString * iconSetName = [[[list objectAtIndex: tbUnsignedIntegerValue(newValue)] objectForKey: @"value"] lastPathComponent];
                if (  [iconSetName isEqualToString: @"TunnelBlick.TBMenuIcons"]  ) {
                    [gTbDefaults removeObjectForKey: @"menuIconSet"];
                } else {
                    [gTbDefaults setObject: iconSetName forKey: @"menuIconSet"];
                }
            }
            
            // Start using the new setting
			if (  ! [((MenuController *)[NSApp delegate]) loadMenuIconSet]  ) {
				NSLog(@"Unable to load the Menu icon set");
				[((MenuController *)[NSApp delegate]) terminateBecause: terminatingBecauseOfError];
			}
        }
    }
}


-(void) setSelectedAppearanceConnectionWindowDisplayCriteriaIndex: (NSNumber *) newValue
{
    if (  [newValue isNotEqualTo: [self selectedAppearanceConnectionWindowDisplayCriteriaIndex]]  ) {
        NSArrayController * ac = [appearancePrefsView appearanceConnectionWindowDisplayCriteriaArrayController];
        NSArray * list = [ac content];
        if (  tbUnsignedIntegerValue(newValue) < [list count]  ) {
            
            [self setSelectedAppearanceConnectionWindowDisplayCriteriaIndexDirect: newValue];
            
            // Select the new index
            [ac setSelectionIndex: tbUnsignedIntegerValue(newValue)];
            
            // Set the preference
            NSDictionary * dict = [list objectAtIndex: tbUnsignedIntegerValue(newValue)];
            NSString * preferenceValue = [dict objectForKey: @"value"];
            [gTbDefaults setObject: preferenceValue forKey: @"connectionWindowDisplayCriteria"];
            
            [self setupDisplayStatisticsWindowCheckbox];
            [self setupDisplayStatisticsWindowWhenDisconnectedCheckbox];
			[self setupAppearanceConnectionWindowScreenButton];
        }
    }
}


-(void) setSelectedAppearanceConnectionWindowScreenIndex: (NSNumber *) newValue
{
    if (  [newValue isNotEqualTo: [self selectedAppearanceConnectionWindowScreenIndex]]  ) {
        NSArrayController * ac = [appearancePrefsView appearanceConnectionWindowScreenArrayController];
        NSArray * list = [ac content];
        if (  tbUnsignedIntegerValue(newValue) < [list count]  ) {
            
            [self setSelectedAppearanceConnectionWindowScreenIndexDirect: newValue];
            
            // Select the new size
            [ac setSelectionIndex: tbUnsignedIntegerValue(newValue)];
            
            // Set the preference if this isn't just the initialization
            if (  ! [((MenuController *)[NSApp delegate]) doingSetupOfUI]  ) {
                // Set the preference
                NSNumber * displayNumber = [[list objectAtIndex: tbUnsignedIntegerValue(newValue)] objectForKey: @"value"];
				[gTbDefaults setObject: displayNumber forKey: @"statusDisplayNumber"];
            }
        }
    }
}


-(IBAction) infoHelpButtonWasClicked: (id) sender
{
	(void) sender;
	
    MyGotoHelpPage(@"info.html", nil);
}


//***************************************************************************************************************

-(void) setupInfoView
{
}

//***************************************************************************************************************

-(void) setupUtilitiesView
{
}

-(IBAction) utilitiesRunEasyRsaButtonWasClicked: (id) sender
{
	(void) sender;
	
    NSString * userPath = easyRsaPathToUse(YES);
    if (  ! userPath  ) {
        NSLog(@"utilitiesRunEasyRsaButtonWasClicked: no easy-rsa folder!");
        [[utilitiesPrefsView utilitiesRunEasyRsaButton] setEnabled: NO];
        return;
    }
    
    openTerminalWithEasyRsaFolder(userPath);
}

-(IBAction) utilitiesOpenUninstallInstructionsButtonWasClicked: (id) sender
{
	(void) sender;
	
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://www.tunnelblick.net/uninstall.html"]];
}

-(IBAction) utilitiesKillAllOpenVpnButtonWasClicked: (id) sender
{
	(void) sender;
	
	if (  ! ALLOW_OPENVPNSTART_KILLALL  ) {
		return;
	}
	
    NSArray  * arguments = [NSArray arrayWithObject: @"killall"];
    OSStatus status = runOpenvpnstart(arguments, nil, nil);
    if (  status == EXIT_SUCCESS  ) {
        TBShowAlertWindow(NSLocalizedString(@"Warning!", @"Window title"),
                          NSLocalizedString(@"All OpenVPN process were terminated.", @"Window title"));
    } else {
        TBShowAlertWindow(NSLocalizedString(@"Warning!", @"Window title"),
                          NSLocalizedString(@"One or more OpenVPN processes could not be terminated.", @"Window title"));
    }
}

-(IBAction) utilitiesCopyConsoleLogButtonWasClicked: (id) sender {
	
	(void) sender;
	
	// Get OS and Tunnelblick version info
	NSString * versionContents = [[((MenuController *)[NSApp delegate]) openVPNLogHeader] stringByAppendingString:
								  (isUserAnAdmin()
								   ? @"; Admin user"
								   : @"; Standard user")];
	
	// Get tail of Console log
	NSString * consoleContents;
	if (  runningOnLeopardOrNewer()  ) {
		consoleContents = [self stringContainingRelevantConsoleLogEntries];
	} else {
		consoleContents = [self tigerConsoleContents];
	}
	
	NSString * output = [NSString stringWithFormat:
						 @"%@\n\nConsole Log:\n\n%@",
						 versionContents, consoleContents];
	
	NSPasteboard * pb = [NSPasteboard generalPasteboard];
	[pb declareTypes: [NSArray arrayWithObject: NSStringPboardType] owner: self];
	[pb setString: output forType: NSStringPboardType];
}

-(IBAction) utilitiesHelpButtonWasClicked: (id) sender
{
	(void) sender;
	
    MyGotoHelpPage(@"preferences-utilities.html", nil);
}

//***************************************************************************************************************

-(void) setValueForCheckbox: (NSButton *) checkbox
              preferenceKey: (NSString *) preferenceKey
                   inverted: (BOOL)       inverted
                 defaultsTo: (BOOL)       defaultsTo
{
    if (  checkbox  ) {
        BOOL value = (  defaultsTo
                      ? [gTbDefaults boolWithDefaultYesForKey: preferenceKey]
                      : [gTbDefaults boolForKey: preferenceKey]
                      );
        
        if (  inverted  ) {
            value = ! value;
        }
        
        [checkbox setState: (  value
                             ? NSOnState
                             : NSOffState)];
        [checkbox setEnabled: [gTbDefaults canChangeValueForKey: preferenceKey]];
    }
}

-(NSTextView *) logView
{
    return [configurationsPrefsView logView];
}

@end
