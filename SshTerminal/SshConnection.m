//
//  SshConnection.m
//  LibSshTest
//
//  Created by Denis Vincent on 2015-06-03.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import "SshConnection.h"
#import "VT100TerminalView.h"
#import "SshAgent.h"
#import "PuttyKey.h"


int gInstanceCount = 0;


int PrivateKeyAuthCallback(const char *prompt, char *buf, size_t len, int echo, int verify, void *userdata)
{
    // This callback implementation avoids a password prompt for key files when the provided password is wrong.
    return SSH_ERROR;
}


void logCallback(int priority, const char *function, const char *buffer, void *userdata)
{
    SshConnection *connection = (__bridge SshConnection *)(userdata);
    NSMutableString * message = [NSMutableString stringWithUTF8String:buffer];
    [message appendString:@"\r\n"];
    [connection verboseNotify:message];
}


ssh_channel authAgentCallback(ssh_session session, void* userdata)
{
    SshConnection *connection = (__bridge SshConnection *)(userdata);
    return connection.agentChannel;
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
	int portParameter = newPort; //ssh_options_set utilize a int for the port number. We need the send the config with an int otherwise it sometimes doesn't work Benoit S. 2015-12-14
    ssh_options_set(session, SSH_OPTIONS_PORT, &portParameter);
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

-(void)setVerbose:(BOOL)newVerbose withLevel:(int)level
{
    verbose = newVerbose;
	if (verbose)
    {
		verbosityLevel = level;
    }
}


-(void)setAgentForwarding:(BOOL)newAgentForwarding
{
    agentForwarding = newAgentForwarding;
}


-(void)setUseAgent:(BOOL)newUseAgent
{
    useAgent = newUseAgent;
}


-(void)setWidth:(int)newWidth height:(int)newHeight
{
    if (channel != NULL)
    {
        dispatch_async(queue, ^{
            ssh_channel_change_pty_size(channel, newWidth, newHeight);
            width = newWidth;
            height = newHeight;
        });
    }
    else
    {
        width = newWidth;
        height = newHeight;
    }
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
            }
            NSString* displayNumberString = [x11DisplayName substringWithRange:displayNumberRange];
            x11DisplayNumber = [displayNumberString intValue];
            
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

-(void)setLoggingCallback
{
	if(!verbose)
		return;
	
	ssh_set_log_level(verbosityLevel);
	ssh_set_log_callback(&logCallback);
	ssh_set_log_userdata(self);
}


-(int)writeFrom:(const UInt8 *)buffer length:(int)count
{
    UInt8* writeBuffer = malloc(count);
    memcpy(writeBuffer, buffer, count);
    dispatch_async(queue, ^{
		[self setLoggingCallback];
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

-(ssh_channel)agentChannel
{
    if (agentChannel == NULL)
    {
        agentChannel = ssh_channel_new(session);
        agentBuffer = [NSMutableData new];
        if (agentBuffer == nil || agentChannel == NULL)
        {
            if (verbose == YES)
            {
                [self verboseNotify:@"Out of memory"];
            }
            [self eventNotify:OUT_OF_MEMORY_ERROR];
            dispatch_async(queue, ^{ [self closeAllChannels]; });
            return NULL;
        }
    }
    
    return agentChannel;
}


-(void)eventNotify:(int)code
{
    dispatch_async(mainQueue, ^{ [eventDelegate signalError:code]; });
}


-(void)verboseNotify:(NSString*)verboseString
{
    dispatch_async(screenQueue, ^{
        [verboseString retain];
        const char* stringBuffer = [verboseString UTF8String];
        [dataDelegate newDataAvailableIn:(UInt8*)stringBuffer length:(int)strlen(stringBuffer)];
        [verboseString release];
    });
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
	[self setLoggingCallback];
	
    if (verbose == YES)
    {
        [self verboseNotify:@"Initiating connection\r\n"];
		
    }
    NetworkAddress addresses[2];
    int addressCount = resolveHost(addresses, [host UTF8String]);
    if (addressCount == 0)
    {
        if (verbose == YES)
        {
            [self verboseNotify:@"Host not found\r\n"];
        }
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
    if (verbose == YES)
    {
		uint port;
		ssh_options_get_port(session, &port);
        NSString* message = [NSString stringWithFormat:@"Connecting to %s : %u\r\n", addressString, port];
        [self verboseNotify:message];
    }
    ssh_options_set(session, SSH_OPTIONS_HOST, addressString);
    int result;
    while (1)
    {
        result = ssh_connect(session);
        if (result != SSH_AGAIN)
        {
            break;
        }
        [NSThread sleepForTimeInterval:0.050];
    }
    if (result != SSH_OK)
    {
        if (verbose == YES)
        {
            const char* errorString = ssh_get_error(session);
            NSString* message = [NSString stringWithFormat:@"Ssh connection failed: %s\r\n", errorString];
            [self verboseNotify:message];
        }
        [self eventNotify:CONNECTION_ERROR];
        dispatch_async(queue, ^{ [self disconnect]; });
        return;
    }
    
    dispatch_async(queue, ^{ [self authenticateServer]; });
}


-(void)authenticateServer
{
	[self setLoggingCallback];
    if (verbose == YES)
    {
        [self verboseNotify:@"Authenticating server\r\n"];
    }
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
            if (verbose == YES)
            {
                [self verboseNotify:@"Server key has changed\r\n"];
            }
            [self eventNotify:SERVER_KEY_CHANGED];
            break;
            
        case SSH_SERVER_FOUND_OTHER:
            if (verbose == YES)
            {
                [self verboseNotify:@"Server key has unexpected type\r\n"];
            }
            [self eventNotify:SERVER_KEY_FOUND_OTHER];
            break;
            
        case SSH_SERVER_NOT_KNOWN:
            if (verbose == YES)
            {
                [self verboseNotify:@"Server is unknown\r\n"];
            }
            [self eventNotify:SERVER_NOT_KNOWN];
            break;
        
        // Fatal errors.
        case SSH_SERVER_FILE_NOT_FOUND:
            if (verbose == YES)
            {
                [self verboseNotify:@"Server is unknown, knownhost file does not exist\r\n"];
            }
            [self eventNotify:SERVER_FILE_NOT_FOUND];
            break;
            
        case SSH_SERVER_ERROR:
        default:
            if (verbose == YES)
            {
                const char* errorString = ssh_get_error(session);
                NSString* message = [NSString stringWithFormat:@"Unexpected error: %s\r\n", errorString];
                [self verboseNotify:message];
            }
            [self eventNotify:SERVER_ERROR];
            break;
    }
}


-(void)authenticateUser
{
	[self setLoggingCallback];
    if (verbose == YES)
    {
        [self verboseNotify:@"Authenticating user\r\n"];
    }
    if (useAgent == YES)
    {
        // User authentication by agent:
        if (verbose == YES)
        {
            [self verboseNotify:@"Authentication by agent\r\n"];
        }
        
        int result;
        while (1)
        {
            result = ssh_userauth_agent(session, NULL);
            if (result != SSH_AUTH_AGAIN)
            {
                break;
            }
        }
        
        if (result != SSH_AUTH_SUCCESS)
        {
            if (result == SSH_AUTH_ERROR)
            {
                if (verbose == YES)
                {
                    const char* errorString = ssh_get_error(session);
                    NSString* message = [NSString stringWithFormat:@"Unexpected error: %s\r\n", errorString];
                    [self verboseNotify:message];
                }
                [self eventNotify:FATAL_ERROR];
            }
            else
            {
                if (verbose == YES)
                {
                    [self verboseNotify:@"Server refused the key\r\n"];
                }
                [self eventNotify:PASSWORD_AUTHENTICATION_DENIED];
            }
            dispatch_async(queue, ^{ [self disconnect]; });
            return;
        }
    }
    else if (useKeyAuthentication == YES)
    {
        // User authentication by key:
        if (verbose == YES)
        {
            [self verboseNotify:@"Authentication by key\r\n"];
        }

        const char* path = [keyFilePath UTF8String];
        int keyType = PuttyKeyDetectType(path);
        if (keyType < 0)
        {
            int code = FATAL_ERROR;
            if (keyType == KEY_TYPE_FILE_NOT_FOUND)
            {
                if (verbose == YES)
                {
                    [self verboseNotify:@"Key file not found\r\n"];
                }
                code = KEY_FILE_NOT_FOUND_OR_DENIED;
            }
            else if (keyType == KEY_TYPE_ACCESS_DENIED)
            {
                if (verbose == YES)
                {
                    [self verboseNotify:@"Key file acces denied\r\n"];
                }
                code = KEY_FILE_NOT_FOUND_OR_DENIED;
            }
            else if (keyType == KEY_TYPE_UNKNOWN)
            {
                if (verbose == YES)
                {
                    [self verboseNotify:@"Key file format unknown\r\n"];
                }
            }
            else
            {
                if (verbose == YES)
                {
                    [self verboseNotify:@"Fatal error opening key file\r\n"];
                }
            }
            [self eventNotify:code];
            dispatch_async(queue, ^{ [self closeAllChannels]; });
            return;
        }
        const char* kfpassword = [keyFilePassword UTF8String];
        
        ssh_key key = NULL;
        if (keyType == KEY_TYPE_OPEN_SSH)
        {
            int result = ssh_pki_import_privkey_file(path, kfpassword, PrivateKeyAuthCallback, NULL, &key);
            if (result == SSH_EOF)
            {
                if (verbose == YES)
                {
                    [self verboseNotify:@"Wrong password for key file\r\n"];
                }
                [self eventNotify:KEY_FILE_NOT_FOUND_OR_DENIED];
                key = NULL;
            }
            else if (result != SSH_OK)
            {
                if (verbose == YES)
                {
                    const char* errorString = ssh_get_error(session);
                    NSString* message = [NSString stringWithFormat:@"Unexpected error loading the key file: %s\r\n", errorString];
                    [self verboseNotify:message];
                }
                [self eventNotify:FATAL_ERROR];
                key = NULL;
            }
        }
        else
        {
            int result = PuttyKeyLoadPrivate(path, kfpassword, &key);
            if (result < 0)
            {
                if (result == FAIL_OUT_OF_MEMORY)
                {
                    if (verbose == YES)
                    {
                        [self verboseNotify:@"Out of memory\r\n"];
                    }
                    [self eventNotify:OUT_OF_MEMORY_ERROR];
                }
                else if (result == FAIL_WRONG_PASSWORD)
                {
                    if (verbose == YES)
                    {
                        NSString* message = [NSString stringWithFormat:@"Invalid password for key file: %s\r\n", path];
                        [self verboseNotify:message];
                    }
                    [self eventNotify:PASSWORD_AUTHENTICATION_DENIED];
                }
                else
                {
                    if (verbose == YES)
                    {
                        [self verboseNotify:@"Unexpected error, file may be corrupted\r\n"];
                    }
                    [self eventNotify:FATAL_ERROR];
                }
            }
        }
        
        if (key == NULL)
        {
            dispatch_async(queue, ^{ [self closeAllChannels]; });
            return;
        }
        
        if (verbose == YES)
        {
            [self verboseNotify:@"Key file successfully loaded, sending to server\r\n"];
        }
        int result;
        while (1)
        {
            result = ssh_userauth_publickey(session, NULL, key);
            if (result != SSH_AUTH_AGAIN)
            {
                break;
            }
        }
        
        if (agentForwarding == YES && result == SSH_AUTH_SUCCESS)
        {
            sshAgent = SshAgentNew();
            if (sshAgent == NULL)
            {
                if (verbose == YES)
                {
                    [self verboseNotify:@"Not enough memory\r\n"];
                }
                [self eventNotify:OUT_OF_MEMORY_ERROR];
                dispatch_async(queue, ^{ [self closeAllChannels]; });
                return;
            }
            
            int result = SshAgentAddKey(sshAgent, key);
            if (result < 0)
            {
                ssh_key_free(key);
                if (verbose == YES)
                {
                    [self verboseNotify:@"Not enough memory\r\n"];
                }
                [self eventNotify:OUT_OF_MEMORY_ERROR];
                dispatch_async(queue, ^{ [self closeAllChannels]; });
                return;
            }
        }
        else
        {
            ssh_key_free(key);
        }
        
        if (result != SSH_AUTH_SUCCESS)
        {
            if (result == SSH_AUTH_ERROR)
            {
                if (verbose == YES)
                {
                    const char* errorString = ssh_get_error(session);
                    NSString* message = [NSString stringWithFormat:@"Unexpected error: %s\r\n", errorString];
                    [self verboseNotify:message];
                }
                [self eventNotify:FATAL_ERROR];
            }
            else
            {
                if (verbose == YES)
                {
                    [self verboseNotify:@"Server refused the key\r\n"];
                }
                [self eventNotify:PASSWORD_AUTHENTICATION_DENIED];
            }
            dispatch_async(queue, ^{ [self disconnect]; });
            return;
        }
    }
    else
    {
        // User authentication by password:
        if (verbose == YES)
        {
            [self verboseNotify:@"Authentication by password\r\n"];
        }
        int result;
        do
        {
            result = ssh_userauth_password(session, NULL, [password UTF8String]);
            if (result == SSH_AUTH_AGAIN)
            {
                [NSThread sleepForTimeInterval:0.1];
            }
        } while (result == SSH_AUTH_AGAIN);
        
        if (result != SSH_AUTH_SUCCESS)
        {
            if (verbose == YES)
            {
                [self verboseNotify:@"Using alternative method\r\n"];
            }
            result = ssh_userauth_kbdint(session, NULL, NULL);
            if (result == SSH_AUTH_INFO)
            {
                int promptCount = ssh_userauth_kbdint_getnprompts(session);
                if (promptCount >= 1)
                {
                    ssh_userauth_kbdint_setanswer(session, 0, [password UTF8String]);
                    result = ssh_userauth_kbdint(session, NULL, NULL);
                    if (result == SSH_AUTH_INFO)
                    {
                        ssh_userauth_kbdint_getnprompts(session);
                        result = ssh_userauth_kbdint(session, NULL, NULL);
                    }
                }
            }
        }
        
        if (result != SSH_AUTH_SUCCESS)
        {
            if (result == SSH_AUTH_ERROR)
            {
                if (verbose == YES)
                {
                    const char* errorString = ssh_get_error(session);
                    NSString* message = [NSString stringWithFormat:@"Unexpected error: %s\r\n", errorString];
                    [self verboseNotify:message];
                }
                [self eventNotify:FATAL_ERROR];
            }
            else
            {
                if (verbose == YES)
                {
                    [self verboseNotify:@"Server has refused password\r\n"];
                }
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
	[self setLoggingCallback];
    if (verbose == YES)
    {
        [self verboseNotify:@"Opening terminal\r\n"];
    }
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
        if (verbose == YES)
        {
            const char* errorString = ssh_get_error(session);
            NSString* message = [NSString stringWithFormat:@"Unable to open channel: %s\r\n", errorString];
            [self verboseNotify:message];
        }
        [self eventNotify:OUT_OF_MEMORY_ERROR];
        dispatch_async(queue, ^{ [self disconnect]; });
        return;
    }
    
    int result = ssh_channel_open_session(channel);
    if (result != SSH_OK)
    {
        if (verbose == YES)
        {
            const char* errorString = ssh_get_error(session);
            NSString* message = [NSString stringWithFormat:@"Unable to open session: %s\r\n", errorString];
            [self verboseNotify:message];
        }
        [self eventNotify:CHANNEL_ERROR];
        dispatch_async(queue, ^{ [self closeAllChannels]; });
        return;
    }
    
    result = ssh_channel_request_pty(channel);
    if (result != SSH_OK)
    {
        if (verbose == YES)
        {
            const char* errorString = ssh_get_error(session);
            NSString* message = [NSString stringWithFormat:@"Unable to open pty: %s\r\n", errorString];
            [self verboseNotify:message];
        }
        [self eventNotify:CHANNEL_ERROR];
        dispatch_async(queue, ^{ [self closeAllChannels]; });
        return;
    }
    if (x11Forwarding == YES)
    {
        if (verbose == YES)
        {
            [self verboseNotify:@"Opening X channel\r\n"];
        }
        const char* protocol = NULL;
        const char* cookie = NULL;

        result = ssh_channel_request_x11(channel, 0, protocol, cookie, x11ScreenNumber);
        if (result != SSH_OK)
        {
            if (verbose == YES)
            {
                const char* errorString = ssh_get_error(session);
                NSString* message = [NSString stringWithFormat:@"Unable to open X channel: %s\r\n", errorString];
                [self verboseNotify:message];
            }
            [self eventNotify:X11_ERROR];
        }
    }
    if (agentForwarding == YES)
    {
        if (verbose == YES)
        {
            [self verboseNotify:@"Opening agent forwarding channel\r\n"];
        }
        
        result = ssh_channel_request_auth_agent(channel);
        if (result != SSH_OK)
        {
            if (verbose == YES)
            {
                const char* errorString = ssh_get_error(session);
                NSString* message = [NSString stringWithFormat:@"Unable to open agent forwarding channel: %s\r\n", errorString];
                [self verboseNotify:message];
            }
            [self eventNotify:CHANNEL_ERROR];
            dispatch_async(queue, ^{ [self closeAllChannels]; });
            return;
        }
    }
    
    result = ssh_channel_request_shell(channel);
    if (result != SSH_OK)
    {
        if (verbose == YES)
        {
            const char* errorString = ssh_get_error(session);
            NSString* message = [NSString stringWithFormat:@"Unable to open shell: %s\r\n", errorString];
            [self verboseNotify:message];
        }
        [self eventNotify:CHANNEL_ERROR];
        dispatch_async(queue, ^{ [self closeAllChannels]; });
        return;
    }
    result = ssh_channel_change_pty_size(channel, width, height);
    if (result != SSH_OK)
    {
        if (verbose == YES)
        {
            const char* errorString = ssh_get_error(session);
            NSString* message = [NSString stringWithFormat:@"Setting pty size failed: %s\r\n", errorString];
            [self verboseNotify:message];
        }
        [self eventNotify:CHANNEL_ERROR];
        dispatch_async(queue, ^{ [self closeAllChannels]; });
        return;
    }
    
    
    [self eventNotify:CONNECTED];
    dispatch_resume(readSource);
}


-(void)newTerminalDataAvailable
{
	[self setLoggingCallback];
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
        dispatch_async(screenQueue, ^{
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
    if (agentForwarding == YES)
    {
        if (agentChannel != NULL && ssh_channel_is_open(agentChannel))
        {
            int length = (int)agentBuffer.length;
            if (length == 0)
            {
                int availableCount = ssh_channel_poll(agentChannel, 0);
                if (availableCount != 0)
                {
                    dataHasBeenRead = YES;
                }
                if (availableCount >= 4)
                {
                    UInt32 messageHeader;
                    ssh_channel_read_nonblocking(agentChannel, &messageHeader, 4, 0);
                    length = ntohl(messageHeader);
                    agentBuffer.length = length;
                }
            }
            if (length != 0)
            {
                int availableCount = ssh_channel_poll(agentChannel, 0);
                if (availableCount != 0)
                {
                    dataHasBeenRead = YES;
                }
                if (availableCount >= length)
                {
                    dataHasBeenRead = YES;
                    uint8_t* buffer = agentBuffer.mutableBytes;
                    ssh_channel_read_nonblocking(agentChannel, buffer, length, 0);
                    uint8_t* reply = SshAgentReplyFromRequest(sshAgent, buffer, length);
                    if (reply == NULL)
                    {
                        [self eventNotify:OUT_OF_MEMORY_ERROR];
                        dispatch_async(queue, ^{ [self closeAllChannels]; });
                        return;
                    }
                    uint32_t messageSize;
                    memcpy(&messageSize, reply, 4);
                    messageSize = 4 + ntohl(messageSize);
                    ssh_channel_write(agentChannel, reply, messageSize);
                    free(reply);
                    agentBuffer.length = 0;
                }
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
    
    dispatch_async(screenQueue, ^{
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
	[self setLoggingCallback];
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
            
            dispatch_async(screenQueue, ^{ [self disconnectionMessage:tunnelConnection]; });
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
                    
                    dispatch_async(screenQueue, ^{ [self remoteConnectionMessage:tunnelConnection]; });
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

    dispatch_async(screenQueue, ^{ [self localConnectionMessage:tunnelConnection]; });
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
	[self setLoggingCallback];
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
            
            dispatch_async(screenQueue, ^{ [self brutalDisconnectMessage:tunnelConnection]; });
        }
        [tunnelConnections removeAllObjects];
    });
    
    dispatch_async(queue, ^{ [self disconnect]; });
}


-(void)disconnect
{
	[self setLoggingCallback];
    if (ssh_is_connected(session))
    {
        ssh_disconnect(session);
    }
    
    dispatch_async(screenQueue, ^{
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
        ssh_callbacks_init(&callbacks);
        callbacks.userdata = self;
        callbacks.channel_open_request_auth_agent_function = authAgentCallback;
        ssh_set_callbacks(session, &callbacks);

        queue = dispatch_queue_create("com.Devolutions.SshConnectionQueue", DISPATCH_QUEUE_SERIAL);
        screenQueue = dispatch_queue_create("com.Devolutions.VT100ParsingQueue", DISPATCH_QUEUE_SERIAL);
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
    dispatch_release(queue);
    dispatch_release(screenQueue);
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
