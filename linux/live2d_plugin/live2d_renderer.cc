/*
 * Live2D Renderer for Flutter Plugin
 * Copyright 2025 kozakemi
 * 
 * This implements off-screen rendering for Live2D models using EGL.
 */

#include "live2d_renderer.h"

#include <EGL/egl.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>
#include <cstring>
#include <cstdlib>
#include <string>
#include <iostream>
#include <cmath>

// Live2D Cubism includes
#include "CubismFramework.hpp"
#include "Model/CubismUserModel.hpp"
#include "CubismModelSettingJson.hpp"
#include "Id/CubismIdManager.hpp"
#include "Motion/CubismMotion.hpp"
#include "Motion/CubismMotionManager.hpp"
#include "Physics/CubismPhysics.hpp"
#include "Rendering/OpenGL/CubismRenderer_OpenGLES2.hpp"
#include "Utils/CubismString.hpp"
#include "CubismDefaultParameterId.hpp"
#include "Math/CubismMatrix44.hpp"
#include "Math/CubismViewMatrix.hpp"

using namespace Live2D::Cubism::Framework;
using namespace Live2D::Cubism::Core;

// Simple allocator for Cubism
class SimpleAllocator : public ICubismAllocator {
public:
    void* Allocate(const csmSizeType size) override {
        return malloc(size);
    }
    
    void Deallocate(void* memory) override {
        free(memory);
    }
    
    void* AllocateAligned(const csmSizeType size, const csmUint32 alignment) override {
        size_t offset, shift, alignedAddress;
        void* allocation = malloc(size + alignment);
        if (!allocation) return nullptr;
        
        alignedAddress = (size_t)allocation + alignment;
        shift = alignedAddress % alignment;
        offset = alignment - shift;
        alignedAddress = (size_t)allocation + offset;
        
        ((size_t*)alignedAddress)[-1] = offset;
        return (void*)alignedAddress;
    }
    
    void DeallocateAligned(void* memory) override {
        if (!memory) return;
        size_t offset = ((size_t*)memory)[-1];
        void* ptr = (void*)((size_t)memory - offset);
        free(ptr);
    }
};

// Simple Live2D model class
class SimpleLive2DModel : public CubismUserModel {
public:
    SimpleLive2DModel() : CubismUserModel() {
        _idParamAngleX = CubismFramework::GetIdManager()->GetId(DefaultParameterId::ParamAngleX);
        _idParamAngleY = CubismFramework::GetIdManager()->GetId(DefaultParameterId::ParamAngleY);
        _idParamAngleZ = CubismFramework::GetIdManager()->GetId(DefaultParameterId::ParamAngleZ);
        _idParamBodyAngleX = CubismFramework::GetIdManager()->GetId(DefaultParameterId::ParamBodyAngleX);
        _idParamEyeBallX = CubismFramework::GetIdManager()->GetId(DefaultParameterId::ParamEyeBallX);
        _idParamEyeBallY = CubismFramework::GetIdManager()->GetId(DefaultParameterId::ParamEyeBallY);
    }
    
    ~SimpleLive2DModel() {
        ReleaseMotions();
        ReleaseExpressions();
    }
    
    bool LoadAssets(const std::string& dir, const std::string& fileName) {
        _modelHomeDir = dir;
        
        // Read model setting
        std::string path = dir + fileName;
        
        FILE* file = fopen(path.c_str(), "rb");
        if (!file) {
            std::cerr << "Failed to open model setting: " << path << std::endl;
            return false;
        }
        
        fseek(file, 0, SEEK_END);
        size_t size = ftell(file);
        fseek(file, 0, SEEK_SET);
        
        csmByte* buffer = new csmByte[size];
        fread(buffer, 1, size, file);
        fclose(file);
        
        ICubismModelSetting* setting = new CubismModelSettingJson(buffer, size);
        delete[] buffer;
        
        // Load model
        std::string modelPath = dir + setting->GetModelFileName();
        file = fopen(modelPath.c_str(), "rb");
        if (!file) {
            delete setting;
            return false;
        }
        
        fseek(file, 0, SEEK_END);
        size = ftell(file);
        fseek(file, 0, SEEK_SET);
        
        buffer = new csmByte[size];
        fread(buffer, 1, size, file);
        fclose(file);
        
        LoadModel(buffer, size);
        delete[] buffer;
        
        // Load textures
        for (csmInt32 i = 0; i < setting->GetTextureCount(); i++) {
            std::string texturePath = dir + setting->GetTextureFileName(i);
            // Load texture using stb_image or similar
            LoadTexture(i, texturePath);
        }
        
        // Setup renderer
        CreateRenderer();
        SetupTextures();
        
        // Load physics if available
        if (setting->GetPhysicsFileName() && strlen(setting->GetPhysicsFileName()) > 0) {
            std::string physicsPath = dir + setting->GetPhysicsFileName();
            file = fopen(physicsPath.c_str(), "rb");
            if (file) {
                fseek(file, 0, SEEK_END);
                size = ftell(file);
                fseek(file, 0, SEEK_SET);
                buffer = new csmByte[size];
                fread(buffer, 1, size, file);
                fclose(file);
                LoadPhysics(buffer, size);
                delete[] buffer;
            }
        }
        
        delete setting;
        return true;
    }
    
