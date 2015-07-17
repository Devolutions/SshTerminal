//
//  NsTunnelConnection.h
//  SshTerminal
//
//  Created by Denis Vincent on 2015-07-15.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SshFoundation.h"

#define FORWARD_BUFFER_SIZE 2800

@interface SshTunnelConnection : NSObject
{
    int fd;
    ssh_channel channel;
    dispatch_source_t readSource;
    UInt8 buffer[FORWARD_BUFFER_SIZE];
}

+(instancetype)connectionWithSocket:(int)newFd onChannel:(ssh_channel)newChannel onQueue:(dispatch_queue_t)queue;

-(void)newLocalDataAvailable;
-(BOOL)transferRemoteDataToLocal;
-(BOOL)isAlive;
-(void)disconnect;


@end


