//
//  NsTunnelConnection.h
//  SshTerminal
//
//  Created by Denis Vincent on 2015-07-15.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SshFoundation.h"
#import "SshTunnel.h"

#define FORWARD_BUFFER_SIZE 2800

@interface SshTunnelConnection : NSObject
{
    int fd;
    ssh_channel channel;
    dispatch_source_t readSource;
    UInt8 buffer[FORWARD_BUFFER_SIZE];
    BOOL endedByRemote;
    char address[45];
    char port[6];
    char peerAddress[45];
    char peerPort[6];
}

@property(strong)SshTunnel* tunnel;
@property(readonly)int fd;
@property(readonly)char* address;
@property(readonly)char* port;
@property(readonly)char* peerAddress;
@property(readonly)char* peerPort;
@property(readonly)BOOL endedByRemote;

+(instancetype)connectionWithSocket:(int)newFd onChannel:(ssh_channel)newChannel onQueue:(dispatch_queue_t)queue;

-(void)newLocalDataAvailable;
-(BOOL)transferRemoteDataToLocal;
-(BOOL)isAlive;
-(void)disconnect;


@end


