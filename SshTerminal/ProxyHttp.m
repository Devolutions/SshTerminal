//
//  ConnectionHttp.m
//  SshTerminal
//
//  Created by Denis Vincent on 2015-09-30.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import "ProxyHttp.h"

@implementation ProxyHttp

@synthesize proxyHost;
@synthesize proxyUser;
@synthesize proxyPassword;
@synthesize proxyPort;
@synthesize proxyResolveHostAddress;


-(int)authenticateWithUsernamePasswordMethod
{
    /*
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
    */
    return CONNECTION_RESULT_SUCCEEDED;
}


-(int)receiveReply
{
    // A reply to the connect method will have the form: "HTTP/1.1 2xx ...\r\n\r\n" where 2xx is the success status code from 200 to 299
    // and ... is an optionnal status text and HTTP header lines. Such a response will never have a body as specified in RFC 7230 (section 3.3).
    int flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    
    char buffer[256];
    int receiveIndex = 0;
    int searchIndex = 0;
    BOOL firstSpaceFound = NO;
    while (searchIndex < sizeof(buffer))
    {
        int result = [self peekIn:(UInt8*)buffer size:sizeof(buffer)];
        if (result == 0)
        {
            [NSThread sleepForTimeInterval:0.10];
        }
        else if (result > 0)
        {
            receiveIndex = result;
            if (firstSpaceFound == NO)
            {
                while (searchIndex < receiveIndex)
                {
                    char c = buffer[searchIndex];
                    if (c == ' ' || c == '\t')
                    {
                        firstSpaceFound = YES;
                        break;
                    }
                    searchIndex++;
                }
            }
            
            if (firstSpaceFound == YES)
            {
                while (searchIndex < receiveIndex)
                {
                    char c = buffer[searchIndex];
                    if (c >= '0' && c <= '9')
                    {
                        if (c == '2')
                        {
                            goto FIND_END_OF_REPLY;
                        }
                        else
                        {
                            return CONNECTION_RESULT_FAILED;
                        }
                    }
                    searchIndex++;
                }
            }
        }
        else
        {
            return result;
        }
    }

    // The status code has not been found in the first 256 bytes of the reply, clearly it is a bad sign...
    return CONNECTION_RESULT_FAILED;
    
FIND_END_OF_REPLY:
    while (searchIndex < sizeof(buffer))
    {
        while (searchIndex < receiveIndex - 3)
        {
            if (memcmp("\r\n\r\n", buffer + searchIndex, 4) == 0)
            {
                [self receiveIn:(UInt8*)buffer size:searchIndex + 3];
                return CONNECTION_RESULT_SUCCEEDED;
            }
            searchIndex++;
        }
        if (receiveIndex < sizeof(buffer))
        {
            int result = [self peekIn:(UInt8*)buffer size:sizeof(buffer)];
            if (result < 0)
            {
                return result;
            }
            else if (result == receiveIndex)
            {
                [NSThread sleepForTimeInterval:0.10];
            }
            receiveIndex = result;
        }
        else
        {
            int result = [self receiveIn:(UInt8*)buffer size:sizeof(buffer) - searchIndex];
            if (result < 0)
            {
                return result;
            }
            
            memmove(buffer, buffer + searchIndex, receiveIndex - searchIndex);
            receiveIndex -= searchIndex;
            searchIndex = 0;
            result = [self peekIn:(UInt8*)buffer size:sizeof(buffer)];
            if (result < 0)
            {
                return result;
            }
            else if (result == receiveIndex)
            {
                [NSThread sleepForTimeInterval:0.10];
            }
            receiveIndex = result;
        }
    }
    
    return CONNECTION_RESULT_FAILED;
}


-(int)connectThroughProxy
{
    NSMutableString* command = [NSMutableString new];
    NSMutableString* hostPort = [NSMutableString new];
    
    // Resolve the host name if required.
    
    if (proxyResolveHostAddress == YES)
    {
        NetworkAddress addresses[2];
        int addressCount = resolveHost(addresses, [host UTF8String]);
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
            char addressString[45];
            char portString[6];
            addresses[selectedAddress].port = htons(port);
            getnameinfo(&addresses[selectedAddress].ip, addresses[selectedAddress].len, addressString, sizeof(addressString), portString, sizeof(portString), NI_NUMERICHOST | NI_NUMERICSERV);
            [hostPort appendFormat:@"%s:%s", addressString, portString];
        }
    }
    else
    {
        [hostPort appendFormat:@"%@:%i", host, port];
    }
    
    // Send the connection request.
    [command appendFormat:@"CONNECT %@ HTTP/1.1\r\nHost: %@\r\n", hostPort, hostPort];
    [hostPort release];
    if ([proxyUser length] > 0 || [proxyPassword length] > 0)
    {
        // A user and/or password is provided: add the authorization field.
        NSString* combinedUserPassword = [NSString stringWithFormat:@"%@:%@", proxyUser, proxyPassword];
        const char* stringToEncode = [combinedUserPassword UTF8String];
        NSData* dataToEncode = [NSData dataWithBytes:stringToEncode length:strlen(stringToEncode)];
        NSString* encodedUserPassword = [dataToEncode base64EncodedStringWithOptions:0];
        [command appendFormat:@"Authorization: Basic %@\r\n", encodedUserPassword];
    }
    [command appendString:@"\r\n"];
    const char* commandString = [command UTF8String];
    int commandLength = strlen(commandString);
    int result = send(fd, commandString, commandLength, 0);
    [command release];
    if (result <= 0)
    {
        return CONNECTION_RESULT_FAILED;
    }
    
    // Wait for the connection reply.
    result = [self receiveReply];
    
    return result;
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
