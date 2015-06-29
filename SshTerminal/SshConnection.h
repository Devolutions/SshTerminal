//
//  SshConnection.h
//  LibSshTest
//
//  Created by Denis Vincent on 2015-06-03.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import <Foundation/Foundation.h>
#define LIBSSH_LEGACY_0_4 1
#import "libssh/libssh.h"


#define INPUT_BUFFER_SIZE 1024
#define OUTPUT_BUFFER_SIZE 1024

enum ConnectionEvent
{
    FATAL_ERROR,
    CONNECTION_ERROR,
    SERVER_KEY_CHANGED,
    SERVER_KEY_FOUND_OTHER,
    SERVER_NOT_KNOWN,
    SERVER_FILE_NOT_FOUND,
    SERVER_ERROR,
    PASSWORD_AUTHENTICATION_DENIED,
    CHANNEL_ERROR,
    CHANNEL_RESIZE_ERROR,
    
    CONNECTED,
    DISCONNECTED,
};


@interface SshConnection : NSThread
{
    ssh_session session;
    ssh_channel channel;
    char* password;
    int width;
    int height;
    
    UInt8 inBuffer[INPUT_BUFFER_SIZE];
    UInt8 outBuffer[OUTPUT_BUFFER_SIZE];
    int inIndex;
    int outIndex;
    int changeHeight;
    
    NSLock* inLock;
    NSLock* outLock;
    
    NSObject* dataSink;
    SEL dataSelector;
    NSObject* eventSink;
    SEL eventSelector;
}

@property(readonly)ssh_session session;

-(void)setHost:(const char*)newHost;
-(void)setUser:(const char*)newUser;
-(void)setPassword:(const char*)newPassword;
-(void)setWidth:(int)newWidth;
-(void)setHeight:(int)newHeight;

-(void)main;

-(void)setDataCallbackOn:(NSObject*)newView with:(SEL)selector;
-(void)setEventCallbackOn:(NSObject*)newView with:(SEL)selector;

-(int)readIn:(UInt8*)buffer length:(int)count;
-(int)writeFrom:(const UInt8*)buffer length:(int)count;


@end
