/*  =========================================================================
    czmq - generated layer of public API

    Copyright (c) the Contributors as noted in the AUTHORS file.
    This file is part of CZMQ, the high-level C binding for 0MQ:
    http://czmq.zeromq.org.

    This Source Code Form is subject to the terms of the Mozilla Public
    License, v. 2.0. If a copy of the MPL was not distributed with this
    file, You can obtain one at http://mozilla.org/MPL/2.0/.

################################################################################
#  THIS FILE IS 100% GENERATED BY ZPROJECT; DO NOT EDIT EXCEPT EXPERIMENTALLY  #
#  Read the zproject/README.md for information about making permanent changes. #
################################################################################
    =========================================================================
*/

extern (C):

//  Set up environment for the application

//  External dependencies

//  CZMQ version macros for compile-time API detection
enum CZMQ_VERSION_MAJOR = 4;
enum CZMQ_VERSION_MINOR = 0;
enum CZMQ_VERSION_PATCH = 2;

extern (D) auto CZMQ_MAKE_VERSION(T0, T1, T2)(auto ref T0 major, auto ref T1 minor, auto ref T2 patch)
{
    return major * 10000 + minor * 100 + patch;
}

enum CZMQ_VERSION = CZMQ_MAKE_VERSION(CZMQ_VERSION_MAJOR, CZMQ_VERSION_MINOR, CZMQ_VERSION_PATCH);

//  Opaque class structures to allow forward references
//  These classes are stable or legacy and built in all releases
struct _zactor_t;
alias zactor_t = _zactor_t;
struct _zarmour_t;
alias zarmour_t = _zarmour_t;
struct _zcert_t;
alias zcert_t = _zcert_t;
struct _zcertstore_t;
alias zcertstore_t = _zcertstore_t;
struct _zchunk_t;
alias zchunk_t = _zchunk_t;
struct _zclock_t;
alias zclock_t = _zclock_t;
struct _zconfig_t;
alias zconfig_t = _zconfig_t;
struct _zdigest_t;
alias zdigest_t = _zdigest_t;
struct _zdir_t;
alias zdir_t = _zdir_t;
struct _zdir_patch_t;
alias zdir_patch_t = _zdir_patch_t;
struct _zfile_t;
alias zfile_t = _zfile_t;
struct _zframe_t;
alias zframe_t = _zframe_t;
struct _zhash_t;
alias zhash_t = _zhash_t;
struct _zhashx_t;
alias zhashx_t = _zhashx_t;
struct _ziflist_t;
alias ziflist_t = _ziflist_t;
struct _zlist_t;
alias zlist_t = _zlist_t;
struct _zlistx_t;
alias zlistx_t = _zlistx_t;
struct _zloop_t;
alias zloop_t = _zloop_t;
struct _zmsg_t;
alias zmsg_t = _zmsg_t;
struct _zpoller_t;
alias zpoller_t = _zpoller_t;
struct _zsock_t;
alias zsock_t = _zsock_t;
struct _zstr_t;
alias zstr_t = _zstr_t;
struct _zuuid_t;
alias zuuid_t = _zuuid_t;
struct _zauth_t;
alias zauth_t = _zauth_t;
struct _zbeacon_t;
alias zbeacon_t = _zbeacon_t;
struct _zgossip_t;
alias zgossip_t = _zgossip_t;
struct _zmonitor_t;
alias zmonitor_t = _zmonitor_t;
struct _zproxy_t;
alias zproxy_t = _zproxy_t;
struct _zrex_t;
alias zrex_t = _zrex_t;
struct _zsys_t;
alias zsys_t = _zsys_t;
//  Draft classes are by default not built in stable releases

// CZMQ_BUILD_DRAFT_API

//  Public classes, each with its own header file

// CZMQ_BUILD_DRAFT_API

/*
################################################################################
#  THIS FILE IS 100% GENERATED BY ZPROJECT; DO NOT EDIT EXCEPT EXPERIMENTALLY  #
#  Read the zproject/README.md for information about making permanent changes. #
################################################################################
*/
