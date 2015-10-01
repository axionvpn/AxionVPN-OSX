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


#import "SettingsSheetWindowController.h"

#import "defines.h"
#import "helper.h"
#import "sharedRoutines.h"

#import "MenuController.h"
#import "MyPrefsWindowController.h"
#import "TBUserDefaults.h"
#import "VPNConnection.h"

extern NSString             * gPrivatePath;
extern NSFileManager        * gFileMgr;
extern TBUserDefaults       * gTbDefaults;


@interface SettingsSheetWindowController()    // Private methods

//**********************************************************************************************************************************
// Methods that set up static content (content that is the same for all connections)

-(void) initializeStaticContent;

//**********************************************************************************************************************************
// Methods that set up up content that depends on a connection's settings

// Overall set up
-(void) setupSettingsFromPreferences;

// Methods for setting up specific types of information

-(void) setupCheckbox: (NSButton *) checkbox
                  key: (NSString *) key
             inverted: (BOOL) inverted;

-(void) setupMonitoringOptions;

-(NSInteger) indexForMonitoringOptionButton: (NSPopUpButton *) button
                              newPreference: (NSString *)      preference
                              oldPreference: (NSString *)      oldPreference
                      leasewatchOptionsChar: (NSString *)      leasewatchOptionsChar;
@end


@implementation SettingsSheetWindowController

TBSYNTHESIZE_NONOBJECT_GET(BOOL, showingSettingsSheet)

TBSYNTHESIZE_OBJECT(retain, VPNConnection *, connection,                setConnection)

TBSYNTHESIZE_OBJECT(retain, NSArray *,  removeNamedCredentialsNames,    setRemoveNamedCredentialsNames)

TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedDnsServersIndex,        setSelectedDnsServersIndexDirect)
TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedDomainIndex,            setSelectedDomainIndexDirect)
TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedSearchDomainIndex,      setSelectedSearchDomainIndexDirect)
TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedWinsServersIndex,       setSelectedWinsServersIndexDirect)
TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedNetBiosNameIndex,       setSelectedNetBiosNameIndexDirect)
TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedWorkgroupIndex,         setSelectedWorkgroupIndexDirect)

TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedOtherdnsServersIndex,   setSelectedOtherdnsServersIndexDirect)
TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedOtherdomainIndex,       setSelectedOtherdomainIndexDirect)
TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedOthersearchDomainIndex, setSelectedOthersearchDomainIndexDirect)
TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedOtherwinsServersIndex,  setSelectedOtherwinsServersIndexDirect)
TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedOthernetBiosNameIndex,  setSelectedOthernetBiosNameIndexDirect)
TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedOtherworkgroupIndex,    setSelectedOtherworkgroupIndexDirect)

TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedCredentialsGroupIndex,  setSelectedCredentialsGroupIndexDirect)

TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedSoundOnConnectIndex,          setSelectedSoundOnConnectIndexDirect)
TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedSoundOnDisconnectIndex,       setSelectedSoundOnDisconnectIndexDirect)

TBSYNTHESIZE_OBJECT_GET(retain, NSTabViewItem *,     connectingAndDisconnectingTabViewItem)
TBSYNTHESIZE_OBJECT_GET(retain, NSTabViewItem *,     whileConnectedTabViewItem)
TBSYNTHESIZE_OBJECT_GET(retain, NSTabViewItem *,     credentialsTabViewItem)
TBSYNTHESIZE_OBJECT_GET(retain, NSTabViewItem *,     soundTabViewItem)

TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,          allConfigurationsUseTheSameCredentialsCheckbox)

TBSYNTHESIZE_OBJECT_GET(retain, NSBox *,             namedCredentialsBox)

TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,          credentialsGroupButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSArrayController *, credentialsGroupArrayController)

TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,          addNamedCredentialsButton)

TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,          removeNamedCredentialsButton)

TBSYNTHESIZE_OBJECT_GET(retain, NSBox *,             alertSoundsBox)

TBSYNTHESIZE_OBJECT_GET(retain, NSTextFieldCell *,   connectionAlertSoundTFC)
TBSYNTHESIZE_OBJECT_GET(retain, NSTextFieldCell *,   disconnectionAlertSoundTFC)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,          soundOnConnectButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,          soundOnDisconnectButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSArrayController *, soundOnConnectArrayController)
TBSYNTHESIZE_OBJECT_GET(retain, NSArrayController *, soundOnDisconnectArrayController)

-(id) init {
    self = [super initWithWindowNibName:@"SettingsSheet"];
    if (  ! self  ) {
        return nil;
    }
    
    configurationName = nil;
    connection        = nil;

    configurationType = sharedConfiguration;
    
    showingSettingsSheet   = FALSE;
    doNotModifyPreferences = FALSE;
    
    return self;
}

-(void) dealloc {
	
	[configurationName           release]; configurationName           = nil;
	[connection                  release]; connection                  = nil;
	[removeNamedCredentialsNames release]; removeNamedCredentialsNames = nil;
	
	[super dealloc];
}

-(void) setConfigurationName: (NSString *) newName {
    
    if (  ! [configurationName isEqualToString: newName]  ) {
        [configurationName release];
        configurationName = [newName retain];
		
		if (  newName  ) {
			[self setConnection: [[((MenuController *)[NSApp delegate]) myVPNConnectionDictionary] objectForKey: configurationName]];
		} else {
			[self setConnection: nil];
		}
		
		if (  showingSettingsSheet  ) {
			[self initializeStaticContent];
			[self setupSettingsFromPreferences];
		}
	}
}


-(BOOL) usingSetNameserver {
    
    if (  ! configurationName  ) {
        return FALSE;
    }
    
    NSString * key = [configurationName stringByAppendingString: @"useDNS"];
    unsigned ix = [gTbDefaults unsignedIntForKey: key
                                         default: 1
                                             min: 0
                                             max: MAX_SET_DNS_WINS_INDEX];
    return (ix == 1);
}

- (void) setupCredentialsGroupButton {
    
    if (  ! configurationName  ) {
        return;
    }
    
	BOOL savedDoingSetupOfUI = [((MenuController *)[NSApp delegate]) doingSetupOfUI];
	[((MenuController *)[NSApp delegate]) setDoingSetupOfUI: TRUE];
	
	[self setSelectedCredentialsGroupIndexDirect: tbNumberWithUnsignedInteger(NSNotFound)];
	
	NSInteger ix = 0;
	NSString * prefKey = [configurationName stringByAppendingString: @"-credentialsGroup"];
	NSString * group = [gTbDefaults stringForKey: prefKey];
	if (   [group length] != 0  ) {
        NSArray * listContent = [credentialsGroupArrayController content];
        NSDictionary * dict;
        unsigned i;
        ix = NSNotFound;
        for (  i=0; i<[listContent count]; i++  ) { 
            dict = [listContent objectAtIndex: i];
            if (  [[dict objectForKey: @"value"] isEqualToString: group]  ) {
                ix = (int)i;
                break;
            }
        }
        
        if (  ix == NSNotFound  ) {
            NSLog(@"Preference '%@' ignored: credentials group '%@' was not found", prefKey, group);
            ix = 0;
        }
	}
	
	[self setSelectedCredentialsGroupIndex: tbNumberWithUnsignedInteger(ix)];
	[credentialsGroupButton setEnabled: (   ( ! [gTbDefaults stringForKey: @"namedCredentialsThatAllConfigurationsUse"] )
                                         && [gTbDefaults canChangeValueForKey: prefKey])];
	
	[((MenuController *)[NSApp delegate]) setDoingSetupOfUI: savedDoingSetupOfUI];
}

- (void) setupPrependDomainNameCheckbox {
    
    if (  ! configurationName  ) {
        return;
    }
    
    NSString * key = [configurationName stringByAppendingString: @"useDNS"];
    unsigned ix = [gTbDefaults unsignedIntForKey: key
                                         default: 1
                                             min: 0
                                             max: MAX_SET_DNS_WINS_INDEX];
    
    if (  ix == 1  ) {
        [self setupCheckbox: prependDomainNameCheckbox
                        key: @"-prependDomainNameToSearchDomains"
                   inverted: NO];
    } else {
        [prependDomainNameCheckbox setState: NSOffState];
        [prependDomainNameCheckbox setEnabled: NO];
    }
}

-(void) setupFlushDNSCheckbox {
    
    if (  ! configurationName  ) {
        return;
    }
    
    NSString * key = [configurationName stringByAppendingString: @"useDNS"];
    unsigned ix = [gTbDefaults unsignedIntForKey: key
                                         default: 1
                                             min: 0
                                             max: MAX_SET_DNS_WINS_INDEX];
    
    if (  ix == 1  ) {
        [self setupCheckbox: flushDnsCacheCheckbox
                        key: @"-doNotFlushCache"
                   inverted: YES];
    } else {
        [flushDnsCacheCheckbox setState:   NSOffState];
        [flushDnsCacheCheckbox setEnabled: NO];
    }
}

