//
//  WOWinSwitchMenuExtra.m
//
//  Based on FuseMenuExtra.m
//  Created by Martin Pittenauer on Fri Nov 07 2003.
//  Copyright (c) 2003 TheCodingMonkeys. All rights reserved.
//
//  Thanks to Rustam Muginov for explaining NSMenuExtra at
//  http://cocoadevcentral.com/articles/000078.php
//
//  Thanks to makaio at macosxhints for showing how CGSession works.
//  http://www.macosxhints.com/article.php?story=20031102031045417
//
//  Modifications by Wincent Colaiuta <win@wincent.org>
//  Copyright (c) 2004 Wincent Colaiuta. All rights reserved.
//
//  $Id$

#import "WOWinSwitchMenuExtra.h"
#import "WOWinSwitchMenuExtraView.h"
#import "NSString+WOWinSwitchExtensions.h"

// for getuid()
#import <unistd.h>

// Apple has removed /usr/include/netinfo/ from Panther; will use project copy
#import <netinfo/ni.h>

// for _loggedInUsers method
#import <assert.h>
#import <errno.h>
#import <stdbool.h>
#import <stdlib.h>
#import <stdio.h>
#import <sys/sysctl.h>
#import <sys/proc.h>

#define WO_CGSESSION \
@"/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"

#define WO_BUNDLE_IDENTIFIER        @"com.wincent.WinSwitch"
#define WO_PREF_MENU_STYLE          @"Menu bar style"
#define WO_PREF_SHOW_ROOT_USER      @"Show root user"
#define WO_PREF_USER_PICTURE_SIZE   @"User picture size"
#define WO_PREF_MENU_PICTURE_SIZE   @"User picture size in menu"
#define WO_PREF_HOT_KEY_SUSPENDS    @"Hot key suspends session"

// these notification names taken from output of the "strings" utility run on:
//  /System/Library/PreferencePanes/Accounts.prefPane/Contents/MacOS/Accounts
//  /System/Library/CoreServices/Menu Extras/User.menu/Contents/MacOS/User
#define WO_USER_REMOVED         @"com.apple.UserWasRemovedNotification"
#define WO_USER_DISABLED        @"com.apple.UserWasDisabledNotification"
#define WO_USER_PICTURE         @"com.apple.UserPictureDidChangeNotification"
#define WO_USER_NAME            @"com.apple.FullUserNameDidChangeNotification"
#define WO_USER_ADDED           @"com.apple.UserWasAddedNotification"
#define WO_USER_ENABLED         @"com.apple.UserWasEnabledNotification"

#define WS_UNLOAD_NOTIFICATION                                  \
@"com.wincent.WinSwitch.UnloadNotification"
#define WS_HELPER_CHANGED_NOTIFICATION                          \
@"com.wincent.WinSwitchHelper.PreferencesChangedNotification"
#define WS_PREF_CHANGED_NOTIFICATION                            \
@"com.wincent.WinSwitch.PreferencesChangedNotification"
#define WS_SHOW_PREF_WINDOW_NOTIFICATION                        \
@"com.wincent.WinSwitch.ShowPreferencesWindowNotification"

@interface WOWinSwitchMenuExtra (Private)

// methods for toggling menu bar style
- (void)_showSubmenuItemSelected:(id)sender;
- (void)_showIconInMenuBar;
- (void)_showUserImageInMenuBar;
- (void)_showFullUsernameInMenuBar;
- (void)_showShortUsernameInMenuBar;
- (void)_showFirstNameInMenuBar;
- (void)_showInitialsInMenuBar;
- (void)_flushPrefsToDisk;

// auto-run items on switch out or switch in
- (void)_processSwitchItems:(NSString *)folder;

// an array of the users (NSDictionaries) currently logged in
- (NSArray *)_loggedInUsers;

// as above, optionally forcing _loggedInUsers cache to be refreshed
- (NSArray *)_loggedInUsersForcingRebuild:(BOOL)rebuild;

// maintain a cache of all known users for rapid lookup
- (NSArray *)_allUsersCache;

// as above, optionally forcing _allUsersCache to be fully rebuilt
- (NSArray *)_allUsersCacheForcingRebuild:(BOOL)rebuild;

// get user information for non-local users (in global NetInfo domain)
- (NSDictionary *)_nonlocalUserForUID:(NSNumber *)UID;

// run once only, scans /etc/shells to find out what the "real shells" are
- (NSArray *)_realShells;

// query NetInfo for the property of a given key in the directory matching UID
- (NSString *)_propertyForKey:(NSString *)key user:(uid_t)UID;

// as above, but optionally search in the global domain
- (NSString *)_propertyForKey:(NSString *)key 
                         user:(uid_t)UID
               inGlobalDomain:(BOOL)global;

// get path to user icon by querying NetInfo
- (NSString *)_iconPathForUID:(uid_t)UID;

// as above, but optionally search in the global domain
- (NSString *)_iconPathForUID:(uid_t)UID inGlobalDomain:(BOOL)global;

// returns a "dimmed" version of an image
- (NSImage *)_dimmedImage:(NSImage *)image;

// returns a "padded" version of an image (2 pixel transparent border)
- (NSImage *)_paddedImage:(NSImage *)image;

// convenience method to make NSAttributedStrings for the menu
- (NSAttributedString *)_menuString:(NSString *)aString 
                       withIconPath:(NSString *)iconPath
                              state:(int)state
                          dimImages:(BOOL)dim;

// update cached copy of current user icon
- (void)_updateUserImage:(NSString *)aPath;

// convenience method that sets the NSAttributedString title for the menu extra
- (void)_setMenuTitleWithString:(NSString *)aString;

// returns full user name for current user (doesn't cache unlike NSFullUserName)
- (NSString *)_fullUserName;

@end

@implementation WOWinSwitchMenuExtra

