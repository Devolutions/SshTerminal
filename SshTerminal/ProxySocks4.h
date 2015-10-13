//
//  ConnectionSocks4.h
//  SshTerminal
//
//  Created by Denis Vincent on 2015-09-29.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import "ConnectionTcp.h"

#define SOCKS4_VERSION 4
#define SOCKS4_COMMAND_CONNECT 1
#define SOCKS4_REPLY_REQUEST_GRANTED 90


@interface ProxySocks4 : ConnectionTcp
{
    NSString* proxyHost;
    NSString* proxyUser;
    UInt16 proxyPort;
}

@property(copy,nonatomic) NSString* proxyHost;
@property(copy,nonatomic) NSString* proxyUser;
@property(assign) UInt16 proxyPort;

@end