-(void) setupKeepConnectedCheckbox {
    
    if (  ! configurationName  ) {
        return;
    }
    
    [self setupCheckbox: keepConnectedCheckbox
                    key: @"-keepConnected"
               inverted: NO];
}

-(void) setupEnableIpv6OnTapCheckbox {
    
    if (  ! configurationName  ) {
        return;
    }
    
    NSString * type = [connection tapOrTun];
    if (   ([type rangeOfString: @"tun"].length != 0)
		|| ( ! [self usingSetNameserver] )  ) {
        [enableIpv6OnTapCheckbox setState: NSOffState];
        [enableIpv6OnTapCheckbox setEnabled: NO];
    } else {
        [self setupCheckbox: enableIpv6OnTapCheckbox
                        key: @"-enableIpv6OnTap"
                   inverted: NO];
    }
}

-(void) setupUseRouteUpInsteadOfUpCheckbox {
    
    if (  ! configurationName  ) {
        return;
    }
    
    NSString * key = [configurationName stringByAppendingString: @"useDNS"];
    unsigned ix = [gTbDefaults unsignedIntForKey: key
                                         default: 1
                                             min: 0
                                             max: MAX_SET_DNS_WINS_INDEX];
    
    if (  ix == 1  ) {
        [self setupCheckbox: useRouteUpInsteadOfUpCheckbox
                        key: @"-useRouteUpInsteadOfUp"
                   inverted: NO];
    } else {
        [useRouteUpInsteadOfUpCheckbox setState:   NSOffState];
        [useRouteUpInsteadOfUpCheckbox setEnabled: NO];
    }
}

- (void) setupDisconnectOnSleepCheckbox {
    
    if (  ! connection  ) {
        return;
    }
    
    [self setupCheckbox: disconnectOnSleepCheckbox
                    key: @"-doNotDisconnectOnSleep"
               inverted: YES];
}

- (void) setupReconnectOnWakeFromSleepCheckbox {
    
    if (  ! connection  ) {
        return;
    }
    
    if (  [gTbDefaults boolForKey: [[connection displayName] stringByAppendingString: @"-doNotDisconnectOnSleep"]] ) {
        [reconnectOnWakeFromSleepCheckbox setState:   NSOffState];
        [reconnectOnWakeFromSleepCheckbox setEnabled: NO];
    } else {
        [self setupCheckbox: reconnectOnWakeFromSleepCheckbox
                        key: @"-doNotReconnectOnWakeFromSleep"
                   inverted: YES];
    }
}

- (void) setupRunMtuTestCheckbox {
    
    if (  ! connection  ) {
        return;
    }
    
    [self setupCheckbox: runMtuTestCheckbox
                    key: @"-runMtuTest"
               inverted: NO];
}

- (void) setupTunOrTapButton: (NSPopUpButton *) button key: (NSString *) rawPreferenceKey {
	
    if (  ! connection  ) {
        return;
    }
    
	NSString * key   = [configurationName stringByAppendingString: rawPreferenceKey];
	NSString * value = [gTbDefaults stringForKey: key];
	
	if (   ( ! value)
		|| ( [value length] == 0 )  ) {
		[button selectItemAtIndex: 0];
	} else if (  [value isEqualToString: @"always"]  ) {
		[button selectItemAtIndex: 1];
	} else if (  [value isEqualToString: @"never"]  ) {
		[button selectItemAtIndex: 2];
	} else {
		NSLog(@"setupTunTapButton: Value '%@' for preference '%@' is invalid; assuming 'always'", value, key);
		[button selectItemAtIndex: 1];
	}
}

-(void) setupTunTapButtons {
	[self setupTunOrTapButton: loadTunPopUpButton key: @"-loadTun"];
	[self setupTunOrTapButton: loadTapPopUpButton key: @"-loadTap"];
}

//  Set up a sound popup button from preferences
-(void) setupSoundButton: (NSButton *)          button
         arrayController: (NSArrayController *) ac
              preference: (NSString *)          preference {
    if (   connection
		&& button
		&& ac
		&& preference  ) {
        NSUInteger ix = NSNotFound;
        NSString * key = [[connection displayName] stringByAppendingString: preference];
        NSString * soundName = [gTbDefaults stringForKey: key];
        if (   soundName
            && ( ! [soundName isEqualToString: @"None"] )  ) {
            NSArray * listContent = [ac content];
            NSDictionary * dict;
            unsigned i;
            for (  i=0; i<[listContent count]; i++  ) {  // Look for the sound in the array
                dict = [listContent objectAtIndex: i];
                if (  [[dict objectForKey: @"name"] isEqualToString: soundName]  ) {
                    ix = i;
                    break;
                }
            }
            
            if (  ix == NSNotFound  ) {
                NSLog(@"Preference '%@' ignored: sound '%@' was not found", key, soundName);
                ix = 0;
            }
        } else {
            ix = 0;
        }
        
        //******************************************************************************
        // Don't play sounds because we are just setting the button from the preferences
        BOOL oldDoNotPlaySounds = doNotPlaySounds;
        doNotPlaySounds = TRUE;
        
        if (  button == [self soundOnConnectButton]) {
            [self setSelectedSoundOnConnectIndex:    tbNumberWithUnsignedInteger(ix)];
        } else {
            [self setSelectedSoundOnDisconnectIndex: tbNumberWithUnsignedInteger(ix)];
        }
        
        doNotPlaySounds = oldDoNotPlaySounds;
        //******************************************************************************
        
        BOOL enable = [gTbDefaults canChangeValueForKey: key];
        [button setEnabled: enable];
    } else {
        [[self soundOnConnectButton]             setEnabled: NO];
        [[self soundOnDisconnectButton]          setEnabled: NO];
    }
}

-(void) setupSoundPopUpButtons {
    
    [self setupSoundButton: [self soundOnConnectButton]
           arrayController: [self soundOnConnectArrayController]
                preference: @"-tunnelUpSoundName"];
    
    
    [self setupSoundButton: [self soundOnDisconnectButton]
           arrayController: [self soundOnDisconnectArrayController]
                preference: @"-tunnelDownSoundName"];
}


-(void) showSettingsSheet: (id) sender {
	(void) sender;
	
    [self setupSettingsFromPreferences];
    
    if (  ! settingsSheet  ) {
        [super showWindow: self];
    } else {
        showingSettingsSheet = TRUE;
    }
    
    [[self window] display];
    [[self window] makeKeyAndOrderFront: self];
    [NSApp activateIgnoringOtherApps:YES];
}

-(void) endSettingsSheet:  (id) sender {
    showingSettingsSheet = FALSE;
    [NSApp endSheet: settingsSheet];
    [settingsSheet orderOut: sender];
    [settingsSheet release];
    settingsSheet = nil;
}

-(void) awakeFromNib {
    showingSettingsSheet = TRUE;
    
    [self initializeStaticContent];
    [self setupSettingsFromPreferences];
    [[self window] setReleasedWhenClosed: NO];
}

//**********************************************************************************************************************************

-(void) setTitle: (NSString *) newTitle ofControl: (id) theControl {
	// Sets the title for a control, shifting the origin of the control itself to the left.

    NSRect oldRect = [theControl frame];
    [theControl setTitle: newTitle];
    [theControl sizeToFit];
    
    NSRect newRect = [theControl frame];
    float widthChange = newRect.size.width - oldRect.size.width;
    NSRect oldPos;
    
    if (   [theControl isEqual: addNamedCredentialsButton]  ) {
        oldPos = [theControl frame];
        oldPos.origin.x = oldPos.origin.x - widthChange;
        [theControl setFrame:oldPos];
    }
}

-(void) underlineLabel: tf string: inString alignment: (NSTextAlignment) align {
    NSMutableAttributedString* attrString = [[NSMutableAttributedString alloc] initWithString: inString];
    NSRange range = NSMakeRange(0, [attrString length]);
    
    [attrString beginEditing];
    
    // make the text appear with an underline
    [attrString addAttribute:
     NSUnderlineStyleAttributeName value:[NSNumber numberWithInt:NSSingleUnderlineStyle] range:range];
    
    // make the text appear flush-right
    [attrString setAlignment: align range: range];
    
    [attrString endEditing];
    
    [tf setAttributedStringValue: attrString];
    [attrString release];
}

