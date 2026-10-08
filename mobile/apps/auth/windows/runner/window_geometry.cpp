#include "window_geometry.h"

#include <shellscalingapi.h>

#include <algorithm>
#include <utility>

namespace window_geometry {
namespace {

std::optional<Monitor> ReadMonitor(HMONITOR handle) {
  MONITORINFOEXW info{};
  info.cbSize = sizeof(info);
  UINT dpi_x = 0;
  UINT dpi_y = 0;
  if (!GetMonitorInfoW(handle, &info) ||
      FAILED(GetDpiForMonitor(handle, MDT_EFFECTIVE_DPI, &dpi_x, &dpi_y)) ||
      dpi_x == 0) {
    return std::nullopt;
  }
  const int length = WideCharToMultiByte(CP_UTF8, 0, info.szDevice, -1, nullptr,
                                       0, nullptr, nullptr);
  if (length == 0) return std::nullopt;
  std::string id(static_cast<size_t>(length), '\0');
  if (!WideCharToMultiByte(CP_UTF8, 0, info.szDevice, -1, id.data(), length,
                          nullptr, nullptr)) {
    return std::nullopt;
  }
  id.pop_back();
  return Monitor{handle, std::move(id), info.rcWork, info.rcMonitor, dpi_x,
                 (info.dwFlags & MONITORINFOF_PRIMARY) != 0};
}

BOOL CALLBACK AddMonitor(HMONITOR handle, HDC, LPRECT, LPARAM data) {
  auto monitor = ReadMonitor(handle);
  if (!monitor) return FALSE;
  auto* monitors = reinterpret_cast<std::vector<Monitor>*>(data);
  monitors->push_back(std::move(*monitor));
  return TRUE;
}

}

std::optional<Snapshot> Capture(HWND window) {
  Snapshot snapshot{};
  WINDOWPLACEMENT placement{};
  placement.length = sizeof(placement);
  if (!GetWindowRect(window, &snapshot.normal_bounds) ||
      !GetWindowPlacement(window, &placement)) {
    return std::nullopt;
  }
  if (!EnumDisplayMonitors(nullptr, nullptr, AddMonitor,
                          reinterpret_cast<LPARAM>(&snapshot.monitors))) {
    return std::nullopt;
  }
  const auto current_handle =
      MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
  const auto current = std::find_if(
      snapshot.monitors.begin(), snapshot.monitors.end(),
      [current_handle](const Monitor& monitor) {
        return monitor.handle == current_handle;
      });
  if (current == snapshot.monitors.end()) return std::nullopt;
  snapshot.maximized = placement.showCmd == SW_SHOWMAXIMIZED;
  snapshot.minimized = placement.showCmd == SW_SHOWMINIMIZED;
  if (snapshot.maximized || snapshot.minimized) {
    snapshot.normal_bounds = placement.rcNormalPosition;
    SetLastError(ERROR_SUCCESS);
    const auto style = GetWindowLongPtrW(window, GWL_EXSTYLE);
    if (style == 0 && GetLastError() != ERROR_SUCCESS) return std::nullopt;
    if ((style & WS_EX_TOOLWINDOW) == 0) {
      OffsetRect(&snapshot.normal_bounds,
                 current->work_area.left - current->screen.left,
                 current->work_area.top - current->screen.top);
    }
  }
  const auto normal_handle =
      MonitorFromRect(&snapshot.normal_bounds, MONITOR_DEFAULTTONEAREST);
  const auto normal = std::find_if(
      snapshot.monitors.begin(), snapshot.monitors.end(),
      [normal_handle](const Monitor& monitor) {
        return monitor.handle == normal_handle;
      });
  if (normal == snapshot.monitors.end()) return std::nullopt;
  snapshot.normal_monitor_id = normal->id;
  return snapshot;
}

bool SetBounds(HWND window, const RECT& bounds) {
  for (int attempt = 0; attempt < 2; ++attempt) {
    if (!SetWindowPos(window, nullptr, bounds.left, bounds.top,
                      bounds.right - bounds.left, bounds.bottom - bounds.top,
                      SWP_NOZORDER | SWP_NOACTIVATE)) {
      return false;
    }
    RECT actual{};
    if (!GetWindowRect(window, &actual)) return false;
    if (EqualRect(&actual, &bounds)) return true;
  }
  return false;
}

}
