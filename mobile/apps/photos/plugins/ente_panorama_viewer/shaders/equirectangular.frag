#version 320 es

precision highp float;

#include <flutter/runtime_effect.glsl>

uniform vec2 u_size;
uniform float u_tan_half_fov;
uniform float u_longitude;
uniform float u_latitude;
uniform vec4 u_crop;
uniform float u_wrap_longitude;
uniform sampler2D u_texture;

out vec4 frag_color;

const float PI = 3.14159265358979323846;

void main() {
  vec2 position = FlutterFragCoord().xy / u_size;
  vec2 normalized = vec2(
    position.x * 2.0 - 1.0,
    1.0 - position.y * 2.0
  );
  float aspect = u_size.x / u_size.y;
  vec3 ray = normalize(vec3(
    normalized.x * aspect * u_tan_half_fov,
    normalized.y * u_tan_half_fov,
    1.0
  ));

  float sin_latitude = sin(u_latitude);
  float cos_latitude = cos(u_latitude);
  ray = vec3(
    ray.x,
    cos_latitude * ray.y + sin_latitude * ray.z,
    -sin_latitude * ray.y + cos_latitude * ray.z
  );

  float sin_longitude = sin(u_longitude);
  float cos_longitude = cos(u_longitude);
  ray = vec3(
    cos_longitude * ray.x + sin_longitude * ray.z,
    ray.y,
    -sin_longitude * ray.x + cos_longitude * ray.z
  );

  float source_u = 0.5 + atan(ray.x, ray.z) / (2.0 * PI);
  source_u = u_wrap_longitude > 0.5 ? fract(source_u) : source_u;
  if (u_wrap_longitude < 0.5) {
    if (u_crop.z > 0.99999 && source_u < u_crop.x) {
      source_u += 1.0;
    } else if (u_crop.x < 0.00001 && source_u > u_crop.z) {
      source_u -= 1.0;
    }
  }
  vec2 sphere_uv = vec2(
    source_u,
    0.5 - asin(clamp(ray.y, -1.0, 1.0)) / PI
  );

  vec2 texture_uv = (sphere_uv - u_crop.xy) / (u_crop.zw - u_crop.xy);
  bool inside_crop =
    texture_uv.x >= 0.0 &&
    texture_uv.x <= 1.0 &&
    texture_uv.y >= 0.0 &&
    texture_uv.y <= 1.0;
  if (!inside_crop) {
    frag_color = vec4(0.0);
    return;
  }

  vec2 clamped_uv = clamp(texture_uv, vec2(0.00001), vec2(0.99999));
#if defined(IMPELLER_TARGET_OPENGLES) && !defined(IMPELLER_OPENGLES_UNFLIPPED_DEPRECATED)
  clamped_uv.y = 1.0 - clamped_uv.y;
#endif
  vec4 sharp_color = texture(u_texture, clamped_uv);
  vec2 crop_size = u_crop.zw - u_crop.xy;
  bool full_sphere = crop_size.x > 0.99999 && crop_size.y > 0.99999;
  float edge_distance = min(
    min(texture_uv.x, 1.0 - texture_uv.x),
    min(texture_uv.y, 1.0 - texture_uv.y)
  );
  float edge_alpha = full_sphere
    ? 1.0
    : smoothstep(0.0, 0.004, edge_distance);
  frag_color = sharp_color * edge_alpha;
}
