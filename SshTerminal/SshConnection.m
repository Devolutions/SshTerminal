//
//  SshConnection.m
//  LibSshTest
//
//  Created by Denis Vincent on 2015-06-03.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import "SshConnection.h"
#import "VT100TerminalView.h"


int gInstanceCount = 0;


int PrivateKeyAuthCallback(const char *prompt, char *buf, size_t len, int echo, int verify, void *userdata)
{
    // This callback implementation avoids a password prompt for key files when the provided password is wrong.
    return SSH_ERROR;
}


@implementation SshConnection

-(void)setDataDelegate:(id<VT100TerminalDataDelegate>)newDataDelegate
{
    dataDelegate = newDataDelegate;
    [newDataDelegate retain];
}


-(void)setEventDelegate:(id<SshConnectionEventDelegate>)newEventDelegate
{
    eventDelegate = newEventDelegate;
    [newEventDelegate retain];
}


-(void)setHost:(NSString *)newHost port:(UInt16)newPort protocol:(int)newProtocol
{
    [host release];
    host = [newHost copy];
    ssh_options_set(session, SSH_OPTIONS_PORT, &newPort);
    internetProtocol = newProtocol;
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
            [keyFilePath release];
            keyFilePath = newKeyFilePath;
            [keyFilePath retain];
            useKeyAuthentication = YES;
        }
    }
    
    [keyFilePassword release];
    keyFilePassword = newPassword;
    [keyFilePassword retain];
}


-(void)setPassword:(NSString*)passwordString
{
    [password release];
    password = passwordString;
    [password retain];
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
    tunnel.reverse = NO;
    
    [forwardTunnels addObject:tunnel];
    [tunnel release];
}


-(void)addReverseTunnelPort:(SInt16)newPort host:(NSString*)newHost remotePort:(SInt16)newRemotePort remoteHost:(NSString*)newRemoteHost
{
    SshTunnel* tunnel = [SshTunnel new];
    
    tunnel.port = newPort;
    tunnel.remotePort = newRemotePort;
    tunnel.host = newHost;
    tunnel.remoteHost = newRemoteHost;
    tunnel.reverse = YES;
    
    [reverseTunnels addObject:tunnel];
    [tunnel release];
}


-(void)setX11Forwarding:(BOOL)enable withDisplay:(NSString *)display
{
    [x11DisplayName release];
    x11DisplayName = display;
    [x11DisplayName retain];
    if (x11DisplayName == nil)
    {
        char* displayEnv = getenv("DISPLAY");
        if (displayEnv != NULL && strlen(displayEnv) > 0)
        {
            x11DisplayName = [NSString stringWithUTF8String:displayEnv];
            [x11DisplayName retain];
        }
    }
    if (x11DisplayName == nil)
    {
        enable = NO;
    }
    
    if (enable == YES)
    {
        int displayNameLength = (int)[x11DisplayName length];
        NSRange colonRange = [x11DisplayName rangeOfString:@":" options:NSBackwardsSearch];
        if (colonRange.length > 0)
        {
            NSRange displayNumberRange = NSMakeRange(colonRange.location + 1, displayNameLength - colonRange.location - 1);
            NSRange dotRange = [x11DisplayName rangeOfString:@"." options:0 range:displayNumberRange];
            if (dotRange.length > 0)
            {
                NSRange screenNumberRange = NSMakeRange(dotRange.location + 1, [x11DisplayName length] - dotRange.location - 1);
                displayNumberRange.length = dotRange.location - displayNumberRange.location;
                NSString* screenNumberString = [x11DisplayName substringWithRange:screenNumberRange];
                x11ScreenNumber = [screenNumberString intValue];
                [screenNumberString release];
            }
            NSString* displayNumberString = [x11DisplayName substringWithRange:displayNumberRange];
            x11DisplayNumber = [displayNumberString intValue];
            [displayNumberString release];
            
            NSRange hostRange = NSMakeRange(0, colonRange.location);
            [x11Host release];
            x11Host = [x11DisplayName substringWithRange:hostRange];
            [x11Host retain];
        }
        else
        {
            // Malformed X display name:
            enable = NO;
        }
    }
    
    x11Forwarding = enable;
}


-(int)writeFrom:(const UInt8 *)buffer length:(int)count
{
    UInt8* writeBuffer = malloc(count);
    memcpy(writeBuffer, buffer, count);
    dispatch_async(queue, ^{
        ssh_channel_write(channel, writeBuffer, count);
        free(writeBuffer);
    });
    return count;
}