    void Update(float deltaTime) {
        _model->LoadParameters();
        
        if (_motionManager->IsFinished()) {
            // Idle animation logic could go here
        } else {
            _motionManager->UpdateMotion(_model, deltaTime);
        }
        
        _model->SaveParameters();
        
        // Eye blink, lip sync could be added here
        
        if (_physics) {
            _physics->Evaluate(_model, deltaTime);
        }
        
        _model->Update();
    }
    
    void Draw(CubismMatrix44& projectionMatrix) {
        if (_model == nullptr) return;
        
        Rendering::CubismRenderer_OpenGLES2* renderer = 
            dynamic_cast<Rendering::CubismRenderer_OpenGLES2*>(GetRenderer());
        if (renderer) {
            renderer->SetMvpMatrix(&projectionMatrix);
            renderer->DrawModel();
        }
    }
    
    void SetDragging(float x, float y) {
        _dragX = x;
        _dragY = y;
        
        if (_model) {
            _model->SetParameterValue(_idParamAngleX, _dragX * 30);
            _model->SetParameterValue(_idParamAngleY, _dragY * 30);
            _model->SetParameterValue(_idParamAngleZ, _dragX * _dragY * -30);
            _model->SetParameterValue(_idParamBodyAngleX, _dragX * 10);
            _model->SetParameterValue(_idParamEyeBallX, _dragX);
            _model->SetParameterValue(_idParamEyeBallY, _dragY);
        }
    }
    
private:
    void LoadTexture(int index, const std::string& path) {
        // Simple texture loading - in production, use stb_image
        _textureIds.PushBack(0);
        
        // Load texture from file
        FILE* file = fopen(path.c_str(), "rb");
        if (!file) return;
        
        // Skip PNG header and read image data
        // For simplicity, create a placeholder texture
        GLuint textureId;
        glGenTextures(1, &textureId);
        glBindTexture(GL_TEXTURE_2D, textureId);
        
        // Create a simple white texture as placeholder
        unsigned char whitePixel[] = {255, 255, 255, 255};
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 1, 1, 0, GL_RGBA, GL_UNSIGNED_BYTE, whitePixel);
        
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        
        _textureIds[index] = textureId;
        
        fclose(file);
    }
    
    void SetupTextures() {
        Rendering::CubismRenderer_OpenGLES2* renderer = 
            dynamic_cast<Rendering::CubismRenderer_OpenGLES2*>(GetRenderer());
        if (renderer) {
            for (int i = 0; i < _textureIds.GetSize(); i++) {
                renderer->BindTexture(i, _textureIds[i]);
            }
            renderer->IsPremultipliedAlpha(false);
        }
    }
    
    std::string _modelHomeDir;
    csmVector<GLuint> _textureIds;
    
    float _dragX = 0.0f;
    float _dragY = 0.0f;
    
    const CubismId* _idParamAngleX;
    const CubismId* _idParamAngleY;
    const CubismId* _idParamAngleZ;
    const CubismId* _idParamBodyAngleX;
    const CubismId* _idParamEyeBallX;
    const CubismId* _idParamEyeBallY;
};

struct Live2DRenderer {
    EGLDisplay eglDisplay;
    EGLContext eglContext;
    EGLSurface eglSurface;
    
    GLuint framebuffer;
    GLuint renderbuffer;
    GLuint texture;
    
    uint32_t width;
    uint32_t height;
    
    SimpleAllocator allocator;
    SimpleLive2DModel* model;
    CubismMatrix44 projectionMatrix;
    
    float lastTime;
    bool initialized;
    
    float touchX;
    float touchY;
    bool isTouching;
};

