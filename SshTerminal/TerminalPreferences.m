//
//  TerminalPreferences.m
//  SshTerminal
//
//  Created by Xavier Fortin on 2017-07-31.
//  Copyright © 2017 Denis Vincent. All rights reserved.
//

#import "TerminalPreferences.h"

TerminalPreferences *_sharedPreferences = nil;

@implementation TerminalPreferences

@synthesize copyMode;

-(TerminalPreferences *) init
{
    self.copyMode = DefaultCopyMode;
    return self;
}

+ (TerminalPreferences *) sharedPreferences
{
    if (_sharedPreferences == nil)
    {
        _sharedPreferences = [[TerminalPreferences alloc] init];
    }
    
    return _sharedPreferences;
}

@end