- (id)initWithBundle:(NSBundle *)bundle
{
    self = [super initWithBundle:bundle];
    if (self == nil) return nil;
    
    theView = [[WOWinSwitchMenuExtraView alloc] initWithFrame:
        [[self view] frame] menuExtra:self];
    [self setView:theView];
    
    theMenu = [[NSMenu alloc] initWithTitle:@""];
    [theMenu setAutoenablesItems:NO];
    theImage = [[NSImage alloc] initWithContentsOfFile:
        [[self bundle] pathForImageResource:@"userIcon"]];
    altImage = [[NSImage alloc] initWithContentsOfFile:
        [[self bundle] pathForImageResource:@"userIconAlt"]];
    
    // register for notifications from System Preferences (Accounts.prefPane)
    NSDistributedNotificationCenter *distributedCenter =
        [NSDistributedNotificationCenter defaultCenter];

#define WO_ADD_OBSERVER(aNotification)                              \
    [distributedCenter addObserver:self                             \
                          selector:@selector(_handleNotification:)  \
                              name:aNotification                    \
                            object:nil]

    WO_ADD_OBSERVER(WO_USER_REMOVED);
    WO_ADD_OBSERVER(WO_USER_DISABLED);
    WO_ADD_OBSERVER(WO_USER_PICTURE);
    WO_ADD_OBSERVER(WO_USER_NAME);
    WO_ADD_OBSERVER(WO_USER_ADDED);
    WO_ADD_OBSERVER(WO_USER_ENABLED);
    WO_ADD_OBSERVER(WS_HELPER_CHANGED_NOTIFICATION);
    
    // other notifications (NSWorkspace)
    NSNotificationCenter *workspaceCenter = 
        [[NSWorkspace sharedWorkspace] notificationCenter];

    [workspaceCenter addObserver:self 
                        selector:@selector(_handleNotification:) 
                            name:NSWorkspaceSessionDidResignActiveNotification
                          object:nil];
    [workspaceCenter addObserver:self 
                        selector:@selector(_handleNotification:) 
                            name:NSWorkspaceSessionDidBecomeActiveNotification
                          object:nil];    

    // read preferences
    NSDictionary *preferences =
        [[NSUserDefaults standardUserDefaults] persistentDomainForName:
            WO_BUNDLE_IDENTIFIER];
    
    // menu style defaults to 0 (Standard Icon), even if preference not set
    menuStyle = [[preferences objectForKey:WO_PREF_MENU_STYLE] intValue];

    menuPictureSize = 
        [[preferences objectForKey:WO_PREF_MENU_PICTURE_SIZE] floatValue];
    
    if (menuPictureSize == 0)
        menuPictureSize = 32.0;         // if size is unset, use default size
    else if (menuPictureSize < 24.0)
        menuPictureSize = 16.0;         // in other cases force size to 16.0...
    else if (menuPictureSize > 42.0)
        menuPictureSize = 48.0;         // 48.0...
    else
        menuPictureSize = 32.0;         // or 32.0...
    
    showRootUser = 
        [[preferences objectForKey:WO_PREF_SHOW_ROOT_USER] boolValue];
    
    userPictureSize = 
        [[preferences objectForKey:WO_PREF_USER_PICTURE_SIZE] floatValue];
    
    if ((userPictureSize < 5.0) || (userPictureSize > 19.0))    // sanity check
        userPictureSize = 19.0;                     // use default picture size

    // get and store current user picture
    [self _updateUserImage:[self _iconPathForUID:getuid()]];
    
    if (menuStyle == WOSwitchMenuFullUsername)
        [self _showFullUsernameInMenuBar];
    else if (menuStyle == WOSwitchMenuShortUsername)
        [self _showShortUsernameInMenuBar];
    else if (menuStyle == WOSwitchMenuFirstName)
        [self _showFirstNameInMenuBar];
    else if (menuStyle == WOSwitchMenuInitials)
        [self _showInitialsInMenuBar];    

    // launch WinSwitchHelper, if present
    NSString *helper = [[self bundle] pathForResource:@"WinSwitchHelper" 
                                               ofType:@"app"];
    
    if (helper && [[NSWorkspace sharedWorkspace] openFile:helper])
        NSLog(@"WinSwitchHelper launched");
    else
        NSLog(@"Error trying to launch WinSwitchHelper");        
        
    NSLog(@"WinSwitch.menu loaded.");
    return self;
}

- (void)willUnload
{
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];

    NSDistributedNotificationCenter *distributedCenter =
        [NSDistributedNotificationCenter defaultCenter];
    
#define WO_REMOVE_OBSERVER(aNotification)           \
    [distributedCenter removeObserver:self          \
                                 name:aNotification \
                               object:nil]
        
    WO_REMOVE_OBSERVER(WO_USER_REMOVED);
    WO_REMOVE_OBSERVER(WO_USER_DISABLED);
    WO_REMOVE_OBSERVER(WO_USER_PICTURE);
    WO_REMOVE_OBSERVER(WO_USER_NAME);
    WO_REMOVE_OBSERVER(WO_USER_ADDED);
    WO_REMOVE_OBSERVER(WO_USER_ENABLED);    
    WO_REMOVE_OBSERVER(WS_HELPER_CHANGED_NOTIFICATION);

    // try to terminate WinSwitchHelper
    [distributedCenter postNotificationName:WS_UNLOAD_NOTIFICATION object:nil];
    
    [super willUnload];
}

- (void)dealloc
{
    [theMenu            release];
    [theView            release];
    [theImage           release];
    [altImage           release];
    [userImage          release];
    [_attributedTitle   release];
    [_allUsersCache     release];
    [_sortedCache       release];
    [_loggedInUsers     release];
    [_realShells        release];
    [_tick              release];
    [_dimmedTick        release];
    [_noTick            release];
    [super              dealloc];
}

- (void)_handleNotification:(NSNotification *)aNotification
{
    NSString *name = [aNotification name];
    if ([name isEqualToString:WO_USER_REMOVED]  ||
        [name isEqualToString:WO_USER_DISABLED] ||
        [name isEqualToString:WO_USER_ADDED]    ||
        [name isEqualToString:WO_USER_ENABLED])
    {
        // force rebuild of cache next time user clicks on the menu
        _refreshAllUsersCache = YES;
    }
    else if ([name isEqualToString:WO_USER_NAME])
    {
        _refreshAllUsersCache = YES;                // force cache rebuild
        if (menuStyle == WOSwitchMenuFullUsername)  // update title in menubar
            [self _showFullUsernameInMenuBar];
        else if (menuStyle == WOSwitchMenuInitials)
            [self _showInitialsInMenuBar];
        else if (menuStyle == WOSwitchMenuFirstName)
            [self _showFirstNameInMenuBar];
    }
    else if ([name isEqualToString:WO_USER_PICTURE])
    {
        [self _updateUserImage:[self _iconPathForUID:getuid()]];
        [theView setNeedsDisplay:YES];              	
        _refreshAllUsersCache = YES;
    }
    else if ([name isEqualToString:NSWorkspaceSessionDidBecomeActiveNotification])
    {
       // force rebuild of "logged in users" cache next time menu is clicked
        _refreshLoggedInUsers = YES;
        [self _processSwitchItems:@"Switch-In Items"];
    }
    else if ([name isEqualToString:NSWorkspaceSessionDidResignActiveNotification])
    {
        // force rebuild of "logged in users" cache next time menu is clicked
        _refreshLoggedInUsers = YES;
        [self _processSwitchItems:@"Switch-Out Items"];
    }
    else if ([name isEqualToString:WS_HELPER_CHANGED_NOTIFICATION])
    {
        NSDictionary *userInfo = [aNotification userInfo];
        if (userInfo)
        {
            id object = nil;
            if ((object = [userInfo objectForKey:WO_PREF_MENU_STYLE]))
            {
                WOSwitchMenuStyle newStyle = [object intValue];
                if ((newStyle == WOSwitchMenuFirstName) && 
                    (menuStyle != WOSwitchMenuFirstName))
                    [self _showFirstNameInMenuBar];
                else if ((newStyle == WOSwitchMenuFullUsername) &&
                         (menuStyle != WOSwitchMenuFullUsername))
                    [self _showFullUsernameInMenuBar];
                else if ((newStyle == WOSwitchMenuIcon) &&
                         (menuStyle != WOSwitchMenuIcon))
                    [self _showIconInMenuBar];
                else if ((newStyle == WOSwitchMenuInitials) &&
                         (menuStyle != WOSwitchMenuInitials))
                    [self _showInitialsInMenuBar];
                else if ((newStyle == WOSwitchMenuShortUsername) &&
                         (menuStyle != WOSwitchMenuShortUsername))
                    [self _showShortUsernameInMenuBar];
                else if ((newStyle == WOSwitchMenuUserPicture) &&
                         (menuStyle != WOSwitchMenuUserPicture))
                    [self _showUserImageInMenuBar];
            }
            if ((object = [userInfo objectForKey:WO_PREF_SHOW_ROOT_USER]))
            {
                if ([object boolValue] != showRootUser)
                    [self _showSubmenuItemSelected:showRootUserMenuItem];    
            }
            if ((object = [userInfo objectForKey:WO_PREF_MENU_PICTURE_SIZE]))
            {   
                if ([object floatValue] != menuPictureSize)
                {
                    menuPictureSize = [object floatValue];
                    if (menuPictureSize < 24.0)
                        menuPictureSize = 16.0;         // force size to 16.0...
                    else if (menuPictureSize > 42.0)
                        menuPictureSize = 48.0;         // 48.0...
                    else
                        menuPictureSize = 32.0;         // or 32.0 (the default)
                    [self _flushPrefsToDisk];
                    _refreshAllUsersCache = YES;
                }
            }
            if ((object = [userInfo objectForKey:WO_PREF_USER_PICTURE_SIZE]))
            {
                if ([object floatValue] != userPictureSize)
                {
                    userPictureSize = [object floatValue];
                    if ((userPictureSize < 5.0) || (userPictureSize > 19.0))
                        userPictureSize = 19.0;
                    [self _updateUserImage:[self _iconPathForUID:getuid()]];
                    [self _flushPrefsToDisk];
                    [theView setNeedsDisplay:YES];
                }
            }
        }
    }
}

