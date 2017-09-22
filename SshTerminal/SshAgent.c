

#include <stdlib.h>
//#include <libssh/string.h>
//#include <libssh/pki.h>
#include "SshAgent.h"
#include <openssl/rsa.h>
#include <openssl/dsa.h>
#include <openssl/sha.h>
#include <openssl/ssl.h>

int ssh_pki_export_pubkey_blob(const ssh_key key, ssh_string* pblob);


void pack32(uint8_t* d, uint32_t value)
{
    uint8_t* s = ((uint8_t*)&value) + 3;
    *d++ = *s--;
    *d++ = *s--;
    *d++ = *s--;
    *d++ = *s--;
}


uint32_t unpack32(uint8_t* s)
{
    uint32_t value;
    uint8_t* d = ((uint8_t*)&value) + 3;
    *d-- = *s++;
    *d-- = *s++;
    *d-- = *s++;
    *d-- = *s++;
    return value;
}


uint8_t* SshAgentMakeIdentityListReply(SshAgentContext* context)
{
    uint8_t* message = NULL;
    
    int keyCount = (context->isLocked ? 0 : context->keyCount);
    
    ssh_string* keyBlobs = (keyCount > 0 ? calloc(keyCount, sizeof(ssh_string*)) : NULL);
    if (keyBlobs == NULL && keyCount > 0)
    {
        return NULL;
    }
    int totalBlobSize = 0;
    int i;
    for (i = 0; i < keyCount; i++)
    {
        int sshResult = ssh_pki_export_pubkey_blob(context->keys[i], keyBlobs + i);
        if (sshResult != SSH_OK)
        {
            goto FREE_KEY_BLOBS;
        }
        totalBlobSize += ssh_string_len(keyBlobs[i]);
    }

    int messageSize = 5 + totalBlobSize + 8 * keyCount;
    message = malloc(messageSize + 4);
    if (message == NULL)
    {
        goto FREE_KEY_BLOBS;
    }
    
    pack32(message, messageSize);
    message[4] = SSH2_AGENT_IDENTITIES_ANSWER;
    pack32(message + 5, keyCount);
    int index = 9;
    for (i = 0; i < keyCount; i++)
    {
        ssh_string blob = keyBlobs[i];
        int blobSize = unpack32((uint8_t*)blob) + 4;
        memcpy(message + index, blob, blobSize);
        index += blobSize;
        
        memset(message + index, 0, 4);
        index += 4;
    }
    
FREE_KEY_BLOBS:
    for (i = 0; i < keyCount; i++)
    {
        ssh_string blob = keyBlobs[i];
        ssh_string_free(blob);
    }

    free(keyBlobs);
    
    return message;
}


uint8_t* SshAgentMakeSuccessReply()
{
    uint8_t* message = malloc(5);
    if (message == NULL)
    {
        return NULL;
    }
    pack32(message, 1);
    message[4] = SSH_AGENT_SUCCESS;
    return message;
}


uint8_t* SshAgentMakeErrorReply()
{
    uint8_t* message = malloc(5);
    if (message == NULL)
    {
        return NULL;
    }
    pack32(message, 1);
    message[4] = SSH_AGENT_FAILURE;
    return message;
}


ssh_string SshAgentSignDss(uint8_t* data, int dataSize, ssh_key key, uint32_t flags)
{
    unsigned char hash[SHA_DIGEST_LENGTH] = {0};
    SHA_CTX ctx;
    
    int result = SHA1_Init(&ctx);
    if (result == 0)
    {
        return NULL;
    }
    
    SHA1_Update(&ctx, data, dataSize);
    SHA1_Final(hash, &ctx);   // This release ctx.
    
    DSA_SIG* sig = NULL;
    sig = DSA_do_sign(hash, sizeof(hash), getKeyDsa(key));
    if (sig == NULL)
    {
        return NULL;
    }
    
    uint8_t sigblob[40];
    memset(sigblob, 0, 40);
    int rlen = BN_num_bytes(sig->r);
    int slen = BN_num_bytes(sig->s);
    BN_bn2bin(sig->r, sigblob + 20 - rlen);
    BN_bn2bin(sig->s, sigblob + 40 - slen);
    
    if (flags & SSH_AGENT_OLD_SIGNATURE)
    {
        uint8_t* signatureBlob = malloc(sizeof(sigblob));
        if (signatureBlob == NULL)
        {
            return NULL;
        }
        memcpy(signatureBlob, sigblob, 40);
        
        return (ssh_string)signatureBlob;
    }
    
    int signatureTypeLength = 7;
    int signatureLength = 40;
    int signatureBlobLength = 8 + signatureTypeLength + signatureLength;
    
    uint8_t* signatureBlob = malloc(4 + signatureBlobLength);
    if (signatureBlob == NULL)
    {
        return NULL;
    }
    
    pack32(signatureBlob, signatureBlobLength);
    pack32(signatureBlob + 4, signatureTypeLength);
    memcpy(signatureBlob + 8, "ssh-dss", signatureTypeLength);
    pack32(signatureBlob + 15, signatureLength);
    memcpy(signatureBlob + 19, sigblob, 40);
    
    return (ssh_string)signatureBlob;
}


