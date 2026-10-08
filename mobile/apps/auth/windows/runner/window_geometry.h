#ifndef RUNNER_WINDOW_GEOMETRY_H_
#define RUNNER_WINDOW_GEOMETRY_H_

#include <windows.h>

#include <optional>
#include <string>
#include <vector>

namespace window_geometry {

struct Monitor {
  HMONITOR handle;
  std::string id;
  RECT work_area;
  RECT screen;
  UINT dpi;
  bool primary;
};

struct Snapshot {
  RECT normal_bounds;
  std::string normal_monitor_id;
  bool maximized;
  bool minimized;
  std::vector<Monitor> monitors;
};

std::optional<Snapshot> Capture(HWND window);
bool SetBounds(HWND window, const RECT& bounds);

}

#endif