// drop back to login window
- (void)suspend:(id)sender
{
    [NSTask launchedTaskWithLaunchPath:WO_CGSESSION 
                             arguments:[NSArray arrayWithObject:@"-suspend"]];
}

// open Accounts.prefPane
- (void)accountsPrefPane:(id)sender
{
    NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
    [workspace openFile:@"/System/Library/PreferencePanes/Accounts.prefPane"
        withApplication:@"System Preferences"
          andDeactivate:YES];
}

// open WinSwitch preferences (WinSwitchHelper)
- (void)openPreferences:(id)sender
{
    [[NSDistributedNotificationCenter 
        defaultCenter] postNotificationName:WS_SHOW_PREF_WINDOW_NOTIFICATION
                                     object:nil];
}

- (void)switchToUser:(id)sender
{
    NSString *UID = 
        [[[sender representedObject] objectForKey:@"UID"] stringValue];
    NSArray *args = [NSArray arrayWithObjects:@"-switchToUserID", UID, nil];
    [NSTask launchedTaskWithLaunchPath:WO_CGSESSION arguments:args];
}

- (void)_showSubmenuItemSelected:(id)sender
{
    NSDictionary *userInfo = nil;
    
    // Use performSelector:WithObject:AfterDelay: to give Cocoa time to 
    // unhighlight the menu title before actually performing the action
    // (changing the view size while the item is still highlighted can result in
    // visual glitches, such as temporarily clobbering any NSMenuExtras to the
    // right, whenever the view size is reduced); in the unlikely even that 
    // the user re-clicks the menu during the interval, we'll still get 
    // glitches, but they'll be cosmetic only
    if ((sender == showIconMenuItem) && 
        (menuStyle != WOSwitchMenuIcon))
    {
        userInfo = 
            [NSDictionary dictionaryWithObject:
                [NSNumber numberWithInt:WOSwitchMenuIcon]
                                        forKey:WO_PREF_MENU_STYLE];
        [self performSelector:@selector(_showIconInMenuBar) 
                   withObject:nil 
                   afterDelay:0.5];
    }
    else if ((sender == showUserPictureMenuItem) && 
             (menuStyle != WOSwitchMenuUserPicture))
    {
        userInfo = 
            [NSDictionary dictionaryWithObject:
                [NSNumber numberWithInt:WOSwitchMenuUserPicture]
                                        forKey:WO_PREF_MENU_STYLE];
        [self performSelector:@selector(_showUserImageInMenuBar) 
                   withObject:nil 
                   afterDelay:0.5];
    }
    else if ((sender == showFullUsernameMenuItem) && 
             (menuStyle != WOSwitchMenuFullUsername)) 
    {
        userInfo = 
            [NSDictionary dictionaryWithObject:
                [NSNumber numberWithInt:WOSwitchMenuFullUsername]
                                        forKey:WO_PREF_MENU_STYLE];
        [self performSelector:@selector(_showFullUsernameInMenuBar) 
                   withObject:nil 
                   afterDelay:0.5];
    }
    else if ((sender == showShortUsernameMenuItem) && 
             (menuStyle != WOSwitchMenuShortUsername))
    {
        userInfo = 
            [NSDictionary dictionaryWithObject:
                [NSNumber numberWithInt:WOSwitchMenuShortUsername]
                                        forKey:WO_PREF_MENU_STYLE];
        [self performSelector:@selector(_showShortUsernameInMenuBar) 
                   withObject:nil 
                   afterDelay:0.5];
    }
    else if ((sender == showFirstNameOnlyMenuItem) &&
             (menuStyle != WOSwitchMenuFirstName))
    {
        userInfo = 
            [NSDictionary dictionaryWithObject:
                [NSNumber numberWithInt:WOSwitchMenuFirstName]
                                        forKey:WO_PREF_MENU_STYLE];
        [self performSelector:@selector(_showFirstNameInMenuBar) 
                   withObject:nil 
                   afterDelay:0.5];
    }
    else if ((sender == showInitialsOnlyMenuItem) &&
             (menuStyle != WOSwitchMenuInitials))
    {
        userInfo = 
            [NSDictionary dictionaryWithObject:
                [NSNumber numberWithInt:WOSwitchMenuInitials]
                                        forKey:WO_PREF_MENU_STYLE];
        [self performSelector:@selector(_showInitialsInMenuBar) 
                   withObject:nil 
                   afterDelay:0.5];
    }
    else if (sender == showRootUserMenuItem)
    {
        if ([showRootUserMenuItem state] == NSOnState)
        {
            [showRootUserMenuItem setState:NSOffState];
            showRootUser = NO;
        }
        else
        {
            [showRootUserMenuItem setState:NSOnState];
            showRootUser = YES;
        }
        userInfo = 
            [NSDictionary dictionaryWithObject:
                [NSNumber numberWithBool:showRootUser]
                                    forKey:WO_PREF_SHOW_ROOT_USER];
                
        // force rebuild of cache next time user clicks on the menu
        _refreshAllUsersCache = YES;
        [self _flushPrefsToDisk];
    }
    if (userInfo)
        [[NSDistributedNotificationCenter 
            defaultCenter] postNotificationName:WS_PREF_CHANGED_NOTIFICATION 
                                         object:nil 
                                       userInfo:userInfo];
}

- (void)_flushPrefsToDisk
{
    // update preferences on disk
    NSDictionary *preferences =
    [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithInt:menuStyle],         WO_PREF_MENU_STYLE,
        [NSNumber numberWithBool:showRootUser],     WO_PREF_SHOW_ROOT_USER,
        [NSNumber numberWithFloat:userPictureSize], WO_PREF_USER_PICTURE_SIZE,
        [NSNumber numberWithFloat:menuPictureSize], WO_PREF_MENU_PICTURE_SIZE,
        nil];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setPersistentDomain:preferences
                          forName:WO_BUNDLE_IDENTIFIER];
    
    // synchronize method forces a disk-write
    if ([defaults synchronize] == NO)
        NSLog(@"WinSwitch.menu: error while writing preferences to disk");
}

