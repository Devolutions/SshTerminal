//
//  TelnetConnection.h
//  SshTerminal
//
//  Created by Denis Vincent on 2015-07-22.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "VT100Connection.h"
#import "NetworkHelpers.h"


#define INPUT_BUFFER_SIZE 1024
#define OUTPUT_BUFFER_SIZE 1024


enum TelnetConnectionEvent
{
    tceFatalError,
    
    tceConnected,
    tceDisconnected,
};


@protocol TelnetConnectionEventDelegate <NSObject>

-(void)signalError:(int)code;

@end


typedef struct
{
    UInt8 value;
    UInt8 remoteValue;
} TelnetOption;

@interface TelnetConnection : NSObject <VT100Connection>
{
    NSString* host;
    NSString* user;
    NSString* password;
    UInt16 port;
    int width;
    int height;
    int internetProtocol;
    
    int fd;
    BOOL userNameSent;
    
    UInt8 inBuffer[INPUT_BUFFER_SIZE];
    UInt8 outBuffer[OUTPUT_BUFFER_SIZE];
    int inIndex;
    int outIndex;
    
    dispatch_queue_t queue;
    dispatch_queue_t mainQueue;
    dispatch_source_t readSource;
    
    TelnetOption options[256];
    
    id<VT100TerminalDataDelegate> dataDelegate;
    id<TelnetConnectionEventDelegate> eventDelegate;
}

// Methods called from the UI thread.
-(void)setHost:(NSString*)newHost port:(UInt16)newPort protocol:(int)newProtocol;
-(void)setUser:(NSString*)newUser;
-(void)setPassword:(NSString*)newPassword;
-(void)setWidth:(int)newWidth;

-(void)setEventDelegate:(id<TelnetConnectionEventDelegate>)newEventDelegate;

-(int)writeFrom:(const UInt8*)buffer length:(int)count;
-(void)startConnection;
-(void)endConnection;

@end
