//
//  WOWinSwitchMenuExtraView.h
//
//  Based on FuseMenuExtraView.h
//  Created by Martin Pittenauer on Fri Nov 07 2003.
//  Copyright (c) 2003 TheCodingMonkeys. All rights reserved.
//
//  Modifications by Wincent Colaiuta <win@wincent.org>
//  Copyright 2004-2006 Wincent Colaiuta.
//
//  $Id$

#import <Foundation/Foundation.h>

#if defined(__ppc__)
#import "SystemUIPlugin_Panther.h"
#elif defined(__i386)
#import "SystemUIPlugin_Tiger.h"
#else
#error Unknown architecture
#endif

@interface WOWinSwitchMenuExtraView : NSMenuExtraView {
    NSMenuExtra *menuExtra;
}

@end