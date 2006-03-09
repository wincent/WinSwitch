//
//  NSString+WOWinSwitchExtensions.h
//  WinSwitch
//
//  Created by Wincent Colaiuta on 25/10/04.
//  Copyright 2004-2006 Wincent Colaiuta.
//  $Id$
//

#import <Foundation/Foundation.h>

@interface NSString (WOWinSwitchExtensions)

- (NSArray *)componentsSeparatedByWhitespace:(NSString *)whitespaceCharacters;

- (BOOL)pathIsOwnedByCurrentUser;

- (BOOL)pathIsWritableOnlyByCurrentUser;

@end
