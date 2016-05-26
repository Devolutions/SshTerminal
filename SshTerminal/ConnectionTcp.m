//
//  ConnectionTcp.m
//  SshTerminal
//
//  Created by Denis Vincent on 2015-09-29.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import "ConnectionTcp.h"

@implementation ConnectionTcp

@synthesize host;
@synthesize port;
@synthesize internetProtocol;
@synthesize fd;


-(int)connect
{
    if (fd != -1)
    {
        // Already connected:
        return CONNECTION_RESULT_SUCCEEDED;
    }
    
    fd = [self createSocketAndConnectToHost:[host UTF8String] onPort:port];
    if (fd < 0)
    {
        fd = -1;
        return CONNECTION_RESULT_FAILED;
    }
    
    int flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    
    return CONNECTION_RESULT_SUCCEEDED;
}


-(int)send:(const UInt8 *)buffer size:(int)byteCount
{
    if (fd == -1)
    {
        return CONNECTION_RESULT_CLOSED;
    }
    
    int byteSent = 0;
    for (int i = 0; i < 10; i++)
    {
        int result = (int)send(fd, buffer + byteSent, byteCount - byteSent, 0);
        if (result == 0)
        {
            close(fd);
            fd = -1;
            return CONNECTION_RESULT_CLOSED;
        }
        else if (result < 0)
        {
            if (errno != EAGAIN)
            {
                return CONNECTION_RESULT_FAILED;
            }
            else
            {
                [NSThread sleepForTimeInterval:0.100];
                continue;
            }
        }
        
        byteSent += result;
        if (byteSent >= byteCount)
        {
            break;
        }
    }
    
    return byteSent;
}


-(int)receiveIn:(UInt8 *)buffer size:(int)bufferSize
{
    if (fd == -1)
    {
        return CONNECTION_RESULT_CLOSED;
    }
    
    int result = (int)recv(fd, buffer, bufferSize, 0);
    if (result == 0)
    {
        return CONNECTION_RESULT_CLOSED;
    }
    else if (result < 0)
    {
        if (errno != EAGAIN)
        {
            return CONNECTION_RESULT_FAILED;
        }
        result = 0;
    }
    
    return result;
}


-(int)peekIn:(UInt8 *)buffer size:(int)bufferSize
{
    if (fd == -1)
    {
        return CONNECTION_RESULT_CLOSED;
    }
    
    int result = (int)recv(fd, buffer, bufferSize, MSG_PEEK);
    if (result == 0)
    {
        return CONNECTION_RESULT_CLOSED;
    }
    else if (result < 0)
    {
        if (errno != EAGAIN)
        {
            return CONNECTION_RESULT_FAILED;
        }
        result = 0;
    }
    
    return result;
}


-(void)disconnect
{
    if (fd == -1)
    {
        return;
    }
    
    close(fd);
    fd = -1;
}


-(int)createSocketAndConnectToHost:(const char*)newHost onPort:(UInt16)newPort
{
    NetworkAddress addresses[2];
    int addressCount = resolveHost(addresses, newHost);
    if (addressCount == 0)
    {
        // Unable to resolve host.
        return CONNECTION_RESULT_FAILED;
    }
    int selectedAddress = 0;
    if (addressCount > 1 && internetProtocol != PF_UNSPEC)
    {
        if (addresses[0].family != internetProtocol)
        {
            selectedAddress = 1;
        }
    }
    
    int newFd = socket(addresses[selectedAddress].family, SOCK_STREAM, IPPROTO_TCP);
    if (newFd < 0)
    {
        return CONNECTION_RESULT_FAILED;
    }
    
    NetworkAddress bindAddress;
    memset(&bindAddress, 0, sizeof(NetworkAddress));
    bindAddress.len = addresses[selectedAddress].len;
    bindAddress.family = addresses[selectedAddress].family;
    int result = bind(newFd, &bindAddress.ip, bindAddress.len);
    if (result != 0 )
    {
        close(newFd);
        return CONNECTION_RESULT_FAILED;
    }
    
    addresses[selectedAddress].port = htons(newPort);
    result = connect(newFd, &addresses[selectedAddress].ip, addresses[selectedAddress].len);
    if (result != 0)
    {
        close(newFd);
        return CONNECTION_RESULT_FAILED;
    }
    
    return newFd;
}


-(instancetype)init
{
    self = [super init];
    if (self != nil)
    {
        host = [NSString new];
        fd = -1;
    }
    return self;
}


-(void)dealloc
{
    if (fd != -1)
    {
        [self disconnect];
        [host release];
    }
    [super dealloc];
}


@end
