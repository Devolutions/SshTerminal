//
//  ProxyTelnet.m
//  SshTerminal
//
//  Created by Denis Vincent on 2015-10-08.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import "ProxyTelnet.h"


BOOL isStringAtLocation(NSString* command, NSUInteger location, NSString* pattern)
{
    NSRange range = NSMakeRange(location, pattern.length);
    if (range.location + range.length > command.length)
    {
        return NO;
    }
    
    if ([command compare:pattern options:0 range:range] == NSOrderedSame)
    {
        return YES;
    }
    
    return NO;
}


@implementation ProxyTelnet

@synthesize proxyHost;
@synthesize proxyUser;
@synthesize proxyPassword;
@synthesize connectCommand;
@synthesize proxyPort;
@synthesize proxyResolveHostAddress;


-(NSUInteger)substituteDirectiveIn:(NSMutableString*)command at:(NSUInteger)location
{
    
    if (isStringAtLocation(command, location, @"%host") == YES)
    {
        [command replaceCharactersInRange:NSMakeRange(location, 5) withString:host];
        location += host.length;
    }
    else if (isStringAtLocation(command, location, @"%port") == YES)
    {
        NSString* portText = [NSString stringWithFormat:@"%d", port];
        [command replaceCharactersInRange:NSMakeRange(location, 5) withString:portText];
        location += portText.length;
    }
    else if (isStringAtLocation(command, location, @"%user") == YES)
    {
        [command replaceCharactersInRange:NSMakeRange(location, 5) withString:proxyUser];
        location += proxyUser.length;
    }
    else if (isStringAtLocation(command, location, @"%pass") == YES)
    {
        [command replaceCharactersInRange:NSMakeRange(location, 5) withString:proxyPassword];
        location += proxyPassword.length;
    }
    else if (isStringAtLocation(command, location, @"%proxyhost") == YES)
    {
        [command replaceCharactersInRange:NSMakeRange(location, 10) withString:proxyHost];
        location += proxyHost.length;
    }
    else if (isStringAtLocation(command, location, @"%proxyport") == YES)
    {
        NSString* portText = [NSString stringWithFormat:@"%d", proxyPort];
        [command replaceCharactersInRange:NSMakeRange(location, 10) withString:portText];
        location += portText.length;
    }
    else if (isStringAtLocation(command, location, @"%%") == YES)
    {
        [command replaceCharactersInRange:NSMakeRange(location, 2) withString:@"%"];
        location++;
    }
    else
    {
        location++;
    }
    
    return location;
}


-(NSUInteger)substituteSpecialCharIn:(NSMutableString*)command at:(NSUInteger)location
{
    if (isStringAtLocation(command, location, @"\\r") == YES)
    {
        [command replaceCharactersInRange:NSMakeRange(location, 2) withString:@"\r"];
        location++;
    }
    else if (isStringAtLocation(command, location, @"\\n") == YES)
    {
        [command replaceCharactersInRange:NSMakeRange(location, 2) withString:@"\n"];
        location++;
    }
    else if (isStringAtLocation(command, location, @"\\t") == YES)
    {
        [command replaceCharactersInRange:NSMakeRange(location, 2) withString:@"\t"];
        location++;
    }
    else if (isStringAtLocation(command, location, @"\\x") == YES)
    {
        if (location + 4 < command.length)
        {
            NSString* digits = [command substringWithRange:NSMakeRange(location + 2, 2)];
            NSScanner* scanner = [NSScanner scannerWithString:digits];
            unsigned int value;
            if ([scanner scanHexInt:&value] == NO)
            {
                value = 0;
            }
            NSString* character = [NSString stringWithFormat:@"%c", (unsigned char)value];
            [command replaceCharactersInRange:NSMakeRange(location, 4) withString:character];
        }
        location++;
    }
    else if (isStringAtLocation(command, location, @"\\\\") == YES)
    {
        [command replaceCharactersInRange:NSMakeRange(location, 2) withString:@"\\"];
        location++;
    }
    else if (isStringAtLocation(command, location, @"\\%") == YES)
    {
        [command replaceCharactersInRange:NSMakeRange(location, 2) withString:@"%"];
        location++;
    }
    else
    {
        location++;
    }
    
    return location;
}


-(void)formatCommand:(NSMutableString*)command
{
    if ([connectCommand length] == 0)
    {
        [command appendFormat:@"connect %@ %d\n", host, port];
        return;
    }
    
    [command appendString:connectCommand];
    
    NSCharacterSet* escapeCharacters = [NSCharacterSet characterSetWithCharactersInString:@"%\\"];
    NSRange searchRange = NSMakeRange(0, command.length);
    NSRange range;
    do
    {
        range = [command rangeOfCharacterFromSet:escapeCharacters options:0 range:searchRange];
        if (range.length > 0)
        {
            if ([command characterAtIndex:range.location] == '%')
            {
                searchRange.location = [self substituteDirectiveIn:command at:range.location];
            }
            else
            {
                searchRange.location = [self substituteSpecialCharIn:command at:range.location];
            }
            searchRange.length = command.length - searchRange.location;
        }
    } while (range.length > 0);
}


-(int)connectThroughProxy
{
    NSMutableString* command = [NSMutableString new];
    [self formatCommand:command];
    
    const char* commandString = [command UTF8String];
    int bufferLength = (int)strlen(commandString);
    int result = (int)send(fd, commandString, bufferLength, 0);
    [command release];
    if (result != bufferLength)
    {
        return CONNECTION_RESULT_FAILED;
    }
    
    // According to my comprehension of Putty, once the connect command has been sent, no proxy reply is to be expected...
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
        connectCommand = [NSString new];
    }
    return self;
}


-(void)dealloc
{
    [proxyHost release];
    [proxyUser release];
    [proxyPassword release];
    [connectCommand release];
    [super dealloc];
}


@end
