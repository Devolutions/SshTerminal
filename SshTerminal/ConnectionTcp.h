//
//  ConnectionTcp.h
//  SshTerminal
//
//  Created by Denis Vincent on 2015-09-29.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "NetworkHelpers.h"

enum
{
    CONNECTION_RESULT_SUCCEEDED,
    CONNECTION_RESULT_FAILED = -1,
    CONNECTION_RESULT_CLOSED = -2,
};

@interface ConnectionTcp : NSObject
{
    int fd;
    int internetProtocol;
    UInt16 port;
    NSString* host;
}

@property(copy,nonatomic) NSString* host;
@property(assign) UInt16 port;
@property(assign) int internetProtocol;
@property(readonly) int fd;

-(int)connect;
-(int)send:(const UInt8*)buffer size:(int)byteCount;
-(int)receiveIn:(UInt8*)buffer size:(int)bufferSize;
-(void)disconnect;

-(int)createSocketAndConnectToHost:(const char*)newHost onPort:(UInt16)newPort;

@end

