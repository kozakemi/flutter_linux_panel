/*
 * Live2D Cubism Renderer for Flutter Plugin
 * Copyright 2025 kozakemi
 * 
 * This implements off-screen rendering for Live2D Cubism models using EGL.
 */

#include "live2d_renderer.h"

#include <EGL/egl.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>

#include <cstring>
#include <cstdlib>
#include <cstdio>
#include <string>
#include <iostream>
#include <fstream>
#include <vector>
#include <sys/stat.h>
#include <cmath>
#include <ctime>

// stb_image for texture loading
#define STBI_ONLY_PNG
#define STB_IMAGE_IMPLEMENTATION
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#endif
#include "stb_image.h"
#if defined(__clang__)
#pragma clang diagnostic pop
#endif

// Cubism SDK includes
#include <CubismFramework.hpp>
#include <CubismModelSettingJson.hpp>
#include <Model/CubismUserModel.hpp>
#include <Model/CubismMoc.hpp>
#include <Id/CubismIdManager.hpp>
#include <CubismDefaultParameterId.hpp>
#include <Motion/CubismMotion.hpp>
#include <Motion/CubismMotionManager.hpp>
#include <Motion/CubismExpressionMotion.hpp>
#include <Physics/CubismPhysics.hpp>
#include <Effect/CubismBreath.hpp>
#include <Effect/CubismEyeBlink.hpp>
#include <Rendering/OpenGL/CubismRenderer_OpenGLES2.hpp>
#include <Math/CubismMatrix44.hpp>
#include <Math/CubismViewMatrix.hpp>
#include <Type/csmVector.hpp>
#include <Type/csmMap.hpp>
#include <Utils/CubismString.hpp>

// Common includes
#include "LAppAllocator_Common.hpp"

using namespace Live2D::Cubism::Framework;
using namespace Live2D::Cubism::Framework::DefaultParameterId;

// Forward declarations
class FlutterLive2DModel;

//------------------------------------------------------------
// Allocator
//------------------------------------------------------------
static LAppAllocator_Common s_allocator;
static CubismFramework::Option s_cubismOption;
static bool s_cubismInitialized = false;

//------------------------------------------------------------
// File loading utility
//------------------------------------------------------------
static csmByte* LoadFileAsBytes(const std::string& filePath, csmSizeInt* outSize) {
    struct stat statBuf;
    if (stat(filePath.c_str(), &statBuf) != 0) {
        std::cerr << "[Live2D] File not found: " << filePath << std::endl;
        return nullptr;
    }
    
    int size = statBuf.st_size;
    if (size == 0) {
        std::cerr << "[Live2D] File is empty: " << filePath << std::endl;
        return nullptr;
    }
    
    std::ifstream file(filePath, std::ios::binary);
    if (!file.is_open()) {
        std::cerr << "[Live2D] Failed to open: " << filePath << std::endl;
        return nullptr;
    }
    
    csmByte* buf = new csmByte[size];
    file.read(reinterpret_cast<char*>(buf), size);
    file.close();
    
    *outSize = size;
    return buf;
}

static void ReleaseBytes(csmByte* data) {
    delete[] data;
}

//------------------------------------------------------------
// Texture Manager
//------------------------------------------------------------
struct TextureInfo {
    GLuint id;
    int width;
    int height;
    std::string fileName;
};

class TextureManager {
public:
    TextureManager() {}
    ~TextureManager() { ReleaseAll(); }
    
    TextureInfo* CreateTextureFromPng(const std::string& filePath) {
        // Check if already loaded
        for (size_t i = 0; i < _textures.size(); i++) {
            if (_textures[i].fileName == filePath) {
                return &_textures[i];
            }
        }
        
        csmSizeInt size;
        csmByte* data = LoadFileAsBytes(filePath, &size);
        if (!data) return nullptr;
        
        int width, height, channels;
        unsigned char* png = stbi_load_from_memory(data, size, &width, &height, &channels, STBI_rgb_alpha);
        ReleaseBytes(data);
        
        if (!png) {
            std::cerr << "[Live2D] Failed to decode PNG: " << filePath << std::endl;
            return nullptr;
        }
        
        GLuint textureId;
        glGenTextures(1, &textureId);
        glBindTexture(GL_TEXTURE_2D, textureId);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, png);
        glGenerateMipmap(GL_TEXTURE_2D);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glBindTexture(GL_TEXTURE_2D, 0);
        
        stbi_image_free(png);
        
        TextureInfo info;
        info.id = textureId;
        info.width = width;
        info.height = height;
        info.fileName = filePath;
        _textures.push_back(info);
        
        return &_textures.back();
    }
    
    void ReleaseAll() {
        for (size_t i = 0; i < _textures.size(); i++) {
            glDeleteTextures(1, &_textures[i].id);
        }
        _textures.clear();
    }
    
private:
    std::vector<TextureInfo> _textures;
};

