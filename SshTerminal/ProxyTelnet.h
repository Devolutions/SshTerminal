//
//  ProxyTelnet.h
//  SshTerminal
//
//  Created by Denis Vincent on 2015-10-08.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import "ConnectionTcp.h"

@interface ProxyTelnet : ConnectionTcp
{
    NSString* proxyHost;
    NSString* proxyUser;
    NSString* proxyPassword;
    NSString* connectCommand;
    BOOL proxyResolveHostAddress;
    UInt16 proxyPort;
}

@property(copy,nonatomic) NSString* proxyHost;
@property(copy,nonatomic) NSString* proxyUser;
@property(copy,nonatomic) NSString* proxyPassword;
@property(copy,nonatomic) NSString* connectCommand;
@property(assign) BOOL proxyResolveHostAddress;
@property(assign) UInt16 proxyPort;

@end
