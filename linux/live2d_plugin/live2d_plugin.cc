/*
 * Live2D Flutter Plugin
 * Copyright 2025 kozakemi
 */

#include "live2d_plugin.h"
#include "live2d_texture.h"
#include "live2d_renderer.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <cstring>
#include <memory>

// Define the plugin type
struct _Live2DPlugin {
  GObject parent_instance;
  
  FlPluginRegistrar* registrar;
  FlMethodChannel* channel;
  FlTextureRegistrar* texture_registrar;
  
  Live2DTexture* texture;
  int64_t texture_id;
  
  Live2DRenderer* renderer;
  guint render_timer_id;
  gboolean is_running;
};

// Declare the type
G_DECLARE_FINAL_TYPE(Live2DPlugin, live2d_plugin, LIVE2D, PLUGIN, GObject)

// Define the type
G_DEFINE_TYPE(Live2DPlugin, live2d_plugin, G_TYPE_OBJECT)

static void live2d_plugin_dispose(GObject* object);
static void method_call_handler(FlMethodChannel* channel,
                                FlMethodCall* method_call,
                                gpointer user_data);

static void live2d_plugin_class_init(Live2DPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = live2d_plugin_dispose;
}

static void live2d_plugin_init(Live2DPlugin* self) {
  self->texture = nullptr;
  self->texture_id = -1;
  self->renderer = nullptr;
  self->render_timer_id = 0;
  self->is_running = FALSE;
}

static void live2d_plugin_dispose(GObject* object) {
  Live2DPlugin* self = LIVE2D_PLUGIN(object);
  
  // Stop render timer
  if (self->render_timer_id != 0) {
    g_source_remove(self->render_timer_id);
    self->render_timer_id = 0;
  }
  
  // Cleanup renderer
  if (self->renderer != nullptr) {
    live2d_renderer_destroy(self->renderer);
    self->renderer = nullptr;
  }
  
  // Unregister texture
  if (self->texture != nullptr && self->texture_registrar != nullptr) {
    fl_texture_registrar_unregister_texture(self->texture_registrar, 
                                            FL_TEXTURE(self->texture));
    g_object_unref(self->texture);
    self->texture = nullptr;
  }
  
  g_clear_object(&self->channel);
  
  G_OBJECT_CLASS(live2d_plugin_parent_class)->dispose(object);
}

static gboolean render_callback(gpointer user_data) {
  Live2DPlugin* self = LIVE2D_PLUGIN(user_data);
  
  if (!self->is_running || self->renderer == nullptr || self->texture == nullptr) {
    return G_SOURCE_CONTINUE;
  }
  
  // Lock texture and render
  live2d_texture_lock(self->texture);
  
  // Get buffer and render Live2D frame
  uint8_t* buffer = live2d_texture_get_buffer(self->texture);
  uint32_t width = live2d_texture_get_width(self->texture);
  uint32_t height = live2d_texture_get_height(self->texture);
  
  live2d_renderer_render(self->renderer, buffer, width, height);
  
  live2d_texture_unlock(self->texture);
  
  // Mark texture as updated
  fl_texture_registrar_mark_texture_frame_available(self->texture_registrar,
                                                    FL_TEXTURE(self->texture));
  
  return G_SOURCE_CONTINUE;
}

