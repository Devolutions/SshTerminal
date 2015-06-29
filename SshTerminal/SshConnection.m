//
//  SshConnection.m
//  LibSshTest
//
//  Created by Denis Vincent on 2015-06-03.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import "SshConnection.h"
#import "SshTerminalView.h"


int gInstanceCount = 0;


@implementation SshConnection

@synthesize session;


-(void)setHost:(const char *)hostString
{
    ssh_options_set(session, SSH_OPTIONS_HOST, hostString);
}


-(void)setUser:(const char *)userString
{
    ssh_options_set(session, SSH_OPTIONS_USER, userString);
}


-(void)setPassword:(const char *)passwordString
{
    password = strdup(passwordString);
}


-(void)setWidth:(int)newWidth
{
    width = newWidth;
}


-(void)setHeight:(int)newHeight
{
    if (newHeight != height)
    {
        height = newHeight;
        [outLock lock];
        changeHeight = newHeight;
        [outLock unlock];
    }
}


-(int)readIn:(UInt8 *)buffer length:(int)count
{
    [inLock lock];
    
    if (count > inIndex)
    {
        count = inIndex;
    }

    memcpy(buffer, inBuffer, count);
    if (count < inIndex)
    {
        memmove(inBuffer, inBuffer + count, inIndex - count);
    }
    inIndex -= count;

    [inLock unlock];
    
    return count;
}


-(int)writeFrom:(const UInt8 *)buffer length:(int)count
{
    [outLock lock];
    
    if (count > OUTPUT_BUFFER_SIZE - outIndex)
    {
        count = OUTPUT_BUFFER_SIZE - outIndex;
    }
    
    memcpy(outBuffer + outIndex, buffer, count);
    outIndex += count;
    
    [outLock unlock];
    
    return count;
}


-(void)setDataCallbackOn:(NSObject *)newSink with:(SEL)selector
{
    dataSink = newSink;
    dataSelector = selector;
}


-(void)setEventCallbackOn:(NSObject *)newSink with:(SEL)selector
{
    eventSink = newSink;
    eventSelector = selector;
}


-(void)eventNotify:(NSInteger)code
{
    [eventSink performSelectorOnMainThread:eventSelector withObject:[NSNumber numberWithInteger:code] waitUntilDone:NO];
}


-(void)main
{
    int result = ssh_connect(session);
    if (result != SSH_OK)
    {
        [self eventNotify:CONNECTION_ERROR];
        goto EXIT;
    }
    
    result = ssh_is_server_known(session);
    switch (result)
    {
        case SSH_SERVER_KNOWN_OK:
            break;
            
        case SSH_SERVER_KNOWN_CHANGED:
            [self eventNotify:SERVER_KEY_CHANGED];
            break;
            
        case SSH_SERVER_FOUND_OTHER:
            [self eventNotify:SERVER_KEY_FOUND_OTHER];
            break;
            
        case SSH_SERVER_FILE_NOT_FOUND:
            [self eventNotify:SERVER_FILE_NOT_FOUND];
            break;
            
        case SSH_SERVER_NOT_KNOWN:
            [self eventNotify:SERVER_NOT_KNOWN];
            break;
            
        case SSH_SERVER_ERROR:
            [self eventNotify:SERVER_ERROR];
            break;
            
        default:
            break;
    }
    
    result = ssh_userauth_password(session, NULL, password);
    if (result != SSH_AUTH_SUCCESS)
    {
        if (result == SSH_AUTH_ERROR)
        {
            [self eventNotify:FATAL_ERROR];
        }
        else
        {
            [self eventNotify:PASSWORD_AUTHENTICATION_DENIED];
        }
        goto DISCONNECT_EXIT;
    }
    
    channel = ssh_channel_new(session);
    if (channel == NULL)
    {
        [self eventNotify:CHANNEL_ERROR];
        goto DISCONNECT_EXIT;
    }
    
    result = ssh_channel_open_session(channel);
    if (result != SSH_OK)
    {
        [self eventNotify:CHANNEL_ERROR];
        goto CLOSE_CHANNEL_EXIT;
    }
    
    result = ssh_channel_request_pty(channel);
    if (result != SSH_OK)
    {
        [self eventNotify:CHANNEL_ERROR];
        goto CLOSE_CHANNEL_EXIT;
    }
    result = ssh_channel_change_pty_size(channel, width, height);
    if (result != SSH_OK)
    {
        [self eventNotify:CHANNEL_ERROR];
        goto CLOSE_CHANNEL_EXIT;
    }
    changeHeight = 0;
    
    result = ssh_channel_request_shell(channel);
    if (result != SSH_OK)
    {
        [self eventNotify:CHANNEL_ERROR];
        goto CLOSE_CHANNEL_EXIT;
    }
    
    [self eventNotify:CONNECTED];
    while (ssh_channel_is_open(channel) && ssh_channel_is_eof(channel) == 0)
    {
        [inLock lock];
        int readCount = ssh_channel_read_nonblocking(channel, inBuffer + inIndex, INPUT_BUFFER_SIZE - inIndex, 0);
        if (readCount > 0)
        {
            inIndex += readCount;
        }
        [inLock unlock];
        if (readCount > 0)
        {
            [dataSink performSelectorOnMainThread:dataSelector withObject:nil waitUntilDone:NO];
        }
        
        [outLock lock];
        if (outIndex)
        {
            int writeCount = ssh_channel_write(channel, outBuffer, outIndex);
            if (writeCount > 0)
            {
                memmove(outBuffer, outBuffer + writeCount, outIndex - writeCount);
                outIndex -= writeCount;
            }
        }
        if (changeHeight != 0)
        {
            result = ssh_channel_change_pty_size(channel, width, changeHeight);
            if (result != SSH_OK)
            {
                [self eventNotify:CHANNEL_RESIZE_ERROR];
            }
            changeHeight = 0;
        }
        [outLock unlock];
        
        if ([self isCancelled] == YES)
        {
            break;
        }
        
        if (readCount == 0)
        {
            [NSThread sleepForTimeInterval:0.01];
        }
    }
    
CLOSE_CHANNEL_EXIT:
    ssh_channel_close(channel);
    ssh_channel_free(channel);

DISCONNECT_EXIT:
    ssh_disconnect(session);
    
EXIT:
    [self eventNotify:DISCONNECTED];
}


-(SshConnection*)init
{
    self = [super init];
    if (self != nil)
    {
        inIndex = 0;
        outIndex = 0;

        inLock = [[NSLock alloc] init];
        outLock = [[NSLock alloc] init];
        changeHeight = 0;
        
        session = ssh_new();
        if (session != NULL)
        {
            gInstanceCount++;
        }
        
        if (session == NULL || inLock == nil || outLock == nil)
        {
            self = nil;
        }
    }
    
    return self;
}


-(void)dealloc
{
    if (session != NULL)
    {
        ssh_free(session);
        gInstanceCount--;
        if (gInstanceCount == 0)
        {
            ssh_finalize();
        }
    }
}


@end