static bool initEGL(Live2DRenderer* renderer) {
    // Get EGL display
    renderer->eglDisplay = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (renderer->eglDisplay == EGL_NO_DISPLAY) {
        std::cerr << "Failed to get EGL display" << std::endl;
        return false;
    }
    
    // Initialize EGL
    EGLint major, minor;
    if (!eglInitialize(renderer->eglDisplay, &major, &minor)) {
        std::cerr << "Failed to initialize EGL" << std::endl;
        return false;
    }
    
    // Choose config
    EGLint configAttribs[] = {
        EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
        EGL_RED_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8,
        EGL_ALPHA_SIZE, 8,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
        EGL_NONE
    };
    
    EGLConfig config;
    EGLint numConfigs;
    if (!eglChooseConfig(renderer->eglDisplay, configAttribs, &config, 1, &numConfigs) || numConfigs == 0) {
        std::cerr << "Failed to choose EGL config" << std::endl;
        return false;
    }
    
    // Create pbuffer surface
    EGLint pbufferAttribs[] = {
        EGL_WIDTH, (EGLint)renderer->width,
        EGL_HEIGHT, (EGLint)renderer->height,
        EGL_NONE
    };
    
    renderer->eglSurface = eglCreatePbufferSurface(renderer->eglDisplay, config, pbufferAttribs);
    if (renderer->eglSurface == EGL_NO_SURFACE) {
        std::cerr << "Failed to create EGL pbuffer surface" << std::endl;
        return false;
    }
    
    // Create context
    EGLint contextAttribs[] = {
        EGL_CONTEXT_CLIENT_VERSION, 2,
        EGL_NONE
    };
    
    renderer->eglContext = eglCreateContext(renderer->eglDisplay, config, EGL_NO_CONTEXT, contextAttribs);
    if (renderer->eglContext == EGL_NO_CONTEXT) {
        std::cerr << "Failed to create EGL context" << std::endl;
        return false;
    }
    
    // Make context current
    if (!eglMakeCurrent(renderer->eglDisplay, renderer->eglSurface, renderer->eglSurface, renderer->eglContext)) {
        std::cerr << "Failed to make EGL context current" << std::endl;
        return false;
    }
    
    return true;
}

static void setupFramebuffer(Live2DRenderer* renderer) {
    // Create framebuffer
    glGenFramebuffers(1, &renderer->framebuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, renderer->framebuffer);
    
    // Create renderbuffer for color
    glGenRenderbuffers(1, &renderer->renderbuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, renderer->renderbuffer);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA4, renderer->width, renderer->height);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, renderer->renderbuffer);
    
    // Create texture for reading pixels
    glGenTextures(1, &renderer->texture);
    glBindTexture(GL_TEXTURE_2D, renderer->texture);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, renderer->width, renderer->height, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, renderer->texture, 0);
    
    GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    if (status != GL_FRAMEBUFFER_COMPLETE) {
        std::cerr << "Framebuffer not complete: " << status << std::endl;
    }
    
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
}

static void initCubism(Live2DRenderer* renderer, const char* modelPath) {
    // Initialize Cubism Framework
    CubismFramework::Option option;
    option.LogFunction = [](const char* message) {
        std::cout << "[Live2D] " << message << std::endl;
    };
    option.LoggingLevel = CubismFramework::Option::LogLevel_Verbose;
    
    CubismFramework::StartUp(&renderer->allocator, &option);
    CubismFramework::Initialize();
    
    // Create and load model
    renderer->model = new SimpleLive2DModel();
    
    std::string dir, fileName;
    if (modelPath && strlen(modelPath) > 0) {
        std::string path(modelPath);
        size_t lastSlash = path.find_last_of('/');
        if (lastSlash != std::string::npos) {
            dir = path.substr(0, lastSlash + 1);
            fileName = path.substr(lastSlash + 1);
        } else {
            dir = "./";
            fileName = path;
        }
    } else {
        // Default model path
        dir = "/home/kozakemi/git/flutter_linux_panel/linux/CubismNativeSamples/Samples/Resources/Hiyori/";
        fileName = "Hiyori.model3.json";
    }
    
    if (!renderer->model->LoadAssets(dir, fileName)) {
        std::cerr << "Failed to load Live2D model" << std::endl;
    }
    
    // Setup projection matrix
    float aspectRatio = (float)renderer->width / (float)renderer->height;
    renderer->projectionMatrix.LoadIdentity();
    if (aspectRatio > 1.0f) {
        renderer->projectionMatrix.Scale(1.0f, aspectRatio);
    } else {
        renderer->projectionMatrix.Scale(1.0f / aspectRatio, 1.0f);
    }
}