-(void) initializeDnsWinsPopUp: (NSPopUpButton *) popUpButton arrayController: (NSArrayController *) ac {
    NSArray * content = [NSArray arrayWithObjects:
                         [NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString(@"Ignore"            , @"Button"), @"name", @"ignore" , @"value", nil],
                         [NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString(@"Restore"           , @"Button"), @"name", @"restore", @"value", nil],
                         [NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString(@"Restart connection", @"Button"), @"name", @"restart", @"value", nil],
                         nil];
    [ac setContent: content];
    
    /*
     if (  popUpButton == dnsServersPopUpButton  ) {
     
     // When resize this control, shift the columns that are to its right either left or right to match the size change
     NSRect oldRect = [popUpButton frame];
     [popUpButton sizeToFit];
     NSRect newRect = [popUpButton frame];
     float widthChange = newRect.size.width - oldRect.size.width;
     
     NSArray * stuffToShift = [NSArray arrayWithObjects:
     whenChangesToAnythingElseTF,
     otherdnsServersPopUpButton,
     otherdomainPopUpButton,
     othersearchDomainPopUpButton,
     otherwinsServersPopUpButton,
     othernetBiosNamePopUpButton,
     otherworkgroupPopUpButton,
     nil];
     NSEnumerator * arrayEnum = [stuffToShift objectEnumerator];
     id control;
     while (  (control = [arrayEnum nextObject])  ) {
     NSRect oldPos;
     oldPos = [control frame];
     oldPos.origin.x = oldPos.origin.x + widthChange;
     [control setFrame:oldPos];
     }
     } else {
     */
    [popUpButton sizeToFit];
    /*
     }
     */
}

-(void) initializeSoundPopUpButtons {
	
    NSArray * soundsSorted = [((MenuController *)[NSApp delegate]) sortedSounds];
    
    // Create an array of dictionaries of sounds. (Don't get the actual sounds, just the names of the sounds)
    NSMutableArray * soundsDictionaryArray = [NSMutableArray arrayWithCapacity: [soundsSorted count]];
    
    [soundsDictionaryArray addObject: [NSDictionary dictionaryWithObjectsAndKeys:
                                       NSLocalizedString(@"No sound", @"Button"), @"name",
                                       @"None", @"value", nil]];
    
    [soundsDictionaryArray addObject: [NSDictionary dictionaryWithObjectsAndKeys:
                                       NSLocalizedString(@"Speak", @"Button"), @"name",
                                       @"Speak", @"value", nil]];
    
    unsigned i;
    for (  i=0; i<[soundsSorted count]; i++  ) {
        [soundsDictionaryArray addObject: [NSDictionary dictionaryWithObjectsAndKeys:
                                           [soundsSorted objectAtIndex: i], @"name",
                                           [soundsSorted objectAtIndex: i], @"value", nil]];
    }
    
	NSArrayController * connectController = [self soundOnConnectArrayController];
    [connectController setContent: soundsDictionaryArray];
	NSArrayController * disconnectController = [self soundOnDisconnectArrayController];
    [disconnectController setContent: soundsDictionaryArray];
}

-(void) initializeStaticContent {
    
    // For Connecting tab
	
    [connectingAndDisconnectingTabViewItem  setLabel: NSLocalizedString(@"Connecting & Disconnecting", @"Window title")];
    
    [flushDnsCacheCheckbox                  setTitle: NSLocalizedString(@"Flush DNS cache after connecting or disconnecting",                                   @"Checkbox name")];
    [keepConnectedCheckbox                  setTitle: NSLocalizedString(@"Keep connected",                                                                      @"Checkbox name")];
    [enableIpv6OnTapCheckbox                setTitle: NSLocalizedString(@"Enable IPv6 (tap only)",                                                              @"Checkbox name")];
    [useRouteUpInsteadOfUpCheckbox          setTitle: NSLocalizedString(@"Set DNS after routes are set instead of before routes are set",                       @"Checkbox name")];
    [prependDomainNameCheckbox              setTitle: NSLocalizedString(@"Prepend domain name to search domains",                                               @"Checkbox name")];
    [disconnectOnSleepCheckbox              setTitle: NSLocalizedString(@"Disconnect when computer goes to sleep",                                              @"Checkbox name")];
    [reconnectOnWakeFromSleepCheckbox       setTitle: NSLocalizedString(@"Reconnect when computer wakes from sleep (if connected when computer went to sleep)", @"Checkbox name")];
    [runMtuTestCheckbox                     setTitle: NSLocalizedString(@"Run MTU maximum size test after connecting",                                          @"Checkbox name")];
    
    [sleepWakeBox                           setTitle: NSLocalizedString(@"Computer sleep/wake",                        @"Window text")];
    [disconnectOnSleepCheckbox              setTitle: NSLocalizedString(@"Disconnect when computer goes to sleep",     @"Checkbox name")];
    [disconnectOnSleepCheckbox              sizeToFit];
    [reconnectOnWakeFromSleepCheckbox       setTitle: NSLocalizedString(@"Reconnect when computer wakes up",           @"Checkbox name")];
    [reconnectOnWakeFromSleepCheckbox       sizeToFit];
	[ifConnectedWhenComputerWentToSleepTFC  setTitle: NSLocalizedString(@"(if connected when computer went to sleep)", @"Window text")];
    [ifConnectedWhenComputerWentToSleepTF   sizeToFit];
	
    [fastUserSwitchingBox                   setTitle: NSLocalizedString(@"Fast User Switching",                   @"Window text")];
    [disconnectWhenUserSwitchesOutCheckbox  setTitle: NSLocalizedString(@"Disconnect when user switches out",     @"Checkbox name")];
    [disconnectWhenUserSwitchesOutCheckbox  sizeToFit];
    [reconnectWhenUserSwitchesInCheckbox    setTitle: NSLocalizedString(@"Reconnect when user switches in"  ,     @"Checkbox name")];
    [reconnectWhenUserSwitchesInCheckbox    sizeToFit];
	[ifConnectedWhenUserSwitchedOutTFC      setTitle: NSLocalizedString(@"(if connected when user switched out)", @"Window text")];
    [ifConnectedWhenUserSwitchedOutTF       sizeToFit];
	
    [loadTunAutomaticallyMenuItem setTitle: NSLocalizedString(@"Load Tun driver automatically", @"Button")];
    [loadTunAlwaysMenuItem        setTitle: NSLocalizedString(@"Always load Tun driver",        @"Button")];
    [loadTunNeverMenuItem         setTitle: NSLocalizedString(@"Never load Tun driver",         @"Button")];
	
    [loadTapAutomaticallyMenuItem setTitle: NSLocalizedString(@"Load Tap driver automatically", @"Button")];
    [loadTapAlwaysMenuItem        setTitle: NSLocalizedString(@"Always load Tap driver",        @"Button")];
    [loadTapNeverMenuItem         setTitle: NSLocalizedString(@"Never load Tap driver",         @"Button")];
	
	// Set both the tun and tap buttons to the width of the wider one
    [loadTunPopUpButton sizeToFit];
    [loadTapPopUpButton sizeToFit];
	NSRect newTun = [loadTunPopUpButton frame];
	NSRect newTap = [loadTapPopUpButton frame];
	if (  newTun.size.width > newTap.size.width  ) {
		newTap.size.width = newTun.size.width;
	} else {
		newTun.size.width = newTap.size.width;
	}
	[loadTunPopUpButton setFrame: newTun];
	[loadTapPopUpButton setFrame: newTap];
	
    // For WhileConnected tab
    
    [whileConnectedTabViewItem        setLabel: NSLocalizedString(@"While Connected", @"Window title")];

    [monitorNetworkForChangesCheckbox setTitle: NSLocalizedString(@"Monitor network settings", @"Checkbox name")];
    
    [self underlineLabel: networkSettingTF            string: NSLocalizedString(@"Network setting"              , @"Window text") alignment: NSRightTextAlignment];
    [self underlineLabel: whenChangesToPreVpnValueTF  string: NSLocalizedString(@"When changes to pre-VPN value", @"Window text") alignment: NSLeftTextAlignment ];
    [self underlineLabel: whenChangesToAnythingElseTF string: NSLocalizedString(@"When changes to anything else", @"Window text") alignment: NSLeftTextAlignment ];
    
    [dnsServersTFC   setTitle: NSLocalizedString(@"DNS servers:"  , @"Window text")];
    [domainTFC       setTitle: NSLocalizedString(@"Domain:"       , @"Window text")];
    [searchDomainTFC setTitle: NSLocalizedString(@"Search domain:", @"Window text")];
    [winsServersTFC  setTitle: NSLocalizedString(@"WINS servers:" , @"Window text")];
    [netBiosNameTFC  setTitle: NSLocalizedString(@"NetBIOS name:" , @"Window text")];
    [workgroupTFC    setTitle: NSLocalizedString(@"Workgroup:"    , @"Window text")];
    
    [self initializeDnsWinsPopUp: dnsServersPopUpButton   arrayController: dnsServersArrayController   ];
    [self initializeDnsWinsPopUp: domainPopUpButton       arrayController: domainArrayController       ];
    [self initializeDnsWinsPopUp: searchDomainPopUpButton arrayController: searchDomainArrayController ];
    [self initializeDnsWinsPopUp: winsServersPopUpButton  arrayController: winsServersArrayController  ];
    [self initializeDnsWinsPopUp: netBiosNamePopUpButton  arrayController: netBiosNameArrayController  ];
    [self initializeDnsWinsPopUp: workgroupPopUpButton    arrayController: workgroupArrayController    ];

    [self initializeDnsWinsPopUp: otherdnsServersPopUpButton   arrayController: otherdnsServersArrayController  ];
    [self initializeDnsWinsPopUp: otherdomainPopUpButton       arrayController: otherdomainArrayController      ];
    [self initializeDnsWinsPopUp: othersearchDomainPopUpButton arrayController: othersearchDomainArrayController];
    [self initializeDnsWinsPopUp: otherwinsServersPopUpButton  arrayController: otherwinsServersArrayController ];
    [self initializeDnsWinsPopUp: othernetBiosNamePopUpButton  arrayController: othernetBiosNameArrayController ];
    [self initializeDnsWinsPopUp: otherworkgroupPopUpButton    arrayController: otherworkgroupArrayController   ];
    
	
	// For Credentials tab, everything depends on preferences; there is nothing static
	
    // For Sound tab
    
    [alertSoundsBox setTitle: NSLocalizedString(@"Alert sounds", @"Window title")];
    
    [connectionAlertSoundTFC    setTitle: NSLocalizedString(@"Connection:", @"Window text")              ];
    [disconnectionAlertSoundTFC setTitle: NSLocalizedString(@"Unexpected disconnection:", @"Window text")];
	
	[self initializeSoundPopUpButtons];
}

