//
//  NsTunnelConnection.m
//  SshTerminal
//
//  Created by Denis Vincent on 2015-07-15.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import "SshTunnelConnection.h"

@implementation SshTunnelConnection

+(instancetype)connectionWithSocket:(int)newFd onChannel:(ssh_channel)newChannel onQueue:(dispatch_queue_t)queue
{
    if (newFd < 0 || newChannel == NULL)
    {
        return nil;
    }

    SshTunnelConnection* tunnelConnection = [SshTunnelConnection new];
    if (tunnelConnection != nil)
    {
        tunnelConnection->fd = newFd;
        tunnelConnection->channel = newChannel;
        
        tunnelConnection->readSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, tunnelConnection->fd, 0, queue);
        if (tunnelConnection->readSource == nil)
        {
            return nil;
        }
        dispatch_source_set_event_handler(tunnelConnection->readSource, ^(void){ [tunnelConnection newLocalDataAvailable]; });
        dispatch_resume(tunnelConnection->readSource);
    }
    
    return tunnelConnection;
}


-(void)releaseResources
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
    if (channel != NULL)
    {
        ssh_channel_free(channel);
        channel = NULL;
    }
}


-(void)newLocalDataAvailable
{
    if (fd < 0 || channel == NULL)
    {
        return;
    }
    
    int readCount = (int)recv(fd, buffer, 1500, 0);
    if (readCount <= 0)
    {
        // The socket side connection ended (this method is called by a dispatch source, so it must have data to read, otherwise...):
        [self releaseResources];
        return;
    }
    int result = ssh_channel_write(channel, buffer, readCount);   // This call is blocking.
    if (result < 0)
    {
        [self releaseResources];
    }
}


-(BOOL)transferRemoteDataToLocal
{
    if (channel == NULL || fd < 0)
    {
        return NO;
    }
    int availableCount = ssh_channel_poll(channel, 0);
    if (availableCount > 0)
    {
        UInt8* tempBuffer = malloc(availableCount);
        int result = ssh_channel_read_nonblocking(channel, tempBuffer, availableCount, 0);
        if (result < 0)
        {
            [self releaseResources];
            return NO;
        }
        int flags = fcntl(fd, F_GETFL, 0);
        fcntl(fd, F_SETFL, flags & ~O_NONBLOCK);
        result = (int)send(fd, tempBuffer, availableCount, 0);   // This call is blocking.
        if (result < 0)
        {
            [self releaseResources];
            return NO;
        }
        fcntl(fd, F_SETFL, flags | O_NONBLOCK);
        free(tempBuffer);
    }
    else
    {
        if (ssh_channel_is_eof(channel))
        {
            [self releaseResources];
        }
        return NO;
    }
    
    return YES;
}


-(BOOL)isAlive
{
    if (fd < 0 || channel == NULL)
    {
        return NO;
    }
    
    return YES;
}


-(void)disconnect
{
    [self releaseResources];
}


-(instancetype)init
{
    self = [super init];
    if (self != nil)
    {
        fd = -1;
    }
    
    return self;
}


-(void)dealloc
{
    [self releaseResources];
}


@end