//------------------------------------------------------------
// Live2D Model
//------------------------------------------------------------
class FlutterLive2DModel : public CubismUserModel {
public:
    FlutterLive2DModel()
        : CubismUserModel()
        , _modelSetting(nullptr)
        , _userTimeSeconds(0.0f)
    {
        _idParamAngleX = CubismFramework::GetIdManager()->GetId(ParamAngleX);
        _idParamAngleY = CubismFramework::GetIdManager()->GetId(ParamAngleY);
        _idParamAngleZ = CubismFramework::GetIdManager()->GetId(ParamAngleZ);
        _idParamBodyAngleX = CubismFramework::GetIdManager()->GetId(ParamBodyAngleX);
        _idParamEyeBallX = CubismFramework::GetIdManager()->GetId(ParamEyeBallX);
        _idParamEyeBallY = CubismFramework::GetIdManager()->GetId(ParamEyeBallY);
    }
    
    ~FlutterLive2DModel() {
        ReleaseMotions();
        ReleaseExpressions();
        
        if (_modelSetting) {
            delete _modelSetting;
            _modelSetting = nullptr;
        }
    }
    
    bool LoadAssets(const std::string& dir, const std::string& fileName, TextureManager* texMgr) {
        _modelHomeDir = dir;
        _textureManager = texMgr;
        
        std::cout << "[Live2D] LoadAssets: dir=" << dir << " fileName=" << fileName << std::endl;
        
        std::string path = dir + fileName;
        csmSizeInt size;
        csmByte* buffer = LoadFileAsBytes(path, &size);
        if (!buffer) {
            std::cerr << "[Live2D] Failed to load model setting file: " << path << std::endl;
            return false;
        }
        
        std::cout << "[Live2D] Model setting loaded, size=" << size << std::endl;
        
        _modelSetting = new CubismModelSettingJson(buffer, size);
        ReleaseBytes(buffer);
        
        std::cout << "[Live2D] Model file: " << _modelSetting->GetModelFileName() << std::endl;
        
        // Load model
        if (strlen(_modelSetting->GetModelFileName()) > 0) {
            std::string modelPath = dir + _modelSetting->GetModelFileName();
            std::cout << "[Live2D] Loading moc3: " << modelPath << std::endl;
            buffer = LoadFileAsBytes(modelPath, &size);
            if (buffer) {
                LoadModel(buffer, size);
                ReleaseBytes(buffer);
                std::cout << "[Live2D] Moc3 loaded, _model=" << (_model != nullptr ? "OK" : "NULL") << std::endl;
            } else {
                std::cerr << "[Live2D] Failed to load moc3 file" << std::endl;
            }
        }
        
        if (_model == nullptr) {
            std::cerr << "[Live2D] Model is NULL after loading!" << std::endl;
            return false;
        }
        
        // Load physics
        if (_modelSetting->GetPhysicsFileName() && strlen(_modelSetting->GetPhysicsFileName()) > 0) {
            std::string physicsPath = dir + _modelSetting->GetPhysicsFileName();
            buffer = LoadFileAsBytes(physicsPath, &size);
            if (buffer) {
                LoadPhysics(buffer, size);
                ReleaseBytes(buffer);
            }
        }
        
        // Load pose
        if (_modelSetting->GetPoseFileName() && strlen(_modelSetting->GetPoseFileName()) > 0) {
            std::string posePath = dir + _modelSetting->GetPoseFileName();
            buffer = LoadFileAsBytes(posePath, &size);
            if (buffer) {
                LoadPose(buffer, size);
                ReleaseBytes(buffer);
            }
        }
        
        // Eye blink
        if (_modelSetting->GetEyeBlinkParameterCount() > 0) {
            _eyeBlink = CubismEyeBlink::Create(_modelSetting);
        }
        
        // Breath
        _breath = CubismBreath::Create();
        csmVector<CubismBreath::BreathParameterData> breathParams;
        breathParams.PushBack(CubismBreath::BreathParameterData(_idParamAngleX, 0.0f, 15.0f, 6.5345f, 0.5f));
        breathParams.PushBack(CubismBreath::BreathParameterData(_idParamAngleY, 0.0f, 8.0f, 3.5345f, 0.5f));
        breathParams.PushBack(CubismBreath::BreathParameterData(_idParamAngleZ, 0.0f, 10.0f, 5.5345f, 0.5f));
        breathParams.PushBack(CubismBreath::BreathParameterData(_idParamBodyAngleX, 0.0f, 4.0f, 15.5345f, 0.5f));
        breathParams.PushBack(CubismBreath::BreathParameterData(
            CubismFramework::GetIdManager()->GetId(ParamBreath), 0.5f, 0.5f, 3.2345f, 0.5f));
        _breath->SetParameters(breathParams);
        
        // Eye blink IDs
        for (csmInt32 i = 0; i < _modelSetting->GetEyeBlinkParameterCount(); i++) {
            _eyeBlinkIds.PushBack(_modelSetting->GetEyeBlinkParameterId(i));
        }
        
        // Lip sync IDs
        for (csmInt32 i = 0; i < _modelSetting->GetLipSyncParameterCount(); i++) {
            _lipSyncIds.PushBack(_modelSetting->GetLipSyncParameterId(i));
        }
        
        // Layout
        csmMap<csmString, csmFloat32> layout;
        _modelSetting->GetLayoutMap(layout);
        _modelMatrix->SetupFromLayout(layout);
        
        _model->SaveParameters();
        
        // Preload motions
        for (csmInt32 i = 0; i < _modelSetting->GetMotionGroupCount(); i++) {
            const csmChar* group = _modelSetting->GetMotionGroupName(i);
            PreloadMotionGroup(group);
        }
        
        // Create renderer
        std::cout << "[Live2D] Creating renderer..." << std::endl;
        CreateRenderer();
        std::cout << "[Live2D] Setting up textures..." << std::endl;
        SetupTextures();
        
        std::cout << "[Live2D] Model loaded successfully!" << std::endl;
        return true;
    }
    
