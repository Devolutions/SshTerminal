//
//  ConnectionSocks5.m
//  SshTerminal
//
//  Created by Denis Vincent on 2015-09-30.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import "ProxySocks5.h"

@implementation ProxySocks5

@synthesize proxyHost;
@synthesize proxyUser;
@synthesize proxyPassword;
@synthesize proxyPort;
@synthesize proxyResolveHostAddress;


-(int)negotiateAuthenticationMethod
{
    // Send the supported authentication methods to the proxy.
    char buffer[4];
    int commandLength = 3;
    buffer[0] = SOCKS5_VERSION;
    buffer[1] = 1;
    buffer[2] = SOCKS5_METHOD_NO_AUTHENTICATION;
    if ([proxyUser length] > 0 || [proxyPassword length] > 0)
    {
        commandLength = 4;
        buffer[1] = 2;
        buffer[3] = SOCKS5_METHOD_USERNAME_PASSWORD;
    }
    int result = send(fd, buffer, commandLength, 0);
    if (result <= 0)
    {
        return SOCKS5_METHOD_NONE;
    }
    
    // Wait for the authentication method selection.
    result = recv(fd, buffer, 2, 0);
    if (result != 2)
    {
        return SOCKS5_METHOD_NONE;
    }
    if (buffer[0] != SOCKS5_VERSION)
    {
        return SOCKS5_METHOD_NONE;
    }
    
    return (UInt8)buffer[1];
}


-(int)authenticateWithUsernamePasswordMethod
{
    char buffer[256];

    // Validate username and password length against buffer length.
    const char* userString = [proxyUser UTF8String];
    int userStringLength = strlen(userString);
    const char* passwordString = [proxyPassword UTF8String];
    int passwordStringLength = strlen(passwordString);
    int commandLength = 3 + userStringLength + passwordStringLength;
    if (commandLength > sizeof(buffer))
    {
        return CONNECTION_RESULT_FAILED;
    }
    
    // Send the username/password authentication request.
    buffer[0] = SOCKS5_USERNAME_PASSWORD_VERSION;
    buffer[1] = userStringLength;
    memcpy(buffer + 2, userString, userStringLength);
    int passwordIndex = 2 + userStringLength;
    buffer[passwordIndex] = passwordStringLength;
    memcpy(buffer + passwordIndex + 1, passwordString, passwordStringLength);
    int result = send(fd, buffer, commandLength, 0);
    if (result <= 0)
    {
        return CONNECTION_RESULT_FAILED;
    }
    
    // Wait for the username/password authentication reply.
    result = recv(fd, buffer, 2, 0);
    if (result != 2)
    {
        return CONNECTION_RESULT_FAILED;
    }
    if (buffer[1] != 00)
    {
        return CONNECTION_RESULT_FAILED;
    }
    
    return CONNECTION_RESULT_SUCCEEDED;
}


