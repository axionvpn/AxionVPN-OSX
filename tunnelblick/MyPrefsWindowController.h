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


#import "DBPrefsWindowController.h"

#import "defines.h"

@class ConfigurationsView;
@class GeneralView;
@class AppearanceView;
@class InfoView;
@class UtilitiesView;
@class VPNConnection;
@class SettingsSheetWindowController;

@interface MyPrefsWindowController : DBPrefsWindowController <NSTextStorageDelegate, NSWindowDelegate, NSTabViewDelegate, NSTableViewDelegate>
{   
    NSString                      * currentViewName;
    NSRect                          currentFrame;
    
    IBOutlet ConfigurationsView   * configurationsPrefsView;
    IBOutlet GeneralView          * generalPrefsView;
    IBOutlet AppearanceView       * appearancePrefsView;
    IBOutlet InfoView             * infoPrefsView;
    IBOutlet UtilitiesView        * utilitiesPrefsView;
    
	NSSize                          windowContentMinSize;	// Saved when switch FROM Configurations view
	NSSize                          windowContentMaxSize;   // And restored when switch back
	//												        // (In other views, set min = max so can't change size)
	
    // For ConfigurationsView
    NSString                      * previouslySelectedNameOnLeftNavList;
    
    NSMutableArray                * leftNavList;                      // Items in the left navigation list as displayed to the user
    //                                                             Each item is a string with either
    //                                                             a folder name (possibly indented) or
    //                                                             a connection name (possibly indented)
    
    NSMutableArray                * leftNavDisplayNames;              // A string for each item in leftNavList
    //                                                             Each item is a string with either
    //                                                             An empty string (corresponding to a folder name entry in leftNavList) or
    //                                                             The full display name for the corresponding connection
    
    SettingsSheetWindowController * settingsSheetWindowController;
    
    AuthorizationRef               authorization;                    // Authorization reference for Shared/Deployed configuration manipulation
    
    NSUInteger                     selectedWhenToConnectIndex;
    
    NSUInteger                     selectedLeftNavListIndex;
    IBOutlet NSNumber            * selectedSetNameserverIndex;
    IBOutlet NSNumber            * selectedPerConfigOpenvpnVersionIndex;
    
    
    // For GeneralView
    IBOutlet NSNumber            * selectedKeyboardShortcutIndex;
    IBOutlet NSNumber            * selectedMaximumLogSizeIndex;
    
    // For AppearanceView
    IBOutlet NSNumber            * selectedAppearanceIconSetIndex;
    IBOutlet NSNumber            * selectedAppearanceConnectionWindowDisplayCriteriaIndex;
    IBOutlet NSNumber            * selectedAppearanceConnectionWindowScreenIndex;
}


// Methods used by MenuController to update the window

-(void) update;
-(BOOL) forceDisableOfNetworkMonitoring;

-(void) indicateWaitingForConnection:                         (VPNConnection *) theConnection;
-(void) indicateNotWaitingForConnection:                      (VPNConnection *) theConnection;
-(void) hookedUpOrStartedConnection:                          (VPNConnection *) theConnection;
-(void) validateWhenConnectingForConnection:                  (VPNConnection *) theConnection;
-(void) validateConnectAndDisconnectButtonsForConnection:     (VPNConnection *) theConnection;
-(void) monitorNetworkForChangesCheckboxChangedForConnection: (VPNConnection *) theConnection;
-(void) setupAppearanceConnectionWindowScreenButton;
-(void) setupAppearancePlaceIconNearSpotlightCheckbox;

// Used by LogDisplay to scroll to the current point in the log
-(NSTextView *) logView;

// Methods for ConfigurationsView

- (VPNConnection*) selectedConnection;

-(IBAction) addConfigurationButtonWasClicked:         (id)  sender;
-(IBAction) removeConfigurationButtonWasClicked:      (id)  sender;

-(IBAction) renameConfigurationMenuItemWasClicked:    (id) sender;
-(IBAction) duplicateConfigurationMenuItemWasClicked: (id) sender;
-(IBAction) makePrivateOrSharedMenuItemWasClicked:    (id) sender;
-(IBAction) revertToShadowMenuItemWasClicked:         (id) sender;
-(IBAction) showHideOnTbMenuMenuItemWasClicked:       (id) sender;
-(IBAction) editOpenVPNConfigurationFileMenuItemWasClicked: (id) sender;
-(IBAction) showOpenvpnLogMenuItemWasClicked:         (id)  sender;
-(IBAction) removeCredentialsMenuItemWasClicked:      (id) sender;

-(IBAction) disconnectButtonWasClicked:               (id)  sender;
-(IBAction) connectButtonWasClicked:                  (id)  sender;

-(IBAction) logToClipboardButtonWasClicked:           (id)  sender;

