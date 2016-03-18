/*
* Copyright 2014 Jonathan Bullard
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

@interface AlertWindowController : NSWindowController <NSWindowDelegate> {
    
    NSString                    * headline;
    NSString                    * message;
    
	IBOutlet NSImageView        * iconIV;
	
    IBOutlet NSTextField        * headlineTF;
    IBOutlet NSTextFieldCell    * headlineTFC;
    
	IBOutlet NSScrollView       * messageSV;
	IBOutlet NSTextView         * messageTV;
    
    IBOutlet NSButton           * okButton;

}


TBPROPERTY(NSString *, headline, setHeadline)
TBPROPERTY(NSString *, message,  setMessage)

TBPROPERTY_READONLY(NSImageView     *, iconIV)

TBPROPERTY_READONLY(NSTextField     *, headlineTF)
TBPROPERTY_READONLY(NSTextFieldCell *, headlineTFC)

TBPROPERTY_READONLY(NSScrollView    *, messageSV)
TBPROPERTY_READONLY(NSTextView      *, messageTV)

TBPROPERTY_READONLY(NSButton        *, okButton)
@end