-(int)connectThroughProxy
{
    char buffer[256];
    
    // Resolve the host name if required.
    const char* hostString = [host UTF8String];
    int hostStringLength = strlen(hostString);
    int addressType = SOCKS5_ADDRESS_TYPE_STRING;
    NetworkAddress addresses[2];
    if (proxyResolveHostAddress == YES)
    {
        int addressCount = resolveHost(addresses, hostString);
        if (addressCount > 0)
        {
            int selectedAddress = 0;
            if (addresses[0].family != PF_INET)
            {
                if (addressCount > 1)
                {
                    // For now, prefer the IPv4 addresses.
                    selectedAddress = 1;
                }
            }
            if (addresses[selectedAddress].family == PF_INET)
            {
                addressType = SOCKS5_ADDRESS_TYPE_IPV4;
                hostString = (char*)&(addresses[selectedAddress].ipv4.sin_addr);
                hostStringLength = 4;
            }
            else
            {
                addressType = SOCKS5_ADDRESS_TYPE_IPV6;
                hostString = (char*)&(addresses[selectedAddress].ipv6.sin6_addr);
                hostStringLength = 16;
            }
        }
    }
    
    // Validate the selected host name length against buffer length.
    int baseLength = (addressType == SOCKS5_ADDRESS_TYPE_STRING ? 7 : 6);
    int commandLength = baseLength + hostStringLength;
    if (commandLength > sizeof(buffer))
    {
        return CONNECTION_RESULT_FAILED;
    }
    
    // Send the connection request.
    buffer[0] = SOCKS5_VERSION;
    buffer[1] = SOCKS5_COMMAND_CONNECT_METHOD;
    buffer[2] = 0;   // Reserved.
    buffer[3] = addressType;
    int hostStringIndex;
    if (addressType == SOCKS5_ADDRESS_TYPE_STRING)
    {
        buffer[4] = hostStringLength;
        hostStringIndex = 5;
    }
    else
    {
        hostStringIndex = 4;
    }
    memcpy(buffer + hostStringIndex, hostString, hostStringLength);
    int portIndex = hostStringIndex + hostStringLength;
    buffer[portIndex] = HI_BYTE(port);
    buffer[portIndex + 1] = LO_BYTE(port);
    int result = send(fd, buffer, commandLength, 0);
    if (result <= 0)
    {
        return CONNECTION_RESULT_FAILED;
    }
    
    // Wait for the connection reply (partial read).
    result = recv(fd, buffer, 5, 0);
    if (result != 5)
    {
        return CONNECTION_RESULT_FAILED;
    }
    if (buffer[0] != SOCKS5_VERSION || buffer[1] != SOCKS5_REPLY_SUCCESS)
    {
        return CONNECTION_RESULT_FAILED;
    }
    // Read the remaining of the reply.
    int remaininglength;
    if (buffer[3] == SOCKS5_ADDRESS_TYPE_STRING)
    {
        remaininglength = buffer[4] + 2;
    }
    else if (buffer[3] == SOCKS5_ADDRESS_TYPE_IPV4)
    {
        remaininglength = 5;
    }
    else if (buffer[3] == SOCKS5_ADDRESS_TYPE_IPV6)
    {
        remaininglength = 19;
    }
    else
    {
        // Unknown address type:
        return CONNECTION_RESULT_FAILED;
    }
    result = recv(fd, buffer, remaininglength, 0);
    if (result != remaininglength)
    {
        return CONNECTION_RESULT_FAILED;
    }
    
    return CONNECTION_RESULT_SUCCEEDED;
}


-(int)connect
{
    if (fd != -1)
    {
        // Already connected:
        return CONNECTION_RESULT_SUCCEEDED;
    }
    
    // Connect to the proxy.
    fd = [self createSocketAndConnectToHost:[proxyHost UTF8String] onPort:proxyPort];
    if (fd < 0)
    {
        fd = -1;
        return CONNECTION_RESULT_FAILED;
    }
    
    // Negotiate the authentication method.
    int authenticationMethod = [self negotiateAuthenticationMethod];
    if (authenticationMethod == SOCKS5_METHOD_NONE)
    {
        [self disconnect];
        return CONNECTION_RESULT_FAILED;
    }
    
    if (authenticationMethod == SOCKS5_METHOD_USERNAME_PASSWORD)
    {
        // The proxy selected the username/password method:
        int result = [self authenticateWithUsernamePasswordMethod];
        if (result != CONNECTION_RESULT_SUCCEEDED)
        {
            [self disconnect];
            return CONNECTION_RESULT_FAILED;
        }
    }

    // Connect to the final host.
    int result = [self connectThroughProxy];
    if (result != CONNECTION_RESULT_SUCCEEDED)
    {
        [self disconnect];
        return CONNECTION_RESULT_FAILED;
    }
    
    // Connection is complete, switch to non blocking mode.
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
        proxyPassword = [NSString new];
    }
    return self;
}


-(void)dealloc
{
    [proxyHost release];
    [proxyUser release];
    [proxyPassword release];
    [super dealloc];
}


@end