-(void)startConnection
{
    dispatch_async(queue, ^{ [self connect]; });
}


-(void)resume:(BOOL)isResuming andSaveHost:(BOOL)needsSaveHost
{
    if (needsSaveHost == YES)
    {
        ssh_write_knownhost(session);
    }
    dispatch_async(queue, ^{ [self authenticateUser]; });
}


-(void)endConnection
{
    dispatch_async(queue, ^{ [self closeAllChannels]; });
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
    dispatch_async(mainQueue, ^{ [eventDelegate signalError:code]; });
}


-(int)x11ConnectSocket
{
    if (x11DisplayName == nil)
    {
        return -1;
    }
    
    int fd = -1;
    if ([x11DisplayName characterAtIndex:0] == '/')
    {
        fd = socket(PF_UNIX, SOCK_STREAM, 0);
        struct sockaddr_un unixDomainAddress;
        memset(&unixDomainAddress, 0, sizeof(unixDomainAddress));
        unixDomainAddress.sun_family = AF_UNIX;
        const char* displayAddress = [x11DisplayName UTF8String];
        snprintf(unixDomainAddress.sun_path, sizeof(unixDomainAddress.sun_path), "%s", displayAddress);
        int result = connect(fd, (struct sockaddr*)&unixDomainAddress, sizeof(unixDomainAddress));
        if (result < 0)
        {
            close(fd);
            return -1;
        }
    }
    else
    {
        NetworkAddress hostAddresses[2];
        int addressCount = resolveHost(hostAddresses, [x11Host UTF8String]);
        if (addressCount == 0)
        {
            return -1;
        }
        
        fd = socket(hostAddresses[0].family, SOCK_STREAM, IPPROTO_TCP);
        if (fd < 0)
        {
            return -1;
        }
        NetworkAddress bindAddress;
        memset(&bindAddress, 0, sizeof(bindAddress));
        bindAddress.len = hostAddresses[0].len;
        bindAddress.family = hostAddresses[0].family;
        int result = bind(fd, &bindAddress.ip, bindAddress.len);
        if (result < 0)
        {
            close(fd);
            return -1;
        }
        
        hostAddresses[0].port = htons(6000 + x11DisplayNumber);
        result = connect(fd, &hostAddresses[0].ip, hostAddresses[0].len);
        if (result < 0)
        {
            close(fd);
            return -1;
        }
    }
    
    return fd;
}