// auto-run items on switch out or switch in
- (void)_processSwitchItems:(NSString *)folder
{
    // get path to "Application Support"
    NSString *applicationSupport = nil;
    
    int     domain      = kUserDomain;
    int     folderType  = kApplicationSupportFolderType;
    Boolean createFlag  = kDontCreateFolder;
    FSRef   folderRef;
    
    OSErr err = FSFindFolder(domain, folderType, createFlag, &folderRef);
    if (err == noErr)
    {
        CFURLRef url = CFURLCreateFromFSRef(kCFAllocatorDefault, &folderRef);
        if (url)
        {   
            applicationSupport = 
            [NSString stringWithString:[(NSURL *)url path]];
            CFRelease(url);
        }
    }
    
    NSString *path = 
        [[applicationSupport stringByAppendingPathComponent:@"WinSwitch"]
            stringByAppendingPathComponent:folder];
    NSFileManager   *defaultManager = [NSFileManager defaultManager];
    NSArray         *items = [defaultManager directoryContentsAtPath:path];
    NSWorkspace     *sharedWorkspace = [NSWorkspace sharedWorkspace];
    NSEnumerator    *enumerator = [items objectEnumerator];
    NSString        *itemName;
    
    while ((itemName = [enumerator nextObject]))
    {
        if ([itemName hasPrefix:@"."]) continue;
        NSString *itemPath = [path stringByAppendingPathComponent:itemName];
        if ([sharedWorkspace openFile:itemPath])
            NSLog(@"Auto-launched item \"%@\"", itemPath);
        else
            NSLog(@"Error auto-launching item \"%@\"", itemPath);
    }
}

- (void)_showIconInMenuBar
{
    [[showSubmenu itemAtIndex:(int)menuStyle] setState:NSOffState];
    menuStyle = WOSwitchMenuIcon;
    [[showSubmenu itemAtIndex:(int)menuStyle] setState:NSOnState];
    [theView setFrameSize:NSMakeSize(19.0, [theView frame].size.height)];      
    [self setLength:19.0];
    [theView setNeedsDisplay:YES];
    [self _flushPrefsToDisk];
}

- (void)_showUserImageInMenuBar
{
    [[showSubmenu itemAtIndex:(int)menuStyle] setState:NSOffState];
    menuStyle = WOSwitchMenuUserPicture;
    [[showSubmenu itemAtIndex:(int)menuStyle] setState:NSOnState];
    [theView setFrameSize:NSMakeSize(19.0, [theView frame].size.height)];      
    [self setLength:19.0];
    [theView setNeedsDisplay:YES];              	
    [self _flushPrefsToDisk];
}

- (void)_showFullUsernameInMenuBar
{
    [[showSubmenu itemAtIndex:(int)menuStyle] setState:NSOffState];
    menuStyle = WOSwitchMenuFullUsername;
    [[showSubmenu itemAtIndex:(int)menuStyle] setState:NSOnState];
    // Cocoa bug: NSFullUserName() caches user names, and so may not pick up 
    // changes if user edits name; use custom method instead (<rdar://3607237/>)
    [self _setMenuTitleWithString:[self _fullUserName]];
    NSSize textSize = [[self attributedTitle] size];
	[theView setFrameSize:
        NSMakeSize(textSize.width + 8.0, [theView frame].size.height)];     
	[self setLength:textSize.width + 8.0];
    [theView setNeedsDisplay:YES];              	
    [self _flushPrefsToDisk];
}

- (void)_showShortUsernameInMenuBar
{
    [[showSubmenu itemAtIndex:(int)menuStyle] setState:NSOffState];
    menuStyle = WOSwitchMenuShortUsername;
    [[showSubmenu itemAtIndex:(int)menuStyle] setState:NSOnState];
    [self _setMenuTitleWithString:NSUserName()];
    NSSize textSize = [[self attributedTitle] size];
	[theView setFrameSize:
        NSMakeSize(textSize.width + 8.0, [theView frame].size.height)];     
	[self setLength:textSize.width + 8.0];
    [theView setNeedsDisplay:YES];              	
    [self _flushPrefsToDisk];
}

- (void)_showFirstNameInMenuBar
{    
    [[showSubmenu itemAtIndex:(int)menuStyle] setState:NSOffState];
    menuStyle = WOSwitchMenuFirstName;
    [[showSubmenu itemAtIndex:(int)menuStyle] setState:NSOnState];
    
    NSString *firstName = nil;
    NSArray *names = [[self _fullUserName] componentsSeparatedByString:@" "];
    if (names && ([names count] > 0))
        firstName = [names objectAtIndex:0];
    
    [self _setMenuTitleWithString:firstName];
    NSSize textSize = [[self attributedTitle] size];
    [theView setFrameSize:
        NSMakeSize(textSize.width + 8.0, [theView frame].size.height)];
    [self setLength:textSize.width + 8.0];
    [theView setNeedsDisplay:YES];
    [self _flushPrefsToDisk];
}

- (void)_showInitialsInMenuBar
{
    [[showSubmenu itemAtIndex:(int)menuStyle] setState:NSOffState];
    menuStyle = WOSwitchMenuInitials;
    [[showSubmenu itemAtIndex:(int)menuStyle] setState:NSOnState];
    
    NSMutableString *initials = [NSMutableString string];
    NSArray *names = 
        [[self _fullUserName] componentsSeparatedByWhitespace:@" .,"];
    NSEnumerator *enumerator = [names objectEnumerator];
    NSString *name;
    
    while ((name = [enumerator nextObject]))
    {
        if ([name length] > 0)
            [initials appendString:[name substringToIndex:1]];
    }
    
    [self _setMenuTitleWithString:initials];
    NSSize textSize = [[self attributedTitle] size];
    [theView setFrameSize:
        NSMakeSize(textSize.width + 8.0, [theView frame].size.height)];
    [self setLength:textSize.width + 8.0];
    [theView setNeedsDisplay:YES];
    [self _flushPrefsToDisk];
}

