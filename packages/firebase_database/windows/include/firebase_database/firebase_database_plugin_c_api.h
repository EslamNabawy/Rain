/*
 * Copyright 2025, the Chromium project authors.  Please see the AUTHORS file
 * for details. All rights reserved. Use of this source code is governed by a
 * BSD-style license that can be found in the LICENSE file.
 */

#ifndef FLUTTER_PLUGIN_FIREBASE_DATABASE_PLUGIN_C_API_H_
#define FLUTTER_PLUGIN_FIREBASE_DATABASE_PLUGIN_C_API_H_

#include <flutter_plugin_registrar.h>
#include <windows.h>

#if defined(__cplusplus)
#include <flutter/flutter_engine.h>
#endif

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FLUTTER_PLUGIN_EXPORT __declspec(dllimport)
#endif

#if defined(__cplusplus)
extern "C" {
#endif

FLUTTER_PLUGIN_EXPORT void FirebaseDatabasePluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);

#if defined(__cplusplus)
}  // extern "C"
#endif

#if defined(__cplusplus)
// Installs the engine used to marshal Firebase worker callbacks onto Flutter's
// platform thread. The runner clears this before destroying the engine.
FLUTTER_PLUGIN_EXPORT void FirebaseDatabasePluginCApiSetFlutterEngine(
    flutter::FlutterEngine* engine);
FLUTTER_PLUGIN_EXPORT void FirebaseDatabasePluginCApiSetFlutterWindow(
    HWND window);
FLUTTER_PLUGIN_EXPORT void FirebaseDatabasePluginCApiDrainPlatformThreadTasks();
#endif

#endif /* FLUTTER_PLUGIN_FIREBASE_DATABASE_PLUGIN_C_API_H_ */