    void Update(float deltaTime) {
        _userTimeSeconds += deltaTime;
        
        _dragManager->Update(deltaTime);
        _dragX = _dragManager->GetX();
        _dragY = _dragManager->GetY();
        
        csmBool motionUpdated = false;
        
        _model->LoadParameters();
        
        if (_motionManager->IsFinished()) {
            // Start idle motion
            StartRandomMotion("Idle", 1);
        } else {
            motionUpdated = _motionManager->UpdateMotion(_model, deltaTime);
        }
        
        _model->SaveParameters();
        
        // Eye blink
        if (!motionUpdated && _eyeBlink) {
            _eyeBlink->UpdateParameters(_model, deltaTime);
        }
        
        // Expression
        if (_expressionManager) {
            _expressionManager->UpdateMotion(_model, deltaTime);
        }
        
        // Drag effect
        _model->AddParameterValue(_idParamAngleX, _dragX * 30);
        _model->AddParameterValue(_idParamAngleY, _dragY * 30);
        _model->AddParameterValue(_idParamAngleZ, _dragX * _dragY * -30);
        _model->AddParameterValue(_idParamBodyAngleX, _dragX * 10);
        _model->AddParameterValue(_idParamEyeBallX, _dragX);
        _model->AddParameterValue(_idParamEyeBallY, _dragY);
        
        // Breath
        if (_breath) {
            _breath->UpdateParameters(_model, deltaTime);
        }
        
        // Physics
        if (_physics) {
            _physics->Evaluate(_model, deltaTime);
        }
        
        // Pose
        if (_pose) {
            _pose->UpdateParameters(_model, deltaTime);
        }
        
        _model->Update();
    }
    
    void Draw(CubismMatrix44& matrix) {
        if (_model == nullptr) return;
        
        matrix.MultiplyByMatrix(_modelMatrix);
        
        auto* renderer = GetRenderer<Rendering::CubismRenderer_OpenGLES2>();
        renderer->SetMvpMatrix(&matrix);
        renderer->DrawModel();
    }
    
    void SetDragging(float x, float y) {
        _dragManager->Set(x, y);
    }
    
    CubismMotionQueueEntryHandle StartRandomMotion(const csmChar* group, csmInt32 priority) {
        if (_modelSetting->GetMotionCount(group) == 0) {
            return InvalidMotionQueueEntryHandleValue;
        }
        
        csmInt32 no = rand() % _modelSetting->GetMotionCount(group);
        return StartMotion(group, no, priority);
    }
    
    CubismMotionQueueEntryHandle StartMotion(const csmChar* group, csmInt32 no, csmInt32 priority) {
        if (!_motionManager->ReserveMotion(priority)) {
            return InvalidMotionQueueEntryHandleValue;
        }
        
        csmString name = Utils::CubismString::GetFormatedString("%s_%d", group, no);
        CubismMotion* motion = static_cast<CubismMotion*>(_motions[name.GetRawString()]);
        
        if (motion == nullptr) {
            std::string path = _modelHomeDir + _modelSetting->GetMotionFileName(group, no);
            csmSizeInt size;
            csmByte* buffer = LoadFileAsBytes(path, &size);
            if (buffer) {
                motion = static_cast<CubismMotion*>(LoadMotion(buffer, size, nullptr, nullptr, nullptr, _modelSetting, group, no));
                if (motion) {
                    motion->SetEffectIds(_eyeBlinkIds, _lipSyncIds);
                }
                ReleaseBytes(buffer);
            }
        }
        
        return _motionManager->StartMotionPriority(motion, false, priority);
    }
    
private:
    void PreloadMotionGroup(const csmChar* group) {
        csmInt32 count = _modelSetting->GetMotionCount(group);
        for (csmInt32 i = 0; i < count; i++) {
            csmString name = Utils::CubismString::GetFormatedString("%s_%d", group, i);
            std::string path = _modelHomeDir + _modelSetting->GetMotionFileName(group, i);
            
            csmSizeInt size;
            csmByte* buffer = LoadFileAsBytes(path, &size);
            if (buffer) {
                CubismMotion* motion = static_cast<CubismMotion*>(
                    LoadMotion(buffer, size, name.GetRawString(), nullptr, nullptr, _modelSetting, group, i));
                if (motion) {
                    motion->SetEffectIds(_eyeBlinkIds, _lipSyncIds);
                    if (_motions[name.GetRawString()] != nullptr) {
                        ACubismMotion::Delete(_motions[name.GetRawString()]);
                    }
                    _motions[name.GetRawString()] = motion;
                }
                ReleaseBytes(buffer);
            }
        }
    }
    