- (NSMenu *)menu
{
    BOOL    addNonUserItems = NO;       // default: do not add non-user items
    int     count           = [theMenu numberOfItems];
    
    if (count == 0)             // must build menu for the very first time
        addNonUserItems = YES;  // must add "Login window...", "Show" etc
    else if (_refreshAllUsersCache || _refreshLoggedInUsers) // must re-build
    {
        int i;                                  // erase all items
        for (i = 0; i < (count - 7); i++)       // except the last seven
            [theMenu removeItemAtIndex:0];      // "Login window...", "Show" etc
    }
    else
        return theMenu;             // menu is already built, return it
    
    if (_nonlocalUsersCurrentlyLoggedIn)
    {        
        // it's never enough to just refresh the logged-in users cache;
        // non-local user may have logged out, invalidating the all users cache
        _refreshAllUsersCache = YES;    

        // force rebuild of _loggedInUsers cache because otherwise updating the
        // _allUsersCache will discard logged-in users from list
        _refreshLoggedInUsers = YES;
    }
        
    // order matters because _loggedInUsers might add items to the array
    NSArray         *allUsersCache  = [self _allUsersCache];    // order matters
    NSArray         *loggedInUsers  = [self _loggedInUsers];    // order matters
    uid_t           currentUid      = getuid();
    NSEnumerator    *enumerator     = [allUsersCache reverseObjectEnumerator];
    NSDictionary    *user           = nil;

    while ((user = [enumerator nextObject]))
    {
        if (![[user objectForKey:@"RealShell"] boolValue])
            continue;   // skip "users" without real shells
           
        NSMenuItem *item = 
        [[NSMenuItem alloc] initWithTitle:[user objectForKey:@"Username"]
                                   action:@selector(switchToUser:)
                            keyEquivalent:@""];
        [item setRepresentedObject:user];
        
        // check if user is logged in
        if ([loggedInUsers containsObject:user])
            [item setAttributedTitle:[user objectForKey:@"UsernamePlusTick"]];
        else
            [item setAttributedTitle:[user objectForKey:@"UsernameNoTick"]];    
        
        [theMenu insertItem:item atIndex:0];    // insert at start of menu
        [item setTarget:self];
        [item release];
        
        if ((uid_t)[[user objectForKey:@"UID"] intValue] == currentUid)
            [item setEnabled:NO]; // disable item if corresponds to current user
    }
    
    if (addNonUserItems)
    {
        // add "Show" submenu
        [theMenu addItem:[NSMenuItem separatorItem]];
        
        NSString *showSubmenuTitle = NSLocalizedStringFromTableInBundle
            (@"Show", @"", [self bundle], @"Show");
        
        NSMenuItem *showItem = 
            [theMenu addItemWithTitle:showSubmenuTitle
                               action:@selector(_showSubmenuItemSelected:) 
                        keyEquivalent:@""];
        
        [showItem setTarget:self];

        showSubmenu = [[NSMenu alloc] initWithTitle:@"foo"];
        [theMenu setSubmenu:showSubmenu forItem:showItem];
        [showSubmenu release];
        
#define WO_ADD_SHOW_SUBMENU_ITEM(menu, text)                                \
        NSString *menu ## Title = NSLocalizedStringFromTableInBundle        \
            (text, @"", [self bundle], text);                               \
        menu = (NSMenuItem *)[showSubmenu addItemWithTitle:menu ## Title    \
                               action:@selector(_showSubmenuItemSelected:)  \
                               keyEquivalent:@""];                          \
        [menu setTarget:self]; /* can call macro with or without semicolon */
            
        WO_ADD_SHOW_SUBMENU_ITEM(showIconMenuItem,          @"Standard icon");
        WO_ADD_SHOW_SUBMENU_ITEM(showUserPictureMenuItem,   @"User picture");
        WO_ADD_SHOW_SUBMENU_ITEM(showFullUsernameMenuItem,  @"Name");
        WO_ADD_SHOW_SUBMENU_ITEM(showShortUsernameMenuItem, @"Short name");
        WO_ADD_SHOW_SUBMENU_ITEM(showFirstNameOnlyMenuItem, @"First name only");
        WO_ADD_SHOW_SUBMENU_ITEM(showInitialsOnlyMenuItem,  @"Initials only");
        [showSubmenu addItem:[NSMenuItem separatorItem]];   // separator
        WO_ADD_SHOW_SUBMENU_ITEM(showRootUserMenuItem,      @"Root user");
        
        if (menuStyle == WOSwitchMenuIcon)
            [showIconMenuItem setState:NSOnState];
        else if (menuStyle == WOSwitchMenuUserPicture)
            [showUserPictureMenuItem setState:NSOnState];
        else if (menuStyle == WOSwitchMenuFullUsername)
            [showFullUsernameMenuItem setState:NSOnState];
        else if (menuStyle == WOSwitchMenuShortUsername)
            [showShortUsernameMenuItem setState:NSOnState];
        else if (menuStyle == WOSwitchMenuFirstName)
            [showFirstNameOnlyMenuItem setState:NSOnState];
        else if (menuStyle == WOSwitchMenuInitials)
            [showInitialsOnlyMenuItem setState:NSOnState];
        
        if (showRootUser)
            [showRootUserMenuItem setState:NSOnState];

        // add "WinSwitch Preferences..." item
        [theMenu addItem:[NSMenuItem separatorItem]];        
        NSString *winSwitchPreferences = NSLocalizedStringFromTableInBundle
            (@"WinSwitch Preferences", @"", [self bundle], 
             @"WinSwitch Preferences");
        [[theMenu addItemWithTitle:winSwitchPreferences
                            action:@selector(openPreferences:)
                     keyEquivalent:@""] setTarget:self];
        
        // add "Open Accounts..." item
        NSString *openAccounts = NSLocalizedStringFromTableInBundle
            (@"Open Accounts", @"", [self bundle], @"Open Accounts");
        [[theMenu addItemWithTitle:openAccounts
                            action:@selector(accountsPrefPane:)
                     keyEquivalent:@""] setTarget:self];
        
        // add "Login Window..." item
        [theMenu addItem:[NSMenuItem separatorItem]];
        NSString *loginWindow = NSLocalizedStringFromTableInBundle
            (@"Login Window", @"", [self bundle],
             @"Login Window");
        [[theMenu addItemWithTitle:loginWindow 
                            action:@selector(suspend:) 
                     keyEquivalent:@""] setTarget:self];
    }
    return theMenu;
}

- (NSImage *)image
{
    if (menuStyle == WOSwitchMenuIcon)
        return theImage;
    else if (menuStyle == WOSwitchMenuUserPicture)
        return userImage;
    else
        return nil;
}

- (NSImage *)alternateImage
{
    if (menuStyle == WOSwitchMenuIcon)
        return altImage;
    else if (menuStyle == WOSwitchMenuUserPicture)
        return userImage;
    else
        return nil;
}

- (NSArray *)_loggedInUsers
{
    return [self _loggedInUsersForcingRebuild:_refreshLoggedInUsers];
}

/*
 Look for "loginwindow" processes and get corresponding user IDs. Cache results
 and only refresh cache if explicitly requested.
 */
- (NSArray *)_loggedInUsersForcingRebuild:(BOOL)rebuild
{
    if (rebuild)    // must rebuild array (users have switched, logged in etc)
    {
        [_loggedInUsers release];   // dispose of old array
        _refreshLoggedInUsers = NO; // no need to rebuild next time around
    }
    else if (_loggedInUsers)        // array already exists, no rebuild required
        return _loggedInUsers;
    
    if (!_allUsersCache)                // ensure that cache is initialized
        (void)[self _allUsersCache];    // forces initialization
    
    // reset these to their original states
    _loggedInUsers = [[NSMutableArray alloc] initWithCapacity:1];
    _nonlocalUsersCurrentlyLoggedIn = NO;                   
    
    NSDictionary *userList = _allUsersCache;
    
    // for checking if user is logged in already:
    //   <http://developer.apple.com/qa/qa2001/qa1123.html>

    int                 mib[4]      = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    struct kinfo_proc   *processes  = NULL;
    size_t              length      = 0;
    int                 err;
    
    err = sysctl(mib, 4, NULL, &length, NULL, 0);   // find out size of buffer
    if (err >= 0)
    {
        processes = (struct kinfo_proc*)malloc(length);
        if (processes)
        {
            err = sysctl(mib, 4, processes, &length, NULL, 0);
            if (err >= 0)
            {
                int i;  // search for "loginwindow" processes
                int procCount = length / sizeof(struct kinfo_proc);
                for (i = 0; i < procCount; i++)
                {
                    if ((processes[i].kp_proc.p_comm) &&
                        (strcmp(processes[i].kp_proc.p_comm,"loginwindow")==0))
                    {
                        // match found! find out owner
                        uid_t userId = processes[i].kp_eproc.e_ucred.cr_uid;
                        
                        // skip root user unless preferences say otherwise
                        if (userId == 0 && !showRootUser) continue;
                        
                        NSNumber *UID = [NSNumber numberWithInt:userId];
                        NSDictionary *user = [userList objectForKey:UID];
                        if (user)   // local user
                        {
                                [_loggedInUsers addObject:user];                            
                        }
                        else        // non-local user
                        {
                            user = [self _nonlocalUserForUID:UID];
                            if (!user) 
                                continue; // failed to get non-local user info
                            [_loggedInUsers addObject:user];
                            [_allUsersCache setObject:user forKey:UID];
                            [_sortedCache   addObject:user];
                            _nonlocalUsersCurrentlyLoggedIn = YES;
                        }
                    }
                }
            }
            free(processes);
        }
    }
    
    if (_nonlocalUsersCurrentlyLoggedIn)  // must resort _sortedCache
    {
        NSSortDescriptor *descriptor = [NSSortDescriptor alloc];
        [descriptor initWithKey:@"Username" 
                      ascending:YES
                       selector:@selector(caseInsensitiveCompare:)];
        [_sortedCache sortUsingDescriptors:
            [NSArray arrayWithObject:descriptor]];
        [descriptor release];
    }
    
    return _loggedInUsers;
}