-(IBAction) configurationsHelpButtonWasClicked:       (id)  sender;

-(IBAction) monitorNetworkForChangesCheckboxWasClicked:             (NSButton *) sender;
-(IBAction) routeAllTrafficThroughVpnCheckboxWasClicked:            (NSButton *) sender;
-(IBAction) checkIPAddressAfterConnectOnAdvancedCheckboxWasClicked: (NSButton *) sender;
-(IBAction) resetPrimaryInterfaceAfterDisconnectCheckboxWasClicked: (NSButton *) sender;
-(IBAction) disableIpv6OnTunCheckboxWasClicked:                     (NSButton *) sender;

-(void)		validateDetailsWindowControls;

-(IBAction) whenToConnectManuallyMenuItemWasClicked:          (id) sender;
-(IBAction) whenToConnectTunnelBlickLaunchMenuItemWasClicked: (id) sender;
-(IBAction) whenToConnectOnComputerStartMenuItemWasClicked:   (id) sender;

-(IBAction) advancedButtonWasClicked:                         (id) sender;


// Methods for GeneralView

-(IBAction) inhibitOutboundTBTrafficCheckboxWasClicked: (NSButton *) sender;
-(IBAction) updatesCheckAutomaticallyCheckboxWasClicked:         (NSButton *) sender;
-(IBAction) updatesCheckForBetaUpdatesCheckboxWasClicked:        (NSButton *) sender;
-(IBAction) updatesSendProfileInfoCheckboxWasClicked:            (NSButton *) sender;
-(IBAction) updatesCheckNowButtonWasClicked:                     (id) sender;

-(IBAction) resetDisabledWarningsButtonWasClicked:        (id) sender;

-(IBAction) generalHelpButtonWasClicked:                  (id) sender;


// Methods for AppearanceView

-(IBAction) appearancePlaceIconNearSpotlightCheckboxWasClicked:    (NSButton *) sender;

-(IBAction) appearanceDisplayConnectionSubmenusCheckboxWasClicked: (NSButton *) sender;
-(IBAction) appearanceDisplayConnectionTimersCheckboxWasClicked:   (NSButton *) sender;

-(IBAction) appearanceDisplaySplashScreenCheckboxWasClicked:       (NSButton *) sender;

-(IBAction) appearanceDisplayStatisticsWindowsCheckboxWasClicked:  (NSButton *) sender;

-(IBAction) appearanceDisplayStatisticsWindowWhenDisconnectedCheckboxWasClicked: (NSButton *) sender;

-(IBAction) appearanceHelpButtonWasClicked:                        (id) sender;


// Method for InfoView
-(IBAction) infoHelpButtonWasClicked: (id) sender;


// Methods for UtiltiesView

-(IBAction) utilitiesKillAllOpenVpnButtonWasClicked:      (id) sender;

-(IBAction) utilitiesCopyConsoleLogButtonWasClicked:      (id) sender;

-(IBAction) utilitiesHelpButtonWasClicked:                (id) sender;

-(IBAction) utilitiesOpenUninstallInstructionsButtonWasClicked: (id) sender;

// Getters & Setters

TBPROPERTY_READONLY(NSMutableArray *, leftNavDisplayNames)

TBPROPERTY_READONLY(ConfigurationsView *, configurationsPrefsView)

TBPROPERTY(NSString *, previouslySelectedNameOnLeftNavList, setPreviouslySelectedNameOnLeftNavList)

TBPROPERTY_READONLY(NSUInteger, selectedWhenToConnectIndex)

TBPROPERTY_READONLY(SettingsSheetWindowController *, settingsSheetWindowController)

TBPROPERTY(NSUInteger, selectedLeftNavListIndex,             setSelectedLeftNavListIndex)

TBPROPERTY(NSNumber *, selectedSetNameserverIndex,           setSelectedSetNameserverIndex)
TBPROPERTY(NSNumber *, selectedPerConfigOpenvpnVersionIndex, setSelectedPerConfigOpenvpnVersionIndex)

TBPROPERTY(NSNumber *, selectedKeyboardShortcutIndex, setSelectedKeyboardShortcutIndex)
TBPROPERTY(NSNumber *, selectedMaximumLogSizeIndex,   setSelectedMaximumLogSizeIndex)

TBPROPERTY(NSNumber *, selectedAppearanceIconSetIndex,                         setSelectedAppearanceIconSetIndex)
TBPROPERTY(NSNumber *, selectedAppearanceConnectionWindowDisplayCriteriaIndex, setSelectedAppearanceConnectionWindowDisplayCriteriaIndex)
TBPROPERTY(NSNumber *, selectedAppearanceConnectionWindowScreenIndex,          setSelectedAppearanceConnectionWindowScreenIndex)

@end
