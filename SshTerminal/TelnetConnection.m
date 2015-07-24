//
//  TelnetConnection.m
//  SshTerminal
//
//  Created by Denis Vincent on 2015-07-22.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import "TelnetConnection.h"

// Commands
#define IAC 255   // Interpret As Command.
#define DONT 254
#define DO 253
#define WONT 252
#define WILL 251
#define SB 250   // Sub option Begin.
#define SE 240   // Sub option End.

#define GA 249   // Go Ahead.
#define EL 248   // Erase Line.
#define EC 247   // Erase Character.
#define AYT 246   // Are You There.
#define AO 245   // Abort Output.
#define IP 244   // Interrupt Process.
#define BREAK 243
#define DM 242   // Data Mark.
#define NOP 241
#define EOR 239   // End Of Record.
#define ABORT 238
#define SUSP 237   // Suspend.
#define telnetEOF 236

// Options.
#define optionBinaryTransmission 0x00
#define optionEcho 0x01
#define optionSuppressGoAhead 0x03
#define optionAuthenticate 0x25
#define optionNewEnvironment 0x27
#define optionNegotiateAboutWindowSize 0x1f

#define optionOff 0x00
#define optionOn 0x01
#define optionWillRequest 0x10
#define optionWontRequest 0x11
#define optionDoRequest 0x20
#define optionDontRequest 0x21
typedef struct
{
    UInt8 value;
    UInt8 remoteValue;
} TelnetOption;


#define INPUT_BUFFER_SIZE 1024
#define OUTPUT_BUFFER_SIZE 1024


@interface TelnetConnection ()
{
    NSString* host;
    NSString* user;
    NSString* password;
    UInt16 port;
    int width;
    int height;
    int fd;
    
    UInt8 inBuffer[INPUT_BUFFER_SIZE];
    UInt8 outBuffer[OUTPUT_BUFFER_SIZE];
    int inIndex;
    int outIndex;
    
    dispatch_queue_t queue;
    dispatch_queue_t mainQueue;
    dispatch_source_t readSource;
    
    TelnetOption options[256];
    
    id<VT100TerminalDataDelegate> dataDelegate;
    id<TelnetConnectionEventDelegate> eventDelegate;
}

// Methods called from the private queue thread.
-(void)connect;
-(void)interpretRequest:(UInt8)request forOption:(UInt8)option;
-(int)interpretCommand:(int)i;
-(void)newTerminalDataAvailable;
-(void)closeAllChannels;
-(void)disconnect;

@end


@implementation TelnetConnection

-(void)setDataDelegate:(id<VT100TerminalDataDelegate>)newDataDelegate
{
    dataDelegate = newDataDelegate;
}


-(void)setEventDelegate:(id<TelnetConnectionEventDelegate>)newEventDelegate
{
    eventDelegate = newEventDelegate;
}


-(void)setHost:(NSString*)hostString
{
    host = hostString;
}


-(void)setPort:(SInt16)newPort
{
    port = newPort;
}


-(void)setUser:(NSString*)userString
{
    user = userString;
}


-(void)setPassword:(NSString*)passwordString
{
    password = passwordString;
}


-(void)setWidth:(int)newWidth
{
    width = newWidth;
}


-(int)writeFrom:(const UInt8 *)buffer length:(int)count
{
    UInt8* writeBuffer = malloc(count);
    memcpy(writeBuffer, buffer, count);
    dispatch_async(queue, ^{
        int result = (int)send(fd, writeBuffer, count, 0);
        assert(result == count);
        free(writeBuffer);
    });
    return count;
}


-(void)startConnection
{
    dispatch_async(queue, ^{ [self connect]; });
}


-(void)endConnection
{
    dispatch_async(queue, ^{ [self closeAllChannels]; });
}


// The following methods are executed on the private queue.

-(void)eventNotify:(int)code
{
    dispatch_async(mainQueue, ^{ [eventDelegate signalError:code]; });
}


