#include "window_geometry_channel.h"

#include <flutter/standard_method_codec.h>

#include <cmath>

#include "window_geometry.h"

namespace {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;

Map Rectangle(const RECT& rect) {
  return {{Value("x"), Value(static_cast<double>(rect.left))},
          {Value("y"), Value(static_cast<double>(rect.top))},
          {Value("width"), Value(static_cast<double>(rect.right - rect.left))},
          {Value("height"), Value(static_cast<double>(rect.bottom - rect.top))}};
}
}

std::unique_ptr<flutter::MethodChannel<Value>> CreateWindowGeometryChannel(
    flutter::BinaryMessenger* messenger, HWND window) {
  auto channel = std::make_unique<flutter::MethodChannel<Value>>(
      messenger, "io.ente.auth/window_geometry",
      &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([window](const auto& call, auto result) {
    if (call.method_name() == "snapshot") {
      const auto snapshot = window_geometry::Capture(window);
      if (!snapshot) {
        result->Error("win32", "Cannot query window placement");
        return;
      }
      flutter::EncodableList monitors;
      for (const auto& monitor : snapshot->monitors) {
        monitors.emplace_back(Map{
            {Value("id"), Value(monitor.id)},
            {Value("workArea"), Value(Rectangle(monitor.work_area))},
            {Value("dpi"), Value(static_cast<int>(monitor.dpi))},
            {Value("primary"), Value(monitor.primary)}});
      }
      result->Success(Value(Map{
          {Value("normalBounds"), Value(Rectangle(snapshot->normal_bounds))},
          {Value("normalMonitorId"), Value(snapshot->normal_monitor_id)},
          {Value("maximized"), Value(snapshot->maximized)},
          {Value("minimized"), Value(snapshot->minimized)},
          {Value("monitors"), Value(monitors)}}));
    } else if (call.method_name() == "setBounds") {
      const auto& args = std::get<Map>(*call.arguments());
      const auto number = [&args](const char* key) {
        return std::lround(std::get<double>(args.at(Value(key))));
      };
      const LONG x = number("x");
      const LONG y = number("y");
      if (!window_geometry::SetBounds(
              window, RECT{x, y, x + number("width"), y + number("height")})) {
        result->Error("win32", "Cannot restore window placement");
        return;
      }
      result->Success();
    } else {
      result->NotImplemented();
    }
  });
  return channel;
}
