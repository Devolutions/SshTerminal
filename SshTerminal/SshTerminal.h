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


@protocol SshTerminalEvent <NSObject>
@optional
-(void)connected;
-(void)disconnected;
-(void)serverMismatch:(NSString*)fingerPrint;   // The connection process has been suspended because the server is either unknown or has changed. Must call -(void)resume or -(void)resumeAndRememberServer or -(void)disconnect.
-(void)error:(int)code;

@end

@interface SshTerminal : NSScrollView
{
    id terminalView;
    id connection;
    
    NSString* password;
    NSString* hostName;
    NSString* userName;
    NSString* keyFilePath;
    NSString* keyFilePassword;
    int columnCount;
    id eventDelegate;
}

-(void)setPassword:(NSString *)string;
-(void)setKeyFilePassword:(NSString *)string;

@property(copy,nonatomic)NSString* hostName;
@property(copy,nonatomic)NSString* userName;
@property(copy,nonatomic)NSString* keyFilePath;

@property(assign)int columnCount;

-(void)setEventDelegate:(id) delegate;
-(void)connect;
-(void)resume;
-(void)resumeAndRememberServer;
-(void)disconnect;


@end
