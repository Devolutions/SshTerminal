//
//  ConnectionSocks4.m
//  SshTerminal
//
//  Created by Denis Vincent on 2015-09-29.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import "ProxySocks4.h"

@implementation ProxySocks4

@synthesize proxyHost;
@synthesize proxyUser;
@synthesize proxyPort;


-(int)connect
{
    if (fd != -1)
    {
        // Already connected:
        return CONNECTION_RESULT_SUCCEEDED;
    }
    
    // Resolve the address to the destination host.
    NetworkAddress addresses[2];
    int addressCount = resolveHost(addresses, [host UTF8String]);
    if (addressCount == 0)
    {
        return CONNECTION_RESULT_FAILED;
    }
    int selectedAddress = 0;
    if (addresses[0].family != PF_INET)
    {
        if (addressCount == 1)
        {
            return CONNECTION_RESULT_FAILED;
        }
        else
        {
            selectedAddress = 1;
        }
    }
    
    // Connect to the proxy.
    fd = [self createSocketAndConnectToHost:[proxyHost UTF8String] onPort:proxyPort];
    if (fd < 0)
    {
        fd = -1;
        return CONNECTION_RESULT_FAILED;
    }
    
    // Send the connect command to the proxy.
    char commandString[256];
    commandString[0] = SOCKS4_VERSION;
    commandString[1] = SOCKS4_COMMAND_CONNECT;
    *((UInt16*)(commandString + 2)) = htons(port);
    memcpy(commandString + 4, &(addresses[selectedAddress].ipv4.sin_addr), 4);
    const char* proxyUserString = [proxyUser UTF8String];
    strcpy(commandString + 8, proxyUserString);   // TODO : check for the possibility of using the IDENT protocol (RFC 1413).
    int result = (int)send(fd, commandString, 9 + strlen(proxyUserString), 0);
    if (result <= 0)
    {
        [self disconnect];
        return CONNECTION_RESULT_FAILED;
    }
    
    // Wait for the connection reply.
    result = (int)recv(fd, commandString, 8, 0);
    if (result != 8)
    {
        [self disconnect];
        return CONNECTION_RESULT_FAILED;
    }
    if (commandString[0] != 0 && commandString[1] != SOCKS4_REPLY_REQUEST_GRANTED)
    {
        [self disconnect];
        return CONNECTION_RESULT_FAILED;
    }
    
    // Connection is complete, 
    int flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    
    return CONNECTION_RESULT_SUCCEEDED;
}


-(instancetype)init
{
    self = [super init];
    if (self != nil)
    {
        proxyHost = [NSString new];
        proxyUser = [NSString new];
    }
    return self;
}


-(void)dealloc
{
    [proxyHost release];
    [proxyUser release];
    [super dealloc];
}


@end
