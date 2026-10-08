#ifndef RUNNER_WINDOW_GEOMETRY_CHANNEL_H_
#define RUNNER_WINDOW_GEOMETRY_CHANNEL_H_

#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreateWindowGeometryChannel(flutter::BinaryMessenger* messenger, HWND window);

#endif
