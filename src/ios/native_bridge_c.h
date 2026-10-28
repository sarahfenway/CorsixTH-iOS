// The C side of the native UI bridge, as seen from Swift (implemented in
// src/native_bridge.cpp).
#ifndef CORSIX_TH_NATIVE_BRIDGE_C_H_
#define CORSIX_TH_NATIVE_BRIDGE_C_H_

#ifdef __cplusplus
extern "C" {
#endif

//! Queues an action (with a JSON object payload) for the Lua UI.
void cth_native_post(const char* action, const char* json);

#ifdef __cplusplus
}
#endif

#endif  // CORSIX_TH_NATIVE_BRIDGE_C_H_
