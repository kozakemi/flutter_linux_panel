/*
 * Live2D Flutter Plugin for eLinux
 * Copyright 2025 kozakemi
 */

#ifndef LIVE2D_PLUGIN_ELINUX_H_
#define LIVE2D_PLUGIN_ELINUX_H_

#include <memory>
#include <mutex>
#include <thread>
#include <atomic>

#include "flutter/method_channel.h"
#include "flutter/plugin_registrar.h"
#include "flutter/standard_method_codec.h"
#include "flutter/texture_registrar.h"

// Forward declaration
struct Live2DRenderer;

namespace flutter {

class Live2DPluginElinux : public Plugin {
 public:
  static void RegisterWithRegistrar(PluginRegistrar* registrar);

  Live2DPluginElinux(
      TextureRegistrar* texture_registrar,
      std::unique_ptr<MethodChannel<EncodableValue>> channel);
  ~Live2DPluginElinux();

 private:
  void HandleMethodCall(
      const MethodCall<EncodableValue>& call,
      std::unique_ptr<MethodResult<EncodableValue>> result);

  void HandleInitialize(const EncodableValue& args,
                        std::unique_ptr<MethodResult<EncodableValue>> result);
  void HandleStart(std::unique_ptr<MethodResult<EncodableValue>> result);
  void HandleStop(std::unique_ptr<MethodResult<EncodableValue>> result);
  void HandleDispose(std::unique_ptr<MethodResult<EncodableValue>> result);
  void HandleTouch(const EncodableValue& args,
                   std::unique_ptr<MethodResult<EncodableValue>> result);
  void HandleSetScale(const EncodableValue& args,
                      std::unique_ptr<MethodResult<EncodableValue>> result);
  void HandleSetOffset(const EncodableValue& args,
                        std::unique_ptr<MethodResult<EncodableValue>> result);
  void HandleGetTransform(
      std::unique_ptr<MethodResult<EncodableValue>> result);

  void RenderLoop();

  TextureRegistrar* texture_registrar_;
  std::unique_ptr<MethodChannel<EncodableValue>> channel_;

  std::unique_ptr<TextureVariant> texture_;
  int64_t texture_id_;
  Live2DRenderer* renderer_;

  std::atomic<bool> is_running_;
  std::thread render_thread_;
  std::mutex buffer_mutex_;

  uint32_t width_;
  uint32_t height_;
  std::unique_ptr<uint8_t[]> pixel_buffer_;
};

}  // namespace flutter

#endif  // LIVE2D_PLUGIN_ELINUX_H_