//**********************************************************************************************************************************
-(void) setupSettingsFromPreferences {
    
    if (  ! connection  ) {
        return;
    }
	
	BOOL savedDoingSetupOfUI = [((MenuController *)[NSApp delegate]) doingSetupOfUI];
	[((MenuController *)[NSApp delegate]) setDoingSetupOfUI: TRUE];
	
    NSString * programName;
    if (  [configurationName isEqualToString: NSLocalizedString(@"Tunnelblick", @"Window title")]  ) {
        programName = @"";
    } else {
        programName = [NSString stringWithFormat: @" - Tunnelblick"];
    }
	
	NSString * localName = [((MenuController *)[NSApp delegate]) localizedNameForDisplayName: configurationName];
	NSString * privateSharedDeployed = [connection displayLocation];
    [settingsSheet setTitle: [NSString stringWithFormat: NSLocalizedString(@"%@%@ Disconnected - Advanced Settings%@", @"Window title"), localName, privateSharedDeployed, programName]];
    
	[self setupCredentialsGroupButton]; // May not need to, but set up this first, so it is set up for the rest
	
    // For Connecting tab
    
    [self setupFlushDNSCheckbox];
    [self setupKeepConnectedCheckbox];
    [self setupEnableIpv6OnTapCheckbox];
    [self setupPrependDomainNameCheckbox];
    [self setupDisconnectOnSleepCheckbox];
    [self setupReconnectOnWakeFromSleepCheckbox];
	[self setupUseRouteUpInsteadOfUpCheckbox];

    [self setupCheckbox: disconnectWhenUserSwitchesOutCheckbox
                    key: @"-doNotDisconnectOnFastUserSwitch"
               inverted: YES];
    
    [self setupCheckbox: reconnectWhenUserSwitchesInCheckbox
                    key: @"-doNotReconnectOnFastUserSwitch"
               inverted: YES];
    
	[self setupTunTapButtons];
    
    // For WhileConnected tab
    
    [self setupRunMtuTestCheckbox];
    
    if (  [[((MenuController *)[NSApp delegate]) logScreen] forceDisableOfNetworkMonitoring]  ) {
        [monitorNetworkForChangesCheckbox setState: NSOffState];
        [monitorNetworkForChangesCheckbox setEnabled: NO];
    } else {
        [self setupCheckbox: monitorNetworkForChangesCheckbox
                        key: @"-notMonitoringConnection"
                   inverted: YES];
    }
    
    [self setupMonitoringOptions];
	
	
	// For VPN Credentials tab
	
	[self setRemoveNamedCredentialsNames: [gTbDefaults sortedCredentialsGroups]];
	
    [credentialsTabViewItem setLabel: NSLocalizedString(@"VPN Credentials", @"Window title")];
	
	[namedCredentialsBox
	 setTitle: NSLocalizedString(@"Named Credentials", @"Window text")];
	
	[self setTitle: NSLocalizedString(@"Add Credentials...", @"Window text")
		 ofControl: addNamedCredentialsButton];
	
    // Create a menu for the Remove Credentials pull-down button
    NSMenu * removeCredentialMenu = [[[NSMenu alloc] init] autorelease];
	NSMenuItem * item = [[[NSMenuItem alloc] initWithTitle: NSLocalizedString(@"Remove Credentials", @"Button")
													action: @selector(removeNamedCredentialsCommand:)
											 keyEquivalent: @""] autorelease];	
	[item setTag: 0];
	[item setTarget: self];
	[removeCredentialMenu addItem: item];
    
	// Create an array of dictionaries of credentials groups, with both name and value = name of group
 	NSMutableArray * groupsDictionaryArray = [NSMutableArray arrayWithCapacity: [removeNamedCredentialsNames count]];
	NSString * groupName = [gTbDefaults stringForKey: @"namedCredentialsThatAllConfigurationsUse"];
	if (  groupName  ) {
		[groupsDictionaryArray addObject: [NSDictionary dictionaryWithObjectsAndKeys:
									 [NSString stringWithFormat:
											NSLocalizedString(@"This configuration uses %@ credentials", @"Button"),
											groupName], @"name",
									 groupName, @"value", nil]];
	} else {
		[groupsDictionaryArray addObject: [NSDictionary dictionaryWithObjectsAndKeys:
									 NSLocalizedString(@"This configuration has its own separate credentials", @"Button"), @"name",
									 @"", @"value", nil]];
	}
	unsigned i;
	for (  i=0; i<[removeNamedCredentialsNames count]; i++  ) {
        NSString * groupName = [removeNamedCredentialsNames objectAtIndex: i];
		[groupsDictionaryArray addObject: [NSDictionary dictionaryWithObjectsAndKeys:
									 [NSString stringWithFormat:
											NSLocalizedString(@"This configuration uses %@ credentials", @"Button"),
											groupName], @"name",
									 groupName, @"value", nil]];
        
		NSMenuItem * item = [[[NSMenuItem alloc] initWithTitle: groupName
                                                        action: @selector(removeNamedCredentialsCommand:)
                                                 keyEquivalent: @""] autorelease];
        [item setTag: (int) i];
		[item setTarget: self];
        [removeCredentialMenu addItem: item];
	}
	
	NSString * prefKey = [[connection displayName] stringByAppendingString: @"-credentialsGroup"];
	[credentialsGroupArrayController setContent: groupsDictionaryArray];
	[credentialsGroupButton          sizeToFit];
	[credentialsGroupButton          setEnabled: (   ( ! [gTbDefaults stringForKey: @"namedCredentialsThatAllConfigurationsUse"] )
                                                  && [gTbDefaults canChangeValueForKey: prefKey])];
	
    
    [removeNamedCredentialsButton setMenu: removeCredentialMenu];
	[removeNamedCredentialsButton sizeToFit];
	[removeNamedCredentialsButton setEnabled: ! [gTbDefaults stringForKey: @"namedCredentialsThatAllConfigurationsUse"]];
	
	NSString * groupAllConfigurationsUse = [removeNamedCredentialsNames objectAtIndex: 0];
	if (  ! groupAllConfigurationsUse  ) {
		groupAllConfigurationsUse = NSLocalizedString(@"Common", @"Credentials name");
	}
	
	[self setupCredentialsGroupButton];
	
	NSString * groupFromPrefs = [gTbDefaults stringForKey: @"namedCredentialsThatAllConfigurationsUse"];
	if (  groupFromPrefs  ) {
		[allConfigurationsUseTheSameCredentialsCheckbox setState: NSOnState];
		[credentialsGroupButton       setEnabled: NO];
		[addNamedCredentialsButton    setEnabled: NO];
		[removeNamedCredentialsButton setEnabled: NO];
		
	} else {
		[allConfigurationsUseTheSameCredentialsCheckbox setState: NSOffState];
		[credentialsGroupButton       setEnabled: YES];
		[addNamedCredentialsButton    setEnabled: YES];
		[removeNamedCredentialsButton setEnabled: YES];
	}
	
	[allConfigurationsUseTheSameCredentialsCheckbox setTitle: [NSString stringWithFormat:
														 NSLocalizedString(@"All configurations use %@ credentials", @"Window text"),
														 groupAllConfigurationsUse]];
	[allConfigurationsUseTheSameCredentialsCheckbox sizeToFit];
    
    // Sounds tab
    
    doNotPlaySounds = FALSE;
    
	[soundTabViewItem setLabel: NSLocalizedString(@"Sounds", @"Window title")];
    [self setSelectedSoundOnConnectIndexDirect:          tbNumberWithInteger(NSNotFound)];
    [self setSelectedSoundOnDisconnectIndexDirect:       tbNumberWithInteger(NSNotFound)];
	[self setupSoundPopUpButtons];

	
	[((MenuController *)[NSApp delegate]) setDoingSetupOfUI: savedDoingSetupOfUI];
}

