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

#import "AlertWindowController.h"

#import "defines.h"
#import "helper.h"

extern BOOL gShuttingDownWorkspace;

@implementation AlertWindowController

-(id) init
{
    self = [super initWithWindowNibName:@"AlertWindow"];
    if (  ! self  ) {
        return nil;
    }
    
	[self retain];		// Retain ourself. windowWillClose will release ourself.
    return self;
}

- (void) dealloc {
    
    [headline release]; headline = nil;
    [message  release]; message = nil;
    
	[super dealloc];
}

-(void) windowWillClose: (NSNotification *) notification {
	
    (void) notification;
	[self autorelease];
}

-(void) setupHeadline {
    
	NSTextField     * tf =  [self headlineTF];
	NSTextFieldCell * tfc = [self headlineTFC];

	[tfc setFont: [NSFont boldSystemFontOfSize: 12.0]];
	
    NSRect oldFrame = [tf frame];
    [tfc setTitle: [self headline]];
    [tf sizeToFit];
    NSRect newFrame = [tf frame];
    
	[tf setFrame: newFrame];
	
    CGFloat widthChange  = newFrame.size.width  - oldFrame.size.width;
    
	// If title doesn't fit window, adjust the window width so it does
    if (  widthChange > 0.0  ) {
		NSWindow * w = [self window];
		NSRect windowFrame = [w frame];
        windowFrame.size.width += widthChange;
		[w setFrame: windowFrame display: NO];
    }
}

float heightForStringDrawing(NSString *myString,
							 NSFont *myFont,
							 float myWidth) {
	
	// From http://stackoverflow.com/questions/1992950/nsstring-sizewithattributes-content-rect/1993376#1993376
	
	NSTextStorage *textStorage = [[[NSTextStorage alloc] initWithString:myString] autorelease];
	NSTextContainer *textContainer = [[[NSTextContainer alloc] initWithContainerSize:NSMakeSize(myWidth, FLT_MAX)] autorelease];
	
	NSLayoutManager *layoutManager = [[[NSLayoutManager alloc] init] autorelease];
	[layoutManager addTextContainer:textContainer];
	[textStorage addLayoutManager:layoutManager];
	[textStorage addAttribute:NSFontAttributeName value:myFont
						range:NSMakeRange(0, [textStorage length])];
	[textContainer setLineFragmentPadding:0.0];
	
	(void) [layoutManager glyphRangeForTextContainer:textContainer];
	return [layoutManager
			usedRectForTextContainer:textContainer].size.height;
}

-(void) setupMessage {
	
	NSTextView * tv = [self messageTV];
	
	// Calculate the change in height required to fit the text
	NSRect tvFrame = [tv frame];
	NSFont * font = [NSFont systemFontOfSize: 11.9];
	CGFloat newHeight = heightForStringDrawing([self message], font, tvFrame.size.width);
	CGFloat heightChange = newHeight - tvFrame.size.height;
	
	// Adjust the window for the new height
	NSWindow * w = [self window];
	[w setShowsResizeIndicator: NO];
	NSRect wFrame = [w frame];
	wFrame.size.height += heightChange;
	[w setFrame: wFrame display: NO];
	
	// Adjust the scroll view for the new height
	NSScrollView * sv = [self messageSV];
	[sv setBorderType: NSNoBorder];
	[sv setHasVerticalScroller: NO];
	NSRect svFrame = [sv frame];
	svFrame.size.height += heightChange;
	svFrame.origin.y    -= heightChange;
	[sv setFrame: svFrame];
	
	// Adjust the text vew for the new height
	tvFrame.size.height = newHeight;
	[tv setFrame: tvFrame];
	
	// Set the string
	NSString * msg = [self message];
	NSAttributedString * msgAs = [[[NSAttributedString alloc] initWithString: msg] autorelease];
	[[tv textStorage] setAttributedString: msgAs];
	
	[tv setSelectedRange: NSMakeRange([msg length] + 1, 0)];	// Make cursor disappear
}

-(void) setTitleOfButton: (NSButton *) button
					  to: (NSString *) newValue {
    
	// Allow button to get wider, but not narrrower
    NSRect oldFrame = [button frame];
    [button setTitle: newValue];
    [button sizeToFit];
    NSRect newFrame = [button frame];
    CGFloat widthChange  = newFrame.size.width  - oldFrame.size.width;
	
    if (  widthChange < 0.0  ) {
		[button setFrame: oldFrame];
		return;
	}
}

-(void) awakeFromNib {
	
    [[self window] setDelegate: self];
    
    [iconIV setImage: [NSImage imageNamed: @"NSApplicationIcon"]];
    
	[self setupHeadline];
    
	[self setupMessage];

	[self setTitleOfButton: [self okButton] to: NSLocalizedString(@"OK", @"Button")];
    
	NSWindow * w = [self window];
    
    [w setTitle: NSLocalizedString(@"Tunnelblick", @"Window title")];
    
	[w setDefaultButtonCell: [okButton cell]];
	
	[w center];
    [w display];
    [self showWindow: self];
    
	[NSApp activateIgnoringOtherApps: YES];
	
    [w makeKeyAndOrderFront: self];
}

TBSYNTHESIZE_OBJECT(retain, NSString *, headline, setHeadline)
TBSYNTHESIZE_OBJECT(retain, NSString *, message,  setMessage)

TBSYNTHESIZE_OBJECT_GET(retain, NSImageView     *, iconIV)

TBSYNTHESIZE_OBJECT_GET(retain, NSTextField     *, headlineTF)
TBSYNTHESIZE_OBJECT_GET(retain, NSTextFieldCell *, headlineTFC)

TBSYNTHESIZE_OBJECT_GET(retain, NSScrollView    *, messageSV)
TBSYNTHESIZE_OBJECT_GET(retain, NSTextView      *, messageTV)

TBSYNTHESIZE_OBJECT_GET(retain, NSButton        *, okButton)

@end
