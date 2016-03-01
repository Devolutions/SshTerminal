//
//  NetworkHelpers.m
//  SshTerminal
//
//  Created by Denis Vincent on 2015-07-22.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "NetworkHelpers.h"


struct addrinfo* findSockaddr(int family, struct addrinfo* info)
{
    while (1)
    {
        if (info->ai_family == family && info->ai_socktype == SOCK_STREAM)
        {
            return info;
        }
        if (info->ai_next == NULL)
        {
            break;
        }
        info = info->ai_next;
    }
    return NULL;
}


int resolveHost(NetworkAddress* addresses, const char* host)
{
    if (host == NULL)
    {
        host = "";
    }

    // Get the address info for the host.
    struct addrinfo* info;
    struct addrinfo hint;
    memset(&hint, 0, sizeof(hint));
    hint.ai_flags = AI_ADDRCONFIG | AI_PASSIVE;
    hint.ai_family = PF_UNSPEC;
    hint.ai_socktype = SOCK_STREAM;
    hint.ai_protocol = IPPROTO_TCP;
    int result = getaddrinfo(host, NULL, &hint, &info);
    if (result != 0)
    {
        return 0;
    }
    
    // Parse the address info to find appropriate IPV4 and IPV6 sockaddr.
    int addressCount = 0;
    while (1)
    {
        if ((info->ai_family == PF_INET || info->ai_family == PF_INET6) && info->ai_socktype == SOCK_STREAM)
        {
            memcpy(addresses + addressCount, info->ai_addr, info->ai_addrlen);
            addressCount++;
        }
        if (info->ai_next == NULL || addressCount >= 2)
        {
            break;
        }
        info = info->ai_next;
    }

    freeaddrinfo(info);
    
    return addressCount;
}


