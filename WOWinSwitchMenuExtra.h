//
//  WOWinSwitchMenuExtra.h
//
//  Based on FuseMenuExtra.h
//  Created by Martin Pittenauer on Fri Nov 07 2003.
//  Copyright (c) 2003 TheCodingMonkeys. All rights reserved.
//
//  Modifications by Wincent Colaiuta <win@wincent.org>
//  Copyright 2004-2006 Wincent Colaiuta.
// 
//  $Id$

#import <Cocoa/Cocoa.h>

#if defined(__ppc__)
#import "SystemUIPlugin_Panther.h"
#elif defined(__i386)
#import "SystemUIPlugin_Tiger.h"
#else
#error Unknown architecture
#endif

typedef enum WOSwitchMenuStyle {

    WOSwitchMenuIcon            = 0,
    WOSwitchMenuUserPicture     = 1,
    WOSwitchMenuFullUsername    = 2,
    WOSwitchMenuShortUsername   = 3,
    WOSwitchMenuFirstName       = 4,
    WOSwitchMenuInitials        = 5
    
} WOSwitchMenuStyle;

@class WOWinSwitchMenuExtraView;

@interface WOWinSwitchMenuExtra : NSMenuExtra {
    
    BOOL                        isPanther;
    
    NSMenu                      *theMenu;
    NSImage                     *theImage;      // default menu icon
    NSImage                     *altImage;      // default menu item, selected
    NSImage                     *userImage;     // custom user picture
    WOWinSwitchMenuExtraView    *theView;

    // NSMenuExtra has methods for attributed titles, but they look like NOPs
    NSAttributedString          *_attributedTitle;  // manage title here
    
    // user-settable preferences
    WOSwitchMenuStyle           menuStyle;      // icon, picture, full, short
    BOOL                        showRootUser; 
    float                       userPictureSize;    // 5.0 to 19.0 pixels
    float                       menuPictureSize;    // 16.0, 32.0 or 48.0 pixels
    
    // convenience pointers to items in the "Show" submenu
    NSMenu                      *showSubmenu;
    NSMenuItem                  *showIconMenuItem;
    NSMenuItem                  *showUserPictureMenuItem;
    NSMenuItem                  *showFullUsernameMenuItem;
    NSMenuItem                  *showShortUsernameMenuItem;
    NSMenuItem                  *showFirstNameOnlyMenuItem;
    NSMenuItem                  *showInitialsOnlyMenuItem;
    NSMenuItem                  *showRootUserMenuItem;
    
    @private
        // caches
        NSMutableDictionary     *_allUsersCache;
        NSMutableArray          *_sortedCache;
        NSMutableArray          *_loggedInUsers;
        NSMutableArray          *_realShells;
        
        // flags
        BOOL                    _refreshAllUsersCache;
        BOOL                    _refreshLoggedInUsers;
        BOOL                    _nonlocalUsersCurrentlyLoggedIn;
        
        // oft-used strings
        NSAttributedString      *_tick;
        NSAttributedString      *_dimmedTick;
        NSAttributedString      *_noTick;
        
}

- (id)initWithBundle:(NSBundle *)bundle;

@end