ssh_string SshAgentSignRsaSha1(uint8_t* data, int dataSize, ssh_key key, uint32_t flags)
{
    // Compute the hash.
    unsigned char hash[SHA_DIGEST_LENGTH] = {0};
    SHA_CTX ctx;
    
	int result = SHA1_Init(&ctx);
	if (result == 0)
    {
        return NULL;
    }
    
    SHA1_Update(&ctx, data, dataSize);
    SHA1_Final(hash, &ctx);   // This release ctx.
    
    // Prepare the buffer to hold the signature in a blob of the form:
    // signatureBlobLength[ signatureTypeLength[ signatureType ] signatureLength[ signature ] ]
    int signatureTypeLength = 7;
    int signatureLength = RSA_size(getKeyRsa(key));
    int signatureBlobLength = 8 + signatureTypeLength + signatureLength;
    
    uint8_t* signatureBlob = malloc(4 + signatureBlobLength);
    if (signatureBlob == NULL)
    {
        return NULL;
    }
    
    pack32(signatureBlob, signatureBlobLength);
    int index = 4;
    pack32(signatureBlob + index, signatureTypeLength);
    index += 4;
    memcpy(signatureBlob + index, "ssh-rsa", signatureTypeLength);
    index += signatureTypeLength;
    pack32(signatureBlob + 15, signatureLength);
    index += 4;
    
    // Sign the hash in place in the signature blob buffer.
    unsigned int len;
    result = RSA_sign(NID_sha1, hash, sizeof(hash), signatureBlob + index, &len, getKeyRsa(key));
    if (result != 1)
    {
        free(signatureBlob);
        return NULL;
    }
    
    return (ssh_string)signatureBlob;
}


ssh_string SshAgentSignRsaSha256(uint8_t* data, int dataSize, ssh_key key, uint32_t flags)
{
    // Compute the hash.
    unsigned char hash[SHA256_DIGEST_LENGTH] = {0};
    SHA256_CTX ctx;
    
	int result = SHA256_Init(&ctx);
	if (result == 0)
    {
        return NULL;
    }
    
    SHA256_Update(&ctx, data, dataSize);
    SHA256_Final(hash, &ctx);   // This release ctx.
    
    // Prepare the buffer to hold the signature in a blob of the form:
    // signatureBlobLength[ signatureTypeLength[ signatureType ] signatureLength[ signature ] ]
    int signatureTypeLength = 12;
    int signatureLength = RSA_size(getKeyRsa(key));
    int signatureBlobLength = 8 + signatureTypeLength + signatureLength;
    
    uint8_t* signatureBlob = malloc(4 + signatureBlobLength);
    if (signatureBlob == NULL)
    {
        return NULL;
    }
    
    pack32(signatureBlob, signatureBlobLength);
    int index = 4;
    pack32(signatureBlob + index, signatureTypeLength);
    index += 4;
    memcpy(signatureBlob + index, "rsa-sha2-256", signatureTypeLength);
    index += signatureTypeLength;
    pack32(signatureBlob + 15, signatureLength);
    index += 4;
    
    // Sign the hash in place in the signature blob buffer.
    unsigned int len;
    result = RSA_sign(NID_sha256, hash, sizeof(hash), signatureBlob + index, &len, getKeyRsa(key));
    if (result != 1)
    {
        free(signatureBlob);
        return NULL;
    }
    
    return (ssh_string)signatureBlob;
}


