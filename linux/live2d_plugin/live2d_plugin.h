/*
 * Live2D Flutter Plugin
 * Copyright 2025 kozakemi
 */

#ifndef LIVE2D_PLUGIN_H_
#define LIVE2D_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

/**
 * live2d_plugin_register_with_registrar:
 * @registrar: the plugin registrar
 *
 * Registers the Live2D plugin with the given registrar.
 */
void live2d_plugin_register_with_registrar(FlPluginRegistrar* registrar);

G_END_DECLS

#endif  // LIVE2D_PLUGIN_H_

