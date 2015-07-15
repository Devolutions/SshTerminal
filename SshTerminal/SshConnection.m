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


// Helper functions.
int PrivateKeyAuthCallback(const char *prompt, char *buf, size_t len, int echo, int verify, void *userdata)
{
    // This callback implementation avoids a password prompt for key files when the provided password is wrong.
    return SSH_ERROR;
}


int createBoundSocket(UInt16 port, const char* host)
{
    struct addrinfo* info;
    struct addrinfo hint;
    memset(&hint, 0, sizeof(hint));
    hint.ai_flags = AI_ADDRCONFIG | AI_PASSIVE;
    hint.ai_family = PF_UNSPEC;
    hint.ai_socktype = SOCK_STREAM;
    hint.ai_protocol = IPPROTO_TCP;
    int result = getaddrinfo(host, NULL, NULL, &info);
    if (result != 0)
    {
        return -1;
    }
    struct addrinfo* selectedInfo = info;
    while (selectedInfo->ai_next != NULL)
    {
        if ((selectedInfo->ai_family == PF_INET || selectedInfo->ai_family == PF_INET6) && selectedInfo->ai_socktype == SOCK_STREAM)
        {
            break;
        }
        selectedInfo = selectedInfo->ai_next;
    }
    
    int fd = socket(selectedInfo->ai_family, selectedInfo->ai_socktype, selectedInfo->ai_protocol);
    if (fd == -1)
    {
        freeaddrinfo(info);
        return -1;
    }
    
    int flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    
    struct sockaddr_in* address = (struct sockaddr_in*)selectedInfo->ai_addr;
    address->sin_port = htons(port);
    result = bind(fd, (struct sockaddr*)address, selectedInfo->ai_addrlen);
    freeaddrinfo(info);
    if (result != 0)
    {
        close(fd);
        return -1;
    }
    return fd;
}


//-----------------------------------------------------------------------

@implementation SshConnection

-(void)setDataDelegate:(id<SshConnectionDataDelegate>)newDataDelegate
{
    dataDelegate = newDataDelegate;
}


-(void)setEventDelegate:(id<SshConnectionEventDelegate>)newEventDelegate
{
    eventDelegate = newEventDelegate;
}


-(void)setHost:(NSString*)hostString
{
    ssh_options_set(session, SSH_OPTIONS_HOST, [hostString UTF8String]);
}


-(void)setPort:(SInt16)newPort
{
    ssh_options_set(session, SSH_OPTIONS_PORT, &newPort);
}


-(void)setUser:(NSString*)userString
{
    ssh_options_set(session, SSH_OPTIONS_USER, [userString UTF8String]);
}


-(void)setKeyFilePath:(NSString*)newKeyFilePath withPassword:(NSString*)newPassword
{
    useKeyAuthentication = NO;
    
    if (newKeyFilePath != nil)
    {
        if ([newKeyFilePath length] > 0)
        {
            keyFilePath = newKeyFilePath;
            useKeyAuthentication = YES;
        }
    }
    
    keyFilePassword = newPassword;
}


-(void)setPassword:(NSString*)passwordString
{
    password = passwordString;
}


-(void)setWidth:(int)newWidth
{
    width = newWidth;
}


-(void)addForwardTunnelPort:(SInt16)newPort host:(NSString*)newHost remotePort:(SInt16)newRemotePort remoteHost:(NSString*)newRemoteHost
{
    SshTunnel* tunnel = [SshTunnel new];
    
    tunnel.port = newPort;
    tunnel.remotePort = newRemotePort;
    tunnel.host = newHost;
    tunnel.remoteHost = newRemoteHost;
    
    [forwardTunnels addObject:tunnel];
}


-(void)addReverseTunnelPort:(SInt16)newPort host:(NSString*)newHost remotePort:(SInt16)newRemotePort remoteHost:(NSString*)newRemoteHost
{
    
}


-(int)readIn:(UInt8 *)buffer length:(int)count
{/*
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
    return readCount;*/
    return 0;
}


-(int)writeFrom:(const UInt8 *)buffer length:(int)count
{
    UInt8* writeBuffer = malloc(count);
    memcpy(writeBuffer, buffer, count);
    dispatch_async(queue, ^(void){
        ssh_channel_write(channel, writeBuffer, count);
        free(writeBuffer);
    });
    return count;
}


-(void)startConnection
{
    dispatch_async(queue, ^(void){ [self connect]; });
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
    dispatch_async(queue, ^(void){ [self closeAllChannels]; });
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


// The following methods are executed on the private queue.

-(void)eventNotify:(int)code
{
    dispatch_async(mainQueue, ^(void){ [eventDelegate signalError:code]; });
}


-(void)connect
{
    int result = ssh_connect(session);
    if (result != SSH_OK)
    {
        [self eventNotify:CONNECTION_ERROR];
        dispatch_async(queue, ^(void){ [self disconnect]; });
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
        int result = ssh_pki_import_privkey_file([keyFilePath UTF8String], [keyFilePassword UTF8String], PrivateKeyAuthCallback, NULL, &key);
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
        int result = ssh_userauth_password(session, NULL, [password UTF8String]);
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
    
    if (forwardTunnels.count > 0 || reverseTunnels.count > 0)
    {
        dispatch_async(queue, ^(void){ [self openTunnelChannels]; });
    }
    else
    {
        dispatch_async(queue, ^(void){ [self openTerminalChannel]; });
    }
}


-(void)openTerminalChannel
{
    int fd = ssh_get_fd(session);
    readSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, fd, 0, queue);
    dispatch_source_set_event_handler(readSource, ^(void){ [self newTerminalDataAvailable]; });
    
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
        dispatch_async(queue, ^(void){ [self closeAllChannels]; });
    }
    
    result = ssh_channel_request_pty(channel);
    if (result != SSH_OK)
    {
        [self eventNotify:CHANNEL_ERROR];
        dispatch_async(queue, ^(void){ [self closeAllChannels]; });
    }
    result = ssh_channel_change_pty_size(channel, width, height);
    if (result != SSH_OK)
    {
        [self eventNotify:CHANNEL_ERROR];
        dispatch_async(queue, ^(void){ [self closeAllChannels]; });
    }
    
    result = ssh_channel_request_shell(channel);
    if (result != SSH_OK)
    {
        [self eventNotify:CHANNEL_ERROR];
        dispatch_async(queue, ^(void){ [self closeAllChannels]; });
    }

    [self eventNotify:CONNECTED];
    dispatch_resume(readSource);
}