- (NSArray *)_allUsersCache
{
    return [self _allUsersCacheForcingRebuild:_refreshAllUsersCache];
}

//  Maintain a cache of all known users for rapid lookup
- (NSArray *)_allUsersCacheForcingRebuild:(BOOL)rebuild
{
    if (rebuild) // must rebuild cache (user added, icon changed etc)
    {
        [_allUsersCache release];   // dispose of old caches
        [_sortedCache   release];
        _refreshAllUsersCache = NO; // no need to rebuild next time around
    }
    else if (_sortedCache)          // cache already exists, no rebuild required
        return _sortedCache;        // return pre-built cache
    
    _allUsersCache  = [[NSMutableDictionary alloc] initWithCapacity:1];
    _sortedCache    = [[NSMutableArray alloc] initWithCapacity:1];

    // get UIDs in "users" directory in current (local) domain from NetInfo
    void *handle;
    ni_status status = ni_open(NULL, ".", &handle);
    if (status != NI_OK) return _sortedCache; // can't even connect to NetInfo!
    ni_id dir;
    const char *search = "/users";
    status = ni_pathsearch(handle, &dir, search);   // find "users" dir
    if (status == NI_OK)
    {
        ni_entrylist users;
        status = ni_list(handle, &dir, "uid", &users);  // check for UIDs > 500
        if (status == NI_OK)
        {
            unsigned i;
            for (i = 0; i < users.ni_entrylist_len; i++)
            {
                ni_name user = 
                users.ni_entrylist_val[i].names->ni_namelist_val[0];
                uid_t uid = strtol(user, NULL, 10);
                // must cast to signed otherwise user "nobody" (-2) passes test
                if (showRootUser)
                {
                    if (((signed)uid <= 500) && ((signed)uid != 0)) continue;
                }
                else
                {
                    if ((signed)uid <= 500) continue;
                }
                
                // add user to caches
                NSMutableDictionary *theUser = 
                    [NSMutableDictionary dictionary];
                NSNumber *UIDKey = [NSNumber numberWithInt:uid];
                [_allUsersCache setObject:theUser forKey:UIDKey];
                [_sortedCache addObject:theUser];
                
                // UID is also an object in the dictionary
                [theUser setObject:UIDKey forKey:@"UID"];
                
                // does user have a real shell?
                NSArray  *realShells = [self _realShells];
                NSString *shell = [self _propertyForKey:@"shell" user:uid];
                
                if (shell && [realShells containsObject:shell])
                    [theUser setObject:[NSNumber numberWithBool:YES]
                                forKey:@"RealShell"];
                else // "user" has no real shell so is probably a daemon
                {
                    [theUser setObject:[NSNumber numberWithBool:NO]
                                forKey:@"RealShell"];
                    continue;
                }
                
                // long username, used for sorting
                NSString *username = 
                    [self _propertyForKey:@"realname" user:uid];

                if (!username)  // try to use short name as fallback
                {
                    username = [self _propertyForKey:@"name" user:uid];
                    
                    // this should never happen, but just in case...
                    if (!username) username = @"...";
                }
                
                [theUser setObject:username forKey:@"Username"];
                
                // username + image + tick (NSAttributedString)
                // (dimmed for current user)
                NSAttributedString *usernamePlusTick;
                NSString *iconPath = [self _iconPathForUID:uid];
                if (!iconPath)  // no custom icon for this user, use generic
                    iconPath = [[self bundle] pathForImageResource:@"generic"];
                uid_t current_user = getuid();
                if (uid == current_user) // store image + tick, dimmed
                {
                    usernamePlusTick = [self _menuString:username 
                                            withIconPath:iconPath
                                                   state:NSOnState
                                               dimImages:YES];
                    [theUser setObject:usernamePlusTick 
                                forKey:@"UsernamePlusTick"];
                }
                else // not current user: store with & without tick (not dimmed)
                {
                    usernamePlusTick = [self _menuString:username 
                                            withIconPath:iconPath
                                                   state:NSOnState
                                               dimImages:NO];
                    [theUser setObject:usernamePlusTick 
                                forKey:@"UsernamePlusTick"];
                    
                    // NSAttributedString -> username + image + no tick
                    NSAttributedString *usernameNoTick =
                        [self _menuString:username
                             withIconPath:iconPath
                                    state:NSOffState
                                dimImages:NO];
                    [theUser setObject:usernameNoTick 
                                forKey:@"UsernameNoTick"];
                }                    
            }
            ni_entrylist_free(&users);
        }
    }
    ni_free(handle);    // closes NetInfo connection
        
    // keep pointers in sync between _loggedInUsers and _allUsersCache
    // this allows for id-based comparisons between the two lists
    if (_loggedInUsers)
    {
        // enumeration should be quite fast as there are unlikely
        // to be a large number of simultaneous sessions
        unsigned count = [_loggedInUsers count];
        unsigned i; 
        for (i = 0; i < count; i++)
        {
            NSNumber *oldUserKey = 
                [[_loggedInUsers objectAtIndex:i] objectForKey:@"UID"];
            NSDictionary *newUserDictionary = 
                [_allUsersCache objectForKey:oldUserKey];
            if (newUserDictionary)
                // match found: update pointer
                [_loggedInUsers replaceObjectAtIndex:i 
                                          withObject:newUserDictionary];
        }
    }
    
    // instead of returning the raw dictionary, return it as a sorted array
    NSSortDescriptor *descriptor = [NSSortDescriptor alloc];
    [descriptor initWithKey:@"Username" 
                  ascending:YES
                   selector:@selector(caseInsensitiveCompare:)];
    [_sortedCache sortUsingDescriptors:
        [NSArray arrayWithObject:descriptor]];
    [descriptor release];
    
    return _sortedCache;
}

