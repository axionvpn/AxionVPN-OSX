/*
 * Copyright 2011 Jonathan K. Bullard. All rights reserved.
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

#include "defines.h"

@interface LoginWindowController : NSWindowController <NSWindowDelegate>
{
    IBOutlet NSImageView        * iconIV;
    
    IBOutlet NSTextFieldCell    * mainText;
    
    IBOutlet NSButton           * cancelButton;
    IBOutlet NSButton           * OKButton;
    
    IBOutlet NSTextField        * username;
    IBOutlet NSSecureTextField  * password;
    
    IBOutlet NSTextFieldCell    * usernameTFC;
    IBOutlet NSTextFieldCell    * passwordTFC;
    
    IBOutlet NSButton           * saveUsernameInKeychainCheckbox;
    IBOutlet NSButton           * savePasswordInKeychainCheckbox;
    
    id                            delegate;
}

-(id)       initWithDelegate:       (id)            theDelegate;
-(void)     redisplay;

-(IBAction) cancelButtonWasClicked: (id)            sender;
-(IBAction) OKButtonWasClicked:     (id)            sender;

-(IBAction) saveUsernameInKeychainCheckboxWasClicked: (id) sender;

-(BOOL)     isSaveUsernameInKeychainChecked;
-(BOOL)     isSavePasswordInKeychainChecked;

TBPROPERTY_READONLY(NSTextField *,       username)
TBPROPERTY_READONLY(NSSecureTextField *, password)

TBPROPERTY_READONLY(NSButton *,    saveUsernameInKeychainCheckbox)
TBPROPERTY_READONLY(NSButton *,    savePasswordInKeychainCheckbox)

TBPROPERTY_READONLY(id, delegate)

@end