ssh_string SshAgentSignRsaSha512(uint8_t* data, int dataSize, ssh_key key, uint32_t flags)
{
    // Compute the hash.
    unsigned char hash[SHA512_DIGEST_LENGTH] = {0};
    SHA512_CTX ctx;
    
    int result = SHA512_Init(&ctx);
    if (result == 0)
    {
        return NULL;
    }
    
    SHA512_Update(&ctx, data, dataSize);
    SHA512_Final(hash, &ctx);   // This release ctx.
    
    // Prepare the buffer to hold the signature in a blob of the form:
    // signatureBlobLength[ signatureTypeLength[ signatureType ] signatureLength[ signature ] ]
    int signatureTypeLength = 12;
    int signatureLength = RSA_size(getKeyRsa(key));
    int signatureBlobLength = 8 + signatureTypeLength + signatureLength;
    
    uint8_t* signatureBlob = malloc(4 + signatureBlobLength);
    if (signatureBlob == NULL)
    {
        return NULL;
    }
    
    pack32(signatureBlob, signatureBlobLength);
    int index = 4;
    pack32(signatureBlob + index, signatureTypeLength);
    index += 4;
    memcpy(signatureBlob + index, "rsa-sha2-512", signatureTypeLength);
    index += signatureTypeLength;
    pack32(signatureBlob + 15, signatureLength);
    index += 4;
    
    // Sign the hash in place in the signature blob buffer.
    unsigned int len;
    result = RSA_sign(NID_sha512, hash, sizeof(hash), signatureBlob + index, &len, getKeyRsa(key));
    if (result != 1)
    {
        free(signatureBlob);
        return NULL;
    }
    
    return (ssh_string)signatureBlob;
}


ssh_string SshAgentSignRsa(uint8_t* data, int dataSize, ssh_key key, uint32_t flags)
{
    if (flags & SSH_AGENT_RSA_SHA2_256)
    {
        return SshAgentSignRsaSha256(data, dataSize, key, flags);
    }
    else if (flags & SSH_AGENT_RSA_SHA2_512)
    {
        return SshAgentSignRsaSha512(data, dataSize, key, flags);
    }
    
    return SshAgentSignRsaSha1(data, dataSize, key, flags);
}


ssh_string SshAgentSignEcdsaSha256(uint8_t* data, int dataSize, ssh_key key, uint32_t flags)
{
    // Compute the hash.
    unsigned char hash[SHA256_DIGEST_LENGTH] = {0};
    SHA256_CTX ctx;
    
    int result = SHA256_Init(&ctx);
    if (result == 0)
    {
        return NULL;
    }
    
    SHA256_Update(&ctx, data, dataSize);
    SHA256_Final(hash, &ctx);   // This release ctx.
    
    // Sign the hash.
    ECDSA_SIG* sig = NULL;
    sig = ECDSA_do_sign(hash, sizeof(hash), getKeyEcdsa(key));
    if (sig == NULL)
    {
        return NULL;
    }
    
    // Format the signature in a blob of the form:
    // blobLength[ typeNameLength[ typeName ] signatureLength[ rLength[ r ] sLength[ s ] ] ]
    int rMpiLength = BN_bn2mpi(sig->r, NULL);
    int sMpiLength = BN_bn2mpi(sig->s, NULL);
    int signatureLength = rMpiLength + sMpiLength;
    int typeNameLength = 19;
    int blobLength = 8 + typeNameLength + signatureLength;
    
    uint8_t* signatureBlob = malloc(4 + blobLength);
    if (signatureBlob == NULL)
    {
        return NULL;
    }
    
    pack32(signatureBlob, blobLength);
    int index = 4;
    pack32(signatureBlob + index, typeNameLength);
    index += 4;
    memcpy(signatureBlob + index, "ecdsa-sha2-nistp256", typeNameLength);
    index += typeNameLength;
    pack32(signatureBlob + 15, signatureLength);
    index += 4;
    BN_bn2mpi(sig->r, signatureBlob + index);
    index += rMpiLength;
    BN_bn2mpi(sig->s, signatureBlob + index);
    
    return (ssh_string)signatureBlob;
}