-(void) setupMonitoringOptions {
	
	BOOL savedDoingSetupOfUI = [((MenuController *)[NSApp delegate]) doingSetupOfUI];
	[((MenuController *)[NSApp delegate]) setDoingSetupOfUI: TRUE];
	
    if (   connection
        && ( ! [[((MenuController *)[NSApp delegate]) logScreen] forceDisableOfNetworkMonitoring] )
        && ( ! [gTbDefaults boolForKey: [configurationName stringByAppendingString: @"-notMonitoringConnection"]] )  ) {
        
        [dnsServersPopUpButton   setEnabled: YES];
        [domainPopUpButton       setEnabled: YES];
        [searchDomainPopUpButton setEnabled: YES];
        [winsServersPopUpButton  setEnabled: YES];
        [netBiosNamePopUpButton  setEnabled: YES];
        [workgroupPopUpButton    setEnabled: YES];
        
        [otherdnsServersPopUpButton   setEnabled: YES];
        [otherdomainPopUpButton       setEnabled: YES];
        [othersearchDomainPopUpButton setEnabled: YES];
        [otherwinsServersPopUpButton  setEnabled: YES];
        [othernetBiosNamePopUpButton  setEnabled: YES];
        [otherworkgroupPopUpButton    setEnabled: YES];
        
        // *********************************************************************************
        // We DO NOT want to modify the underlying preferences, just the display to the user
        BOOL oldDoNotModifyPreferences = doNotModifyPreferences;
        doNotModifyPreferences = TRUE;
        
        [dnsServersPopUpButton selectItemAtIndex:   [self indexForMonitoringOptionButton: dnsServersPopUpButton   newPreference: @"-changeDNSServersAction"   oldPreference: @"-doNotRestoreOnDnsReset"  leasewatchOptionsChar: @"a"]];
        [domainPopUpButton selectItemAtIndex:       [self indexForMonitoringOptionButton: domainPopUpButton       newPreference: @"-changeDomainAction"       oldPreference: @"-doNotRestoreOnDnsReset"  leasewatchOptionsChar: @"d"]];
        [searchDomainPopUpButton selectItemAtIndex: [self indexForMonitoringOptionButton: searchDomainPopUpButton newPreference: @"-changeSearchDomainAction" oldPreference: @"-doNotRestoreOnDnsReset"  leasewatchOptionsChar: @"s"]];
        [winsServersPopUpButton selectItemAtIndex:  [self indexForMonitoringOptionButton: winsServersPopUpButton  newPreference: @"-changeWINSServersAction"  oldPreference: @"-doNotRestoreOnWinsReset" leasewatchOptionsChar: @"w"]];
        [netBiosNamePopUpButton selectItemAtIndex:  [self indexForMonitoringOptionButton: netBiosNamePopUpButton  newPreference: @"-changeNetBIOSNameAction"  oldPreference: @"-doNotRestoreOnWinsReset" leasewatchOptionsChar: @"n"]];
        [workgroupPopUpButton selectItemAtIndex:    [self indexForMonitoringOptionButton: workgroupPopUpButton    newPreference: @"-changeWorkgroupAction"    oldPreference: @"-doNotRestoreOnWinsReset" leasewatchOptionsChar: @"g"]];
        
        [otherdnsServersPopUpButton selectItemAtIndex:   [self indexForMonitoringOptionButton: otherdnsServersPopUpButton   newPreference: @"-changeOtherDNSServersAction"   oldPreference: nil leasewatchOptionsChar: @"a"]];
        [otherdomainPopUpButton selectItemAtIndex:       [self indexForMonitoringOptionButton: otherdomainPopUpButton       newPreference: @"-changeOtherDomainAction"       oldPreference: nil leasewatchOptionsChar: @"d"]];
        [othersearchDomainPopUpButton selectItemAtIndex: [self indexForMonitoringOptionButton: othersearchDomainPopUpButton newPreference: @"-changeOtherSearchDomainAction" oldPreference: nil leasewatchOptionsChar: @"s"]];
        [otherwinsServersPopUpButton selectItemAtIndex:  [self indexForMonitoringOptionButton: otherwinsServersPopUpButton  newPreference: @"-changeOtherWINSServersAction"  oldPreference: nil leasewatchOptionsChar: @"w"]];
        [othernetBiosNamePopUpButton selectItemAtIndex:  [self indexForMonitoringOptionButton: othernetBiosNamePopUpButton  newPreference: @"-changeOtherNetBIOSNameAction"  oldPreference: nil leasewatchOptionsChar: @"n"]];
        [otherworkgroupPopUpButton selectItemAtIndex:    [self indexForMonitoringOptionButton: otherworkgroupPopUpButton    newPreference: @"-changeOtherWorkgroupAction"    oldPreference: nil leasewatchOptionsChar: @"g"]];
        
        [self setSelectedDnsServersIndex:   tbNumberWithUnsignedInteger([self indexForMonitoringOptionButton: dnsServersPopUpButton   newPreference: @"-changeDNSServersAction"   oldPreference: @"-doNotRestoreOnDnsReset"  leasewatchOptionsChar: @"a"])];
        [self setSelectedDomainIndex:       tbNumberWithUnsignedInteger([self indexForMonitoringOptionButton: domainPopUpButton       newPreference: @"-changeDomainAction"       oldPreference: @"-doNotRestoreOnDnsReset"  leasewatchOptionsChar: @"d"])];
        [self setSelectedSearchDomainIndex: tbNumberWithUnsignedInteger([self indexForMonitoringOptionButton: searchDomainPopUpButton newPreference: @"-changeSearchDomainAction" oldPreference: @"-doNotRestoreOnDnsReset"  leasewatchOptionsChar: @"s"])];
        [self setSelectedWinsServersIndex:  tbNumberWithUnsignedInteger([self indexForMonitoringOptionButton: winsServersPopUpButton  newPreference: @"-changeWINSServersAction"  oldPreference: @"-doNotRestoreOnWinsReset" leasewatchOptionsChar: @"w"])];
        [self setSelectedNetBiosNameIndex:  tbNumberWithUnsignedInteger([self indexForMonitoringOptionButton: netBiosNamePopUpButton  newPreference: @"-changeNetBIOSNameAction"  oldPreference: @"-doNotRestoreOnWinsReset" leasewatchOptionsChar: @"n"])];
        [self setSelectedWorkgroupIndex:    tbNumberWithUnsignedInteger([self indexForMonitoringOptionButton: workgroupPopUpButton    newPreference: @"-changeWorkgroupAction"    oldPreference: @"-doNotRestoreOnWinsReset" leasewatchOptionsChar: @"g"])];
        
        [self setSelectedOtherdnsServersIndex:   tbNumberWithUnsignedInteger([self indexForMonitoringOptionButton: otherdnsServersPopUpButton   newPreference: @"-changeOtherDNSServersAction"   oldPreference: nil leasewatchOptionsChar: @"a"])];
        [self setSelectedOtherdomainIndex:       tbNumberWithUnsignedInteger([self indexForMonitoringOptionButton: otherdomainPopUpButton       newPreference: @"-changeOtherDomainAction"       oldPreference: nil leasewatchOptionsChar: @"d"])];
        [self setSelectedOthersearchDomainIndex: tbNumberWithUnsignedInteger([self indexForMonitoringOptionButton: othersearchDomainPopUpButton newPreference: @"-changeOtherSearchDomainAction" oldPreference: nil leasewatchOptionsChar: @"s"])];
        [self setSelectedOtherwinsServersIndex:  tbNumberWithUnsignedInteger([self indexForMonitoringOptionButton: otherwinsServersPopUpButton  newPreference: @"-changeOtherWINSServersAction"  oldPreference: nil leasewatchOptionsChar: @"w"])];
        [self setSelectedOthernetBiosNameIndex:  tbNumberWithUnsignedInteger([self indexForMonitoringOptionButton: othernetBiosNamePopUpButton  newPreference: @"-changeOtherNetBIOSNameAction"  oldPreference: nil leasewatchOptionsChar: @"n"])];
        [self setSelectedOtherworkgroupIndex:    tbNumberWithUnsignedInteger([self indexForMonitoringOptionButton: otherworkgroupPopUpButton    newPreference: @"-changeOtherWorkgroupAction"    oldPreference: nil leasewatchOptionsChar: @"g"])];
        
        doNotModifyPreferences = oldDoNotModifyPreferences;
        
        NSString * leasewatchOptionsKey = [configurationName stringByAppendingString: @"-leasewatchOptions"];
        NSString * leasewatchOptions = [gTbDefaults stringForKey: leasewatchOptionsKey];
        if (  leasewatchOptions  ) {
            [dnsServersPopUpButton   setEnabled: NO];
            [domainPopUpButton       setEnabled: NO];
            [searchDomainPopUpButton setEnabled: NO];
            [winsServersPopUpButton  setEnabled: NO];
            [netBiosNamePopUpButton  setEnabled: NO];
            [workgroupPopUpButton    setEnabled: NO];
            
            [otherdnsServersPopUpButton   setEnabled: NO];
            [otherdomainPopUpButton       setEnabled: NO];
            [othersearchDomainPopUpButton setEnabled: NO];
            [otherwinsServersPopUpButton  setEnabled: NO];
            [othernetBiosNamePopUpButton  setEnabled: NO];
            [otherworkgroupPopUpButton    setEnabled: NO];
        }
        
        
        // *********************************************************************************
        
    } else {
        
        // *********************************************************************************
        // We DO NOT want to modify the underlying preferences, just the display to the user
        BOOL oldDoNotModifyPreferences = doNotModifyPreferences;
        doNotModifyPreferences = TRUE;
        
        [dnsServersPopUpButton   selectItemAtIndex: 0];
        [domainPopUpButton       selectItemAtIndex: 0];
        [searchDomainPopUpButton selectItemAtIndex: 0];
        [winsServersPopUpButton  selectItemAtIndex: 0];
        [netBiosNamePopUpButton  selectItemAtIndex: 0];
        [workgroupPopUpButton    selectItemAtIndex: 0];
        
        [otherdnsServersPopUpButton   selectItemAtIndex: 0];
        [otherdomainPopUpButton       selectItemAtIndex: 0];
        [othersearchDomainPopUpButton selectItemAtIndex: 0];
        [otherwinsServersPopUpButton  selectItemAtIndex: 0];
        [othernetBiosNamePopUpButton  selectItemAtIndex: 0];
        [otherworkgroupPopUpButton    selectItemAtIndex: 0];
        
        [self setSelectedDnsServersIndex:   tbNumberWithUnsignedInteger(0)];
        [self setSelectedDomainIndex:       tbNumberWithUnsignedInteger(0)];
        [self setSelectedSearchDomainIndex: tbNumberWithUnsignedInteger(0)];
        [self setSelectedWinsServersIndex:  tbNumberWithUnsignedInteger(0)];
        [self setSelectedNetBiosNameIndex:  tbNumberWithUnsignedInteger(0)];
        [self setSelectedWorkgroupIndex:    tbNumberWithUnsignedInteger(0)];
        
        [self setSelectedOtherdnsServersIndex:   tbNumberWithUnsignedInteger(0)];
        [self setSelectedOtherdomainIndex:       tbNumberWithUnsignedInteger(0)];
        [self setSelectedOthersearchDomainIndex: tbNumberWithUnsignedInteger(0)];
        [self setSelectedOtherwinsServersIndex:  tbNumberWithUnsignedInteger(0)];
        [self setSelectedOthernetBiosNameIndex:  tbNumberWithUnsignedInteger(0)];
        [self setSelectedOtherworkgroupIndex:    tbNumberWithUnsignedInteger(0)];
        
        doNotModifyPreferences = oldDoNotModifyPreferences;
        // *********************************************************************************
        
        [dnsServersPopUpButton   setEnabled: NO];
        [domainPopUpButton       setEnabled: NO];
        [searchDomainPopUpButton setEnabled: NO];
        [winsServersPopUpButton  setEnabled: NO];
        [netBiosNamePopUpButton  setEnabled: NO];
        [workgroupPopUpButton    setEnabled: NO];
        
        [otherdnsServersPopUpButton   setEnabled: NO];
        [otherdomainPopUpButton       setEnabled: NO];
        [othersearchDomainPopUpButton setEnabled: NO];
        [otherwinsServersPopUpButton  setEnabled: NO];
        [othernetBiosNamePopUpButton  setEnabled: NO];
        [otherworkgroupPopUpButton    setEnabled: NO];
    }
	
	[((MenuController *)[NSApp delegate]) setDoingSetupOfUI: savedDoingSetupOfUI];
}

