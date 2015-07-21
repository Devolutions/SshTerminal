//
//  SshFoundation.h
//  SshTerminal
//
//  Created by Denis Vincent on 2015-07-15.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#ifndef SshTerminal_SshFoundation_h
#define SshTerminal_SshFoundation_h

#define LIBSSH_LEGACY_0_4 1
#include "libssh/libssh.h"

typedef struct
{
    union
    {
        struct
        {
            UInt8 len;
            UInt8 family;
            UInt16 port;
        };
        struct sockaddr ip;
        struct sockaddr_in ipv4;
        struct sockaddr_in6 ipv6;
    };
} NetworkAddress;


#endif
