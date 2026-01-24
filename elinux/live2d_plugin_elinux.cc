/*
 * Live2D Flutter Plugin for eLinux
 * Copyright 2025 kozakemi
 */

#include "live2d_plugin_elinux.h"

#include <cstring>
#include <iostream>
#include <chrono>
#include <thread>

// Include Live2D renderer (from live2d_core)
#include "linux/live2d_plugin/live2d_renderer.h"

namespace flutter {

// Static method to register plugin
void Live2DPluginElinux::RegisterWithRegistrar(PluginRegistrar* registrar) {
  auto texture_registrar = registrar->texture_registrar();
  auto messenger = registrar->messenger();

  auto channel = std::make_unique<MethodChannel<EncodableValue>>(
      messenger, "com.example.demo1/live2d",
      &StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<Live2DPluginElinux>(
      texture_registrar, std::move(channel));

  // Keep plugin alive
  registrar->AddPlugin(std::move(plugin));
}

Live2DPluginElinux::Live2DPluginElinux(
    TextureRegistrar* texture_registrar,
    std::unique_ptr<MethodChannel<EncodableValue>> channel)
    : texture_registrar_(texture_registrar),
      channel_(std::move(channel)),
      texture_id_(-1),
      renderer_(nullptr),
      is_running_(false),
      width_(0),
      height_(0) {
  channel_->SetMethodCallHandler(
      [this](const MethodCall<EncodableValue>& call,
             std::unique_ptr<MethodResult<EncodableValue>> result) {
        HandleMethodCall(call, std::move(result));
      });
}

Live2DPluginElinux::~Live2DPluginElinux() {
  // Cleanup in destructor
  is_running_ = false;
  if (render_thread_.joinable()) {
    render_thread_.join();
  }
  if (renderer_) {
    live2d_renderer_destroy(renderer_);
    renderer_ = nullptr;
  }
  if (texture_id_ >= 0 && texture_registrar_) {
    texture_registrar_->UnregisterTexture(texture_id_);
    texture_id_ = -1;
  }
  texture_.reset();
  pixel_buffer_.reset();
}

void Live2DPluginElinux::HandleMethodCall(
    const MethodCall<EncodableValue>& call,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  const std::string& method = call.method_name();
  const EncodableValue* args = call.arguments();

  if (method == "initialize") {
    if (args) {
      HandleInitialize(*args, std::move(result));
    } else {
      result->Error("INVALID_ARGS", "Missing arguments");
    }
  } else if (method == "start") {
    HandleStart(std::move(result));
  } else if (method == "stop") {
    HandleStop(std::move(result));
  } else if (method == "dispose") {
    HandleDispose(std::move(result));
  } else if (method == "touch") {
    if (args) {
      HandleTouch(*args, std::move(result));
    } else {
      result->Error("INVALID_ARGS", "Missing arguments");
    }
  } else if (method == "setScale") {
    if (args) {
      HandleSetScale(*args, std::move(result));
    } else {
      result->Error("INVALID_ARGS", "Missing arguments");
    }
  } else if (method == "setOffset") {
    if (args) {
      HandleSetOffset(*args, std::move(result));
    } else {
      result->Error("INVALID_ARGS", "Missing arguments");
    }
  } else if (method == "getTransform") {
    HandleGetTransform(std::move(result));
  } else {
    result->NotImplemented();
  }
}

void Live2DPluginElinux::HandleInitialize(
    const EncodableValue& args,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  if (!std::holds_alternative<EncodableMap>(args)) {
    result->Error("INVALID_ARGS", "Arguments must be a map");
    return;
  }

  const auto& map = std::get<EncodableMap>(args);
  uint32_t width = 800;
  uint32_t height = 600;
  std::string model_path;

  auto width_it = map.find(EncodableValue("width"));
  if (width_it != map.end() &&
      std::holds_alternative<int32_t>(width_it->second)) {
    width = std::get<int32_t>(width_it->second);
  }

  auto height_it = map.find(EncodableValue("height"));
  if (height_it != map.end() &&
      std::holds_alternative<int32_t>(height_it->second)) {
    height = std::get<int32_t>(height_it->second);
  }

  auto path_it = map.find(EncodableValue("modelPath"));
  if (path_it != map.end() &&
      std::holds_alternative<std::string>(path_it->second)) {
    model_path = std::get<std::string>(path_it->second);
  }

  width_ = width;
  height_ = height;
  pixel_buffer_ = std::make_unique<uint8_t[]>(width * height * 4);
  memset(pixel_buffer_.get(), 0, width * height * 4);

  // Create texture
  auto copy_buffer_callback = [this](size_t width, size_t height)
      -> const FlutterDesktopPixelBuffer* {
    static FlutterDesktopPixelBuffer pixel_buffer = {};
    std::lock_guard<std::mutex> lock(buffer_mutex_);
    pixel_buffer.buffer = pixel_buffer_.get();
    pixel_buffer.width = width_;
    pixel_buffer.height = height_;
    return &pixel_buffer;
  };

  PixelBufferTexture pixel_texture(copy_buffer_callback);
  texture_ = std::make_unique<TextureVariant>(std::move(pixel_texture));
  texture_id_ = texture_registrar_->RegisterTexture(texture_.get());

  if (texture_id_ < 0) {
    result->Error("TEXTURE_ERROR", "Failed to register texture");
    return;
  }

  // Create renderer
  const char* model_path_ptr = model_path.empty() ? nullptr : model_path.c_str();
  renderer_ = live2d_renderer_create(width, height, model_path_ptr);
  if (!renderer_) {
    texture_registrar_->UnregisterTexture(texture_id_);
    texture_id_ = -1;
    texture_.reset();
    result->Error("RENDERER_ERROR", "Failed to initialize renderer");
    return;
  }

  std::cout << "[Live2D eLinux] Initialized: " << width << "x" << height
            << std::endl;

  result->Success(EncodableValue(static_cast<int64_t>(texture_id_)));
}

void Live2DPluginElinux::HandleStart(
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  if (!texture_ || !renderer_) {
    result->Error("NOT_INITIALIZED", "Plugin not initialized");
    return;
  }

  if (!is_running_) {
    is_running_ = true;
    render_thread_ = std::thread(&Live2DPluginElinux::RenderLoop, this);
    std::cout << "[Live2D eLinux] Render loop started" << std::endl;
  }

  result->Success(EncodableValue(true));
}

void Live2DPluginElinux::HandleStop(
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  is_running_ = false;
  if (render_thread_.joinable()) {
    render_thread_.join();
  }
  result->Success(EncodableValue(true));
}

void Live2DPluginElinux::HandleDispose(
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  is_running_ = false;
  if (render_thread_.joinable()) {
    render_thread_.join();
  }

  if (renderer_) {
    live2d_renderer_destroy(renderer_);
    renderer_ = nullptr;
  }

  if (texture_id_ >= 0 && texture_registrar_) {
    texture_registrar_->UnregisterTexture(texture_id_);
    texture_id_ = -1;
  }

  texture_.reset();
  pixel_buffer_.reset();

  if (result) {
    result->Success(EncodableValue(true));
  }
}

void Live2DPluginElinux::HandleTouch(
    const EncodableValue& args,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  if (!renderer_) {
    result->Success(EncodableValue(false));
    return;
  }

  if (!std::holds_alternative<EncodableMap>(args)) {
    result->Error("INVALID_ARGS", "Arguments must be a map");
    return;
  }

  const auto& map = std::get<EncodableMap>(args);
  double x = 0.0, y = 0.0;
  std::string type = "move";

  auto x_it = map.find(EncodableValue("x"));
  if (x_it != map.end() && std::holds_alternative<double>(x_it->second)) {
    x = std::get<double>(x_it->second);
  }

  auto y_it = map.find(EncodableValue("y"));
  if (y_it != map.end() && std::holds_alternative<double>(y_it->second)) {
    y = std::get<double>(y_it->second);
  }

  auto type_it = map.find(EncodableValue("type"));
  if (type_it != map.end() &&
      std::holds_alternative<std::string>(type_it->second)) {
    type = std::get<std::string>(type_it->second);
  }

  live2d_renderer_on_touch(renderer_, x, y, type.c_str());
  result->Success(EncodableValue(true));
}

void Live2DPluginElinux::HandleSetScale(
    const EncodableValue& args,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  if (!renderer_) {
    result->Success(EncodableValue(false));
    return;
  }

  if (!std::holds_alternative<EncodableMap>(args)) {
    result->Error("INVALID_ARGS", "Arguments must be a map");
    return;
  }

  const auto& map = std::get<EncodableMap>(args);
  float scale = 1.0f;

  auto scale_it = map.find(EncodableValue("scale"));
  if (scale_it != map.end() &&
      std::holds_alternative<double>(scale_it->second)) {
    scale = static_cast<float>(std::get<double>(scale_it->second));
  }

  live2d_renderer_set_scale(renderer_, scale);
  result->Success(EncodableValue(true));
}

void Live2DPluginElinux::HandleSetOffset(
    const EncodableValue& args,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  if (!renderer_) {
    result->Success(EncodableValue(false));
    return;
  }

  if (!std::holds_alternative<EncodableMap>(args)) {
    result->Error("INVALID_ARGS", "Arguments must be a map");
    return;
  }

  const auto& map = std::get<EncodableMap>(args);
  float offsetX = 0.0f, offsetY = 0.0f;

  auto x_it = map.find(EncodableValue("offsetX"));
  if (x_it != map.end() && std::holds_alternative<double>(x_it->second)) {
    offsetX = static_cast<float>(std::get<double>(x_it->second));
  }

  auto y_it = map.find(EncodableValue("offsetY"));
  if (y_it != map.end() && std::holds_alternative<double>(y_it->second)) {
    offsetY = static_cast<float>(std::get<double>(y_it->second));
  }

  live2d_renderer_set_offset(renderer_, offsetX, offsetY);
  result->Success(EncodableValue(true));
}

void Live2DPluginElinux::HandleGetTransform(
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  if (!renderer_) {
    result->Error("NOT_INITIALIZED", "Renderer not initialized");
    return;
  }

  float scale = live2d_renderer_get_scale(renderer_);
  float offsetX = live2d_renderer_get_offset_x(renderer_);
  float offsetY = live2d_renderer_get_offset_y(renderer_);

  EncodableMap result_map;
  result_map[EncodableValue("scale")] = EncodableValue(scale);
  result_map[EncodableValue("offsetX")] = EncodableValue(offsetX);
  result_map[EncodableValue("offsetY")] = EncodableValue(offsetY);

  result->Success(EncodableValue(result_map));
}

void Live2DPluginElinux::RenderLoop() {
  const int target_fps = 30;
  const int frame_duration_ms = 1000 / target_fps;

  while (is_running_) {
    auto start_time = std::chrono::steady_clock::now();

    if (renderer_ && pixel_buffer_ && width_ > 0 && height_ > 0) {
      {
        std::lock_guard<std::mutex> lock(buffer_mutex_);
        live2d_renderer_render(renderer_, pixel_buffer_.get(), width_,
                               height_);
      }

      if (texture_id_ >= 0 && texture_registrar_) {
        texture_registrar_->MarkTextureFrameAvailable(texture_id_);
      }
    }

    auto end_time = std::chrono::steady_clock::now();
    auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
        end_time - start_time);
    auto sleep_time = frame_duration_ms - elapsed.count();

    if (sleep_time > 0) {
      std::this_thread::sleep_for(std::chrono::milliseconds(sleep_time));
    }
  }
}

}  // namespace flutter