-(NSInteger) indexForMonitoringOptionButton: (NSPopUpButton *) button
                              newPreference: (NSString *)      preference
                              oldPreference: (NSString *)      oldPreference
                      leasewatchOptionsChar: (NSString *)      leasewatchOptionsChar {
    NSString * monitorKey = [configurationName stringByAppendingString: @"-notMonitoringConnection"];

    BOOL ignoringBecauseOfLeasewatchOptions = FALSE;
    NSString * leasewatchOptionsKey = [configurationName stringByAppendingString: @"-leasewatchOptions"];
    NSString * leasewatchOptions = [gTbDefaults stringForKey: leasewatchOptionsKey];
    if (  leasewatchOptions  ) {
        if (  [leasewatchOptions rangeOfString: leasewatchOptionsChar].length != 0) {
            ignoringBecauseOfLeasewatchOptions = TRUE;
        }
    }
    
    NSString * defaultValue;
    NSString * actualKey = [configurationName stringByAppendingString: preference];
    
    NSString * oldActualKey = nil;
    if (  oldPreference  ) {
        oldActualKey = [configurationName stringByAppendingString: oldPreference];
    }
    
    [button setEnabled: (   [gTbDefaults canChangeValueForKey: actualKey]
                         && [gTbDefaults canChangeValueForKey: monitorKey]   )];
    
    if (  ignoringBecauseOfLeasewatchOptions  ) {
        return 0;
    }
    
    if (  oldActualKey  ) {
        if (  [gTbDefaults boolForKey: oldActualKey]  ) {
            defaultValue = @"restart";
        } else {
            defaultValue = @"restore";
        }
    } else {
		defaultValue = @"restart";
	}

    NSString * value = [gTbDefaults stringForKey: actualKey];
    if (  value  ) {
        if (  [value isEqualToString: @"ignore"]  ) {
			return 0;
		} else if (  [value isEqualToString: @"restore"]  ) {
			return 1;
		} else if (  [value isEqualToString: @"restart"]  ) {
			return 2;
		} else {
			NSLog(@"%@ preference '%@' ignored: invalid value; must be 'ignore', 'restore', or 'restart'", actualKey, value);
		}
	}

    if (  [defaultValue isEqualToString: @"ignore"]  ) {
        return 0;
    } else if (  [defaultValue isEqualToString: @"restore"]  ) {
        return 1;
    } else if (  [defaultValue isEqualToString: @"restart"]  ) {
        return 2;
    } else {
        NSLog(@"Tunnelblick PROGRAM ERROR -- %@ preference default of '%@' ignored", actualKey, defaultValue);
        return 0;
    }
}

// Methods for Connecting & Disconnecting tab

-(IBAction) reconnectWhenUnexpectedDisconnectCheckboxWasClicked: (NSButton *) sender {
    
    // This preference is NOT IMPLEMENTED, nor is there a checkbox in the .xib
    
    [((MenuController *)[NSApp delegate]) setBooleanPreferenceForSelectedConnectionsWithKey: @"-doNotReconnectOnUnexpectedDisconnect"
																	 to: ([sender state] == NSOnState)
                                                               inverted: YES];
}


-(IBAction) flushDnsCacheCheckboxWasClicked: (NSButton *) sender {
    [((MenuController *)[NSApp delegate]) setBooleanPreferenceForSelectedConnectionsWithKey: @"-doNotFlushCache"
																	 to: ([sender state] == NSOnState)
                                                               inverted: YES];
}


-(IBAction) keepConnectedCheckboxWasClicked: (NSButton *) sender {
    [((MenuController *)[NSApp delegate]) setBooleanPreferenceForSelectedConnectionsWithKey: @"-keepConnected"
                                                                                         to: ([sender state] == NSOnState)
                                                                                   inverted: NO];
}


-(IBAction) enableIpv6OnTapCheckboxWasClicked: (NSButton *) sender {
    [((MenuController *)[NSApp delegate]) setBooleanPreferenceForSelectedConnectionsWithKey: @"-enableIpv6OnTap"
                                                                                         to: ([sender state] == NSOnState)
                                                                                   inverted: NO];
}


-(IBAction) useRouteUpInsteadOfUpCheckboxWasClicked:(NSButton *)sender {
    [((MenuController *)[NSApp delegate]) setBooleanPreferenceForSelectedConnectionsWithKey: @"-useRouteUpInsteadOfUp"
																	 to: ([sender state] == NSOnState)
                                                               inverted: NO];
}


-(IBAction) prependDomainNameCheckboxWasClicked: (NSButton *)sender {
    [((MenuController *)[NSApp delegate]) setBooleanPreferenceForSelectedConnectionsWithKey: @"-prependDomainNameToSearchDomains"
																	 to: ([sender state] == NSOnState)
                                                               inverted: NO];
}


-(IBAction) disconnectOnSleepCheckboxWasClicked: (NSButton *)sender {
    [((MenuController *)[NSApp delegate]) setBooleanPreferenceForSelectedConnectionsWithKey: @"-doNotDisconnectOnSleep"
																	 to: ([sender state] == NSOnState)
                                                               inverted: YES];
    [self setupReconnectOnWakeFromSleepCheckbox];
}


-(IBAction) reconnectOnWakeFromSleepCheckboxWasClicked: (NSButton *) sender {
    [((MenuController *)[NSApp delegate]) setBooleanPreferenceForSelectedConnectionsWithKey: @"-doNotReconnectOnWakeFromSleep"
																	 to: ([sender state] == NSOnState)
                                                               inverted: YES];
}


