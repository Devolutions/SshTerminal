//
//  SshTunnel.m
//  SshTerminal
//
//  Created by Denis Vincent on 2015-07-15.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import "SshTunnel.h"


int resolveHost(struct sockaddr_in* address, const char* host)
{
    if (host == NULL || strlen(host) == 0)
    {
        host = "0.0.0.0";
    }
    
    // Get the address info for the host.
    struct addrinfo* info;
    struct addrinfo hint;
    memset(&hint, 0, sizeof(hint));
    hint.ai_flags = AI_ADDRCONFIG | AI_PASSIVE;
    hint.ai_family = PF_UNSPEC;
    hint.ai_socktype = SOCK_STREAM;
    hint.ai_protocol = IPPROTO_TCP;
    int result = getaddrinfo(host, NULL, NULL, &info);
    if (result != 0)
    {
        return 0;
    }
    
    // Parse the address info to find the most appropriate sockaddr.
    int addressSize = 0;
    struct addrinfo* selectedInfo = info;
    while (1)
    {
        if ((selectedInfo->ai_family == PF_INET || selectedInfo->ai_family == PF_INET6) && selectedInfo->ai_socktype == SOCK_STREAM)
        {
            addressSize = selectedInfo->ai_addrlen;
            break;
        }
        if (selectedInfo->ai_next == NULL)
        {
            break;
        }
        selectedInfo = selectedInfo->ai_next;
    }
    
    // Copy the result.
    if (addressSize > 0)
    {
        memcpy(address, selectedInfo->ai_addr, addressSize);
    }
    freeaddrinfo(info);
    
    return addressSize;
}


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
    struct sockaddr_in address;
    int addressSize = resolveHost(&address, [host UTF8String]);
    if (addressSize <= 0)
    {
        return NO;
    }
    
    listenFd = socket(address.sin_family, SOCK_STREAM, IPPROTO_TCP);
    if (listenFd < 0)
    {
        return NO;
    }
    
    int reuseAddress = 1;
    setsockopt(listenFd, SOL_SOCKET, SO_REUSEADDR, &reuseAddress, sizeof(reuseAddress));
    
    address.sin_port = htons(port);
    int result = bind(listenFd, (struct sockaddr*)&address, addressSize);
    if (result != 0)
    {
        close(listenFd);
        return NO;
    }
    
    int flags = fcntl(listenFd, F_GETFL, 0);
    fcntl(listenFd, F_SETFL, flags | O_NONBLOCK);
    
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


-(int)connectToLocal
{
    struct sockaddr_in hostAddress;
    int hostAddressSize = resolveHost(&hostAddress, [host UTF8String]);
    if (hostAddressSize <= 0)
    {
        return -1;
    }
    
    int fd = socket(hostAddress.sin_family, SOCK_STREAM, IPPROTO_TCP);
    if (fd < 0)
    {
        return -1;
    }
    struct sockaddr bindAddress;
    memset(&bindAddress, 0, sizeof(bindAddress));
    int result = bind(fd, &bindAddress, sizeof(bindAddress));
    if (result < 0)
    {
        close(fd);
        return -1;
    }
    
    hostAddress.sin_port = htons(port);
    result = connect(fd, (struct sockaddr*)&hostAddress, hostAddressSize);
    if (result < 0)
    {
        close(fd);
        return -1;
    }
    
    int flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    
    return fd;
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