    void SetupTextures() {
        auto* renderer = GetRenderer<Rendering::CubismRenderer_OpenGLES2>();
        if (!renderer) {
            std::cerr << "[Live2D] Renderer is NULL!" << std::endl;
            return;
        }
        
        std::cout << "[Live2D] Texture count: " << _modelSetting->GetTextureCount() << std::endl;
        
        for (csmInt32 i = 0; i < _modelSetting->GetTextureCount(); i++) {
            if (strlen(_modelSetting->GetTextureFileName(i)) == 0) continue;
            
            std::string texturePath = _modelHomeDir + _modelSetting->GetTextureFileName(i);
            std::cout << "[Live2D] Loading texture " << i << ": " << texturePath << std::endl;
            TextureInfo* tex = _textureManager->CreateTextureFromPng(texturePath);
            if (tex) {
                std::cout << "[Live2D] Texture loaded: " << tex->width << "x" << tex->height << " id=" << tex->id << std::endl;
                renderer->BindTexture(i, tex->id);
            } else {
                std::cerr << "[Live2D] Failed to load texture: " << texturePath << std::endl;
            }
        }
        
        renderer->IsPremultipliedAlpha(false);
    }
    
    void ReleaseMotions() {
        for (auto iter = _motions.Begin(); iter != _motions.End(); ++iter) {
            ACubismMotion::Delete(iter->Second);
        }
        _motions.Clear();
    }
    
    void ReleaseExpressions() {
        for (auto iter = _expressions.Begin(); iter != _expressions.End(); ++iter) {
            ACubismMotion::Delete(iter->Second);
        }
        _expressions.Clear();
    }
    
    ICubismModelSetting* _modelSetting;
    std::string _modelHomeDir;
    TextureManager* _textureManager;
    float _userTimeSeconds;
    
    csmVector<CubismIdHandle> _eyeBlinkIds;
    csmVector<CubismIdHandle> _lipSyncIds;
    csmMap<csmString, ACubismMotion*> _motions;
    csmMap<csmString, ACubismMotion*> _expressions;
    
    const CubismId* _idParamAngleX;
    const CubismId* _idParamAngleY;
    const CubismId* _idParamAngleZ;
    const CubismId* _idParamBodyAngleX;
    const CubismId* _idParamEyeBallX;
    const CubismId* _idParamEyeBallY;
};

//------------------------------------------------------------
// Renderer Structure
//------------------------------------------------------------
struct Live2DRenderer {
    // EGL context for off-screen rendering
    EGLDisplay eglDisplay;
    EGLContext eglContext;
    EGLSurface eglSurface;
    EGLConfig eglConfig;
    
    // Framebuffer for rendering
    GLuint framebuffer;
    GLuint colorTexture;
    GLuint depthRenderbuffer;
    
    // Dimensions
    uint32_t width;
    uint32_t height;
    
    // Live2D model
    FlutterLive2DModel* model;
    TextureManager* textureManager;
    CubismMatrix44 projectionMatrix;
    
    // State
    float lastTime;
    bool initialized;
    
    // Touch
    float touchX;
    float touchY;
    bool isTouching;
    
    // Background
    GLuint backgroundTexture;
    int backgroundWidth;
    int backgroundHeight;
    GLuint bgShaderProgram;
    
    // Model transform
    float modelScale;
    float modelOffsetX;
    float modelOffsetY;
};

