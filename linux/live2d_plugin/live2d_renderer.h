/*
 * Live2D Renderer for Flutter Plugin
 * Copyright 2025 kozakemi
 */

#ifndef LIVE2D_RENDERER_H_
#define LIVE2D_RENDERER_H_

#include <cstdint>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct Live2DRenderer Live2DRenderer;

/**
 * live2d_renderer_create:
 * @width: render target width
 * @height: render target height
 * @model_path: path to Live2D model (optional, can be NULL for default)
 *
 * Creates a new Live2D renderer with off-screen rendering support.
 *
 * Returns: a new #Live2DRenderer or NULL on failure
 */
Live2DRenderer* live2d_renderer_create(uint32_t width, uint32_t height, const char* model_path);

/**
 * live2d_renderer_destroy:
 * @renderer: a #Live2DRenderer
 *
 * Destroys the renderer and releases all resources.
 */
void live2d_renderer_destroy(Live2DRenderer* renderer);

/**
 * live2d_renderer_render:
 * @renderer: a #Live2DRenderer
 * @buffer: RGBA pixel buffer to render into
 * @width: buffer width
 * @height: buffer height
 *
 * Renders a frame to the pixel buffer.
 */
void live2d_renderer_render(Live2DRenderer* renderer, uint8_t* buffer, uint32_t width, uint32_t height);

/**
 * live2d_renderer_on_touch:
 * @renderer: a #Live2DRenderer
 * @x: touch x coordinate (0.0 to 1.0)
 * @y: touch y coordinate (0.0 to 1.0)
 * @type: touch type ("down", "move", "up")
 *
 * Handle touch input for model interaction.
 */
void live2d_renderer_on_touch(Live2DRenderer* renderer, double x, double y, const char* type);

/**
 * live2d_renderer_resize:
 * @renderer: a #Live2DRenderer
 * @width: new width
 * @height: new height
 *
 * Resize the render target.
 */
void live2d_renderer_resize(Live2DRenderer* renderer, uint32_t width, uint32_t height);

/**
 * live2d_renderer_set_scale:
 * @renderer: a #Live2DRenderer
 * @scale: model scale factor (1.0 = default)
 *
 * Set the model scale.
 */
void live2d_renderer_set_scale(Live2DRenderer* renderer, float scale);

/**
 * live2d_renderer_set_offset:
 * @renderer: a #Live2DRenderer
 * @offsetX: horizontal offset (-1.0 to 1.0)
 * @offsetY: vertical offset (-1.0 to 1.0)
 *
 * Set the model position offset.
 */
void live2d_renderer_set_offset(Live2DRenderer* renderer, float offsetX, float offsetY);

/**
 * live2d_renderer_get_scale:
 * @renderer: a #Live2DRenderer
 *
 * Returns: current model scale
 */
float live2d_renderer_get_scale(Live2DRenderer* renderer);

/**
 * live2d_renderer_get_offset_x:
 * @renderer: a #Live2DRenderer
 *
 * Returns: current horizontal offset
 */
float live2d_renderer_get_offset_x(Live2DRenderer* renderer);

/**
 * live2d_renderer_get_offset_y:
 * @renderer: a #Live2DRenderer
 *
 * Returns: current vertical offset
 */
float live2d_renderer_get_offset_y(Live2DRenderer* renderer);

#ifdef __cplusplus
}
#endif

#endif  // LIVE2D_RENDERER_H_