ssh_string SshAgentSignEcdsaSha384(uint8_t* data, int dataSize, ssh_key key, uint32_t flags)
{
    // Compute the hash.
    unsigned char hash[SHA384_DIGEST_LENGTH] = {0};
    SHA512_CTX ctx;
    
    int result = SHA384_Init(&ctx);
    if (result == 0)
    {
        return NULL;
    }
    
    SHA384_Update(&ctx, data, dataSize);
    SHA384_Final(hash, &ctx);   // This release ctx.
    
    // Sign the hash.
    ECDSA_SIG* sig = NULL;
    sig = ECDSA_do_sign(hash, sizeof(hash), getKeyEcdsa(key));
    if (sig == NULL)
    {
        return NULL;
    }
    
    // Format the signature in a blob of the form:
    // blobLength[ typeNameLength[ typeName ] signatureLength[ rLength[ r ] sLength[ s ] ] ]
    int rMpiLength = BN_bn2mpi(sig->r, NULL);
    int sMpiLength = BN_bn2mpi(sig->s, NULL);
    int signatureLength = rMpiLength + sMpiLength;
    int typeNameLength = 19;
    int blobLength = 8 + typeNameLength + signatureLength;
    
    uint8_t* signatureBlob = malloc(4 + blobLength);
    if (signatureBlob == NULL)
    {
        return NULL;
    }
    
    pack32(signatureBlob, blobLength);
    int index = 4;
    pack32(signatureBlob + index, typeNameLength);
    index += 4;
    memcpy(signatureBlob + index, "ecdsa-sha2-nistp384", typeNameLength);
    index += typeNameLength;
    pack32(signatureBlob + 15, signatureLength);
    index += 4;
    BN_bn2mpi(sig->r, signatureBlob + index);
    index += rMpiLength;
    BN_bn2mpi(sig->s, signatureBlob + index);
    
    return (ssh_string)signatureBlob;
}


ssh_string SshAgentSignEcdsaSha512(uint8_t* data, int dataSize, ssh_key key, uint32_t flags)
{
    // Compute the hash.
    unsigned char hash[SHA512_DIGEST_LENGTH] = {0};
    SHA512_CTX ctx;
    
    int result = SHA512_Init(&ctx);
    if (result == 0)
    {
        return NULL;
    }
    
    SHA512_Update(&ctx, data, dataSize);
    SHA512_Final(hash, &ctx);   // This release ctx.
    
    // Sign the hash.
    ECDSA_SIG* sig = NULL;
    sig = ECDSA_do_sign(hash, sizeof(hash), getKeyEcdsa(key));
    if (sig == NULL)
    {
        return NULL;
    }
    
    // Format the signature in a blob of the form:
    // blobLength[ typeNameLength[ typeName ] signatureLength[ rLength[ r ] sLength[ s ] ] ]
    int rMpiLength = BN_bn2mpi(sig->r, NULL);
    int sMpiLength = BN_bn2mpi(sig->s, NULL);
    int signatureLength = rMpiLength + sMpiLength;
    int typeNameLength = 19;
    int blobLength = 8 + typeNameLength + signatureLength;
    
    uint8_t* signatureBlob = malloc(4 + blobLength);
    if (signatureBlob == NULL)
    {
        return NULL;
    }
    
    pack32(signatureBlob, blobLength);
    int index = 4;
    pack32(signatureBlob + index, typeNameLength);
    index += 4;
    memcpy(signatureBlob + index, "ecdsa-sha2-nistp521", typeNameLength);
    index += typeNameLength;
    pack32(signatureBlob + 15, signatureLength);
    index += 4;
    BN_bn2mpi(sig->r, signatureBlob + index);
    index += rMpiLength;
    BN_bn2mpi(sig->s, signatureBlob + index);
    
    return (ssh_string)signatureBlob;
}


ssh_string SshAgentSignEcdsa(uint8_t* data, int dataSize, ssh_key key, uint32_t flags)
{
    switch (getKeyEcdsaNid(key))
    {
        case NID_X9_62_prime256v1:
            return SshAgentSignEcdsaSha256(data, dataSize, key, flags);
            
        case NID_secp384r1:
            return SshAgentSignEcdsaSha384(data, dataSize, key, flags);
            
        case NID_secp521r1:
            return SshAgentSignEcdsaSha512(data, dataSize, key, flags);
    }
    
    return NULL;
}


