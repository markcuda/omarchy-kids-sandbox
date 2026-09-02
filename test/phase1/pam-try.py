#!/usr/bin/env python3
"""Authenticate USER with PASSWORD against PAM service SERVICE using libpam via ctypes.
Usage: pam-try.py SERVICE USER PASSWORD -> prints 'PAM_SUCCESS' or the error name, exit 0/1."""
import ctypes, ctypes.util, sys
svc, user, pw = sys.argv[1], sys.argv[2], sys.argv[3]
libpam = ctypes.CDLL(ctypes.util.find_library("pam") or "libpam.so.0")
class PamMessage(ctypes.Structure): _fields_=[("msg_style",ctypes.c_int),("msg",ctypes.c_char_p)]
class PamResponse(ctypes.Structure): _fields_=[("resp",ctypes.c_char_p),("resp_retcode",ctypes.c_int)]
CONV=ctypes.CFUNCTYPE(ctypes.c_int,ctypes.c_int,ctypes.POINTER(ctypes.POINTER(PamMessage)),ctypes.POINTER(ctypes.POINTER(PamResponse)),ctypes.c_void_p)
class PamConv(ctypes.Structure): _fields_=[("conv",CONV),("appdata_ptr",ctypes.c_void_p)]
calloc=ctypes.CDLL(None).calloc; calloc.restype=ctypes.c_void_p; strdup=ctypes.CDLL(None).strdup; strdup.restype=ctypes.c_void_p
def conv(n, msgs, resp, data):
    arr = ctypes.cast(calloc(n, ctypes.sizeof(PamResponse)), ctypes.POINTER(PamResponse))
    for i in range(n):
        style = msgs[i].contents.msg_style
        arr[i].resp = ctypes.cast(strdup(pw.encode()), ctypes.c_char_p) if style in (1,2) else None  # 1=PROMPT_ECHO_OFF 2=ECHO_ON
        arr[i].resp_retcode = 0
    resp[0] = arr; return 0
handle=ctypes.c_void_p(); c=PamConv(CONV(conv), None)
r=libpam.pam_start(svc.encode(), user.encode(), ctypes.byref(c), ctypes.byref(handle))
if r!=0: print("pam_start failed", r); sys.exit(1)
r=libpam.pam_authenticate(handle, 0)
libpam.pam_strerror.restype=ctypes.c_char_p
print("PAM_SUCCESS" if r==0 else libpam.pam_strerror(handle, r).decode()); libpam.pam_end(handle, r); sys.exit(0 if r==0 else 1)