extern "C" {

Live2DRenderer* live2d_renderer_create(uint32_t width, uint32_t height, const char* modelPath) {
    Live2DRenderer* renderer = new Live2DRenderer();
    renderer->width = width;
    renderer->height = height;
    renderer->initialized = false;
    renderer->lastTime = 0.0f;
    renderer->touchX = 0.0f;
    renderer->touchY = 0.0f;
    renderer->isTouching = false;
    renderer->model = nullptr;
    
    // Initialize EGL
    if (!initEGL(renderer)) {
        delete renderer;
        return nullptr;
    }
    
    // Setup framebuffer
    setupFramebuffer(renderer);
    
    // Initialize Cubism and load model
    initCubism(renderer, modelPath);
    
    renderer->initialized = true;
    return renderer;
}

void live2d_renderer_destroy(Live2DRenderer* renderer) {
    if (!renderer) return;
    
    if (renderer->model) {
        delete renderer->model;
        renderer->model = nullptr;
    }
    
    CubismFramework::Dispose();
    
    // Cleanup OpenGL resources
    if (renderer->eglContext != EGL_NO_CONTEXT) {
        eglMakeCurrent(renderer->eglDisplay, renderer->eglSurface, renderer->eglSurface, renderer->eglContext);
        
        if (renderer->framebuffer) {
            glDeleteFramebuffers(1, &renderer->framebuffer);
        }
        if (renderer->renderbuffer) {
            glDeleteRenderbuffers(1, &renderer->renderbuffer);
        }
        if (renderer->texture) {
            glDeleteTextures(1, &renderer->texture);
        }
        
        eglMakeCurrent(renderer->eglDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        eglDestroyContext(renderer->eglDisplay, renderer->eglContext);
    }
    
    if (renderer->eglSurface != EGL_NO_SURFACE) {
        eglDestroySurface(renderer->eglDisplay, renderer->eglSurface);
    }
    
    if (renderer->eglDisplay != EGL_NO_DISPLAY) {
        eglTerminate(renderer->eglDisplay);
    }
    
    delete renderer;
}

void live2d_renderer_render(Live2DRenderer* renderer, uint8_t* buffer, uint32_t width, uint32_t height) {
    if (!renderer || !renderer->initialized || !buffer) return;
    
    // Make context current
    eglMakeCurrent(renderer->eglDisplay, renderer->eglSurface, renderer->eglSurface, renderer->eglContext);
    
    // Bind framebuffer
    glBindFramebuffer(GL_FRAMEBUFFER, renderer->framebuffer);
    glViewport(0, 0, renderer->width, renderer->height);
    
    // Clear
    glClearColor(0.0f, 0.0f, 0.0f, 0.0f);  // Transparent background
    glClear(GL_COLOR_BUFFER_BIT);
    
    // Enable blending
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    
    // Update time
    static float time = 0.0f;
    float deltaTime = 1.0f / 60.0f;  // Assume 60 FPS
    time += deltaTime;
    
    // Update model
    if (renderer->model) {
        // Apply touch/drag effect
        if (renderer->isTouching) {
            float normalizedX = (renderer->touchX / renderer->width) * 2.0f - 1.0f;
            float normalizedY = -((renderer->touchY / renderer->height) * 2.0f - 1.0f);
            renderer->model->SetDragging(normalizedX, normalizedY);
        } else {
            renderer->model->SetDragging(0.0f, 0.0f);
        }
        
        renderer->model->Update(deltaTime);
        renderer->model->Draw(renderer->projectionMatrix);
    }
    
    // Read pixels
    glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, buffer);
    
    // Flip vertically (OpenGL has origin at bottom-left)
    uint32_t rowSize = width * 4;
    uint8_t* tempRow = new uint8_t[rowSize];
    for (uint32_t y = 0; y < height / 2; y++) {
        uint8_t* topRow = buffer + y * rowSize;
        uint8_t* bottomRow = buffer + (height - 1 - y) * rowSize;
        memcpy(tempRow, topRow, rowSize);
        memcpy(topRow, bottomRow, rowSize);
        memcpy(bottomRow, tempRow, rowSize);
    }
    delete[] tempRow;
    
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
}

void live2d_renderer_on_touch(Live2DRenderer* renderer, double x, double y, const char* type) {
    if (!renderer) return;
    
    renderer->touchX = (float)x;
    renderer->touchY = (float)y;
    
    if (strcmp(type, "down") == 0) {
        renderer->isTouching = true;
    } else if (strcmp(type, "up") == 0) {
        renderer->isTouching = false;
    }
    // "move" keeps the current touching state
}

void live2d_renderer_resize(Live2DRenderer* renderer, uint32_t width, uint32_t height) {
    if (!renderer || (renderer->width == width && renderer->height == height)) return;
    
    renderer->width = width;
    renderer->height = height;
    
    // Recreate framebuffer
    if (renderer->framebuffer) {
        glDeleteFramebuffers(1, &renderer->framebuffer);
    }
    if (renderer->renderbuffer) {
        glDeleteRenderbuffers(1, &renderer->renderbuffer);
    }
    if (renderer->texture) {
        glDeleteTextures(1, &renderer->texture);
    }
    
    setupFramebuffer(renderer);
    
    // Update projection matrix
    float aspectRatio = (float)width / (float)height;
    renderer->projectionMatrix.LoadIdentity();
    if (aspectRatio > 1.0f) {
        renderer->projectionMatrix.Scale(1.0f, aspectRatio);
    } else {
        renderer->projectionMatrix.Scale(1.0f / aspectRatio, 1.0f);
    }
}

}  // extern "C"

