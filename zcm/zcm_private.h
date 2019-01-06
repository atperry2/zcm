/* This file hides some internal data structs from public header files */
#ifndef _ZCM_PRIVATE_H
#define _ZCM_PRIVATE_H

#include "zcm.h"

#ifdef __cplusplus
extern "C" {
#endif

/* A subscription descriptor object */
struct zcm_sub_t
{
    zchar_t channel[ZCM_CHANNEL_MAXLEN + 1];
    bool regex;
    void *regexobj;
    zcm_msg_handler_t callback;
    void *usr;
};

#ifdef __cplusplus
}
#endif

#endif
