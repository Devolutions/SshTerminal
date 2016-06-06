//
//  PuttyKey.c
//  SshTerminal
//
//  Created by Denis Vincent on 2016-06-06.
//  Copyright © 2016 Denis Vincent. All rights reserved.
//

#include <stdlib.h>
#include <sys/stat.h>
#include <fcntl.h>
#include "PuttyKey.h"

#define SKIP_LINE_END(p, i, s) while (i < s) {if (p[i] != '\r' && p[i] != '\n'){ break; } i++;}
#define FIND_LINE_END(p, i, s) while (i < s) {if (p[i] == '\r' || p[i] == '\n'){ break; } i++;}


uint16_t getNumeric(char* p, int digitCount)
{
    uint16_t value = 0;
    int i;
    for (i = 0; i < digitCount; i++)
    {
        char c = p[i];
        if (c >= '0' && c <= '9')
        {
            value *= 10;
            value += c - '0';
        }
        else
        {
            break;
        }
    }
    
    return value;
}


uint8_t gBase64Reverse[] =
{
    255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
    255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,  62, 255, 255, 255,  63,  52,  53,  54,  55,  56,  57,  58,  59,  60,  61, 255, 255, 255,   0, 255, 255,
    255,   0,   1,   2,   3,   4,   5,   6,   7,   8,   9,  10,  11,  12,  13,  14,  15,  16,  17,  18,  19,  20,  21,  22,  23,  24,  25, 255, 255, 255, 255, 255,
    255,  26,  27,  28,  29,  30,  31,  32,  33,  34,  35,  36,  37,  38,  39,  40,  41,  42,  43,  44,  45,  46,  47,  48,  49,  50,  51, 255, 255, 255, 255, 255,
};
/*
uint8_t* Base64ToData(const char* buffer, int bufferSize, int* decodedSize)
{
    int quadCount = (bufferSize + 3) / 4;
    uint8_t* decoded = malloc(quadCount * 3);
    if (decoded == NULL)
    {
        if (decodedSize != NULL)
        {
            *decodedSize = 0;
        }
        return NULL;
    }
    memset(decoded, 0, quadCount * 3);
    if (decodedSize != NULL)
    {
        *decodedSize = quadCount * 3;
    }
    
    uint8_t* triplet = decoded;
    const char* quad = buffer;
    int i;
    for (i = 2; i < bufferSize; i += 4)
    {
        triplet[0] = (gBase64Reverse[quad[0]] << 2) | (gBase64Reverse[quad[1]] >> 6);
        triplet[1] = ((gBase64Reverse[quad[1]] & 0x3f) << 4) | (gBase64Reverse[quad[2]] >> 2);
        triplet[2] = ((gBase64Reverse[quad[2]] & 0x03) << 6) | (gBase64Reverse[quad[3]]);
        quad += 4;
        triplet += 3;
    }
    if (triplet < (const uint8_t*)buffer + bufferSize)
    {
        quad[0] = gBase64Alphabet[triplet[0] >> 2];
        if (triplet + 1 < (const uint8_t*)buffer + bufferSize)
        {
            quad[1] = gBase64Alphabet[((triplet[0] & 0x03) << 4) | (triplet[1] >> 4)];
            quad[2] = gBase64Alphabet[(triplet[1] & 0x0F) << 2];
        }
        else
        {
            quad[1] = gBase64Alphabet[(triplet[0] & 0x03) << 4];
            quad[2] = '=';
        }
        quad[3] = '=';
    }
    encoded[tripleCount * 4] = 0;
    
    return encoded;
}
*/

int PuttyKeyParseData(char* data, int size, char* password, ssh_key* pkey)
{
    // Key type.
    if (size < 23 || memcmp(data, "PuTTY-User-Key-File-2: ", 23) != 0)
    {
        return -1;
    }
    if (size < 30)
    {
        return -1;
    }
    char keyType[8];
    memcpy(keyType, data + 23, 7);
    keyType[7] = 0;
    if (memcmp(keyType, "ssh-rsa", 7) != 0 && memcmp(keyType, "ssh-dss", 7) != 0)
    {
        return -1;
    }
    
    // Encryption type.
    int index = 30;
    SKIP_LINE_END(data, index, size)
    if (size < index + 12 || memcmp(data, "Encryption: ", 12) != 0)
    {
        return -1;
    }
    index += 12;
    if (size < index + 10)
    {
        return -1;
    }
    int isEncrypted = 0;
    if (memcmp(data, "aes256-cbc", 4) == 0)
    {
        isEncrypted = 1;
        index += 10;
    }
    else if (memcmp(data, "none", 4) == 0)
    {
        index += 4;
    }
    else
    {
        return -1;
    }
    
    // Comment.
    SKIP_LINE_END(data, index, size)
    if (size < index + 9 || memcmp(data, "Comment: ", 9) != 0)
    {
        return -1;
    }
    index += 9;
    int commentStart = index;
    FIND_LINE_END(data, index, size)
    int commentEnd = index;
    
    // Public lines.
    SKIP_LINE_END(data, index, size)
    if (size < index + 14 || memcmp(data, "Public-Lines: ", 14) != 0)
    {
        return -1;
    }
    index += 14;
    int lineCount = getNumeric(data + index, size - index);
    if (lineCount < 1)
    {
        return -1;
    }
    FIND_LINE_END(data, index, size)
    SKIP_LINE_END(data, index, size)
    int blobStart = index;
    FIND_LINE_END(data, index, size)
    int blobEnd = index;
    for (int i = 1; i < lineCount; i++)
    {
        SKIP_LINE_END(data, index, size)
        int lineStart = index;
        FIND_LINE_END(data, index, size)
        int lineEnd = index;
        
        int lineLength = lineEnd - lineStart;
        memmove(data + blobEnd, data + lineStart, lineLength);
        blobEnd += lineLength;
    }
    
    // Private lines;
    SKIP_LINE_END(data, index, size)
    if (size < index + 15 || memcmp(data, "Private-Lines: ", 15) != 0)
    {
        return -1;
    }
    index += 15;
    lineCount = getNumeric(data + index, size - index);
    FIND_LINE_END(data, index, size)
    
    return 0;
}


int PuttyKeyLoadPrivate(char* path, char* password, ssh_key* pkey)
{
    // Get the file size.
    struct stat fileStat;
    int result = stat(path, &fileStat);
    if (result != 0)
    {
        return -1;
    }
    
    // Load the key content in memory.
    int fileSize = (int)fileStat.st_size;
    char* fileData = malloc(fileSize);
    if (fileData == NULL)
    {
        return -1;
    }
    
    int fd = open(path, O_RDONLY);
    if (fd < 0)
    {
        free(fileData);
        return -1;
    }
    int readCount = (int)read(fd, fileData, fileSize);
    close(fd);
    if (readCount != fileSize)
    {
        free(fileData);
        return -1;
    }
    
    // Parse the key content.
    result = PuttyKeyParseData(fileData, fileSize, password, pkey);
    if (result < 0)
    {
        *pkey = NULL;
    }
    free(fileData);
    return result;
}


