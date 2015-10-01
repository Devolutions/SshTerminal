//
//  ConnectionSocks5.h
//  SshTerminal
//
//  Created by Denis Vincent on 2015-09-30.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import "ConnectionTcp.h"

#define SOCKS5_VERSION 5
#define SOCKS5_METHOD_NO_AUTHENTICATION 0
#define SOCKS5_METHOD_USERNAME_PASSWORD 2
#define SOCKS5_METHOD_NONE 0xFF
#define SOCKS5_COMMAND_CONNECT_METHOD 1
#define SOCKS5_ADDRESS_TYPE_IPV4 1
#define SOCKS5_ADDRESS_TYPE_STRING 3
#define SOCKS5_ADDRESS_TYPE_IPV6 4
#define SOCKS5_REPLY_SUCCESS 0

#define SOCKS5_USERNAME_PASSWORD_VERSION 1


@interface ConnectionSocks5 : ConnectionTcp
{
    NSString* proxyHost;
    NSString* proxyUser;
    NSString* proxyPassword;
    BOOL proxyResolveHostAddress;
    UInt16 proxyPort;
}

@property(copy,nonatomic) NSString* proxyHost;
@property(copy,nonatomic) NSString* proxyUser;
@property(copy,nonatomic) NSString* proxyPassword;
@property(assign) BOOL proxyResolveHostAddress;
@property(assign) UInt16 proxyPort;

@end
