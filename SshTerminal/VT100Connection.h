//
//  VT100Connection.h
//  SshTerminal
//
//  Created by Denis Vincent on 2015-07-22.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol VT100TerminalDataDelegate <NSObject>

-(void)newDataAvailableIn:(UInt8*)buffer length:(int)size;

@end


@protocol VT100Connection <NSObject>

-(void)setDataDelegate:(id<VT100TerminalDataDelegate>)newDataDelegate;
-(void)setWidth:(int)newWidth;
-(int)writeFrom:(const UInt8*)buffer length:(int)count;

@end
