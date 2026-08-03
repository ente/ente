#version 320 es

precision highp float;

#include <flutter/runtime_effect.glsl>

uniform vec2 u_size;
uniform float u_time;

out vec4 frag_color;

float sdTriangle(vec2 p, vec2 a, vec2 b, vec2 c) {
  vec2 ba = b - a;
  vec2 pa = p - a;
  vec2 cb = c - b;
  vec2 pb = p - b;
  vec2 ac = a - c;
  vec2 pc = p - c;

  vec2 q1 = ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0) - pa;
  vec2 q2 = cb * clamp(dot(pb, cb) / dot(cb, cb), 0.0, 1.0) - pb;
  vec2 q3 = ac * clamp(dot(pc, ac) / dot(ac, ac), 0.0, 1.0) - pc;

  float s = sign(ba.x * ac.y - ba.y * ac.x);

  vec2 d = min(
    min(
      vec2(dot(q1, q1), s * (pa.x * ba.y - pa.y * ba.x)),
      vec2(dot(q2, q2), s * (pb.x * cb.y - pb.y * cb.x))
    ),
    vec2(dot(q3, q3), s * (pc.x * ac.y - pc.y * ac.x))
  );

  return -sqrt(d.x) * sign(d.y);
}

float sdHeart(vec2 p) {
  const float radius = 0.32;
  const float height = 0.15;
  float offset = radius / sqrt(2.0);

  float circles = min(
    length(p - vec2(-offset, height)) - radius,
    length(p - vec2(offset, height)) - radius
  );

  float triangle = sdTriangle(
    p,
    vec2(0.0, height - 3.0 * offset),
    vec2(-2.0 * offset, height - offset),
    vec2(2.0 * offset, height - offset)
  );

  return min(circles, triangle);
}

vec3 palette(float index) {
  float band = mod(index, 4.0);

  if (band < 0.5) return vec3(0.64, 0.79, 0.45);
  if (band < 1.5) return vec3(0.27, 0.59, 0.25);
  if (band < 2.5) return vec3(0.15, 0.48, 0.20);

  return vec3(0.10, 0.27, 0.12);
}

vec3 renderPattern(vec2 p) {
  const float ratio = 1.5;
  const float baseScale = 0.09;
  const int heartCount = 16;

  float animation = u_time * 1.2;
  float phase = fract(animation);
  float cycle = floor(animation);

  vec3 color = vec3(0.10, 0.27, 0.12);

  for (int n = 0; n < heartCount; n++) {
    int i = heartCount - 1 - n;
    float index = float(i);
    float scale = baseScale * pow(ratio, index + phase);

    if (sdHeart(p / scale) < 0.0) {
      color = palette(index - cycle);
    }
  }

  return color;
}

vec3 renderAt(vec2 fragCoord) {
  vec2 p = vec2(
    2.0 * fragCoord.x - u_size.x,
    u_size.y - 2.0 * fragCoord.y
  ) / u_size.y;
  return renderPattern(p);
}

vec3 gaussianBlur(vec2 fragCoord, float radius) {
  vec3 color = vec3(0.0);

  color += renderAt(fragCoord + radius * vec2(-1.0, -1.0));
  color += renderAt(fragCoord + radius * vec2(0.0, -1.0)) * 2.0;
  color += renderAt(fragCoord + radius * vec2(1.0, -1.0));

  color += renderAt(fragCoord + radius * vec2(-1.0, 0.0)) * 2.0;
  color += renderAt(fragCoord) * 4.0;
  color += renderAt(fragCoord + radius * vec2(1.0, 0.0)) * 2.0;

  color += renderAt(fragCoord + radius * vec2(-1.0, 1.0));
  color += renderAt(fragCoord + radius * vec2(0.0, 1.0)) * 2.0;
  color += renderAt(fragCoord + radius * vec2(1.0, 1.0));

  return color / 16.0;
}

void main() {
  vec2 fragCoord = FlutterFragCoord().xy;
  vec2 p = (2.0 * fragCoord - u_size) / u_size.y;

  vec3 level0 = renderAt(fragCoord);
  vec3 level1 = gaussianBlur(fragCoord, 2.0);
  vec3 level2 = gaussianBlur(fragCoord, 4.0);
  vec3 level3 = gaussianBlur(fragCoord, 7.0);

  float blurLevel = smoothstep(0.05, 1.25, length(p)) * 3.0;
  vec3 color;

  if (blurLevel < 1.0) {
    color = mix(level0, level1, smoothstep(0.0, 1.0, blurLevel));
  } else if (blurLevel < 2.0) {
    color = mix(level1, level2, smoothstep(1.0, 2.0, blurLevel));
  } else {
    color = mix(level2, level3, smoothstep(2.0, 3.0, blurLevel));
  }

  frag_color = vec4(color, 1.0);
}
