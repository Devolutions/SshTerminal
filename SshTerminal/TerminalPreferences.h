//
//  TerminalPreferences.h
//  SshTerminal
//
//  Created by Xavier Fortin on 2017-07-31.
//  Copyright © 2017 Denis Vincent. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef enum
{
    DefaultCopyMode,
    
    PlainTextCopyMode
} CopyMode;

@interface TerminalPreferences : NSObject
{
    CopyMode copyMode;
}

+ (TerminalPreferences *)sharedPreferences;

@property (assign, nonatomic) CopyMode copyMode;

@end
