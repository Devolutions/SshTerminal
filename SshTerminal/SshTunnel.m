//
//  SshTunnel.m
//  SshTerminal
//
//  Created by Denis Vincent on 2015-07-15.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import "SshTunnel.h"


@implementation SshTunnel

@synthesize port;
@synthesize remotePort;
@synthesize host;
@synthesize remoteHost;


-(void)releaseResources
{
    if (listenSource != nil)
    {
        dispatch_source_cancel(listenSource);
        listenSource = nil;
    }
    if (listenFd >= 0)
    {
        close(listenFd);
        listenFd = -1;
    }
}


-(BOOL)startListeningAndDispatchTo:(dispatch_block_t)handler onQueue:(dispatch_queue_t)queue
{
    listenFd = createBoundSocket(port, [host UTF8String]);
    if (listenFd < 0)
    {
        return NO;
    }
    
    listenSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, listenFd, 0, queue);
    if (listenSource == NULL)
    {
        [self releaseResources];
        return NO;
    }
    dispatch_source_set_event_handler(listenSource, handler);
    listen(listenFd, 10);
    dispatch_resume(listenSource);
    
    return YES;
}


-(void)endListening
{
    [self releaseResources];
}


-(int)acceptConnection
{
    if (listenFd < 0)
    {
        return -1;
    }
    struct sockaddr address;
    socklen_t size = sizeof(address);
    return accept(listenFd, &address, &size);
}


-(instancetype)init
{
    self = [super init];
    if (self != nil)
    {
        listenFd = -1;
    }
    
    return self;
}


-(void)dealloc
{
    [self releaseResources];
}


@end