-(void)newTerminalDataAvailable
{
    int availableCount = ssh_channel_poll(channel, 0);
    if (availableCount > 0)
    {
        UInt8* buffer = malloc(availableCount);
        ssh_channel_read_nonblocking(channel, buffer, availableCount, 0);
        dispatch_async(dispatch_get_main_queue(), ^(void){
            [dataDelegate newDataAvailableIn:buffer length:availableCount];
            free(buffer);
        });
        
        // Some data might still be available: reschedule this task to be sure the channel is completely emptied.
        dispatch_async(queue, ^(void){ [self newTerminalDataAvailable]; } );
    }
    else if (ssh_channel_is_eof(channel))
    {
        // The terminal has exited:
        dispatch_async(queue, ^(void){ [self disconnect]; });
    }
}


-(void)openTunnelChannels
{
    int fd = ssh_get_fd(session);
    readSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, fd, 0, queue);
    dispatch_source_set_event_handler(readSource, ^(void){ [self newSshDataAvailable]; });
    dispatch_resume(readSource);
    
    for (int i = 0; i < [forwardTunnels count]; i++)
    {
        SshTunnel* tunnel = [forwardTunnels objectAtIndex:i];
        BOOL success = [tunnel startListeningAndDispatchTo:^(void){ [self newTunnelConnection:tunnel]; } onQueue:queue];
        if (success == NO)
        {
            [self eventNotify:TUNNEL_ERROR];
            [forwardTunnels removeObjectAtIndex:i];
        }
    }
    
    [self eventNotify:CONNECTED];
}


-(void)newSshDataAvailable
{
    BOOL dataHasBeenRead = NO;
    
    // Read data from the tunnel connection channels, if any.
    for (int i = 0; i < [tunnelConnections count]; i++)
    {
        SshTunnelConnection* tunnelConnection = [tunnelConnections objectAtIndex:i];
        dataHasBeenRead |= [tunnelConnection transferRemoteDataToLocal];
        if ([tunnelConnection isAlive] == NO)
        {
            [tunnelConnections removeObjectAtIndex:i];
        }
    }
    
    if (dataHasBeenRead == YES)
    {
        // Some data might still be available: reschedule this task to be sure all channels are emptied.
        dispatch_async(queue, ^(void){ [self newSshDataAvailable]; } );
    }
}


-(void)newTunnelConnection:(SshTunnel *)tunnel
{
    ssh_channel tunnelChannel = ssh_channel_new(session);
    if (tunnelChannel == NULL)
    {
        [self eventNotify:TUNNEL_ERROR];
        return;
    }
    int result = ssh_channel_open_forward(tunnelChannel, [tunnel.remoteHost UTF8String], tunnel.remotePort, [tunnel.host UTF8String], tunnel.port);
    if (result != SSH_OK)
    {
        [self eventNotify:TUNNEL_ERROR];
        return;
    }
    int tunnelFd = [tunnel acceptConnection];
    SshTunnelConnection* tunnelConnection = [SshTunnelConnection connectionWithSocket:tunnelFd onChannel:tunnelChannel onQueue:queue];
    
    if (tunnelConnection == nil)
    {
        [self eventNotify:TUNNEL_ERROR];
        return;
    }
    
    [tunnelConnections addObject:tunnelConnection];
}


-(void)closeAllChannels
{
    if (readSource != NULL)
    {
        dispatch_source_cancel(readSource);
        readSource = NULL;
    }
    if (channel != NULL)
    {
        ssh_channel_free(channel);
        channel = NULL;
    }
    
    for (int i = 0; i < [forwardTunnels count]; i++)
    {
        SshTunnel* tunnel = [forwardTunnels objectAtIndex:i];
        [tunnel endListening];
    }
    [forwardTunnels removeAllObjects];
    
    for (int i = 0; i < [reverseTunnels count]; i++)
    {
        SshTunnel* tunnel = [reverseTunnels objectAtIndex:i];
        //[tunnel endListening];
    }
    [reverseTunnels removeAllObjects];
    
    for (int i = 0; i < [tunnelConnections count]; i++)
    {
        SshTunnelConnection* tunnelConnection = [tunnelConnections objectAtIndex:i];
        [tunnelConnection disconnect];
    }
    [tunnelConnections removeAllObjects];
    
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

        queue = dispatch_queue_create("com.Devolutions.SshConnectionQueue", DISPATCH_QUEUE_SERIAL);
        mainQueue = dispatch_get_main_queue();
        forwardTunnels = [NSMutableArray new];
        tunnelConnections = [NSMutableArray new];
        
        if (session == NULL)
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
