//
//  WOWinSwitchMenuExtraView.m
//
//  Based on FuseMenuExtraView.m
//  Created by Martin Pittenauer on Fri Nov 07 2003.
//  Copyright (c) 2003 TheCodingMonkeys. All rights reserved.
//
//  Modifications by Wincent Colaiuta <win@wincent.org>
//  Copyright (c) 2004 Wincent Colaiuta. All rights reserved.
//
//  $Id$

#import "WOWinSwitchMenuExtraView.h"

@implementation WOWinSwitchMenuExtraView

- (id)initWithFrame:(NSRect)aRect menuExtra:aMenuExtra
{
    if (self = [super initWithFrame:aRect])
        menuExtra = aMenuExtra;
    return self;
}

- (void)drawRect:(NSRect)rect
{
    if (![menuExtra image])         // no image, draw title instead
    {
        NSGraphicsContext   *context    = [NSGraphicsContext currentContext];
        [context            setShouldAntialias:YES];
        [context            setImageInterpolation:NSImageInterpolationHigh];        
        NSMutableAttributedString *title =
            [[NSMutableAttributedString alloc] initWithAttributedString:
                [menuExtra attributedTitle]];
        if ([menuExtra isMenuDown])
        {
            [menuExtra drawMenuBackground:YES];
            [title addAttribute:NSForegroundColorAttributeName 
                          value:[NSColor selectedMenuItemTextColor] 
                          range:NSMakeRange(0, [title length])];
            [title drawAtPoint:NSMakePoint(4.0, 3.0)];
        }
        else
        {
            [menuExtra drawMenuBackground:NO];
            [title addAttribute:NSForegroundColorAttributeName 
                          value:[NSColor textColor]
                          range:NSMakeRange(0, [title length])];
            [title drawAtPoint:NSMakePoint(4.0, 3.0)];    
        }
        [title release];
    }
    else                                // no title, draw image
    {
        if ([menuExtra isMenuDown])
            [[menuExtra alternateImage] compositeToPoint:NSZeroPoint
                                               operation:NSCompositeSourceOver];
        else
            [[menuExtra image] compositeToPoint:NSZeroPoint
                                      operation:NSCompositeSourceOver];
    }
}

@end