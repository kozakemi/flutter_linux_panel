//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <audioplayers_elinux/audioplayers_elinux_plugin.h>
#include <video_player_elinux/video_player_elinux_plugin.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  AudioplayersElinuxPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("AudioplayersElinuxPlugin"));
  VideoPlayerElinuxPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("VideoPlayerElinuxPlugin"));
}
