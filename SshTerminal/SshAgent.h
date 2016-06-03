

#ifndef __SshAgent_h__
#define __SshAgent_h__

#include <stdio.h>
#include "SshFoundation.h"

#define SSH_AGENTC_REQUEST_RSA_IDENTITIES               1
#define SSH_AGENTC_RSA_CHALLENGE                        3
#define SSH_AGENTC_ADD_RSA_IDENTITY                     7
#define SSH_AGENTC_REMOVE_RSA_IDENTITY                  8
#define SSH_AGENTC_REMOVE_ALL_RSA_IDENTITIES            9
#define SSH_AGENTC_ADD_RSA_ID_CONSTRAINED               24
#define SSH2_AGENTC_REQUEST_IDENTITIES                  11
#define SSH2_AGENTC_SIGN_REQUEST                        13
#define SSH2_AGENTC_ADD_IDENTITY                        17
#define SSH2_AGENTC_REMOVE_IDENTITY                     18
#define SSH2_AGENTC_REMOVE_ALL_IDENTITIES               19
#define SSH2_AGENTC_ADD_ID_CONSTRAINED                  25
#define SSH_AGENTC_ADD_SMARTCARD_KEY                    20
#define SSH_AGENTC_REMOVE_SMARTCARD_KEY                 21
#define SSH_AGENTC_LOCK                                 22
#define SSH_AGENTC_UNLOCK                               23
#define SSH_AGENTC_ADD_SMARTCARD_KEY_CONSTRAINED        26
#define SSH_AGENT_FAILURE                               5
#define SSH_AGENT_SUCCESS                               6
#define SSH_AGENT_RSA_IDENTITIES_ANSWER                 2
#define SSH_AGENT_RSA_RESPONSE                          4
#define SSH2_AGENT_IDENTITIES_ANSWER                    12
#define SSH2_AGENT_SIGN_RESPONSE                        14
#define SSH_AGENT_CONSTRAIN_LIFETIME                    1
#define SSH_AGENT_CONSTRAIN_CONFIRM                     2

#define	SSH_AGENT_OLD_SIGNATURE			0x01
#define	SSH_AGENT_RSA_SHA2_256			0x02
#define	SSH_AGENT_RSA_SHA2_512			0x04


typedef struct _SshAgentContext
{
    ssh_key* keys;
    char* lockPassword;
    int keyCount;
    char isLocked;
} SshAgentContext;


int SshAgentAddKey(SshAgentContext* context, ssh_key key);
uint8_t* SshAgentReplyFromRequest(SshAgentContext* context, uint8_t* request, int requestSize);

SshAgentContext* SshAgentNew(ssh_session session);
void SshAgentRelease(SshAgentContext* context);

#endif


