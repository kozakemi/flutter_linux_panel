/*
 * Live2D Flutter Texture Plugin
 * Copyright 2025 kozakemi
 */

#include "live2d_texture.h"
#include <cstring>
#include <mutex>

struct _Live2DTexture {
  FlPixelBufferTexture parent_instance;
  
  uint32_t width;
  uint32_t height;
  uint8_t* buffer;
  std::mutex* mutex;
  bool dirty;
};

G_DEFINE_TYPE(Live2DTexture, live2d_texture, fl_pixel_buffer_texture_get_type())

static gboolean live2d_texture_copy_pixels(FlPixelBufferTexture* texture,
                                           const uint8_t** out_buffer,
                                           uint32_t* width,
                                           uint32_t* height,
                                           GError** error) {
  Live2DTexture* self = LIVE2D_TEXTURE(texture);
  
  if (self->buffer == nullptr) {
    g_set_error(error, g_quark_from_string("live2d"), 1, "Buffer not initialized");
    return FALSE;
  }
  
  // Thread-safe access
  std::lock_guard<std::mutex> lock(*self->mutex);
  
  *out_buffer = self->buffer;
  *width = self->width;
  *height = self->height;
  
  return TRUE;
}

static void live2d_texture_dispose(GObject* object) {
  Live2DTexture* self = LIVE2D_TEXTURE(object);
  
  if (self->buffer != nullptr) {
    delete[] self->buffer;
    self->buffer = nullptr;
  }
  
  if (self->mutex != nullptr) {
    delete self->mutex;
    self->mutex = nullptr;
  }
  
  G_OBJECT_CLASS(live2d_texture_parent_class)->dispose(object);
}

static void live2d_texture_class_init(Live2DTextureClass* klass) {
  FL_PIXEL_BUFFER_TEXTURE_CLASS(klass)->copy_pixels = live2d_texture_copy_pixels;
  G_OBJECT_CLASS(klass)->dispose = live2d_texture_dispose;
}

static void live2d_texture_init(Live2DTexture* self) {
  self->width = 0;
  self->height = 0;
  self->buffer = nullptr;
  self->mutex = new std::mutex();
  self->dirty = false;
}

Live2DTexture* live2d_texture_new(uint32_t width, uint32_t height) {
  Live2DTexture* texture = LIVE2D_TEXTURE(g_object_new(LIVE2D_TYPE_TEXTURE, nullptr));
  
  texture->width = width;
  texture->height = height;
  texture->buffer = new uint8_t[width * height * 4];
  
  // Initialize to transparent black
  memset(texture->buffer, 0, width * height * 4);
  
  return texture;
}

uint32_t live2d_texture_get_width(Live2DTexture* texture) {
  return texture->width;
}

uint32_t live2d_texture_get_height(Live2DTexture* texture) {
  return texture->height;
}

uint8_t* live2d_texture_get_buffer(Live2DTexture* texture) {
  return texture->buffer;
}

void live2d_texture_lock(Live2DTexture* texture) {
  if (texture->mutex) {
    texture->mutex->lock();
  }
}

void live2d_texture_unlock(Live2DTexture* texture) {
  if (texture->mutex) {
    texture->mutex->unlock();
  }
}

void live2d_texture_mark_dirty(Live2DTexture* texture) {
  texture->dirty = true;
}

