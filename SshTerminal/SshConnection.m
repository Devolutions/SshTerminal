//
//  SshConnection.m
//  LibSshTest
//
//  Created by Denis Vincent on 2015-06-03.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import "SshConnection.h"
#import "SshTerminalView.h"

enum
{
    CONNECTION_ABORT = -1,
    CONNECTION_SUSPENDED = 0,
    CONNECTION_RESUME = 1,
};


int gInstanceCount = 0;


int PrivateKeyAuthCallback(const char *prompt, char *buf, size_t len, int echo, int verify, void *userdata)
{
    return SSH_ERROR;
}


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


-(void)setKeyFilePath:(const char *)newKeyFilePath withPassword:(const char*)newPassword
{
    free(keyFilePath);
    keyFilePath = NULL;
    free(keyFilePassword);
    keyFilePassword = NULL;
    useKeyAuthentication = NO;
    
    if (newKeyFilePath != NULL)
    {
        if (strlen(newKeyFilePath) > 0)
        {
            keyFilePath = strdup(newKeyFilePath);
            useKeyAuthentication = YES;
        }
    }
    
    if (newPassword != NULL)
    {
        keyFilePassword = strdup(newPassword);
    }
}


-(void)setPassword:(const char *)passwordString
{
    free(password);
    password = NULL;
    if (passwordString != NULL)
    {
        password = strdup(passwordString);
    }
}


-(void)setWidth:(int)newWidth
{
    width = newWidth;
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


-(void)resume:(BOOL)isResuming andSaveHost:(BOOL)needsSaveHost
{
    if (needsSaveHost == YES)
    {
        ssh_write_knownhost(session);
    }
    [connectCondition lock];
    resumeConnection = (isResuming == YES ? CONNECTION_RESUME : CONNECTION_ABORT);
    [connectCondition signal];
    [connectCondition unlock];
}


-(NSString*)fingerPrint
{
    ssh_key key = ssh_key_new();
    ssh_get_publickey(session, &key);
    unsigned char* hash;
    size_t len;
    ssh_get_publickey_hash(key, SSH_PUBLICKEY_HASH_MD5, &hash, &len);
    
    char* hexString = ssh_get_hexa(hash, len);
    NSString* returnString = [NSString stringWithUTF8String:hexString];
    
    free(hexString);
    free(hash);
    ssh_key_free(key);
    
    return returnString;
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


-(void)cancel
{
    [connectCondition lock];
    resumeConnection = CONNECTION_ABORT;
    [connectCondition signal];
    [connectCondition unlock];
    [super cancel];
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
    if (result != SSH_SERVER_KNOWN_OK)
    {
        BOOL suspendConnection = YES;
        switch (result)
        {
            case SSH_SERVER_KNOWN_CHANGED:
                [self eventNotify:SERVER_KEY_CHANGED];
                break;
                
            case SSH_SERVER_FOUND_OTHER:
                [self eventNotify:SERVER_KEY_FOUND_OTHER];
                break;
                
            case SSH_SERVER_FILE_NOT_FOUND:
                suspendConnection = NO;
                [self eventNotify:SERVER_FILE_NOT_FOUND];
                break;
                
            case SSH_SERVER_NOT_KNOWN:
                [self eventNotify:SERVER_NOT_KNOWN];
                break;
                
            case SSH_SERVER_ERROR:
            default:
                [self eventNotify:SERVER_ERROR];
                suspendConnection = NO;
                break;
        }
        
        if (suspendConnection == NO)
        {
            goto DISCONNECT_EXIT;
        }
        else
        {
            // A connection IS established, but could be compromised: suspend the connection process,
            // and wait for user feedback (eventNotify has caused an event to be sent to the user).
            BOOL disconnect = NO;
            [connectCondition lock];
            while (resumeConnection == CONNECTION_SUSPENDED)
            {
                [connectCondition wait];
            }
            if (resumeConnection == CONNECTION_ABORT)
            {
                disconnect = YES;
            }
            [connectCondition unlock];
            if (disconnect == YES)
            {
                goto DISCONNECT_EXIT;
            }
        }
    }
    
    if (useKeyAuthentication == YES)
    {
        // User authentication by key:
        ssh_key key = ssh_key_new();
        result = ssh_pki_import_privkey_file(keyFilePath, keyFilePassword, PrivateKeyAuthCallback, NULL, &key);
        if (result == SSH_OK)
        {
            result = ssh_userauth_publickey(session, NULL, key);
            ssh_key_free(key);
            
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
        }
        else
        {
            if (result == SSH_EOF)
            {
                [self eventNotify:KEY_FILE_NOT_FOUND_OR_DENIED];
            }
            else
            {
                [self eventNotify:FATAL_ERROR];
            }
            goto DISCONNECT_EXIT;
        }
    }
    else
    {
        // User authentication by password:
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
        session = ssh_new();
        if (session != NULL)
        {
            gInstanceCount++;
        }
        channel = NULL;
        
        useKeyAuthentication = NO;
        password = NULL;
        keyFilePassword = NULL;
        keyFilePath = NULL;
        width = 0;
        height = 0;
        
        inIndex = 0;
        outIndex = 0;
        resumeConnection = CONNECTION_SUSPENDED;

        inLock = [[NSLock alloc] init];
        outLock = [[NSLock alloc] init];
        connectCondition = [[NSCondition alloc] init];
        
        dataSink = nil;
        dataSelector = nil;
        eventSink = nil;
        eventSelector = nil;
        
        if (session == NULL || inLock == nil || outLock == nil || connectCondition == nil)
        {
            self = nil;
        }
    }
    
    return self;
}


-(void)dealloc
{
    free(password);
    free(keyFilePassword);
    free(keyFilePath);
    
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
