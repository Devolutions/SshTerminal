

#ifndef __PuttyKey_h__
#define __PuttyKey_h__

#include <stdio.h>
#include "SshFoundation.h"


enum KeyTypeReturns
{
    KEY_TYPE_OPEN_SSH = 1,
    KEY_TYPE_PUTTY = 2,
    
    KEY_TYPE_ERROR = -1,
    KEY_TYPE_UNKNOWN = -2,
    KEY_TYPE_FILE_NOT_FOUND = -3,
    KEY_TYPE_ACCESS_DENIED = -4,
};

enum KeyLoadReturns
{
    SUCCESS = 0,
    FAIL = -1,
    FAIL_CORRUPTED = -2,
    FAIL_OUT_OF_MEMORY = -3,
    FAIL_INVALID_ARG = -4,
    FAIL_WRONG_PASSWORD = -5,
};


int PuttyKeyLoadPrivate(char* path, char* password, ssh_key* pkey);
int PuttyKeyDetectType(const char* path);


#endif


