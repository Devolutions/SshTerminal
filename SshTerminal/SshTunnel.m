//
//  SshTunnel.m
//  SshTerminal
//
//  Created by Denis Vincent on 2015-07-15.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import "SshTunnel.h"


struct addrinfo* findSockaddr(int family, struct addrinfo* info)
{
    while (1)
    {
        if (info->ai_family == family && info->ai_socktype == SOCK_STREAM)
        {
            return info;
        }
        if (info->ai_next == NULL)
        {
            break;
        }
        info = info->ai_next;
    }
    return NULL;
}


int resolveHost(NetworkAddress* address, const char* host)
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
    struct addrinfo* selectedInfo = findSockaddr(PF_INET, info);
    if (selectedInfo == NULL)
    {
        selectedInfo = findSockaddr(PF_INET6, info);
    }
    if (selectedInfo != NULL)
    {
        addressSize = selectedInfo->ai_addrlen;
    }
    
    // Copy the result.
    if (addressSize > 0)
    {
        assert(addressSize <= sizeof(NetworkAddress));
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
    NetworkAddress address;
    int addressSize = resolveHost(&address, [host UTF8String]);
    if (addressSize <= 0)
    {
        return NO;
    }
    
    listenFd = socket(address.family, SOCK_STREAM, IPPROTO_TCP);
    if (listenFd < 0)
    {
        return NO;
    }
    
    int reuseAddress = 1;
    setsockopt(listenFd, SOL_SOCKET, SO_REUSEADDR, &reuseAddress, sizeof(reuseAddress));
    
    address.port = htons(port);
    int result = bind(listenFd, &address.ip, address.len);
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
    NetworkAddress address;
    socklen_t size = sizeof(address);
    return accept(listenFd, &address.ip, &size);
}


-(int)connectToLocal
{
    NetworkAddress hostAddress;
    int hostAddressSize = resolveHost(&hostAddress, [host UTF8String]);
    if (hostAddressSize <= 0)
    {
        return -1;
    }
    
    int fd = socket(hostAddress.family, SOCK_STREAM, IPPROTO_TCP);
    if (fd < 0)
    {
        return -1;
    }
    NetworkAddress bindAddress;
    memset(&bindAddress, 0, sizeof(bindAddress));
    bindAddress.len = hostAddress.len;
    bindAddress.family = hostAddress.family;
    int result = bind(fd, &bindAddress.ip, bindAddress.len);
    if (result < 0)
    {
        close(fd);
        return -1;
    }
    
    hostAddress.port = htons(port);
    result = connect(fd, &hostAddress.ip, hostAddressSize);
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
