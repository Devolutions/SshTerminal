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


int resolveHost(NetworkAddress* address, const char* host)
{
    if (host == NULL || strlen(host) == 0)
    {
        host = "0.0.0.0";
    }
    
    // Get the address info for the host.
    struct addrinfo* info;
    struct addrinfo hint;
    memset(&hint, 0, sizeof(hint));
    hint.ai_flags = AI_ADDRCONFIG | AI_PASSIVE;
    hint.ai_family = PF_UNSPEC;
    hint.ai_socktype = SOCK_STREAM;
    hint.ai_protocol = IPPROTO_TCP;
    int result = getaddrinfo(host, NULL, NULL, &info);
    if (result != 0)
    {
        return 0;
    }
    
    // Parse the address info to find the most appropriate sockaddr.
    int addressSize = 0;
    struct addrinfo* selectedInfo = findSockaddr(PF_INET, info);
    if (selectedInfo == NULL)
    {
        selectedInfo = findSockaddr(PF_INET6, info);
    }
    if (selectedInfo != NULL)
    {
        addressSize = selectedInfo->ai_addrlen;
    }
    
    // Copy the result.
    if (addressSize > 0)
    {
        assert(addressSize <= sizeof(NetworkAddress));
        memcpy(address, selectedInfo->ai_addr, addressSize);
    }
    freeaddrinfo(info);
    
    return addressSize;
}