-(void)connect
{
    NetworkAddress addresses[2];
    int addressCount = resolveHost(addresses, [host UTF8String]);
    if (addressCount == 0)
    {
        [self eventNotify:CONNECTION_ERROR];
        dispatch_async(queue, ^{ [self disconnect]; });
        return;
    }
    int selectedAddress = 0;
    if (addressCount > 1 && internetProtocol != PF_UNSPEC)
    {
        if (addresses[0].family != internetProtocol)
        {
            selectedAddress = 1;
        }
    }
    char addressString[45];
    getnameinfo(&addresses[selectedAddress].ip, addresses[selectedAddress].len, addressString, sizeof(addressString), NULL, 0, NI_NUMERICHOST | NI_NUMERICSERV);
    ssh_options_set(session, SSH_OPTIONS_HOST, addressString);
    int result = ssh_connect(session);
    if (result != SSH_OK)
    {
        [self eventNotify:CONNECTION_ERROR];
        dispatch_async(queue, ^{ [self disconnect]; });
        return;
    }
    
    dispatch_async(queue, ^{ [self authenticateServer]; });
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
        
        // Potential attack errors (the client will be notified and will need to either -(void)resume or -(void)disconnect).
        case SSH_SERVER_KNOWN_CHANGED:
            [self eventNotify:SERVER_KEY_CHANGED];
            break;
            
        case SSH_SERVER_FOUND_OTHER:
            [self eventNotify:SERVER_KEY_FOUND_OTHER];
            break;
            
        case SSH_SERVER_NOT_KNOWN:
            [self eventNotify:SERVER_NOT_KNOWN];
            break;
        
        // Fatal errors.
        case SSH_SERVER_FILE_NOT_FOUND:
            [self eventNotify:SERVER_FILE_NOT_FOUND];
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
        if (key == NULL)
        {
            [self eventNotify:OUT_OF_MEMORY_ERROR];
            dispatch_async(queue, ^{ [self disconnect]; });
            return;
        }
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
                dispatch_async(queue, ^{ [self disconnect]; });
                return;
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
            dispatch_async(queue, ^{ [self disconnect]; });
            return;
        }
    }
    else
    {
        // User authentication by password:
        int result = ssh_userauth_none(session, NULL);   // This call is required for ssh_userauth_list() to succeed.
        int authList = ssh_userauth_list(session, NULL);
        if (authList & SSH_AUTH_METHOD_PASSWORD)
        {
            do
            {
                result = ssh_userauth_password(session, NULL, [password UTF8String]);
                if (result == SSH_AUTH_AGAIN)
                {
                    [NSThread sleepForTimeInterval:0.1];
                }
            } while (result == SSH_AUTH_AGAIN);
        }
        
        if (result != SSH_AUTH_SUCCESS && (authList & SSH_AUTH_METHOD_INTERACTIVE))
        {
            result = ssh_userauth_kbdint(session, NULL, NULL);
            if (result == SSH_AUTH_INFO)
            {
                int promptCount = ssh_userauth_kbdint_getnprompts(session);
                if (promptCount >= 1)
                {
                    result = ssh_userauth_kbdint_setanswer(session, 0, [password UTF8String]);
                    result = ssh_userauth_kbdint(session, NULL, NULL);
                    if (result == SSH_AUTH_INFO)
                    {
                        promptCount = ssh_userauth_kbdint_getnprompts(session);
                        result = ssh_userauth_kbdint(session, NULL, NULL);
                    }
                }
            }
        }
        
        if (result != SSH_AUTH_SUCCESS && (authList & SSH_AUTH_METHOD_GSSAPI_MIC))
        {
            do
            {
                result = ssh_userauth_gssapi(session);
            } while (result == SSH_AUTH_AGAIN);
        }
        
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
            dispatch_async(queue, ^{ [self disconnect]; });
            return;
        }
    }
    
    if (forwardTunnels.count > 0 || reverseTunnels.count > 0)
    {
        dispatch_async(queue, ^{ [self openTunnelChannels]; });
    }
    else
    {
        dispatch_async(queue, ^{ [self openTerminalChannel]; });
    }
}


-(void)openTerminalChannel
{
    int fd = ssh_get_fd(session);
    readSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, fd, 0, queue);
    if (readSource == nil)
    {
        [self eventNotify:OUT_OF_MEMORY_ERROR];
        dispatch_async(queue, ^{ [self disconnect]; });
        return;
    }
    dispatch_source_set_event_handler(readSource, ^{ [self newTerminalDataAvailable]; });
    
    channel = ssh_channel_new(session);
    if (channel == NULL)
    {
        [self eventNotify:OUT_OF_MEMORY_ERROR];
        dispatch_async(queue, ^{ [self disconnect]; });
        return;
    }
    
    int result = ssh_channel_open_session(channel);
    if (result != SSH_OK)
    {
        [self eventNotify:CHANNEL_ERROR];
        dispatch_async(queue, ^{ [self closeAllChannels]; });
        return;
    }
    
    result = ssh_channel_request_pty(channel);
    if (result != SSH_OK)
    {
        [self eventNotify:CHANNEL_ERROR];
        dispatch_async(queue, ^{ [self closeAllChannels]; });
        return;
    }
    result = ssh_channel_change_pty_size(channel, width, height);
    if (result != SSH_OK)
    {
        [self eventNotify:CHANNEL_ERROR];
        dispatch_async(queue, ^{ [self closeAllChannels]; });
        return;
    }
    
    if (x11Forwarding == YES)
    {
        const char* protocol = NULL;
        const char* cookie = NULL;

        result = ssh_channel_request_x11(channel, 0, protocol, cookie, x11ScreenNumber);
        if (result != SSH_OK)
        {
            [self eventNotify:X11_ERROR];
        }
    }
    
    result = ssh_channel_request_shell(channel);
    if (result != SSH_OK)
    {
        [self eventNotify:CHANNEL_ERROR];
        dispatch_async(queue, ^{ [self closeAllChannels]; });
        return;
    }
    
    [self eventNotify:CONNECTED];
    dispatch_resume(readSource);
}


