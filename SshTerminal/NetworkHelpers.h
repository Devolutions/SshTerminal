//
//  NetworkHelpers.h
//  SshTerminal
//
//  Created by Denis Vincent on 2015-07-22.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#ifndef SshTerminal_NetworkHelpers_h
#define SshTerminal_NetworkHelpers_h

#include <sys/types.h>
#include <sys/socket.h>
#include <netdb.h>


#define LO_BYTE(x) (((UInt8*)(&x))[0])
#define HI_BYTE(x) (((UInt8*)(&x))[1])

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


struct addrinfo* findSockaddr(int family, struct addrinfo* info);
int resolveHost(NetworkAddress* address, const char* host);


#endif