static void handle_initialize(Live2DPlugin* self, FlMethodCall* method_call) {
  FlValue* args = fl_method_call_get_args(method_call);
  
  int64_t width = 800;
  int64_t height = 600;
  const gchar* model_path = nullptr;
  
  if (fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
    FlValue* w = fl_value_lookup_string(args, "width");
    FlValue* h = fl_value_lookup_string(args, "height");
    FlValue* path = fl_value_lookup_string(args, "modelPath");
    
    if (w && fl_value_get_type(w) == FL_VALUE_TYPE_INT) {
      width = fl_value_get_int(w);
    }
    if (h && fl_value_get_type(h) == FL_VALUE_TYPE_INT) {
      height = fl_value_get_int(h);
    }
    if (path && fl_value_get_type(path) == FL_VALUE_TYPE_STRING) {
      model_path = fl_value_get_string(path);
    }
  }
  
  // Create texture
  self->texture = live2d_texture_new(width, height);
  
  // Register texture with Flutter
  if (!fl_texture_registrar_register_texture(self->texture_registrar,
                                              FL_TEXTURE(self->texture))) {
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_error_response_new("TEXTURE_ERROR", "Failed to register texture", nullptr));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }
  
  self->texture_id = fl_texture_get_id(FL_TEXTURE(self->texture));
  
  // Initialize Live2D renderer
  self->renderer = live2d_renderer_create(width, height, model_path);
  if (self->renderer == nullptr) {
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_error_response_new("RENDERER_ERROR", "Failed to initialize renderer", nullptr));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }
  
  // Return texture ID
  g_autoptr(FlValue) result = fl_value_new_int(self->texture_id);
  g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
      fl_method_success_response_new(result));
  fl_method_call_respond(method_call, response, nullptr);
}

static void handle_start(Live2DPlugin* self, FlMethodCall* method_call) {
  if (self->texture == nullptr || self->renderer == nullptr) {
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_error_response_new("NOT_INITIALIZED", "Plugin not initialized", nullptr));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }
  
  if (!self->is_running) {
    self->is_running = TRUE;
    
    // Start render timer (~60 FPS)
    if (self->render_timer_id == 0) {
      self->render_timer_id = g_timeout_add(16, render_callback, self);
    }
  }
  
  g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
      fl_method_success_response_new(fl_value_new_bool(TRUE)));
  fl_method_call_respond(method_call, response, nullptr);
}

static void handle_stop(Live2DPlugin* self, FlMethodCall* method_call) {
  self->is_running = FALSE;
  
  g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
      fl_method_success_response_new(fl_value_new_bool(TRUE)));
  fl_method_call_respond(method_call, response, nullptr);
}

static void handle_dispose(Live2DPlugin* self, FlMethodCall* method_call) {
  // Stop rendering
  self->is_running = FALSE;
  
  if (self->render_timer_id != 0) {
    g_source_remove(self->render_timer_id);
    self->render_timer_id = 0;
  }
  
  // Cleanup renderer
  if (self->renderer != nullptr) {
    live2d_renderer_destroy(self->renderer);
    self->renderer = nullptr;
  }
  
  // Unregister texture
  if (self->texture != nullptr && self->texture_registrar != nullptr) {
    fl_texture_registrar_unregister_texture(self->texture_registrar,
                                            FL_TEXTURE(self->texture));
    g_object_unref(self->texture);
    self->texture = nullptr;
    self->texture_id = -1;
  }
  
  g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
      fl_method_success_response_new(fl_value_new_bool(TRUE)));
  fl_method_call_respond(method_call, response, nullptr);
}

static void handle_touch(Live2DPlugin* self, FlMethodCall* method_call) {
  if (self->renderer == nullptr) {
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_bool(FALSE)));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }
  
  FlValue* args = fl_method_call_get_args(method_call);
  
  if (fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
    FlValue* x_val = fl_value_lookup_string(args, "x");
    FlValue* y_val = fl_value_lookup_string(args, "y");
    FlValue* type_val = fl_value_lookup_string(args, "type");
    
    double x = 0, y = 0;
    const gchar* type = "move";
    
    if (x_val && fl_value_get_type(x_val) == FL_VALUE_TYPE_FLOAT) {
      x = fl_value_get_float(x_val);
    }
    if (y_val && fl_value_get_type(y_val) == FL_VALUE_TYPE_FLOAT) {
      y = fl_value_get_float(y_val);
    }
    if (type_val && fl_value_get_type(type_val) == FL_VALUE_TYPE_STRING) {
      type = fl_value_get_string(type_val);
    }
    
    live2d_renderer_on_touch(self->renderer, x, y, type);
  }
  
  g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
      fl_method_success_response_new(fl_value_new_bool(TRUE)));
  fl_method_call_respond(method_call, response, nullptr);
}