ssh_string SshAgentSignEd25519(uint8_t* data, int dataSize, ssh_key key, uint32_t flags)
{
    // Prepare a buffer for the signature in a blob of the form:
    // blobLength[ typeNameLength[ typeName ] signatureLength[ signature ] ]
    uint32_t typeNameLength = 11;
    unsigned long long signatureLength = dataSize + 64;
    uint32_t blobLength = 8 + typeNameLength + (uint32_t)signatureLength;
    uint8_t* signature = malloc(blobLength + 4);
    if (signature == NULL)
    {
        return NULL;
    }
    
    // Sign the data in place in the blob buffer.
    int signatureIndex = 12 + typeNameLength;
    int result = crypto_sign_ed25519(signature + signatureIndex, &signatureLength, data, dataSize, (uint8_t*)getKeyEd25519Private(key));
    if (result != 0)
    {
        free(signature);
        return NULL;
    }
    
    // Recalculate the blob length now that we have the final length of the ED25519 signature and format the rest of the blob.
    blobLength = 8 + typeNameLength + (uint32_t)signatureLength;
    pack32(signature, blobLength);
    int index = 4;
    pack32(signature + index, typeNameLength);
    index += 4;
    memcpy(signature + index, "ssh-ed25519", typeNameLength);
    index += typeNameLength;
    pack32(signature + index, (uint32_t)signatureLength);
    
    return (ssh_string)signature;
}


ssh_string SshAgentSign(uint8_t* data, int dataSize, ssh_key key, uint32_t flags)
{
    switch (ssh_key_type(key))
    {
        case SSH_KEYTYPE_DSS:
            return SshAgentSignDss(data, dataSize, key, flags);
            
        case SSH_KEYTYPE_RSA:
        case SSH_KEYTYPE_RSA1:
            return SshAgentSignRsa(data, dataSize, key, flags);
            
        case SSH_KEYTYPE_ECDSA:
            return SshAgentSignEcdsa(data, dataSize, key, flags);
            
        case SSH_KEYTYPE_ED25519:
            return SshAgentSignEd25519(data, dataSize, key, flags);
            
        default:
            return NULL;
    }
}


uint8_t* SshAgentMakeSignatureReply(SshAgentContext* context, uint8_t* request, int requestSize)
{
    if (context->isLocked)
    {
        return SshAgentMakeErrorReply();
    }
    
    // Find the private key matching the public key from the request.
    int publicBlobIndex = 1;
    uint32_t publicBlobSize = unpack32(request + publicBlobIndex);
    int dataIndex = publicBlobIndex + 4 + publicBlobSize;
    uint32_t dataSize = unpack32(request + dataIndex);
    int flagsIndex = dataIndex + 4 + dataSize;
    uint32_t flags;
    memcpy(&flags, request + flagsIndex, 4);
    
    if (flags != 0)
    {
        return SshAgentMakeErrorReply();
    }
    
    int i;
    for (i = 0; i < context->keyCount; i++)
    {
        ssh_string blob;
        int sshResult = ssh_pki_export_pubkey_blob(context->keys[i], &blob);
        if (sshResult == SSH_OK)
        {
            int cmpResult = memcmp(request + publicBlobIndex, blob, publicBlobSize);
            ssh_string_free(blob);
            if (cmpResult == 0)
            {
                break;
            }
        }
    }
    if (i >= context->keyCount)
    {
        return SshAgentMakeErrorReply();
    }
    
    // Sign the data and return it in a message of the form:
    // messageLength[ SSH2_AGENT_SIGN_RESPONSE signatureBlob]
    ssh_string signatureBlob = SshAgentSign(request + dataIndex + 4, dataSize, context->keys[i], flags);
    if (signatureBlob == NULL)
    {
        return SshAgentMakeErrorReply();
    }
    
    uint32_t signatureBlobLength = unpack32((uint8_t*)signatureBlob);
    int messageLength = 5 + signatureBlobLength;
    uint8_t* message = malloc(messageLength + 4);
    if (message == NULL)
    {
        free(signatureBlob);
        return SshAgentMakeErrorReply();
    }
    pack32(message, messageLength);
    message[4] = SSH2_AGENT_SIGN_RESPONSE;
    memcpy(message + 5, signatureBlob, signatureBlobLength + 4);
    free(signatureBlob);
    
    return message;
}