-(void)newTerminalDataAvailable
{
    BOOL dataHasBeenRead = NO;
    
    // This method is called by the dispatch source associated with the socket of the SSH session.
    int availableCount = ssh_channel_poll(channel, 0);
    if (availableCount > 0)
    {
        dataHasBeenRead = YES;
        UInt8* buffer = malloc(availableCount);
        if (buffer == NULL)
        {
            [self eventNotify:OUT_OF_MEMORY_ERROR];
            dispatch_async(queue, ^{ [self closeAllChannels]; });
            return;
        }
        ssh_channel_read_nonblocking(channel, buffer, availableCount, 0);
        dispatch_async(mainQueue, ^{
            [dataDelegate newDataAvailableIn:buffer length:availableCount];
            free(buffer);
        });
    }
    
    if (x11Forwarding == YES)
    {
        // Read data from the tunnel connection channels, if any.
        for (int i = 0; i < [tunnelConnections count]; i++)
        {
            SshTunnelConnection* tunnelConnection = [tunnelConnections objectAtIndex:i];
            dataHasBeenRead |= [tunnelConnection transferRemoteDataToLocal];
            if ([tunnelConnection isAlive] == NO)
            {
                [tunnelConnections removeObjectAtIndex:i];
                i--;
            }
        }
        
        ssh_channel x11Channel = ssh_channel_accept_x11(channel, 0);
        if (x11Channel != NULL)
        {
            // A X11 tunnel is accepted:
            dataHasBeenRead |= YES;
            int tunnelFd = [self x11ConnectSocket];
            SshTunnelConnection* tunnelConnection = [SshTunnelConnection connectionWithSocket:tunnelFd onChannel:x11Channel onQueue:queue];
            if (tunnelConnection != nil)
            {
                [tunnelConnections addObject:tunnelConnection];
            }
            else
            {
                [self eventNotify:TUNNEL_ERROR];
            }
        }
    }
    
    if (ssh_channel_is_eof(channel))
    {
        // The terminal has closed the connection:
        dispatch_async(queue, ^{ [self closeAllChannels]; });
    }
    else if (dataHasBeenRead == YES)
    {
        // Some data might still be available: reschedule this task to be sure the channel is completely emptied.
        dispatch_async(queue, ^{ [self newTerminalDataAvailable]; } );
    }
}


-(void)openTunnelChannels
{
    int fd = ssh_get_fd(session);
    readSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, fd, 0, queue);
    if (readSource == nil)
    {
        [self eventNotify:OUT_OF_MEMORY_ERROR];
        dispatch_async(queue, ^{ [self disconnect]; });
        return;
    }
    dispatch_source_set_event_handler(readSource, ^{ [self newSshDataAvailable]; });
    dispatch_resume(readSource);
    
    for (int i = 0; i < [forwardTunnels count]; i++)
    {
        SshTunnel* tunnel = [forwardTunnels objectAtIndex:i];
        SshTunnel* counterPartTunnel = [tunnel resolveHost];
        BOOL success = [tunnel startListeningAndDispatchTo:^{ [self newTunnelConnection:tunnel]; } onQueue:queue];
        if (success == NO)
        {
            [self eventNotify:TUNNEL_ERROR];
            [forwardTunnels removeObjectAtIndex:i];
            i--;
        }
        if (counterPartTunnel != nil)
        {
            success = [counterPartTunnel startListeningAndDispatchTo:^{ [self newTunnelConnection:counterPartTunnel]; } onQueue:queue];
            if (success == YES)
            {
                [forwardTunnels insertObject:counterPartTunnel atIndex:i];
                i++;
            }
            else
            {
                [self eventNotify:TUNNEL_ERROR];
            }
            [counterPartTunnel release];
        }
    }
    
    for (int i = 0; i < [reverseTunnels count]; i++)
    {
        SshTunnel* tunnel = [reverseTunnels objectAtIndex:i];
        int boundPort;
        int result = ssh_channel_listen_forward(session, [tunnel.remoteHost UTF8String], tunnel.remotePort, &boundPort);
        if (result != SSH_OK)
        {
            [self eventNotify:TUNNEL_ERROR];
            [reverseTunnels removeObjectAtIndex:i];
            i--;
        }
    }
    
    dispatch_async(mainQueue, ^{
        char stringBuffer[81];
        snprintf(stringBuffer, 80, "Logged in to: %s\r\n", [host UTF8String]);
        [dataDelegate newDataAvailableIn:(UInt8*)stringBuffer length:(int)strlen(stringBuffer)];
    });
    [self eventNotify:CONNECTED];
}