static void handle_set_scale(Live2DPlugin* self, FlMethodCall* method_call) {
  if (self->renderer == nullptr) {
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_bool(FALSE)));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }
  
  FlValue* args = fl_method_call_get_args(method_call);
  
  if (fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
    FlValue* scale_val = fl_value_lookup_string(args, "scale");
    
    float scale = 1.0f;
    if (scale_val && fl_value_get_type(scale_val) == FL_VALUE_TYPE_FLOAT) {
      scale = (float)fl_value_get_float(scale_val);
    }
    
    live2d_renderer_set_scale(self->renderer, scale);
  }
  
  g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
      fl_method_success_response_new(fl_value_new_bool(TRUE)));
  fl_method_call_respond(method_call, response, nullptr);
}

static void handle_set_offset(Live2DPlugin* self, FlMethodCall* method_call) {
  if (self->renderer == nullptr) {
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_bool(FALSE)));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }
  
  FlValue* args = fl_method_call_get_args(method_call);
  
  if (fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
    FlValue* x_val = fl_value_lookup_string(args, "offsetX");
    FlValue* y_val = fl_value_lookup_string(args, "offsetY");
    
    float offsetX = 0.0f, offsetY = 0.0f;
    if (x_val && fl_value_get_type(x_val) == FL_VALUE_TYPE_FLOAT) {
      offsetX = (float)fl_value_get_float(x_val);
    }
    if (y_val && fl_value_get_type(y_val) == FL_VALUE_TYPE_FLOAT) {
      offsetY = (float)fl_value_get_float(y_val);
    }
    
    live2d_renderer_set_offset(self->renderer, offsetX, offsetY);
  }
  
  g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
      fl_method_success_response_new(fl_value_new_bool(TRUE)));
  fl_method_call_respond(method_call, response, nullptr);
}

static void handle_get_transform(Live2DPlugin* self, FlMethodCall* method_call) {
  if (self->renderer == nullptr) {
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_error_response_new("NOT_INITIALIZED", "Renderer not initialized", nullptr));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }
  
  float scale = live2d_renderer_get_scale(self->renderer);
  float offsetX = live2d_renderer_get_offset_x(self->renderer);
  float offsetY = live2d_renderer_get_offset_y(self->renderer);
  
  g_autoptr(FlValue) result = fl_value_new_map();
  fl_value_set_string_take(result, "scale", fl_value_new_float(scale));
  fl_value_set_string_take(result, "offsetX", fl_value_new_float(offsetX));
  fl_value_set_string_take(result, "offsetY", fl_value_new_float(offsetY));
  
  g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
      fl_method_success_response_new(result));
  fl_method_call_respond(method_call, response, nullptr);
}

static void method_call_handler(FlMethodChannel* channel,
                                FlMethodCall* method_call,
                                gpointer user_data) {
  Live2DPlugin* self = LIVE2D_PLUGIN(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  
  if (strcmp(method, "initialize") == 0) {
    handle_initialize(self, method_call);
  } else if (strcmp(method, "start") == 0) {
    handle_start(self, method_call);
  } else if (strcmp(method, "stop") == 0) {
    handle_stop(self, method_call);
  } else if (strcmp(method, "dispose") == 0) {
    handle_dispose(self, method_call);
  } else if (strcmp(method, "touch") == 0) {
    handle_touch(self, method_call);
  } else if (strcmp(method, "setScale") == 0) {
    handle_set_scale(self, method_call);
  } else if (strcmp(method, "setOffset") == 0) {
    handle_set_offset(self, method_call);
  } else if (strcmp(method, "getTransform") == 0) {
    handle_get_transform(self, method_call);
  } else {
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_not_implemented_response_new());
    fl_method_call_respond(method_call, response, nullptr);
  }
}

void live2d_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  Live2DPlugin* plugin = LIVE2D_PLUGIN(
      g_object_new(live2d_plugin_get_type(), nullptr));
  
  plugin->registrar = registrar;
  plugin->texture_registrar = fl_plugin_registrar_get_texture_registrar(registrar);
  
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  plugin->channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "com.example.demo1/live2d",
      FL_METHOD_CODEC(codec));
  
  fl_method_channel_set_method_call_handler(
      plugin->channel, method_call_handler, plugin, g_object_unref);
}
