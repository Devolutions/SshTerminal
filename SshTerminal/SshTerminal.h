//
//  SshTerminal.h
//  SshTerminal
//
//  Created by Denis Vincent on 2015-06-29.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import <Cocoa/Cocoa.h>

//! Project version number for SshTerminal.
FOUNDATION_EXPORT double SshTerminalVersionNumber;

//! Project version string for SshTerminal.
FOUNDATION_EXPORT const unsigned char SshTerminalVersionString[];

// In this header, you should import all the public headers of your framework using statements like #import <SshTerminal/PublicHeader.h>


//#import "SshTerminalView.h"
//#import "SshConnection.h"

@protocol SshTerminalEvent <NSObject>
-(void)connected;
-(void)disconnected;
-(void)error:(int)code;

@end

@interface SshTerminal : NSScrollView
{
    id terminalView;
    id connection;
    
    NSString* password;
    NSString* hostName;
    NSString* userName;
    int columnCount;
    id eventDelegate;
}

-(void)setPassword:(NSString *)string;

@property(copy,nonatomic)NSString* hostName;
@property(copy,nonatomic)NSString* userName;

@property(assign)int columnCount;

-(void)setEventDelegate:(id) delegate;
-(void)connect;
-(void)disconnect;


@end