//------------------------------------------------------------
// Initialize EGL for off-screen rendering
//------------------------------------------------------------
static bool initEGL(Live2DRenderer* renderer) {
    renderer->eglDisplay = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (renderer->eglDisplay == EGL_NO_DISPLAY) {
        std::cerr << "[Live2D] Failed to get EGL display" << std::endl;
        return false;
    }
    
    EGLint major, minor;
    if (!eglInitialize(renderer->eglDisplay, &major, &minor)) {
        std::cerr << "[Live2D] Failed to initialize EGL" << std::endl;
        return false;
    }
    
    std::cout << "[Live2D] EGL initialized: " << major << "." << minor << std::endl;
    
    // Configure EGL
    EGLint configAttribs[] = {
        EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
        EGL_RED_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8,
        EGL_ALPHA_SIZE, 8,
        EGL_DEPTH_SIZE, 16,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
        EGL_NONE
    };
    
    EGLint numConfigs;
    if (!eglChooseConfig(renderer->eglDisplay, configAttribs, &renderer->eglConfig, 1, &numConfigs) || numConfigs == 0) {
        std::cerr << "[Live2D] Failed to choose EGL config" << std::endl;
        return false;
    }
    
    // Create pbuffer surface
    EGLint pbufferAttribs[] = {
        EGL_WIDTH, (EGLint)renderer->width,
        EGL_HEIGHT, (EGLint)renderer->height,
        EGL_NONE
    };
    
    renderer->eglSurface = eglCreatePbufferSurface(renderer->eglDisplay, renderer->eglConfig, pbufferAttribs);
    if (renderer->eglSurface == EGL_NO_SURFACE) {
        std::cerr << "[Live2D] Failed to create EGL pbuffer surface" << std::endl;
        return false;
    }
    
    // Create context
    EGLint contextAttribs[] = {
        EGL_CONTEXT_CLIENT_VERSION, 2,
        EGL_NONE
    };
    
    renderer->eglContext = eglCreateContext(renderer->eglDisplay, renderer->eglConfig, EGL_NO_CONTEXT, contextAttribs);
    if (renderer->eglContext == EGL_NO_CONTEXT) {
        std::cerr << "[Live2D] Failed to create EGL context" << std::endl;
        return false;
    }
    
    // Make current
    if (!eglMakeCurrent(renderer->eglDisplay, renderer->eglSurface, renderer->eglSurface, renderer->eglContext)) {
        std::cerr << "[Live2D] Failed to make EGL context current" << std::endl;
        return false;
    }
    
    return true;
}

//------------------------------------------------------------
// Setup framebuffer for rendering
//------------------------------------------------------------
static void setupFramebuffer(Live2DRenderer* renderer) {
    // Create framebuffer
    glGenFramebuffers(1, &renderer->framebuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, renderer->framebuffer);
    
    // Create color texture
    glGenTextures(1, &renderer->colorTexture);
    glBindTexture(GL_TEXTURE_2D, renderer->colorTexture);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, renderer->width, renderer->height, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, renderer->colorTexture, 0);
    
    // Create depth renderbuffer
    glGenRenderbuffers(1, &renderer->depthRenderbuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, renderer->depthRenderbuffer);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT16, renderer->width, renderer->height);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, renderer->depthRenderbuffer);
    
    GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    if (status != GL_FRAMEBUFFER_COMPLETE) {
        std::cerr << "[Live2D] Framebuffer not complete: " << status << std::endl;
    }
    
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
}

//------------------------------------------------------------
// Shader base path
//------------------------------------------------------------
static std::string s_shaderBasePath = "/home/kozakemi/git/flutter_linux_panel/linux/CubismNativeSamples/Framework/src/Rendering/OpenGL/Shaders/StandardES/";
static std::string s_backgroundPath = "/home/kozakemi/git/flutter_linux_panel/linux/CubismNativeSamples/Samples/Resources/back_class_normal.png";

//------------------------------------------------------------
// Background shader source
//------------------------------------------------------------
static const char* s_bgVertexShader = R"(
    attribute vec4 a_position;
    attribute vec2 a_texCoord;
    varying vec2 v_texCoord;
    void main() {
        gl_Position = a_position;
        v_texCoord = a_texCoord;
    }
)";

static const char* s_bgFragmentShader = R"(
    precision mediump float;
    varying vec2 v_texCoord;
    uniform sampler2D u_texture;
    void main() {
        gl_FragColor = texture2D(u_texture, v_texCoord);
    }
)";

//------------------------------------------------------------
// Compile shader
//------------------------------------------------------------
static GLuint compileShader(GLenum type, const char* source) {
    GLuint shader = glCreateShader(type);
    glShaderSource(shader, 1, &source, nullptr);
    glCompileShader(shader);
    
    GLint compiled;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &compiled);
    if (!compiled) {
        GLchar log[512];
        glGetShaderInfoLog(shader, 512, nullptr, log);
        std::cerr << "[Live2D] Shader compile error: " << log << std::endl;
        glDeleteShader(shader);
        return 0;
    }
    return shader;
}

