//
//  NSString+WOWinSwitchExtensions.m
//  WinSwitch
//
//  Created by Wincent Colaiuta on 25/10/04.
//  Copyright (c) 2004 Wincent Colaiuta. All rights reserved.
//  $Id$
//

#import "NSString+WOWinSwitchExtensions.h"

@implementation NSString (WOWinSwitchExtensions)

- (NSArray *)componentsSeparatedByWhitespace:(NSString *)whitespaceCharacters
{
    NSMutableArray *components = [NSMutableArray array];
    
    if (!whitespaceCharacters)
    {
        @throw [NSException exceptionWithName:NSInvalidArgumentException 
                                       reason:@"nil string argument"  
                                     userInfo:nil];
    }
    else if ([whitespaceCharacters length] == 0)
    {
        [components addObject:self];
    }
    else
    {
        NSCharacterSet *whitespace = 
            [NSCharacterSet characterSetWithCharactersInString:
                whitespaceCharacters];
        NSScanner *scanner = [NSScanner scannerWithString:self];
        
        if ([scanner scanCharactersFromSet:whitespace intoString:nil])
            [components addObject:@""];
        
        NSString *component = nil;
        
        while ([scanner scanUpToCharactersFromSet:whitespace 
                                       intoString:&component])
        {
            [components addObject:component];
            if ([scanner scanCharactersFromSet:whitespace intoString:nil] &&
                [scanner isAtEnd])
                [components addObject:@""];
        }
    }
             
    // return immutable, autoreleased array
    return [NSArray arrayWithArray:components];
}

@end