-(void)disconnectionMessage:(SshTunnelConnection*)tunnelConnection
{
    char stringBuffer[80];
    SshTunnel* tunnel = tunnelConnection.tunnel;
    if (tunnelConnection.endedByRemote == NO)
    {
        if (tunnel.reverse == NO)
        {
            snprintf(stringBuffer, sizeof(stringBuffer), "Connection terminated by %s:%s\r\n", tunnelConnection.peerAddress, tunnelConnection.peerPort);
        }
        else
        {
            snprintf(stringBuffer, sizeof(stringBuffer), "Connection terminated by %s:%d\r\n", [tunnel.host UTF8String], tunnel.port);
        }
    }
    else
    {
        if (tunnel.reverse == NO)
        {
            snprintf(stringBuffer, sizeof(stringBuffer), "Connection to %s:%s terminated by remote server\r\n", tunnelConnection.peerAddress, tunnelConnection.peerPort);
        }
        else
        {
            snprintf(stringBuffer, sizeof(stringBuffer), "Connection to %s:%d terminated by remote server\r\n", [tunnel.host UTF8String], tunnel.port);
        }
    }
    [dataDelegate newDataAvailableIn:(UInt8*)stringBuffer length:(int)strlen(stringBuffer)];
}


-(void)remoteConnectionMessage:(SshTunnelConnection*)tunnelConnection
{
    char stringBuffer[240];
    SshTunnel* tunnel = tunnelConnection.tunnel;
    int n = snprintf(stringBuffer, sizeof(stringBuffer), "Connected %s:%s\r\n", tunnelConnection.address, tunnelConnection.port);
    n += snprintf(stringBuffer + n, sizeof(stringBuffer) - n, "    to local %s:%d\r\n", [tunnel.host UTF8String], tunnel.port);
    snprintf(stringBuffer + n, sizeof(stringBuffer) - n, "    from remote %s:%d\r\n", [tunnel.remoteHost UTF8String], tunnel.remotePort);
    [dataDelegate newDataAvailableIn:(UInt8*)stringBuffer length:(int)strlen(stringBuffer)];
}


-(void)newSshDataAvailable
{
    // This method is called by the dispatch source associated with the socket of the SSH session.
    BOOL dataHasBeenRead = NO;
    
    // Read data from the tunnel connection channels, if any.
    for (int i = 0; i < [tunnelConnections count]; i++)
    {
        SshTunnelConnection* tunnelConnection = [tunnelConnections objectAtIndex:i];
        dataHasBeenRead |= [tunnelConnection transferRemoteDataToLocal];
        if ([tunnelConnection isAlive] == NO)
        {
            [tunnelConnections removeObjectAtIndex:i];
            i--;
            
            dispatch_async(mainQueue, ^{ [self disconnectionMessage:tunnelConnection]; });
        }
    }
    
    // Check if a reverse tunnel is ready to be accepted.
    int destinationPort;
    ssh_channel tunnelChannel = ssh_channel_accept_forward(session, 0, &destinationPort);
    if (tunnelChannel != NULL)
    {
        // A reverse tunnel is accepted: search the reverse tunnels to find the tunnel corresponding to the destination port.
        dataHasBeenRead |= YES;
        for (int i = 0; i < [reverseTunnels count]; i++)
        {
            SshTunnel* tunnel = [reverseTunnels objectAtIndex:i];
            if (tunnel.remotePort == destinationPort)
            {
                int tunnelFd = [tunnel connectToLocal];
                SshTunnelConnection* tunnelConnection = [SshTunnelConnection connectionWithSocket:tunnelFd onChannel:tunnelChannel onQueue:queue];
                if (tunnelConnection != nil)
                {
                    tunnelConnection.tunnel = tunnel;
                    [tunnelConnections addObject:tunnelConnection];
                    
                    dispatch_async(mainQueue, ^{ [self remoteConnectionMessage:tunnelConnection]; });
                }
                else
                {
                    [self eventNotify:TUNNEL_ERROR];
                }
                
                break;
            }
        }
    }
    
    if (dataHasBeenRead == YES)
    {
        // Some data might still be available: reschedule this task to be sure all channels are emptied.
        dispatch_async(queue, ^{ [self newSshDataAvailable]; } );
    }
}