//------------------------------------------------------------
// Create shader program
//------------------------------------------------------------
static GLuint createShaderProgram(const char* vertSrc, const char* fragSrc) {
    GLuint vertShader = compileShader(GL_VERTEX_SHADER, vertSrc);
    GLuint fragShader = compileShader(GL_FRAGMENT_SHADER, fragSrc);
    if (!vertShader || !fragShader) return 0;
    
    GLuint program = glCreateProgram();
    glAttachShader(program, vertShader);
    glAttachShader(program, fragShader);
    glLinkProgram(program);
    
    GLint linked;
    glGetProgramiv(program, GL_LINK_STATUS, &linked);
    if (!linked) {
        GLchar log[512];
        glGetProgramInfoLog(program, 512, nullptr, log);
        std::cerr << "[Live2D] Shader link error: " << log << std::endl;
        glDeleteProgram(program);
        return 0;
    }
    
    glDeleteShader(vertShader);
    glDeleteShader(fragShader);
    return program;
}

//------------------------------------------------------------
// Load background texture
//------------------------------------------------------------
static bool loadBackgroundTexture(Live2DRenderer* renderer) {
    csmSizeInt size;
    csmByte* data = LoadFileAsBytes(s_backgroundPath, &size);
    if (!data) {
        std::cerr << "[Live2D] Failed to load background image" << std::endl;
        return false;
    }
    
    int width, height, channels;
    unsigned char* png = stbi_load_from_memory(data, size, &width, &height, &channels, STBI_rgb_alpha);
    ReleaseBytes(data);
    
    if (!png) {
        std::cerr << "[Live2D] Failed to decode background PNG" << std::endl;
        return false;
    }
    
    glGenTextures(1, &renderer->backgroundTexture);
    glBindTexture(GL_TEXTURE_2D, renderer->backgroundTexture);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, png);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glBindTexture(GL_TEXTURE_2D, 0);
    
    renderer->backgroundWidth = width;
    renderer->backgroundHeight = height;
    
    stbi_image_free(png);
    
    std::cout << "[Live2D] Background loaded: " << width << "x" << height << std::endl;
    return true;
}

//------------------------------------------------------------
// Draw background
//------------------------------------------------------------
static void drawBackground(Live2DRenderer* renderer) {
    if (renderer->backgroundTexture == 0 || renderer->bgShaderProgram == 0) return;
    
    glDisable(GL_BLEND);
    glUseProgram(renderer->bgShaderProgram);
    
    // Full screen quad with proper UV for aspect ratio
    float aspectRatio = (float)renderer->width / (float)renderer->height;
    float bgAspectRatio = (float)renderer->backgroundWidth / (float)renderer->backgroundHeight;
    
    float u0 = 0.0f, u1 = 1.0f, v0 = 0.0f, v1 = 1.0f;
    
    // Cover the screen while maintaining background aspect ratio
    if (aspectRatio > bgAspectRatio) {
        float scale = aspectRatio / bgAspectRatio;
        float offset = (scale - 1.0f) / 2.0f / scale;
        v0 = offset;
        v1 = 1.0f - offset;
    } else {
        float scale = bgAspectRatio / aspectRatio;
        float offset = (scale - 1.0f) / 2.0f / scale;
        u0 = offset;
        u1 = 1.0f - offset;
    }
    
    float vertices[] = {
        -1.0f, -1.0f,    u0, v1,
         1.0f, -1.0f,    u1, v1,
        -1.0f,  1.0f,    u0, v0,
         1.0f,  1.0f,    u1, v0,
    };
    
    GLint posLoc = glGetAttribLocation(renderer->bgShaderProgram, "a_position");
    GLint texLoc = glGetAttribLocation(renderer->bgShaderProgram, "a_texCoord");
    GLint texUniform = glGetUniformLocation(renderer->bgShaderProgram, "u_texture");
    
    glEnableVertexAttribArray(posLoc);
    glEnableVertexAttribArray(texLoc);
    glVertexAttribPointer(posLoc, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(float), vertices);
    glVertexAttribPointer(texLoc, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(float), vertices + 2);
    
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, renderer->backgroundTexture);
    glUniform1i(texUniform, 0);
    
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    
    glDisableVertexAttribArray(posLoc);
    glDisableVertexAttribArray(texLoc);
    glUseProgram(0);
    glEnable(GL_BLEND);
}

//------------------------------------------------------------
// File loader callback for Cubism Framework
//------------------------------------------------------------
static csmByte* CubismLoadFileAsBytes(const std::string filePath, csmSizeInt* outSize) {
    std::string actualPath = filePath;
    
    // Redirect shader paths
    if (filePath.find("FrameworkShaders/") == 0) {
        actualPath = s_shaderBasePath + filePath.substr(strlen("FrameworkShaders/"));
        std::cout << "[Live2D] Redirecting shader: " << filePath << " -> " << actualPath << std::endl;
    } else if (filePath.find("SampleShaders/") == 0) {
        actualPath = "/home/kozakemi/git/flutter_linux_panel/linux/CubismNativeSamples/Samples/OpenGL/Shaders/StandardES/" 
                   + filePath.substr(strlen("SampleShaders/"));
        std::cout << "[Live2D] Redirecting shader: " << filePath << " -> " << actualPath << std::endl;
    }
    
    return LoadFileAsBytes(actualPath, outSize);
}