-(IBAction) runMtuTestCheckboxWasClicked: (NSButton *) sender {
    [((MenuController *)[NSApp delegate]) setBooleanPreferenceForSelectedConnectionsWithKey: @"-runMtuTest"
																	 to: ([sender state] == NSOnState)
                                                               inverted: NO];
}

-(void) setTunTapKey: (NSString *) key
		 value: (NSString *) value {
    
	if ( ! [((MenuController *)[NSApp delegate]) doingSetupOfUI]  ) {
		NSDictionary * dict = [NSDictionary dictionaryWithObjectsAndKeys:
						 value,  @"NewValue",
						 key,    @"PreferenceName",
						 nil];
		[((MenuController *)[NSApp delegate]) performSelectorOnMainThread: @selector(setPreferenceForSelectedConfigurationsWithDict:) withObject: dict waitUntilDone: NO];
	}
}

-(IBAction) loadTunAutomaticallyMenuItemWasClicked: (id) sender {
    (void) sender;
    
    [self setTunTapKey: @"-loadTun" value: @""];
}

-(IBAction) loadTapAutomaticallyMenuItemWasClicked: (id)sender {
    (void) sender;
    
    [self setTunTapKey: @"-loadTap" value: @""];
}

-(IBAction) loadTunNeverMenuItemWasClicked: (id)sender {
    (void) sender;
    
    [self setTunTapKey: @"-loadTun" value: @"never"];
}

-(IBAction) loadTapNeverMenuItemWasClicked: (id)sender {
    (void) sender;
    
    [self setTunTapKey: @"-loadTap" value: @"never"];
}

-(IBAction) loadTunAlwaysMenuItemWasClicked: (id)sender {
    (void) sender;
    
    [self setTunTapKey: @"-loadTun" value: @"always"];
}

-(IBAction) loadTapAlwaysMenuItemWasClicked: (id)sender {
    (void) sender;
    
    [self setTunTapKey: @"-loadTap" value: @"always"];
}

-(IBAction) connectingHelpButtonWasClicked: (id) sender {
	(void) sender;
	
    MyGotoHelpPage(@"vpn-details-advanced-connecting-disconnecting.html", nil);
}


-(IBAction) disconnectWhenUserSwitchesOutCheckboxWasClicked: (NSButton *) sender  {
    [((MenuController *)[NSApp delegate]) setBooleanPreferenceForSelectedConnectionsWithKey: @"-doNotDisconnectOnFastUserSwitch"
																	 to: ([sender state] == NSOnState)
														 inverted: YES];
}


-(IBAction) reconnectWhenUserSwitchesInCheckboxWasClicked: (NSButton *) sender {
    [((MenuController *)[NSApp delegate]) setBooleanPreferenceForSelectedConnectionsWithKey: @"-doNotReconnectOnFastUserSwitch"
																	 to: ([sender state] == NSOnState)
														 inverted: YES];
}


// Methods for While Connecting tab

-(void) monitorNetworkForChangesCheckboxChangedForConnection: (VPNConnection *) theConnection {
    // Checkbox was changed by another window
    
    if (   connection
        && (connection == theConnection)  ) {
        if (  [[((MenuController *)[NSApp delegate]) logScreen] forceDisableOfNetworkMonitoring]  ) {
            [monitorNetworkForChangesCheckbox setState: NSOffState];
            [monitorNetworkForChangesCheckbox setEnabled: NO];
        } else {
            NSString * key = [configurationName stringByAppendingString: @"-notMonitoringConnection"];
            BOOL monitoring = [gTbDefaults boolForKey: key];
            int state = (monitoring ? NSOffState : NSOnState);
            [monitorNetworkForChangesCheckbox setState: state];
            [monitorNetworkForChangesCheckbox setEnabled: YES];
        }
        
        [self setupMonitoringOptions];
    }
}

-(IBAction) monitorNetworkForChangesCheckboxWasClicked: (NSButton *) sender {
    
    [((MenuController *)[NSApp delegate]) setBooleanPreferenceForSelectedConnectionsWithKey: @"-notMonitoringConnection"
																	 to: ([sender state] == NSOnState)
														 inverted: YES];
    
    [self setupMonitoringOptions];
    
    [[((MenuController *)[NSApp delegate]) logScreen] monitorNetworkForChangesCheckboxChangedForConnection: connection];
}

-(void) setDnsWinsIndexTo: (NSNumber *)   newValue
               preference: (NSString *)   key {
    
    if (  ! doNotModifyPreferences  ) {
        NSString * newSetting = nil;
        switch (  tbUnsignedIntegerValue(newValue)  ) {
            case 0:
                newSetting = @"ignore";
                break;
            case 1:
                newSetting = @"restore";
                break;
            case 2:
                newSetting = @"restart";
                break;
            default:
                NSLog(@"setDnsWinsIndex: ignoring invalid value %ld", (long) tbUnsignedIntegerValue(newValue));
        }
        if (  newSetting != nil  ) {
            NSString * defaultValue = (  [key hasPrefix: @"-changeOther"]
                                       ? @"restart"
                                       : @"restore");
            
			if ( ! [((MenuController *)[NSApp delegate]) doingSetupOfUI]  ) {
				NSString * newStringValue = (  [newSetting isEqualToString: defaultValue]
                                             ? @""
                                             : newSetting
                                             );
				NSDictionary * dict = [NSDictionary dictionaryWithObjectsAndKeys:
                                       newStringValue,  @"NewValue",
                                       key,    @"PreferenceName",
                                       nil];
				[((MenuController *)[NSApp delegate]) performSelectorOnMainThread: @selector(setPreferenceForSelectedConfigurationsWithDict:) withObject: dict waitUntilDone: NO];
			}
		}
    }
}

-(void) setSelectedDnsServersIndex: (NSNumber *) newValue {
    
    [self setDnsWinsIndexTo: newValue preference: @"-changeDNSServersAction"];
    [self setSelectedDnsServersIndexDirect: newValue];
}

-(void) setSelectedDomainIndex: (NSNumber *) newValue {
    
    [self setDnsWinsIndexTo: newValue preference: @"-changeDomainAction"];
    [self setSelectedDomainIndexDirect: newValue];
}

-(void) setSelectedSearchDomainIndex: (NSNumber *) newValue {
    
    [self setDnsWinsIndexTo: newValue preference: @"-changeSearchDomainAction"];
    [self setSelectedSearchDomainIndexDirect: newValue];
}

-(void) setSelectedWinsServersIndex: (NSNumber *) newValue {
    
    [self setDnsWinsIndexTo: newValue preference: @"-changeWINSServersAction"];
    [self setSelectedWinsServersIndexDirect: newValue];
}

-(void) setSelectedNetBiosNameIndex: (NSNumber *) newValue {
    
    [self setDnsWinsIndexTo: newValue preference: @"-changeNetBIOSNameAction"];
    [self setSelectedNetBiosNameIndexDirect: newValue];
}

-(void) setSelectedWorkgroupIndex: (NSNumber *) newValue {
    
    [self setDnsWinsIndexTo: newValue preference: @"-changeWorkgroupAction"];
    [self setSelectedWorkgroupIndexDirect: newValue];
}

-(void) setSelectedOtherdnsServersIndex: (NSNumber *) newValue {
    
    [self setDnsWinsIndexTo: newValue preference: @"-changeOtherDNSServersAction"];
    [self setSelectedOtherdnsServersIndexDirect: newValue];
}

-(void) setSelectedOtherdomainIndex: (NSNumber *) newValue {
    
    [self setDnsWinsIndexTo: newValue preference: @"-changeOtherDomainAction"];
    [self setSelectedOtherdomainIndexDirect: newValue];
}

-(void) setSelectedOthersearchDomainIndex: (NSNumber *) newValue {
    
    [self setDnsWinsIndexTo: newValue preference: @"-changeOtherSearchDomainAction"];
    [self setSelectedOthersearchDomainIndexDirect: newValue];
}

-(void) setSelectedOtherwinsServersIndex: (NSNumber *) newValue {
    
    [self setDnsWinsIndexTo: newValue preference: @"-changeOtherWINSServersAction"];
    [self setSelectedOtherwinsServersIndexDirect: newValue];
}

-(void) setSelectedOthernetBiosNameIndex: (NSNumber *) newValue {
    
    [self setDnsWinsIndexTo: newValue preference: @"-changeOtherNetBIOSNameAction"];
    [self setSelectedOthernetBiosNameIndexDirect: newValue];
}

-(void) setSelectedOtherworkgroupIndex: (NSNumber *) newValue {
    
    [self setDnsWinsIndexTo: newValue preference: @"-changeOtherWorkgroupAction"];
    [self setSelectedOtherworkgroupIndexDirect: newValue];
}