-(void)localConnectionMessage:(SshTunnelConnection*)tunnelConnection
{
    char stringBuffer[240];
    SshTunnel* tunnel = tunnelConnection.tunnel;
    int n = snprintf(stringBuffer, sizeof(stringBuffer), "Accepted connection from %s:%s\r\n", tunnelConnection.peerAddress, tunnelConnection.peerPort);
    n += snprintf(stringBuffer + n, sizeof(stringBuffer) - n, "    on local %s:%d\r\n", [tunnel.host UTF8String], tunnel.port);
    snprintf(stringBuffer + n, sizeof(stringBuffer) - n, "    to remote %s:%d\r\n", [tunnel.remoteHost UTF8String], tunnel.remotePort);
    [dataDelegate newDataAvailableIn:(UInt8*)stringBuffer length:(int)strlen(stringBuffer)];
}


-(void)newTunnelConnection:(SshTunnel *)tunnel
{
    // This method is called by the dispatch source associated with the listen socket of a forward tunnel.
    int tunnelFd = [tunnel acceptConnection];
    if (tunnelFd < 0)
    {
        [self eventNotify:TUNNEL_ERROR];
        return;
    }
    ssh_channel tunnelChannel = ssh_channel_new(session);
    if (tunnelChannel == NULL)
    {
        close(tunnelFd);
        [self eventNotify:OUT_OF_MEMORY_ERROR];
        return;
    }
    int result = ssh_channel_open_forward(tunnelChannel, [tunnel.remoteHost UTF8String], tunnel.remotePort, [tunnel.host UTF8String], tunnel.port);
    if (result != SSH_OK)
    {
        close(tunnelFd);
        [self eventNotify:TUNNEL_ERROR];
        return;
    }
    SshTunnelConnection* tunnelConnection = [SshTunnelConnection connectionWithSocket:tunnelFd onChannel:tunnelChannel onQueue:queue];
    if (tunnelConnection == nil)
    {
        close(tunnelFd);
        [self eventNotify:OUT_OF_MEMORY_ERROR];
        return;
    }
    
    tunnelConnection.tunnel = tunnel;
    [tunnelConnections addObject:tunnelConnection];

    dispatch_async(mainQueue, ^{ [self localConnectionMessage:tunnelConnection]; });
}


-(void)brutalDisconnectMessage:(SshTunnelConnection*)tunnelConnection
{
    char stringBuffer[240];
    SshTunnel* tunnel = tunnelConnection.tunnel;
    if (tunnel.reverse == NO)
    {
        snprintf(stringBuffer, sizeof(stringBuffer), "Connection %s:%s aborted\r\n", tunnelConnection.peerAddress, tunnelConnection.peerPort);
    }
    else
    {
        snprintf(stringBuffer, sizeof(stringBuffer), "Connection %s:%s aborted\r\n", tunnelConnection.address, tunnelConnection.port);
    }
    [dataDelegate newDataAvailableIn:(UInt8*)stringBuffer length:(int)strlen(stringBuffer)];
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
        ssh_channel_cancel_forward(session, [tunnel.remoteHost UTF8String], tunnel.remotePort);
    }
    [reverseTunnels removeAllObjects];
    
    // Some dispatch sources might have been triggered after the beginning of this method and before they were canceled. Since they will
    // be executed later and might result in new tunnel connections, the removal of all tunnelConnection objects is performed in
    // a queued task that will necessary happen after all tasks queued by the cancelled sources will have been executed.
    dispatch_async(queue, ^{
        for (int i = 0; i < [tunnelConnections count]; i++)
        {
            SshTunnelConnection* tunnelConnection = [tunnelConnections objectAtIndex:i];
            [tunnelConnection disconnect];
            
            dispatch_async(mainQueue, ^{ [self brutalDisconnectMessage:tunnelConnection]; });
        }
        [tunnelConnections removeAllObjects];
    });
    
    dispatch_async(queue, ^{ [self disconnect]; });
}


-(void)disconnect
{
    if (ssh_is_connected(session))
    {
        ssh_disconnect(session);
    }
    
    dispatch_async(mainQueue, ^{
        [dataDelegate newDataAvailableIn:(UInt8*)"\r\nLogged out\r\n" length:14];
    });
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
        reverseTunnels = [NSMutableArray new];
        tunnelConnections = [NSMutableArray new];
        
        if (session == NULL || forwardTunnels == nil || reverseTunnels == nil || tunnelConnections == nil)
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
    [forwardTunnels release];
    [reverseTunnels release];
    [tunnelConnections release];
    [super dealloc];
}


@end
