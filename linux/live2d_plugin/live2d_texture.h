/*
 * Live2D Flutter Texture Plugin
 * Copyright 2025 kozakemi
 */

#ifndef LIVE2D_TEXTURE_H_
#define LIVE2D_TEXTURE_H_

#include <flutter_linux/flutter_linux.h>
#include <cstdint>
#include <mutex>
#include <atomic>

G_BEGIN_DECLS

#define LIVE2D_TYPE_TEXTURE (live2d_texture_get_type())

G_DECLARE_FINAL_TYPE(Live2DTexture, live2d_texture, LIVE2D, TEXTURE, FlPixelBufferTexture)

/**
 * live2d_texture_new:
 * @width: texture width in pixels
 * @height: texture height in pixels
 *
 * Creates a new Live2D texture.
 *
 * Returns: a new #Live2DTexture
 */
Live2DTexture* live2d_texture_new(uint32_t width, uint32_t height);

/**
 * live2d_texture_get_width:
 * @texture: a #Live2DTexture
 *
 * Returns: the width of the texture
 */
uint32_t live2d_texture_get_width(Live2DTexture* texture);

/**
 * live2d_texture_get_height:
 * @texture: a #Live2DTexture
 *
 * Returns: the height of the texture
 */
uint32_t live2d_texture_get_height(Live2DTexture* texture);

/**
 * live2d_texture_get_buffer:
 * @texture: a #Live2DTexture
 *
 * Returns: pointer to the pixel buffer (RGBA format)
 */
uint8_t* live2d_texture_get_buffer(Live2DTexture* texture);

/**
 * live2d_texture_lock:
 * @texture: a #Live2DTexture
 *
 * Lock the texture for thread-safe access
 */
void live2d_texture_lock(Live2DTexture* texture);

/**
 * live2d_texture_unlock:
 * @texture: a #Live2DTexture
 *
 * Unlock the texture
 */
void live2d_texture_unlock(Live2DTexture* texture);

/**
 * live2d_texture_mark_dirty:
 * @texture: a #Live2DTexture
 *
 * Mark the texture as needing update
 */
void live2d_texture_mark_dirty(Live2DTexture* texture);

G_END_DECLS

#endif  // LIVE2D_TEXTURE_H_