- (NSDictionary *)_nonlocalUserForUID:(NSNumber *)UID
{
    uid_t               uid     = [UID intValue]; 
    NSMutableDictionary *user   = [NSMutableDictionary dictionary];
    
    // key 1: UID
    [user setObject:UID forKey:@"UID"];
    
    // key 2: RealShell
    NSArray *realShells = [self _realShells];
    NSString *shell = [self _propertyForKey:@"shell"
                                       user:uid
                             inGlobalDomain:YES];
    if (shell && [realShells containsObject:shell])
        [user setObject:[NSNumber numberWithBool:YES]
                 forKey:@"RealShell"];
    else
        return nil;
    
    // key 3: Username
    NSString *username = [self _propertyForKey:@"realname"
                                          user:uid
                                inGlobalDomain:YES];
    
    if (!username) // try to use short name as fallback
    {
        username = [self _propertyForKey:@"name"
                                    user:uid
                          inGlobalDomain:YES];
        
        // this should never happen, but just in case...
        if (!username) username = @"...";
    }
    
    [user setObject:username forKey:@"Username"];
    
    // key 4: UsernamePlusTick (username + image + tick)
    NSAttributedString *usernamePlusTick;
    NSString *iconPath = [self _iconPathForUID:uid inGlobalDomain:YES];
    if (!iconPath)  // no custom icon available for this user, use generic
        iconPath = [[self bundle] pathForImageResource:@"generic"];
    uid_t current_user = getuid();
    if (uid == current_user) // store image + tick, dimmed
    {
        usernamePlusTick = [self _menuString:username
                                withIconPath:iconPath
                                       state:NSOnState
                                   dimImages:YES];
    }
    else // not current user: store image + tick, not dimmed
    {
        usernamePlusTick = [self _menuString:username
                                withIconPath:iconPath
                                       state:NSOnState
                                   dimImages:NO];
    }
    [user setObject:usernamePlusTick forKey:@"UsernamePlusTick"];
    
    return user;
}

// run once only, scans /etc/shells to find out what the "real shells" are
- (NSArray *)_realShells
{
    if (!_realShells)   // first time here, initialize list of shells
    {
        NSString *shells = [NSString stringWithContentsOfFile:@"/etc/shells"];
        if (shells) // file read successfully, try to extract paths from output
        {
            // this would be so much easier with a regular expression
            _realShells = 
            [[shells componentsSeparatedByString:@"\n"] mutableCopy];

            // must use signed ints here because the for loop will run towards 0
            // if we "continue" on the last line we'd hit -1 and keep looping
            signed max = (signed)[_realShells count];
            signed i;

            // strip out empty lines and lines not beinging with "/"
            for (i = max - 1; i >= 0; i--)
            {
                NSString *line = [_realShells objectAtIndex:i];
                
                if ([line isEqualToString:@""] || ![line hasPrefix:@"/"])
                {
                    [_realShells removeObjectAtIndex:i];
                    continue;
                }
                
                // strip out comments
                NSRange comment = [line rangeOfString:@"#"];
                
                if (!NSEqualRanges(comment, NSMakeRange(NSNotFound, 0)))
                {
                    // this line has a comment! strip it
                    line = [line substringToIndex:comment.location];
                    [_realShells replaceObjectAtIndex:i withObject:line];
                }
                
                // strip trailing whitespace
                line = [line stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceAndNewlineCharacterSet]];
                [_realShells replaceObjectAtIndex:i withObject:line];
            }
        }
        else        // file could not be read: supply defaults
            _realShells = [[NSArray alloc] initWithObjects:@"/bin/bash",
                @"/bin/csh", @"/bin/sh", @"/bin/tcsh", @"/bin/zsh", nil];
    }    
    return _realShells; // release message is sent in the dealloc method
}

// query NetInfo for the property of a given key in the directory matching UID
- (NSString *)_propertyForKey:(NSString *)key user:(uid_t)UID
{
    return [self _propertyForKey:key user:UID inGlobalDomain:NO];
}

- (NSString *)_propertyForKey:(NSString *)key 
                         user:(uid_t)UID
               inGlobalDomain:(BOOL)global
{
    NSString *returnString = nil;
    void *handle;
    ni_status status;
    if (global)     // global domain
        status = ni_open(NULL, "/", &handle);
    else            // local domain
        status = ni_open(NULL, ".", &handle);
    if (status != NI_OK) return nil;
    ni_id dir;
    const char *search = 
        [[NSString stringWithFormat:@"/users/uid=%d", UID] UTF8String];
    status = ni_pathsearch(handle, &dir, search);
    if (status == NI_OK)
    {
        ni_namelist properties;
        NI_INIT(&properties);
        status = ni_lookupprop(handle, &dir, [key UTF8String], &properties);
        if ((status == NI_OK) && (properties.ni_namelist_val[0]))
        {
            // note that only first property is returned
            returnString = 
            [NSString stringWithUTF8String:properties.ni_namelist_val[0]];
        }
        ni_namelist_free(&properties);
    }
    ni_free(handle);
    return returnString;    // returns nil on failure
}

// get path to user icon by querying NetInfo, returns nil on failure
- (NSString *)_iconPathForUID:(uid_t)UID
{
    return [self _iconPathForUID:UID inGlobalDomain:NO];
}

- (NSString *)_iconPathForUID:(uid_t)UID inGlobalDomain:(BOOL)global
{
    NSString *path
    = [self _propertyForKey:@"picture" user:UID inGlobalDomain:global];

    // watch out for an empty "picture" key in the NetInfo database
    if (path && ([path length] == 0)) path  = nil;
    
    // check to make sure file exists on disk (NetInfo may be stale)
    if (path)
    {
        if (![[NSFileManager defaultManager] fileExistsAtPath:path
                                                  isDirectory:NO])
            path = nil;
    }
    return path;
}

- (NSImage *)_dimmedImage:(NSImage *)image
{
    NSRect bounds;
    bounds.origin           = NSZeroPoint;
    bounds.size             = [image size];
    NSImage *dimmedImage    = [[NSImage alloc] initWithSize:bounds.size];
    [dimmedImage lockFocus];
    {
        [image compositeToPoint:NSZeroPoint
                      operation:NSCompositeSourceOver];
        [[NSColor colorWithDeviceWhite:1.0 alpha:0.5] set];
        NSRectFillUsingOperation(bounds, NSCompositeSourceAtop);
    }
    [dimmedImage unlockFocus];
    return [dimmedImage autorelease];
}

- (NSImage *)_paddedImage:(NSImage *)image
{
    NSRect bounds, paddedBounds;
    bounds.origin           = NSZeroPoint;
    bounds.size             = [image size];
    paddedBounds            = NSMakeRect(bounds.origin.x, 
                                         bounds.origin.y, 
                                         bounds.size.height + 8.0, 
                                         bounds.size.height + 8.0);
    NSImage *paddedImage    = [[NSImage alloc] initWithSize:paddedBounds.size];
    [paddedImage lockFocus];
    {
        [image compositeToPoint:NSMakePoint(4.0, 4.0)
                      operation:NSCompositeSourceOver];
    }
    [paddedImage unlockFocus];
    return [paddedImage autorelease];
}

