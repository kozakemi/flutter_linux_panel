/*
 * Simple Live2D Renderer for Flutter Plugin
 * Copyright 2025 kozakemi
 * 
 * This is a simplified version that renders a placeholder animation
 * to verify Flutter texture integration works correctly.
 */

#include "live2d_renderer.h"

#include <cstring>
#include <cmath>
#include <cstdlib>
#include <iostream>

struct Live2DRenderer {
    uint32_t width;
    uint32_t height;
    float time;
    float touchX;
    float touchY;
    bool isTouching;
    bool initialized;
};

// Helper function for smooth interpolation
static float smoothstep(float edge0, float edge1, float x) {
    float t = fmaxf(0.0f, fminf(1.0f, (x - edge0) / (edge1 - edge0)));
    return t * t * (3.0f - 2.0f * t);
}

extern "C" {

Live2DRenderer* live2d_renderer_create(uint32_t width, uint32_t height, const char* modelPath) {
    Live2DRenderer* renderer = new Live2DRenderer();
    renderer->width = width;
    renderer->height = height;
    renderer->time = 0.0f;
    renderer->touchX = 0.5f;
    renderer->touchY = 0.5f;
    renderer->isTouching = false;
    renderer->initialized = true;
    
    std::cout << "[Live2D] Renderer created: " << width << "x" << height << std::endl;
    if (modelPath) {
        std::cout << "[Live2D] Model path: " << modelPath << std::endl;
    }
    
    return renderer;
}

void live2d_renderer_destroy(Live2DRenderer* renderer) {
    if (!renderer) return;
    std::cout << "[Live2D] Renderer destroyed" << std::endl;
    delete renderer;
}

// Simple animated gradient background with a bouncing circle
void live2d_renderer_render(Live2DRenderer* renderer, uint8_t* buffer, uint32_t width, uint32_t height) {
    if (!renderer || !renderer->initialized || !buffer) return;
    
    renderer->time += 1.0f / 60.0f;  // Assume 60 FPS
    
    // Animation parameters
    float phase = renderer->time * 2.0f;
    float circleX = renderer->isTouching ? renderer->touchX : (0.5f + 0.3f * sinf(phase));
    float circleY = renderer->isTouching ? renderer->touchY : (0.5f + 0.2f * cosf(phase * 1.3f));
    float circleRadius = 0.15f + 0.05f * sinf(phase * 2.0f);
    
    // Background color animation
    float bgR = 0.1f + 0.05f * sinf(phase * 0.5f);
    float bgG = 0.1f + 0.05f * sinf(phase * 0.7f);
    float bgB = 0.2f + 0.1f * sinf(phase * 0.3f);
    
    // Circle color (pinkish, like Live2D character skin tone)
    float circleR = 0.95f;
    float circleG = 0.75f;
    float circleB = 0.8f;
    
    // Eye positions (follow touch or animate)
    float eyeOffsetX = renderer->isTouching ? (renderer->touchX - 0.5f) * 0.1f : 0.05f * sinf(phase);
    float eyeOffsetY = renderer->isTouching ? (renderer->touchY - 0.5f) * 0.1f : 0.03f * cosf(phase);
    
    for (uint32_t y = 0; y < height; y++) {
        for (uint32_t x = 0; x < width; x++) {
            float fx = (float)x / (float)width;
            float fy = (float)y / (float)height;
            
            float r, g, b, a;
            
            // Distance from circle center
            float dx = fx - circleX;
            float dy = fy - circleY;
            float dist = sqrtf(dx * dx + dy * dy);
            
            // Eye positions
            float eyeLeftX = circleX - 0.04f + eyeOffsetX;
            float eyeLeftY = circleY - 0.02f + eyeOffsetY;
            float eyeRightX = circleX + 0.04f + eyeOffsetX;
            float eyeRightY = circleY - 0.02f + eyeOffsetY;
            float eyeRadius = 0.015f;
            
            float distLeftEye = sqrtf((fx - eyeLeftX) * (fx - eyeLeftX) + (fy - eyeLeftY) * (fy - eyeLeftY));
            float distRightEye = sqrtf((fx - eyeRightX) * (fx - eyeRightX) + (fy - eyeRightY) * (fy - eyeRightY));
            
            // Mouth (smile)
            float mouthX = circleX;
            float mouthY = circleY + 0.04f;
            float distMouth = sqrtf((fx - mouthX) * (fx - mouthX) + (fy - mouthY) * (fy - mouthY));
            bool inSmile = distMouth < 0.03f && fy > mouthY - 0.005f;
            
            if (distLeftEye < eyeRadius || distRightEye < eyeRadius) {
                // Eyes (black)
                r = 0.1f;
                g = 0.1f;
                b = 0.1f;
                a = 1.0f;
            } else if (inSmile) {
                // Mouth (darker pink)
                r = 0.8f;
                g = 0.4f;
                b = 0.5f;
                a = 1.0f;
            } else if (dist < circleRadius) {
                // Face circle with soft edge
                float edge = smoothstep(circleRadius - 0.02f, circleRadius, dist);
                r = circleR * (1.0f - edge) + bgR * edge;
                g = circleG * (1.0f - edge) + bgG * edge;
                b = circleB * (1.0f - edge) + bgB * edge;
                a = 1.0f - edge * 0.5f;
                
                // Add slight blush
                float blushLeftDist = sqrtf((fx - (circleX - 0.05f)) * (fx - (circleX - 0.05f)) + 
                                           (fy - (circleY + 0.01f)) * (fy - (circleY + 0.01f)));
                float blushRightDist = sqrtf((fx - (circleX + 0.05f)) * (fx - (circleX + 0.05f)) + 
                                            (fy - (circleY + 0.01f)) * (fy - (circleY + 0.01f)));
                if (blushLeftDist < 0.025f || blushRightDist < 0.025f) {
                    r = fminf(1.0f, r + 0.15f);
                    g = fmaxf(0.0f, g - 0.1f);
                }
            } else {
                // Background gradient
                r = bgR + 0.1f * fy;
                g = bgG + 0.05f * fx;
                b = bgB + 0.15f * (1.0f - fy);
                a = 1.0f;
            }
            
            // Write pixel (RGBA format)
            uint32_t idx = (y * width + x) * 4;
            buffer[idx + 0] = (uint8_t)(fminf(1.0f, fmaxf(0.0f, r)) * 255);
            buffer[idx + 1] = (uint8_t)(fminf(1.0f, fmaxf(0.0f, g)) * 255);
            buffer[idx + 2] = (uint8_t)(fminf(1.0f, fmaxf(0.0f, b)) * 255);
            buffer[idx + 3] = (uint8_t)(fminf(1.0f, fmaxf(0.0f, a)) * 255);
        }
    }
}

void live2d_renderer_on_touch(Live2DRenderer* renderer, double x, double y, const char* type) {
    if (!renderer) return;
    
    renderer->touchX = (float)x;
    renderer->touchY = (float)y;
    
    if (strcmp(type, "down") == 0) {
        renderer->isTouching = true;
        std::cout << "[Live2D] Touch down: " << x << ", " << y << std::endl;
    } else if (strcmp(type, "up") == 0) {
        renderer->isTouching = false;
        std::cout << "[Live2D] Touch up" << std::endl;
    }
}

void live2d_renderer_resize(Live2DRenderer* renderer, uint32_t width, uint32_t height) {
    if (!renderer) return;
    renderer->width = width;
    renderer->height = height;
    std::cout << "[Live2D] Resized: " << width << "x" << height << std::endl;
}

}  // extern "C"