-(void) setSelectedCredentialsGroupIndex: (NSNumber *) newValue {
	
    NSArray * contents = [credentialsGroupArrayController content];
    if (  tbUnsignedIntegerValue(newValue) < [contents count]  ) {
		NSString * groupValue = nil;
        if (  tbUnsignedIntegerValue(newValue) == 0) {
			groupValue = @"";
        } else {
            NSString * groupName = [[contents objectAtIndex: tbUnsignedIntegerValue(newValue)] objectForKey: @"value"];
			NSArray * groups = [gTbDefaults sortedCredentialsGroups];
            if (  [groups containsObject: groupName]  ) {
				groupValue = groupName;
			} else {
		  NSLog(@"setSelectedCredentialsGroupIndex: '%@' credentials are not available", groupName);
            }
        }
		
		if (  groupValue  ) {
			if (  ! [((MenuController *)[NSApp delegate]) doingSetupOfUI]  ) {
				NSDictionary * dict = [NSDictionary dictionaryWithObjectsAndKeys:
								 groupValue, @"NewValue",
								 @"-credentialsGroup", @"PreferenceName",
								 nil];
				[((MenuController *)[NSApp delegate]) performSelectorOnMainThread: @selector(setPreferenceForSelectedConfigurationsWithDict:) withObject: dict waitUntilDone: NO];
			}
		}
		
		[self setSelectedCredentialsGroupIndexDirect: newValue];
		[connection initializeAuthAgent];
		
    } else if (  [contents count] != 0  ) {
        NSLog(@"setSelectedCredentialsGroupIndex: %ld but there are only %ld groups", (long) tbUnsignedIntegerValue(newValue), (long) ([contents count] - 1));
    }
}

-(void) setupSoundIndexTo: (NSUInteger) newValue
               preference: (NSString *) preference
{
    NSArray * contents = [[self soundOnConnectArrayController] content];
    NSUInteger size = [contents count];
    if (  newValue < size  ) {
        NSString * newName;
        NSSound  * newSound;
        BOOL       speakIt = FALSE;
        if (  newValue == 0) {
            newName = @"None";
            newSound = nil;
        } else if (  newValue == 1) {
            newName = @"Speak";
            newSound = nil;
            if (  ! doNotPlaySounds  ) {
                if (  [preference hasSuffix: @"tunnelUpSoundName"]  ) {
                    [connection speakActivity: @"connected"];
                } else {
                    [connection speakActivity: @"disconnected"];
                }
            }
            speakIt = TRUE;
        } else {
            newName = [[contents objectAtIndex: newValue] objectForKey: @"name"];
            newSound = [NSSound soundNamed: newName];
            if (  newSound  ) {
                if (  ! doNotPlaySounds  ) {
                    [newSound play];
                }
            } else {
                NSLog(@"Sound '%@' is not available", newName);
            }
        }
        
        
        if ( ! [((MenuController *)[NSApp delegate]) doingSetupOfUI]  ) {
            NSDictionary * dict = [NSDictionary dictionaryWithObjectsAndKeys:
                                   newName, @"NewValue",
                                   preference, @"PreferenceName",
                                   nil];
            [((MenuController *)[NSApp delegate]) performSelectorOnMainThread: @selector(setPreferenceForSelectedConfigurationsWithDict:) withObject: dict waitUntilDone: NO];
        }
        if (  [preference hasSuffix: @"tunnelUpSoundName"]  ) {
            [connection setTunnelUpSound: newSound];
            [connection setSpeakWhenConnected: speakIt];
        } else {
            [connection setTunnelDownSound: newSound];
            [connection setSpeakWhenDisconnected: speakIt];
        }
    } else if (  size != 0  ) {
        NSLog(@"setSelectedSoundIndex: %ld but there are only %ld sounds", (long) newValue, (long) size);
    }
}

-(void) setSelectedSoundOnConnectIndex: (NSNumber *) newValue
{
    [self setupSoundIndexTo: tbUnsignedIntegerValue(newValue) preference: @"-tunnelUpSoundName"];
    
    [self setSelectedSoundOnConnectIndexDirect: newValue];
}


-(void) setSelectedSoundOnDisconnectIndex: (NSNumber *) newValue
{
    [self setupSoundIndexTo: tbUnsignedIntegerValue(newValue) preference: @"-tunnelDownSoundName"];
    
    [self setSelectedSoundOnDisconnectIndexDirect: newValue];
}

-(void) bringToFront2
{
	NSLog(@"activate/makeKeyAndOrderFront; window = %@", [self window]);
	[NSApp activateIgnoringOtherApps: YES];
	[[self window] display];
	[self showWindow: self];
	[[self window] makeKeyAndOrderFront: self];
}

-(void) bringToFront1
{
	[self performSelectorOnMainThread: @selector(bringToFront2) withObject: nil waitUntilDone: NO];
}

-(void) removeNamedCredentialsCommand: (id) sender {
    unsigned ix = (unsigned)[sender tag];
    NSString * groupName = [removeNamedCredentialsNames objectAtIndex: ix];
	int result = TBRunAlertPanel(NSLocalizedString(@"Tunnelblick", @"Window title"),
								 [NSString stringWithFormat:
							NSLocalizedString(@"Do you wish to delete the %@ credentials?", @"Window text"),
							groupName],
								 NSLocalizedString(@"Cancel", @"Button"),    // Default button
								 NSLocalizedString(@"Delete", @"Button"),    // Alternate button
								 nil);
	
	if (  result != NSAlertAlternateReturn  ) {
		return;
	}
    
	NSString * errMsg = [gTbDefaults removeNamedCredentialsGroup: groupName];
	if (  errMsg  ) {
        TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                          [NSString stringWithFormat:
						   NSLocalizedString(@"The credentials named %@ could not be removed:\n\n%@", @"Window text"),
						   groupName,
						   errMsg]);
	} else {
		[self initializeStaticContent];
		[self setupSettingsFromPreferences];
		[self performSelectorOnMainThread: @selector(bringToFront1) withObject: nil waitUntilDone: NO];
	}
}

-(IBAction) allConfigurationsUseTheSameCredentialsCheckboxWasClicked: (NSButton *) sender {
	NSString * prefKey = @"namedCredentialsThatAllConfigurationsUse";
	if (  [gTbDefaults canChangeValueForKey: prefKey]  ) {
		if (  [sender state] == NSOffState) {
			[gTbDefaults removeObjectForKey: prefKey];
		} else {
			NSString * name = [removeNamedCredentialsNames objectAtIndex: 0];
			[gTbDefaults setObject: name forKey: prefKey];
		}
		[self setupSettingsFromPreferences];
        NSDictionary * connections = [[NSApp delegate] myVPNConnectionDictionary];
        NSEnumerator * e = [connections objectEnumerator];
        VPNConnection * conn;
        while (  (conn = [e nextObject])  ) {
            [conn initializeAuthAgent];
        }
	} else {
		NSLog(@"allConfigurationsUseTheSameCredentialsCheckboxWasClicked: but the '%@' preference is forced.", prefKey);
	}
}

-(IBAction) addNamedCredentialsButtonWasClicked: (id) sender {
	(void) sender;
	
	NSString * msg = NSLocalizedString(@"Please enter a name for the credentials:\n\n", @"Window text");
	NSString * newName = @"";
	while (  newName  ) {
		newName = TBGetString(msg, newName);
		if (   newName
			&& ([newName length] > 0)  ) {
			if (  invalidConfigurationName(newName, PROHIBITED_DISPLAY_NAME_CHARACTERS_INCLUDING_SLASH_CSTRING)  ) {
				msg = [NSString stringWithFormat:
				 NSLocalizedString(@"Names may not include any of the following characters: %s\n\nPlease enter a name for the new credentials:\n\n", @"Window text"),
				 PROHIBITED_DISPLAY_NAME_CHARACTERS_INCLUDING_SLASH_CSTRING];
			} else {
				NSString * errMsg = [gTbDefaults addNamedCredentialsGroup: newName];
				if (  errMsg  ) {
					TBShowAlertWindow(NSLocalizedString(@"Warning!", @"Window title"),
                                      [NSString stringWithFormat:
                                       NSLocalizedString(@"The credentials named %@ could not be added:\n\n%@", @"Window text"),
                                       newName,
                                       errMsg]);
				} else {
					[self initializeStaticContent];
					[self setupSettingsFromPreferences];
				}
				
				[self performSelectorOnMainThread: @selector(bringToFront1) withObject: nil waitUntilDone: NO];
				return;
			}
		}
	}
}

-(IBAction) whileConnectedHelpButtonWasClicked: (id) sender {
	(void) sender;
	
    MyGotoHelpPage(@"vpn-details-advanced-connecting-disconnecting.html", nil);
}

-(IBAction) vpnCredentialsHelpButtonWasClicked: (id) sender {
	(void) sender;
	
    MyGotoHelpPage(@"vpn-details-advanced-connecting-disconnecting.html", nil);
}

// General methods

// Set a checkbox from preferences
-(void) setupCheckbox: (NSButton *) checkbox
                  key: (NSString *) key
             inverted: (BOOL)       inverted {
    
    if (  checkbox  ) {
        NSString * actualKey = [configurationName stringByAppendingString: key];
        BOOL state = [gTbDefaults boolForKey: actualKey];
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


@end