-(void)connect
{
    NetworkAddress address;
    int addressSize = resolveHost(&address, [host UTF8String]);
    if (addressSize <= 0)
    {
        // Unable to resolve host.
        dispatch_async(queue, ^{ [self disconnect]; });
        return;
    }
    
    fd = socket(address.family, SOCK_STREAM, IPPROTO_TCP);
    if (fd < 0)
    {
        dispatch_async(queue, ^{ [self disconnect]; });
        return;
    }
    
    NetworkAddress bindAddress;
    memset(&bindAddress, 0, sizeof(NetworkAddress));
    bindAddress.len = address.len;
    bindAddress.family = address.family;
    int result = bind(fd, &bindAddress.ip, bindAddress.len);
    if (result != 0 )
    {
        dispatch_async(queue, ^{ [self disconnect]; });
        return;
    }
    
    address.port = htons(port);
    result = connect(fd, &address.ip, address.len);
    if (result != 0)
    {
        dispatch_async(queue, ^{ [self disconnect]; });
        return;
    }
    
    readSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, fd, 0, queue);
    if (readSource == nil)
    {
        dispatch_async(queue, ^{ [self disconnect]; });
        return;
    }
    dispatch_source_set_event_handler(readSource, ^{ [self newTerminalDataAvailable]; });
    dispatch_resume(readSource);
}


-(void)writeOption:(UInt8)option withRequest:(UInt8)request
{
    UInt8 buffer[3];
    buffer[0] = IAC;
    buffer[1] = request;
    buffer[2] = option;
    int result = (int)send(fd, buffer, 3, 0);
    assert(result == 3);
}


-(void)writeWindowSizeAndAck:(BOOL)writeAck
{
    UInt8 buffer[12];
    int i = 0;
    
    if (writeAck == YES)
    {
        buffer[i++] = IAC;
        buffer[i++] = WILL;
        buffer[i++] = optionNegotiateAboutWindowSize;
    }
    
    buffer[i++] = IAC;
    buffer[i++] = SB;
    buffer[i++] = optionNegotiateAboutWindowSize;
    buffer[i++] = HI_BYTE(width);
    buffer[i++] = LO_BYTE(width);
    buffer[i++] = 0;
    buffer[i++] = 24;
    buffer[i++] = IAC;
    buffer[i++] = SE;
    
    int result = (int)send(fd, buffer, i, 0);
    assert(result == i);
}


-(void)interpretRequest:(UInt8)request forOption:(UInt8)option
{
    printf("interpretRequest:%d forOption:%d\r\n", request, option);
    TelnetOption* telnetOption = options + option;
    switch (option)
    {
        case optionNegotiateAboutWindowSize:
        {
            if (request == DO)
            {
                if (telnetOption->value == optionWillRequest)
                {
                    // The server aggrees using window size negotiation:
                    telnetOption->value = optionOn;
                    [self writeWindowSizeAndAck:NO];
                }
                else
                {
                    // The server suggests using window size negotiation:
                    telnetOption->value = optionOn;
                    [self writeWindowSizeAndAck:YES];
                }
            }
            else
            {
                // The server either refuses using window size negociation (DONT), or sends unexpected requests (WILL, WONT) for this option:
                telnetOption->value = optionOff;
            }
            break;
        }
            
        /*case optionAuthenticate:
        {
            if (request == DO)
            {
                [self writeOption:optionAuthenticate withRequest:WILL];
            }
            break;
        }*/
            
        case optionBinaryTransmission:
        case optionEcho:
        case optionSuppressGoAhead:
        {
            // Standard options:
            if (request == DO)
            {
                if (telnetOption->value == optionOff)
                {
                    // The server is requesting this client to turn on an option: turn it on and acknowledge.
                    telnetOption->value = optionOn;
                    [self writeOption:option withRequest:WILL];
                }
                else if ( telnetOption->value == optionWillRequest)
                {
                    // The server is acknowledging that this client can turn on an option:
                    telnetOption->value = optionOn;
                }
                else if (telnetOption->value == optionWontRequest)
                {
                    // This case should not happen (turning off an option should never be refused).
                    telnetOption->value = optionOff;
                }
            }
            else if (request == DONT)
            {
                if (telnetOption->value == optionOn)
                {
                    // The server is requesting this client to turn off an option: turn it off and acknowledge.
                    telnetOption->value = optionOff;
                    [self writeOption:option withRequest:WONT];
                }
                else if ( telnetOption->value == optionWillRequest)
                {
                    // The server is refusing that this client can turn on an option:
                    telnetOption->value = optionOff;
                }
                else if (telnetOption->value == optionWontRequest)
                {
                    // The server is acknowledging that this client can turn off an option:
                    telnetOption->value = optionOff;
                }
            }
            else if (request == WILL)
            {
                if (telnetOption->remoteValue == optionOff)
                {
                    // The server is requesting to turn on an option on his side: mark it turned on and acknowledge.
                    telnetOption->remoteValue = optionOn;
                    [self writeOption:option withRequest:DO];
                }
                else if ( telnetOption->remoteValue == optionDoRequest)
                {
                    // The server is acknowledging that it is tunring on an option:
                    telnetOption->remoteValue = optionOn;
                }
                else if (telnetOption->remoteValue == optionDontRequest)
                {
                    // This case should not happen (turning off an option should never be refused).
                    telnetOption->remoteValue = optionOn;
                }
            }
            else if (request == WONT)
            {
                if (telnetOption->remoteValue == optionOn)
                {
                    // The server is requesting to turn off an option on his side: mark it turned off and acknowledge.
                    telnetOption->remoteValue = optionOff;
                    [self writeOption:option withRequest:DONT];
                }
                else if ( telnetOption->remoteValue == optionDoRequest)
                {
                    // The server is acknowledging that it is tunring on an option:
                    telnetOption->remoteValue = optionOn;
                }
                else if (telnetOption->remoteValue == optionDontRequest)
                {
                    // The server is acknowledging that it is tunring off an option:
                    telnetOption->remoteValue = optionOff;
                }
            }
            break;
        }
            
        default:
        {
            if (request == DO)
            {
                [self writeOption:option withRequest:WONT];
            }
            else if (request == WILL)
            {
                [self writeOption:option withRequest:DONT];
            }
            break;
        }
    }
}


