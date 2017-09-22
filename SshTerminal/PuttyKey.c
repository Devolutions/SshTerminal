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
#include <errno.h>
#include "openssl/dsa.h"
#include "openssl/rsa.h"
#include "openssl/evp.h"
#include "openssl/sha.h"
//#include "libssh/pki.h"
#include "PuttyKey.h"

#define SKIP_LINE_END(p, i, s) while (i < s) {if (p[i] != '\r' && p[i] != '\n'){ break; } i++;}
#define FIND_LINE_END(p, i, s) while (i < s) {if (p[i] == '\r' || p[i] == '\n'){ break; } i++;}
uint32_t unpack32(uint8_t* s);
void pack32(uint8_t* d, uint32_t value);


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

int Base64ToData(const char* buffer, int bufferSize, uint8_t** decoded, int* decodedSize)
{
    int endPadding = 0;
    if (decodedSize != NULL)
    {
        *decodedSize = 0;
    }
    
    // Validate base64 data.
    if (bufferSize % 4 != 0 || bufferSize <= 0)
    {
        return -1;
    }
    for (int i = 0; i < bufferSize; i++)
    {
        char c = buffer[i];
        if (c == '=')
        {
            if (i < bufferSize - 2)
            {
                return -1;
            }
            if (i < bufferSize - 1 && buffer[i + 1] != '=')
            {
                return -1;
            }
            endPadding = (i == bufferSize - 1 ? 1 : 2);
            break;
        }
        if (gBase64Reverse[buffer[i]] == 255)
        {
            return -1;
        }
    }
    
    // Decode.
    int quadCount = bufferSize / 4;
    *decoded = malloc(quadCount * 3);
    if (*decoded == NULL)
    {
        return -1;
    }
    
    uint8_t* triplet = *decoded;
    const char* quad = buffer;
    int i;
    for (i = 2; i < bufferSize; i += 4)
    {
        triplet[0] = (gBase64Reverse[quad[0]] << 2) | (gBase64Reverse[quad[1]] >> 4);
        triplet[1] = ((gBase64Reverse[quad[1]] & 0x3f) << 4) | (gBase64Reverse[quad[2]] >> 2);
        triplet[2] = ((gBase64Reverse[quad[2]] & 0x03) << 6) | (gBase64Reverse[quad[3]]);
        quad += 4;
        triplet += 3;
    }
    
    if (decodedSize != NULL)
    {
        *decodedSize = quadCount * 3 - endPadding;
    }
    
    return 0;
}


int PuttyKeyLoadBignum(uint8_t* blob, int* index, int blobSize, BIGNUM** bignum, int* returnCode)
{
    if (*returnCode < 0)
    {
        return 0;
    }
    
    uint32_t length = unpack32(blob + *index) + 4;
    if (*index + length > blobSize)
    {
        *returnCode = FAIL_CORRUPTED;
        return length;
    }
    
    if (length > 4)
    {
        *bignum = BN_mpi2bn(blob + *index, length, NULL);
        if (*bignum == NULL)
        {
            *returnCode = FAIL_OUT_OF_MEMORY;
        }
    }
    
    *index += length;
    
    return length;
}


void PuttyKeyBinaryToString(uint8_t* input, int inputLength, char* output)
{
    for (int i = 0; i < inputLength; i++)
    {
        sprintf(output + i * 2, "%02x", input[i]);
    }
}


