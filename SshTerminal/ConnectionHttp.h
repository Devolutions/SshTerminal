//
//  ConnectionHttp.h
//  SshTerminal
//
//  Created by Denis Vincent on 2015-09-30.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import "ConnectionTcp.h"

@interface ConnectionHttp : ConnectionTcp
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