static void CubismReleaseBytes(csmByte* byteData) {
    ReleaseBytes(byteData);
}

//------------------------------------------------------------
// Initialize Cubism Framework
//------------------------------------------------------------
static void initCubism() {
    if (s_cubismInitialized) return;
    
    s_cubismOption.LogFunction = [](const char* msg) {
        std::cout << "[Cubism] " << msg << std::endl;
    };
    s_cubismOption.LoggingLevel = CubismFramework::Option::LogLevel_Verbose;
    
    s_cubismOption.LoadFileFunction = CubismLoadFileAsBytes;
    s_cubismOption.ReleaseBytesFunction = CubismReleaseBytes;
    
    CubismFramework::StartUp(&s_allocator, &s_cubismOption);
    CubismFramework::Initialize();
    
    s_cubismInitialized = true;
    std::cout << "[Live2D] Cubism Framework initialized" << std::endl;
}

//------------------------------------------------------------
// Public API implementation
//------------------------------------------------------------
extern "C" {

Live2DRenderer* live2d_renderer_create(uint32_t width, uint32_t height, const char* modelPath) {
    Live2DRenderer* renderer = new Live2DRenderer();
    renderer->eglDisplay = EGL_NO_DISPLAY;
    renderer->eglContext = EGL_NO_CONTEXT;
    renderer->eglSurface = EGL_NO_SURFACE;
    renderer->framebuffer = 0;
    renderer->colorTexture = 0;
    renderer->depthRenderbuffer = 0;
    renderer->model = nullptr;
    renderer->textureManager = nullptr;
    renderer->projectionMatrix.LoadIdentity();
    
    renderer->width = width;
    renderer->height = height;
    renderer->initialized = false;
    renderer->lastTime = 0.0f;
    renderer->touchX = 0.0f;
    renderer->touchY = 0.0f;
    renderer->isTouching = false;
    
    // Background
    renderer->backgroundTexture = 0;
    renderer->backgroundWidth = 0;
    renderer->backgroundHeight = 0;
    renderer->bgShaderProgram = 0;
    
    // Model transform defaults
    renderer->modelScale = 1.0f;
    renderer->modelOffsetX = 0.0f;
    renderer->modelOffsetY = 0.0f;
    
    // Initialize EGL
    if (!initEGL(renderer)) {
        delete renderer;
        return nullptr;
    }
    
    // Setup framebuffer
    setupFramebuffer(renderer);
    
    // Initialize Cubism
    initCubism();
    
    // Create texture manager
    renderer->textureManager = new TextureManager();
    
    // Create and load model
    renderer->model = new FlutterLive2DModel();
    
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
        // Default model
        dir = "/home/kozakemi/git/flutter_linux_panel/linux/CubismNativeSamples/Samples/Resources/Hiyori/";
        fileName = "Hiyori.model3.json";
    }
    
    std::cout << "[Live2D] Loading model: " << dir << fileName << std::endl;
    
    if (!renderer->model->LoadAssets(dir, fileName, renderer->textureManager)) {
        std::cerr << "[Live2D] Failed to load model" << std::endl;
        delete renderer->model;
        delete renderer->textureManager;
        delete renderer;
        return nullptr;
    }
    
    // Load background
    loadBackgroundTexture(renderer);
    renderer->bgShaderProgram = createShaderProgram(s_bgVertexShader, s_bgFragmentShader);
    
    // Setup projection matrix
    float aspectRatio = (float)width / (float)height;
    renderer->projectionMatrix.LoadIdentity();
    if (aspectRatio > 1.0f) {
        renderer->projectionMatrix.Scale(1.0f, aspectRatio);
    } else {
        renderer->projectionMatrix.Scale(1.0f / aspectRatio, 1.0f);
    }
    
    renderer->initialized = true;
    std::cout << "[Live2D] Renderer created successfully, model=" << (renderer->model != nullptr ? "OK" : "NULL") << std::endl;
    
    return renderer;
}