int PuttyKeyParseData(char* data, int size, const char* password, ssh_key* pkey)
{
    uint8_t* publicBlob = NULL;
    uint8_t* privateBlob = NULL;
    uint8_t* decryptedBlob = NULL;
	uint8_t* macData = NULL;
    int returnCode = 0;
    ssh_key key = NULL;
    
    *pkey = NULL;
    
    // Key type.
    if (size < 30)
    {
        returnCode = FAIL_CORRUPTED;
        goto EXIT;
    }
    int isFormat2 = 0;
    if (memcmp(data, "PuTTY-User-Key-File-2: ", 23) == 0)
    {
        isFormat2 = 1;
    }
    else if (memcmp(data, "PuTTY-User-Key-File-1: ", 23) != 0)
    {
        returnCode = FAIL_CORRUPTED;
        goto EXIT;
    }
    int isDsa = 0;
    int keyTypeNameStart = 23;
    int keyTypeNameEnd = 30;
    if (memcmp(data + 23, "ssh-dss", 7) == 0)
    {
        isDsa = 1;
    }
    else if (memcmp(data +23, "ssh-rsa", 7) != 0)
    {
        returnCode = FAIL_CORRUPTED;
        goto EXIT;
    }
    
    // Encryption type.
    int index = 0;
    FIND_LINE_END(data, index, size)
    SKIP_LINE_END(data, index, size)
    if (size < index + 12 || memcmp(data + index, "Encryption: ", 12) != 0)
    {
        returnCode = FAIL_CORRUPTED;
        goto EXIT;
    }
    index += 12;
    if (size < index + 10)
    {
        returnCode = FAIL_CORRUPTED;
        goto EXIT;
    }
    int isEncrypted = 0;
    int encryptionNameStart = index;
    if (memcmp(data + index, "aes256-cbc", 10) == 0)
    {
        isEncrypted = 1;
        index += 10;
    }
    else if (memcmp(data + index, "none", 4) == 0)
    {
        index += 4;
    }
    else
    {
        returnCode = FAIL_CORRUPTED;
        goto EXIT;
    }
    int encryptionNameEnd = index;
    
    // Comment.
    SKIP_LINE_END(data, index, size)
    if (size < index + 9 || memcmp(data + index, "Comment: ", 9) != 0)
    {
        returnCode = -1;
        goto EXIT;
    }
    index += 9;
    int commentStart = index;
    FIND_LINE_END(data, index, size)
    int commentEnd = index;
    
    // Public lines.
    SKIP_LINE_END(data, index, size)
    if (size < index + 14 || memcmp(data + index, "Public-Lines: ", 14) != 0)
    {
        returnCode = FAIL_CORRUPTED;
        goto EXIT;
    }
    index += 14;
    int lineCount = getNumeric(data + index, size - index);
    if (lineCount < 1)
    {
        returnCode = FAIL_CORRUPTED;
        goto EXIT;
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
    int publicBlobLength;
    int result = Base64ToData(data + blobStart, blobEnd - blobStart, &publicBlob, &publicBlobLength);
    if (result < 0)
    {
        returnCode = FAIL_CORRUPTED;
        goto EXIT;
    }
    
    // Private lines;
    SKIP_LINE_END(data, index, size)
    if (size < index + 15 || memcmp(data + index, "Private-Lines: ", 15) != 0)
    {
        returnCode = FAIL_CORRUPTED;
        goto EXIT;
    }
    index += 15;
    lineCount = getNumeric(data + index, size - index);
    FIND_LINE_END(data, index, size)
    SKIP_LINE_END(data, index, size)
    blobStart = index;
    FIND_LINE_END(data, index, size)
    blobEnd = index;
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
    int privateBlobLength;
    result = Base64ToData(data + blobStart, blobEnd - blobStart, &privateBlob, &privateBlobLength);
    if (result < 0)
    {
        returnCode = FAIL_CORRUPTED;
        goto EXIT;
    }
    
    // The private MAC.
    SKIP_LINE_END(data, index, size)
    if (size < index + 14)
    {
        returnCode = FAIL_CORRUPTED;
        goto EXIT;
    }
    int isMac = 0;
    if (memcmp(data + index, "Private-MAC: ", 13) == 0)
    {
        index += 13;
        isMac = 1;
    }
    else if (memcmp(data + index, "Private-Hash: ", 14) == 0)
    {
        if (isFormat2)
        {
            returnCode = FAIL_CORRUPTED;
            goto EXIT;
        }
        index += 14;
    }
    else
    {
        returnCode = FAIL_CORRUPTED;
        goto EXIT;
    }
    int macStart = index;
    FIND_LINE_END(data, index, size)
    int macEnd = index;
    int macLength = macEnd - macStart;
    
    if (macLength != 40 || publicBlobLength < 4 || privateBlobLength < 4)
    {
        returnCode = FAIL_CORRUPTED;
        goto EXIT;
    }
    
    // Decrypt if necessary.
    if (isEncrypted)
    {
        if (password == NULL)
        {
            returnCode = FAIL_INVALID_ARG;
            goto EXIT;
        }
        unsigned char decryptKey[40];
        memset(decryptKey, 0, sizeof(decryptKey));
        
        // Build the decryption key from the password.
        SHA_CTX hashContext;
		result = SHA1_Init(&hashContext);
        if (result == 0)
        {
            returnCode = FAIL_OUT_OF_MEMORY;
            goto EXIT;
        }
        uint8_t bytes[] = {0, 0, 0, 0};
		SHA1_Update(&hashContext, bytes, sizeof(bytes));
        int passwordLength = (int)strlen(password);
        SHA1_Update(&hashContext, password, passwordLength);
        SHA1_Final(decryptKey, &hashContext);   // This release ctx.
        bytes[3] = 1;
		result = SHA1_Init(&hashContext);
		if (result == 0)
        {
            returnCode = FAIL_OUT_OF_MEMORY;
            goto EXIT;
        }
        SHA1_Update(&hashContext, bytes, sizeof(bytes));
        SHA1_Update(&hashContext, password, passwordLength);
        SHA1_Final(decryptKey + 20, &hashContext);   // This release ctx.
        
        // Decrypt the private blob.
        EVP_CIPHER_CTX* cypherContext = EVP_CIPHER_CTX_new();
        if (cypherContext == NULL)
        {
            returnCode = FAIL_OUT_OF_MEMORY;
            goto EXIT;
        }
        int isSuccess = EVP_DecryptInit(cypherContext, EVP_aes_256_cbc(), decryptKey, NULL);
        if (isSuccess == 0)
        {
            returnCode = FAIL_CORRUPTED;
            goto EXIT;
        }
        decryptedBlob = malloc(privateBlobLength + 16);
        if (decryptedBlob == NULL)
        {
            returnCode = FAIL_OUT_OF_MEMORY;
            goto EXIT;
        }
        int decryptedLength = 0;
        isSuccess = EVP_DecryptUpdate(cypherContext, decryptedBlob, &decryptedLength, privateBlob, privateBlobLength);
        if (isSuccess == 0)
        {
            returnCode = FAIL_CORRUPTED;
            goto EXIT;
        }
        int finaledLenght = 0;
        int isFailed = EVP_DecryptFinal(cypherContext, decryptedBlob + decryptedLength, &finaledLenght);
        if (isFailed)
        {
            returnCode = FAIL_CORRUPTED;
            goto EXIT;
        }
        decryptedLength += finaledLenght;
        free(privateBlob);
        privateBlob = decryptedBlob;
        decryptedBlob = NULL;
        if (decryptedLength > privateBlobLength)
        {
            // For some reason, EVP_DecryptFinal() always yield a finaledLength of 0. Which means that the resulting decryptedLength is always
            // 16 bytes shorter than the encrypted privateBlobLength (at least in my testings).
            // This is why I decided to change the privateBlobLength only if the decryption results in a bigger size.
            privateBlobLength = decryptedLength;
        }
    }
    
    // Verify the MAC or digest.
    int macDataLength = 0;
    if (isFormat2 == 0)
    {
        // Putty key format 1 uses only the private blob for MAC or digest.
        macData = malloc(privateBlobLength);
        if (macData == NULL)
        {
            returnCode = FAIL_OUT_OF_MEMORY;
            goto EXIT;
        }
        memcpy(macData, privateBlob, privateBlobLength);
        macDataLength = privateBlobLength;
    }
    else
    {
        // Putty key format 2: build a blob used as a source for MAC or digest.
        int keyTypeNameLength = keyTypeNameEnd - keyTypeNameStart;
        int encryptionNameLength = encryptionNameEnd - encryptionNameStart;
        int commentLength = commentEnd - commentStart;
        macDataLength = 4 + keyTypeNameLength + 4 + encryptionNameLength + 4 + commentLength + 4 + publicBlobLength + 4 + privateBlobLength;
        macData = malloc(macDataLength);
        if (macData == NULL)
        {
            returnCode = FAIL_OUT_OF_MEMORY;
            goto EXIT;
        }

        int index = 0;
        
        pack32(macData + index, keyTypeNameLength);
        index += 4;
        memcpy(macData + index, data + keyTypeNameStart, keyTypeNameLength);
        index += keyTypeNameLength;
        
        pack32(macData + index, encryptionNameLength);
        index += 4;
        memcpy(macData + index, data + encryptionNameStart, encryptionNameLength);
        index += encryptionNameLength;
        
        pack32(macData + index, commentLength);
        index += 4;
        memcpy(macData + index, data + commentStart, commentLength);
        index += commentLength;
        
        pack32(macData + index, publicBlobLength);
        index += 4;
        memcpy(macData + index, publicBlob, publicBlobLength);
        index += publicBlobLength;
        
        pack32(macData + index, privateBlobLength);
        index += 4;
        memcpy(macData + index, privateBlob, privateBlobLength);
        //index += privateBlobLength;
    }
    
    uint8_t macBinary[20];
    char mac[41];
    if (isMac)
    {
        // Compute a key.
        uint8_t macKey[20];
        SHA_CTX hashContext;
		result = SHA1_Init(&hashContext);
		if (result == 0)
        {
            returnCode = FAIL_OUT_OF_MEMORY;
            goto EXIT;
        }
        SHA1_Update(&hashContext, "putty-private-key-file-mac-key", 30);
        if (isEncrypted && password != NULL)
        {
            SHA1_Update(&hashContext, password, (int)strlen(password));
        }
        SHA1_Final(macKey, &hashContext);   // This release ctx.
        
        // Hash the key with the MAC data to get an intermediate result.
        uint8_t intermediate[20];
        uint8_t iv[64];
        memset(iv, 0x36, 64);
        for (int i = 0; i < 20; i++)
        {
            iv[i] ^= macKey[i];
        }
		result = SHA1_Init(&hashContext);
		if (result == 0)
        {
            returnCode = FAIL_OUT_OF_MEMORY;
            goto EXIT;
        }
        SHA1_Update(&hashContext, iv, 64);
        SHA1_Update(&hashContext, macData, macDataLength);
        SHA1_Final(intermediate, &hashContext);   // This release ctx.
        
        // Hash the key with the intermediate result to get the final MAC in binary form.
        memset(iv, 0x5C, 64);
        for (int i = 0; i < 20; i++)
        {
            iv[i] ^= macKey[i];
        }
		result = SHA1_Init(&hashContext);
		if (result == 0)
        {
            returnCode = FAIL_OUT_OF_MEMORY;
            goto EXIT;
        }
        SHA1_Update(&hashContext, iv, 64);
        SHA1_Update(&hashContext, intermediate, 20);
        SHA1_Final(macBinary, &hashContext);   // This release ctx.
    }
    else
    {
        // Hash the MAC data to get the final MAC in binary form.
        SHA_CTX hashContext;
		result = SHA1_Init(&hashContext);
		if (result == 0)
        {
            returnCode = FAIL_OUT_OF_MEMORY;
            goto EXIT;
        }
        SHA1_Update(&hashContext, macData, macDataLength);
        SHA1_Final(macBinary, &hashContext);   // This release ctx.
    }

    PuttyKeyBinaryToString(macBinary, 20, mac);
    if (strncmp(data + macStart, mac, macLength) != 0)
    {
        returnCode = (isEncrypted ? FAIL_WRONG_PASSWORD : FAIL_CORRUPTED);
        goto EXIT;
    }

    // Build the key.
    key = ssh_key_new();
    if (key == NULL)
    {
        returnCode = FAIL_OUT_OF_MEMORY;
        goto EXIT;
    }
    
    if (isDsa)
    {
        DSA* dsa = DSA_new();
        if (dsa == NULL)
        {
            returnCode = FAIL_OUT_OF_MEMORY;
            goto EXIT;
        }
        
		makeDsaKey(key, dsa);
        
        // Load the private part.
        int index = 0;
        PuttyKeyLoadBignum(privateBlob, &index, privateBlobLength, &dsa->priv_key, &returnCode);
        
        // Load the public part.
        int length = unpack32(publicBlob) + 4;
        if (length > publicBlobLength)
        {
            returnCode = FAIL_CORRUPTED;
            goto EXIT;
        }
        index = length;   // Skip the key type string.
        
        PuttyKeyLoadBignum(publicBlob, &index, publicBlobLength, &dsa->p, &returnCode);
        PuttyKeyLoadBignum(publicBlob, &index, publicBlobLength, &dsa->q, &returnCode);
        PuttyKeyLoadBignum(publicBlob, &index, publicBlobLength, &dsa->g, &returnCode);
        PuttyKeyLoadBignum(publicBlob, &index, publicBlobLength, &dsa->pub_key, &returnCode);
    }
    else
    {
        RSA* rsa = RSA_new();
        if (rsa == NULL)
        {
            returnCode = FAIL_OUT_OF_MEMORY;
            goto EXIT;
        }
        
		makeRsaKey(key, rsa);
        
        // Load the private part.
        int index = 0;
        PuttyKeyLoadBignum(privateBlob, &index, privateBlobLength, &rsa->d, &returnCode);
        PuttyKeyLoadBignum(privateBlob, &index, privateBlobLength, &rsa->p, &returnCode);
        PuttyKeyLoadBignum(privateBlob, &index, privateBlobLength, &rsa->q, &returnCode);
        PuttyKeyLoadBignum(privateBlob, &index, privateBlobLength, &rsa->iqmp, &returnCode);
        
        // Load the public part.
        int length = unpack32(publicBlob) + 4;
        if (length > publicBlobLength)
        {
            returnCode = FAIL_CORRUPTED;
            goto EXIT;
        }
        index = length;   // Skip the key type string.
        PuttyKeyLoadBignum(publicBlob, &index, publicBlobLength, &rsa->e, &returnCode);
        PuttyKeyLoadBignum(publicBlob, &index, publicBlobLength, &rsa->n, &returnCode);
    }
    
EXIT:
    free(privateBlob);
    free(publicBlob);
    free(decryptedBlob);
    free(macData);
    
    if (returnCode == 0)
    {
        *pkey = key;
    }
    else
    {
        ssh_key_free(key);
    }
    return returnCode;
}


int PuttyKeyLoadPrivate(const char* path, const char* password, ssh_key* pkey)
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


int PuttyKeyDetectType(const char* path)
{
    int fd = open(path, O_RDONLY);
    if (fd < 0)
    {
        int error = errno;
        if (error == EEXIST)
        {
            return KEY_TYPE_FILE_NOT_FOUND;
        }
        else if (error == EACCES)
        {
            return KEY_TYPE_ACCESS_DENIED;
        }
        else
        {
            return KEY_TYPE_ERROR;
        }
    }
    
    char buffer[32];
    int readCount = (int)read(fd, buffer, sizeof(buffer));
    close(fd);
    if (readCount < sizeof(buffer))
    {
        return KEY_TYPE_UNKNOWN;
    }
    if (memcmp(buffer, "PuTTY-User-Key-File-2", 21) == 0 || memcmp(buffer, "PuTTY-User-Key-File-1", 21) == 0)
    {
        return KEY_TYPE_PUTTY;
    }
    if (memcmp(buffer, "-----BEGIN ", 11) == 0)
    {
        return KEY_TYPE_OPEN_SSH;
    }
    
    return SSH_KEYTYPE_UNKNOWN;
}


