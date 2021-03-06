//
//  SshTunnel.h
//  SshTerminal
//
//  Created by Denis Vincent on 2015-07-15.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SshFoundation.h"

@interface SshTunnel : NSObject
{
    BOOL reverse;
    UInt16 port;
    UInt16 remotePort;
    int listenFd;
    NetworkAddress address;
    dispatch_source_t listenSource;
    NSString* host;
    NSString* remoteHost;
}

@property(assign)BOOL reverse;
@property(assign)UInt16 port;
@property(assign)UInt16 remotePort;
@property(strong,nonatomic)NSString* host;
@property(strong,nonatomic)NSString* remoteHost;

-(instancetype)resolveHost;
-(BOOL)startListeningAndDispatchTo:(dispatch_block_t)handler onQueue:(dispatch_queue_t)queue;
-(void)endListening;
-(int)acceptConnection;

-(int)connectToLocal;

@end