void live2d_renderer_destroy(Live2DRenderer* renderer) {
    if (!renderer) return;
    
    std::cout << "[Live2D] Destroying renderer" << std::endl;
    
    // Make context current
    if (renderer->eglContext != EGL_NO_CONTEXT) {
        eglMakeCurrent(renderer->eglDisplay, renderer->eglSurface, renderer->eglSurface, renderer->eglContext);
    }
    
    // Delete model
    if (renderer->model) {
        delete renderer->model;
        renderer->model = nullptr;
    }
    
    // Delete texture manager
    if (renderer->textureManager) {
        delete renderer->textureManager;
        renderer->textureManager = nullptr;
    }
    
    // Delete background resources
    if (renderer->backgroundTexture) {
        glDeleteTextures(1, &renderer->backgroundTexture);
    }
    if (renderer->bgShaderProgram) {
        glDeleteProgram(renderer->bgShaderProgram);
    }
    
    // Delete framebuffer
    if (renderer->framebuffer) {
        glDeleteFramebuffers(1, &renderer->framebuffer);
    }
    if (renderer->colorTexture) {
        glDeleteTextures(1, &renderer->colorTexture);
    }
    if (renderer->depthRenderbuffer) {
        glDeleteRenderbuffers(1, &renderer->depthRenderbuffer);
    }
    
    // Dispose Cubism Framework
    if (s_cubismInitialized) {
        CubismFramework::Dispose();
        s_cubismInitialized = false;
        std::cout << "[Live2D] Cubism Framework disposed" << std::endl;
    }
    
    // Cleanup EGL
    if (renderer->eglContext != EGL_NO_CONTEXT) {
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
    
    static int frameCount = 0;
    frameCount++;
    if (frameCount == 1) {
        std::cout << "[Live2D] First render frame, model=" << (renderer->model != nullptr ? "OK" : "NULL") << std::endl;
    }
    
    // Make context current
    if (!eglMakeCurrent(renderer->eglDisplay, renderer->eglSurface, renderer->eglSurface, renderer->eglContext)) {
        if (frameCount == 1) {
            std::cerr << "[Live2D] Failed to make EGL context current" << std::endl;
        }
        return;
    }
    
    // Bind framebuffer
    glBindFramebuffer(GL_FRAMEBUFFER, renderer->framebuffer);
    glViewport(0, 0, renderer->width, renderer->height);
    
    // Clear
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    
    // Draw background first
    drawBackground(renderer);
    
    // Enable blending
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    
    // Update time
    float deltaTime = 1.0f / 60.0f;
    
    // Update model
    if (renderer->model) {
        // Apply touch
        if (renderer->isTouching) {
            float normalizedX = renderer->touchX * 2.0f - 1.0f;
            float normalizedY = -(renderer->touchY * 2.0f - 1.0f);
            renderer->model->SetDragging(normalizedX, normalizedY);
        } else {
            renderer->model->SetDragging(0.0f, 0.0f);
        }
        
        renderer->model->Update(deltaTime);
        
        CubismMatrix44 projection;
        projection.LoadIdentity();
        float aspectRatio = (float)renderer->width / (float)renderer->height;
        if (aspectRatio > 1.0f) {
            projection.Scale(1.0f, aspectRatio);
        } else {
            projection.Scale(1.0f / aspectRatio, 1.0f);
        }
        
        // Apply model scale and offset
        projection.Scale(renderer->modelScale, renderer->modelScale);
        projection.TranslateRelative(renderer->modelOffsetX, renderer->modelOffsetY);
        
        renderer->model->Draw(projection);
        
        if (frameCount == 1) {
            std::cout << "[Live2D] Model drawn" << std::endl;
        }
    } else {
        if (frameCount == 1) {
            std::cerr << "[Live2D] Model is NULL in render!" << std::endl;
        }
    }
    
    // Read pixels
    glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, buffer);
    
    // Flip vertically
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
}

void live2d_renderer_resize(Live2DRenderer* renderer, uint32_t width, uint32_t height) {
    if (!renderer || (renderer->width == width && renderer->height == height)) return;
    
    renderer->width = width;
    renderer->height = height;
    
    // Make context current
    eglMakeCurrent(renderer->eglDisplay, renderer->eglSurface, renderer->eglSurface, renderer->eglContext);
    
    // Recreate framebuffer
    if (renderer->framebuffer) {
        glDeleteFramebuffers(1, &renderer->framebuffer);
    }
    if (renderer->colorTexture) {
        glDeleteTextures(1, &renderer->colorTexture);
    }
    if (renderer->depthRenderbuffer) {
        glDeleteRenderbuffers(1, &renderer->depthRenderbuffer);
    }
    
    setupFramebuffer(renderer);
}

void live2d_renderer_set_scale(Live2DRenderer* renderer, float scale) {
    if (!renderer) return;
    renderer->modelScale = scale;
}

void live2d_renderer_set_offset(Live2DRenderer* renderer, float offsetX, float offsetY) {
    if (!renderer) return;
    renderer->modelOffsetX = offsetX;
    renderer->modelOffsetY = offsetY;
}

float live2d_renderer_get_scale(Live2DRenderer* renderer) {
    if (!renderer) return 1.0f;
    return renderer->modelScale;
}

float live2d_renderer_get_offset_x(Live2DRenderer* renderer) {
    if (!renderer) return 0.0f;
    return renderer->modelOffsetX;
}

float live2d_renderer_get_offset_y(Live2DRenderer* renderer) {
    if (!renderer) return 0.0f;
    return renderer->modelOffsetY;
}

}  // extern "C"

