//
//  NSString+WOWinSwitchExtensions.m
//  WinSwitch
//
//  Created by Wincent Colaiuta on 25/10/04.
//  Copyright (c) 2004 Wincent Colaiuta. All rights reserved.
//  $Id$
//

#import "NSString+WOWinSwitchExtensions.h"

// getuid()
#import <sys/types.h>
#import <unistd.h>

// S_IWGRP, S_IWOTH
#import <sys/types.h>
#import <sys/stat.h>

@implementation NSString (WOWinSwitchExtensions)

- (NSArray *)componentsSeparatedByWhitespace:(NSString *)whitespaceCharacters
{
    NSMutableArray *components = [NSMutableArray array];
    
    if (!whitespaceCharacters)
        @throw [NSException exceptionWithName:NSInvalidArgumentException 
                                       reason:@"nil string argument"  
                                     userInfo:nil];
    else if ([whitespaceCharacters length] == 0)
        [components addObject:self];
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

- (BOOL)pathIsOwnedByCurrentUser
{
    NSFileManager *manager = [NSFileManager defaultManager];
    NSDictionary *attributes = [manager fileAttributesAtPath:self
                                                traverseLink:YES];
    NSNumber *tmp = [attributes fileOwnerAccountID];
    if (!tmp) return NO; // attributes dictionary had no matching key
    unsigned long user = [tmp unsignedLongValue];
    
    return (BOOL)(getuid() == (uid_t)user);
}

- (BOOL)pathIsWritableOnlyByCurrentUser
{
    NSFileManager *manager = [NSFileManager defaultManager];
    NSDictionary *attributes = [manager fileAttributesAtPath:self
                                                traverseLink:YES];
    if (!attributes) return NO; // probably was not a valid path
    unsigned long perms = [attributes filePosixPermissions];
    if (perms == 0) return NO; // attributes dictionary had no matching key
    
    if ((perms & S_IWGRP) || (perms & S_IWOTH)) // "group" or "other" can write!
        return NO;
    
    return YES;
}

@end