-(int)interpretCommand:(int)i
{
    if (i + 1 >= inIndex)
    {
        // Not enough data to interpret a command:
        return 0;
    }
    
    switch (inBuffer[i + 1])
    {
        case SB:
        {
            // Sub option begin:
            printf("SB\r\n");
            break;
        }
            
        case WILL:
        case WONT:
        case DO:
        case DONT:
        {
            if (i + 2 >= inIndex)
            {
                // Not enough data to interpret an option request:
                return 0;
            }
            [self interpretRequest:inBuffer[i + 1] forOption:inBuffer[i + 2]];
            return 3;
        }
    }
    
    return 2;
}


-(void)newTerminalDataAvailable
{
    printf("newTerminalDataAvailable\r\n");
    int result = (int)recv(fd, inBuffer + inIndex, INPUT_BUFFER_SIZE - inIndex, 0);
    if (result <= 0)
    {
        dispatch_async(queue, ^{ [self disconnect]; });
        return;
    }
    
    inIndex += result;
    
    int i = 0;
    int terminalIndex = 0;
    UInt8* terminalBuffer = malloc(inIndex);
    if (terminalBuffer == NULL)
    {
        // Out of memeory:
        dispatch_async(queue, ^{ [self disconnect]; });
        return;
    }
    while (i < inIndex)
    {
        if (inBuffer[i] == IAC)
        {
            // Possible command beginning:
            if (i + 1 >= inIndex)
            {
                // Not enough data to resolve this case:
                break;
            }
            if (inBuffer[i + 1] == IAC)
            {
                // This is a data byte:
                terminalBuffer[terminalIndex] = IAC;
                terminalIndex++;
                i += 2;
            }
            else
            {
                // This is really a command:
                int commandLen = [self interpretCommand:i];
                if (commandLen == 0)
                {
                    // The command is not complete:
                    break;
                }
                i += commandLen;
            }
        }
        else
        {
            terminalBuffer[terminalIndex] = inBuffer[i];
            terminalIndex++;
            i++;
        }
    }

    if (terminalIndex > 0)
    {
        dispatch_async(mainQueue, ^{
            [dataDelegate newDataAvailableIn:terminalBuffer length:terminalIndex];
            free(terminalBuffer);
        });
    }
    else
    {
        free(terminalBuffer);
    }
    
    if (i < inIndex)
    {
        memmove(inBuffer, inBuffer + i, inIndex - i);
    }
    inIndex -= i;
}


-(void)openTunnelChannels
{

}


-(void)newSshDataAvailable
{

}


-(void)closeAllChannels
{

}


-(void)disconnect
{
    if (readSource != NULL)
    {
        dispatch_source_cancel(readSource);
        readSource = NULL;
    }
    if (fd >= 0)
    {
        close(fd);
        fd = -1;
    }
    
    dispatch_async(mainQueue, ^{
        [dataDelegate newDataAvailableIn:(UInt8*)"\r\nLogged out\r\n" length:14];
    });
    [self eventNotify:tceDisconnected];
}


-(instancetype)init
{
    self = [super init];
    if (self != nil)
    {
        fd = -1;
        queue = dispatch_queue_create("com.Devolutions.SshConnectionQueue", DISPATCH_QUEUE_SERIAL);
        mainQueue = dispatch_get_main_queue();
    }
    
    return self;
}


-(void)dealloc
{

}


@end
