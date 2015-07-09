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


int PrivateKeyAuthCallback(const char *prompt, char *buf, size_t len, int echo, int verify, void *userdata)
{
    return SSH_ERROR;
}


@implementation SshConnection

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
    int readCount = ssh_channel_read_nonblocking(channel, buffer, count, 0);
    if (readCount == count)
    {
        // Might have more data to read:
        dispatch_async(queue, ^(void){ [dataDelegate newDataAvailable]; });
    }
    else if (ssh_channel_is_eof(channel))
    {
        dispatch_suspend(readSource);
        dispatch_async(queue, ^(void){ [self closeTerminalChannel]; });
        return 0;
    }
    return readCount;
}


-(int)writeFrom:(const UInt8 *)buffer length:(int)count
{
    int writeCount = ssh_channel_write(channel, buffer, count);
    return writeCount;
}


-(void)resume:(BOOL)isResuming andSaveHost:(BOOL)needsSaveHost
{
    if (needsSaveHost == YES)
    {
        ssh_write_knownhost(session);
    }
    dispatch_async(queue, ^(void){ [self authenticateUser]; });
}


-(void)endConnection
{
    dispatch_async(queue, ^(void){ [self closeTerminalChannel]; });
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


-(void)setDataDelegate:(id<SshConnectionDataDelegate>)newDataDelegate
{
    dataDelegate = newDataDelegate;
}


-(void)setEventDelegate:(id<SshConnectionEventDelegate>)newEventDelegate
{
    eventDelegate = newEventDelegate;
}


-(void)eventNotify:(int)code
{
    [eventDelegate signalError:code];
}


-(void)connect
{
    int result = ssh_connect(session);
    if (result != SSH_OK)
    {
        [self eventNotify:CONNECTION_ERROR];
    }
    
    dispatch_async(queue, ^(void){ [self authenticateServer]; });
}


-(void)authenticateServer
{
    int result = ssh_is_server_known(session);
    switch (result)
    {
        case SSH_SERVER_KNOWN_OK:
        {
            dispatch_async(queue, ^{ [self authenticateUser]; });
            break;
        }
            
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
        default:
            [self eventNotify:SERVER_ERROR];
            break;
    }
}


-(void)authenticateUser
{
    if (useKeyAuthentication == YES)
    {
        // User authentication by key:
        ssh_key key = ssh_key_new();
        int result = ssh_pki_import_privkey_file(keyFilePath, keyFilePassword, PrivateKeyAuthCallback, NULL, &key);
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
                dispatch_async(queue, ^(void){ [self disconnect]; });
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
            dispatch_async(queue, ^(void){ [self disconnect]; });
        }
    }
    else
    {
        // User authentication by password:
        int result = ssh_userauth_password(session, NULL, password);
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
            dispatch_async(queue, ^(void){ [self disconnect]; });
        }
    }
    
    dispatch_async(queue, ^(void){ [self openTerminalChannel]; });
}


-(void)openTerminalChannel
{
    int fd = ssh_get_fd(session);
    readSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, fd, 0, queue);
    dispatch_source_set_event_handler(readSource, ^(void){ [dataDelegate newDataAvailable]; });
    
    channel = ssh_channel_new(session);
    if (channel == NULL)
    {
        [self eventNotify:CHANNEL_ERROR];
        dispatch_async(queue, ^(void){ [self disconnect]; });
    }
    
    int result = ssh_channel_open_session(channel);
    if (result != SSH_OK)
    {
        [self eventNotify:CHANNEL_ERROR];
        dispatch_async(queue, ^(void){ [self closeTerminalChannel]; });
    }
    
    result = ssh_channel_request_pty(channel);
    if (result != SSH_OK)
    {
        [self eventNotify:CHANNEL_ERROR];
        dispatch_async(queue, ^(void){ [self closeTerminalChannel]; });
    }
    result = ssh_channel_change_pty_size(channel, width, height);
    if (result != SSH_OK)
    {
        [self eventNotify:CHANNEL_ERROR];
        dispatch_async(queue, ^(void){ [self closeTerminalChannel]; });
    }
    
    result = ssh_channel_request_shell(channel);
    if (result != SSH_OK)
    {
        [self eventNotify:CHANNEL_ERROR];
        dispatch_async(queue, ^(void){ [self closeTerminalChannel]; });
    }

    [self eventNotify:CONNECTED];
    dispatch_resume(readSource);
}


-(void)closeTerminalChannel
{
    if (ssh_channel_is_open(channel))
    {
        ssh_channel_close(channel);
        ssh_channel_free(channel);
    }
    dispatch_async(queue, ^(void){ [self disconnect]; });
}


-(void)disconnect
{
    if (ssh_is_connected(session))
    {
        ssh_disconnect(session);
    }
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

        queue = dispatch_get_main_queue();
        
        dataDelegate = nil;
        eventDelegate = nil;
        
        if (session == NULL)
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