// The code for creating attributed strings with embedded images is quite bulky
// and ugly, so split it off into a separate method.
- (NSAttributedString *)_menuString:(NSString *)aString 
                       withIconPath:(NSString *)iconPath
                              state:(int)state
                          dimImages:(BOOL)dim
{    
    // initialize instance variables only as required
    if ((state == NSOnState) && (!dim) && (!_tick))
    {
        NSString *path = [[self bundle] pathForResource:@"tick" ofType:@"tiff"];
        NSFileWrapper *wrapper = [[NSFileWrapper alloc] initWithPath:path];
        NSTextAttachment *attachment = 
            [[NSTextAttachment alloc] initWithFileWrapper:wrapper];
        _tick = [NSAttributedString attributedStringWithAttachment:attachment];
        [_tick      retain];    // have this object persist
        [wrapper    release];
        [attachment release];
    }
    
    if ((state == NSOnState) && (dim) && (!_dimmedTick))
    {
        NSString *path = [[self bundle] pathForResource:@"tick" ofType:@"tiff"];
        NSFileWrapper *wrapper = [[NSFileWrapper alloc] initWithPath:path];
        NSTextAttachment *attachment =
            [[NSTextAttachment alloc] initWithFileWrapper:wrapper];
        NSTextAttachmentCell *cell = 
            (NSTextAttachmentCell *)[attachment attachmentCell];
        [cell setImage:[self _dimmedImage:[cell image]]];
        _dimmedTick = 
            [NSAttributedString attributedStringWithAttachment:attachment];
        [_dimmedTick    retain];    // have this object persist
        [wrapper        release];
        [attachment     release];
    }
    
    if ((state == NSOffState) && (!_noTick))
    {
        NSString *path = [[self bundle] pathForResource:@"noTick" 
                                                 ofType:@"tiff"];
        NSFileWrapper *wrapper = [[NSFileWrapper alloc] initWithPath:path];
        NSTextAttachment *attachment = 
            [[NSTextAttachment alloc] initWithFileWrapper:wrapper];
        _noTick = 
            [NSAttributedString attributedStringWithAttachment:attachment];
        [_noTick    retain];    // have this object persist
        [wrapper    release];
        [attachment release];
    }

    // construct an attributed string containing the user icon
    NSAttributedString *iconString = nil;
    if (iconPath)
    {
        NSSize iconSize     = NSMakeSize(menuPictureSize, menuPictureSize);
        NSFileWrapper *wrapper = [[NSFileWrapper alloc] initWithPath:iconPath];
        if (wrapper)
        {
            // need to setIcon: otherwise .userPicture images will not display
            NSImage *icon = [[NSImage alloc] initWithContentsOfFile:iconPath];
            if (!NSEqualSizes([icon size], iconSize))
            {
                [icon setScalesWhenResized:YES];
                [icon setSize:iconSize];
            }

            if (dim)
                [wrapper setIcon:[self _dimmedImage:[self _paddedImage:icon]]];
            else
                [wrapper setIcon:[self _paddedImage:icon]];
            [icon release];
            
            NSTextAttachment *attachment = 
            [[NSTextAttachment alloc] initWithFileWrapper:wrapper];
            if (attachment)
            {
                NSTextAttachmentCell *cell = 
                (NSTextAttachmentCell *)[attachment attachmentCell];
                NSImage *cellImage = [cell image];
                if (!NSEqualSizes([cellImage size], iconSize))
                {
                    [cellImage setScalesWhenResized:YES];
                    [cellImage setSize:iconSize];
                }

                // testing shows that Carbon/Cocoa will crash trying to draw
                // menu if multiple representations present here
                NSMutableArray *reps = 
                    [[[cellImage representations] mutableCopy] autorelease];
                while ([reps count] > 1)
                {
                    [cellImage removeRepresentation:[reps lastObject]];
                    [reps removeLastObject];
                }

                if (dim)
                    [cell setImage:[self _dimmedImage:
                        [self _paddedImage:cellImage]]];
                else
                    [cell setImage:[self _paddedImage:cellImage]];
                iconString = 
                    [NSAttributedString attributedStringWithAttachment:
                        attachment];                
                [attachment release];
            }
            else
                iconString = nil;
            [wrapper release];
        }
    }

    // prepare textual part of string and apply appropriate formatting
    NSAttributedString *textString = nil;
    // prepend two spaces to textual string to make room for graphics
    NSString *spacedString = [NSString stringWithFormat:@"  %@", aString];
    
    // Apple bug: menuFontOfSize:0.0 is too small <rdar://3522284/>
    NSFont *menuFont = [NSFont menuFontOfSize:14.0];
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
        menuFont, NSFontAttributeName, nil];
    textString = [[NSAttributedString alloc] initWithString:spacedString
                                                 attributes:attributes];
    
    // now assemble the components: the state image, icon, spaces and username
    NSMutableAttributedString *returnString = [textString mutableCopy];
    [textString release];
    if (iconString)
        [returnString insertAttributedString:iconString atIndex:0];
    if (state == NSOffState)
        [returnString insertAttributedString:_noTick        atIndex:0];
    else if (state == NSOnState && dim)
        [returnString insertAttributedString:_dimmedTick    atIndex:0];
    else
        [returnString insertAttributedString:_tick          atIndex:0];    

    // get things lined up nicely: default settings
    float tickOffset = 0.0;
    float iconOffset = -15.0;
    float textOffset = 3.0;
    
    if (menuPictureSize == 16.0)
    {
        tickOffset = 0.0;
        iconOffset = -4.0;
        textOffset = 2.0;
    }
    else if (menuPictureSize == 48.0)
    {
        tickOffset = 14.0;
        iconOffset = -6.0;
        textOffset = 17.0;
    }
    
    // lift up tick so it is centre aligned within the menu
    [returnString addAttribute:NSBaselineOffsetAttributeName
                         value:[NSNumber numberWithFloat:tickOffset]
                         range:NSMakeRange(0, 1)];
    
    // move icon down otherwise part of it juts out above highlight rectangle
    [returnString addAttribute:NSBaselineOffsetAttributeName
                         value:[NSNumber numberWithFloat:iconOffset]
                         range:NSMakeRange(1, 1)];
    
    // lift up textual part so it is centre aligned within the menu
    [returnString addAttribute:NSBaselineOffsetAttributeName
                         value:[NSNumber numberWithFloat:textOffset]
                         range:NSMakeRange(3,[returnString length] - 3)];
            
    return [returnString autorelease];
}

// update stored copy of current user icon
- (void)_updateUserImage:(NSString *)aPath
{
    if (userImage) [userImage release];
    if (!aPath) // use generic icon is can't load picture
        aPath = [[self bundle] pathForImageResource:@"generic"];
    NSImage *image = [[NSImage alloc] initWithContentsOfFile:aPath];
    if (image)
    {
        NSSize menuBarIconSize =             
            NSMakeSize(userPictureSize, userPictureSize);
        if (!NSEqualSizes([image size], menuBarIconSize))
        {
            [image setScalesWhenResized:YES];
            [image setSize:menuBarIconSize];
        }
        
        // now centre icon in view
        NSSize paddedMenuBarIconSize = NSMakeSize(19.0, 22.0);
        userImage = [[NSImage alloc] initWithSize:paddedMenuBarIconSize];
        [userImage lockFocus];
        [image compositeToPoint:
            NSMakePoint(floor((19.0 - userPictureSize) / 2.0),
                        ceil((22.0 - userPictureSize) / 2.0))
                      operation:NSCompositeCopy];
        [userImage unlockFocus];    // userImage gets released in dealloc
        [image release];
    }
}

// convenience method for setting an NSAttributedString menu title
- (void)_setMenuTitleWithString:(NSString *)aString
{
    if (!aString)
    {
        [self setAttributedTitle:nil];
        return;
    }
    
    NSFont          *menuFont   = [NSFont boldSystemFontOfSize:14.0];
    NSDictionary    *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
        menuFont, NSFontAttributeName, nil];
    NSAttributedString *title = 
        [[NSAttributedString alloc] initWithString:aString 
                                        attributes:attributes];
    [self setAttributedTitle:title];
    [title release];
}

// returns full user name for current user; Cocoa's NSFullUserName() caches and
// therefore sometimes returns inaccurate results (<rdar://3607237/>)
- (NSString *)_fullUserName
{   
    return [self _propertyForKey:@"realname" user:getuid()];
}

// NSMenuExtra's setAttributedTitle: and attributedTitle: appear to be NOPs
- (NSAttributedString *)attributedTitle
{
    return _attributedTitle;
}

- (void)setAttributedTitle:(NSAttributedString *)aString
{
    [aString retain];
    [_attributedTitle release];
    _attributedTitle = aString;
}

@end