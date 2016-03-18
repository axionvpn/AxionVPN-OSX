/*
 * Copyright 2011, 2012, 2013 Jonathan K. Bullard. All rights reserved.
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


#import "defines.h"

@interface GeneralView : NSView {
    
    IBOutlet NSTextFieldCell    * keyboardShortcutTFC;
    IBOutlet NSTextField        * keyboardShortcutTF;
    IBOutlet NSArrayController  * keyboardShortcutArrayController;
    IBOutlet NSButton           * keyboardShortcutButton;
    
    IBOutlet NSTextFieldCell    * maxLogDisplaySizeTFC;
    IBOutlet NSTextField        * maxLogDisplaySizeTF;
    IBOutlet NSArrayController  * maximumLogSizeArrayController;
    IBOutlet NSButton           * maximumLogSizeButton;
    
    IBOutlet NSTextFieldCell    * warningsTFC;
    IBOutlet NSTextField        * warningsTF;
    IBOutlet NSButton           * resetDisabledWarningsButton;
    
    IBOutlet NSTextFieldCell    * tbInternetAccessTFC;
    IBOutlet NSTextField        * tbInternetAccessTF;
	IBOutlet NSButton           * inhibitOutboundTBTrafficCheckbox;
	
    IBOutlet NSTextFieldCell    * updatesUpdatesTFC;
    IBOutlet NSTextField        * updatesUpdatesTF;
    IBOutlet NSButton           * updatesCheckAutomaticallyCheckbox;
    IBOutlet NSButton           * updatesCheckForBetaUpdatesCheckbox;
    IBOutlet NSButton           * updatesSendProfileInfoCheckbox;
    IBOutlet NSButton           * updatesCheckNowButton;
    IBOutlet NSTextFieldCell    * updatesLastCheckedTFC;
    IBOutlet NSTextField        * updatesLastCheckedTF;
    
    IBOutlet NSButton           * preferencesGeneralHelpButton;
}

TBPROPERTY_READONLY(NSTextFieldCell *,   tbInternetAccessTFC)
TBPROPERTY_READONLY(NSTextField *,       tbInternetAccessTF)
TBPROPERTY_READONLY(NSButton *,          inhibitOutboundTBTrafficCheckbox)


TBPROPERTY_READONLY(NSTextFieldCell *,   updatesUpdatesTFC)
TBPROPERTY_READONLY(NSTextField *,       updatesUpdatesTF)
TBPROPERTY_READONLY(NSButton *,          updatesCheckAutomaticallyCheckbox)
TBPROPERTY_READONLY(NSButton *,          updatesCheckForBetaUpdatesCheckbox)
TBPROPERTY_READONLY(NSButton *,          updatesSendProfileInfoCheckbox)
TBPROPERTY_READONLY(NSTextFieldCell *,   updatesLastCheckedTFC)
TBPROPERTY_READONLY(NSTextField *,       updatesLastCheckedTF)

TBPROPERTY_READONLY(NSArrayController *, keyboardShortcutArrayController)
TBPROPERTY_READONLY(NSButton *,          keyboardShortcutButton)

TBPROPERTY_READONLY(NSArrayController *, maximumLogSizeArrayController)
TBPROPERTY_READONLY(NSButton *,          maximumLogSizeButton)

@end