uint8_t* SshAgentProcessLockRequest(SshAgentContext* context, uint8_t* request, int requestSize)
{
    if (context->isLocked)
    {
        return SshAgentMakeErrorReply();
    }
    
    int passwordLength = unpack32(request + 1);
    context->lockPassword = malloc(passwordLength + 1);
    if (context->lockPassword == NULL)
    {
        return SshAgentMakeErrorReply();
    }
    memcpy(context->lockPassword, request + 5, passwordLength);
    context->lockPassword[passwordLength] = 0;
    context->isLocked = 1;
    
    return SshAgentMakeSuccessReply();
}

uint8_t* SshAgentProcessUnlockRequest(SshAgentContext* context, uint8_t* request, int requestSize)
{
    if (context->isLocked == 0)
    {
        return SshAgentMakeErrorReply();
    }
    
    int passwordLength = unpack32(request + 1);
    if (strncmp(context->lockPassword, (char*)request + 5, passwordLength) != 0)
    {
        return SshAgentMakeErrorReply();
    }
    
    context->isLocked = 0;
    free(context->lockPassword);
    context->lockPassword = NULL;
    
    return SshAgentMakeSuccessReply();
}

int SshAgentAddKey(SshAgentContext* context, ssh_key key)
{
    if (context->keys == NULL)
    {
        context->keys = malloc(sizeof(ssh_key));
        if (context->keys == NULL)
        {
            return -1;
        }
    }
    else
    {
        ssh_key* temp = realloc(context->keys, sizeof(ssh_key) * (context->keyCount + 1));
        if (temp == NULL)
        {
            return -1;
        }
        context->keys = temp;
    }
    
    context->keys[context->keyCount] = key;
    context->keyCount++;
    
    return 0;
}


uint8_t* SshAgentReplyFromRequest(SshAgentContext* context, uint8_t* request, int requestSize)
{
    switch (request[0])
    {
        case SSH2_AGENTC_REQUEST_IDENTITIES:
            return SshAgentMakeIdentityListReply(context);
            
        case SSH2_AGENTC_SIGN_REQUEST:
            return SshAgentMakeSignatureReply(context, request, requestSize);
            
        case SSH_AGENTC_LOCK:
            return SshAgentProcessLockRequest(context, request, requestSize);
            
        case SSH_AGENTC_UNLOCK:
            return SshAgentProcessUnlockRequest(context, request, requestSize);
            
        // Unsupported message types.
        case SSH_AGENTC_ADD_RSA_IDENTITY:
        case SSH_AGENTC_ADD_RSA_ID_CONSTRAINED:
            return SshAgentMakeErrorReply();
            
        case SSH2_AGENTC_ADD_IDENTITY:
        case SSH2_AGENTC_ADD_ID_CONSTRAINED:
            return SshAgentMakeErrorReply();
            
        case SSH_AGENTC_ADD_SMARTCARD_KEY:
        case SSH_AGENTC_ADD_SMARTCARD_KEY_CONSTRAINED:
            return SshAgentMakeErrorReply();
            
        case SSH_AGENTC_REMOVE_ALL_RSA_IDENTITIES:
        case SSH_AGENTC_REMOVE_RSA_IDENTITY:
            return SshAgentMakeErrorReply();
            
        case SSH2_AGENTC_REMOVE_ALL_IDENTITIES:
        case SSH2_AGENTC_REMOVE_IDENTITY:
            return SshAgentMakeErrorReply();
            
        case SSH_AGENTC_REMOVE_SMARTCARD_KEY:
            return SshAgentMakeErrorReply();
            
        case SSH_AGENTC_REQUEST_RSA_IDENTITIES:
            return SshAgentMakeErrorReply();
            
        case SSH_AGENTC_RSA_CHALLENGE:
            return SshAgentMakeErrorReply();
    }

    return NULL;
}


void SshAgentRelease(SshAgentContext* context)
{
    for (int i = 0; i < context->keyCount; i++)
    {
        ssh_key_free(context->keys[i]);
    }
    free(context->keys);
}


SshAgentContext* SshAgentNew()
{
    SshAgentContext* context = calloc(1, sizeof(SshAgentContext));
    if (context != NULL)
    {

    }
    
    return context;
}


