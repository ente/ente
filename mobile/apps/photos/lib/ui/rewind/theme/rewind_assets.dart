import "dart:io";

import "package:photos/service_locator.dart";

abstract final class RewindAssets {
  static const _images = "images";
  static const _rive = "rive";

  static File file(String name) => rewindService.assets.file(name);

  static const coverLockup = "$_images/cover-lockup.png";
  static const cameraSticker = "$_images/camera-sticker.png";
  static const coverDoodle = "$_images/doodle-cover.png";
  static const tileDoodle = "$_images/doodle-tile.png";
  static const tileLockup = "$_images/tile-lockup.png";
  static const tileDucky = "$_images/tile-ducky.png";
  static const grain = "$_images/grain.png";
  static const wordmark = "$_images/ente-wordmark.svg";
  static const photoHeapDucky = "$_images/ducky-photo-heap.webp";
  static const polaroidHugDucky = "$_images/ducky-polaroid-hug.png";
  static const heroDucky = "$_images/ducky-hero-flying.webp";
  static const cloudsBack = "$_images/clouds-back.webp";
  static const cloudsFront = "$_images/clouds-front.webp";
  static const crown = "$_images/crown.svg";
  static const pinkHeart = "$_images/heart-pink.svg";
  static const heartEyesSmiley = "$_images/smiley-heart-eyes.svg";
  static const whiteSparkle = "$_images/sparkle-white.svg";
  static const hundredSticker = "$_images/sticker-hundred.png";
  static const cameraOnPole = "$_images/camera-on-pole.png";
  static const compactHeader = "$_images/rewind-compact-header.png";
  static const yellowSparkle = "$_images/sparkle-yellow.svg";
  static const smallYellowSparkle = "$_images/sparkle-yellow-small.svg";
  static const lightningSticker = "$_images/lightning-sticker.svg";
  static const pinkSparkle = "$_images/sparkle-pink.svg";
  static const creamSparkle = "$_images/sparkle-cream.svg";

  static String lockupPiece(String name) => "$_images/lockup-$name.svg";

  static const introDucky = "$_rive/ente-rewind-intro-ducky.riv";
  static const paletteDucky = "$_rive/ente-rewind-palette-ducky.riv";
  static const globeDucky = "$_rive/ente-rewind-globe-ducky.riv";
  static const hugDucky = "$_rive/ente-rewind-hug-ducky.riv";
  static const famDucky = "$_rive/ente-rewind-fam-ducky.riv";
  static const photosDucky = "$_rive/ente-rewind-photos-ducky.riv";
  static const cameraDucky = "$_rive/ente-rewind-camera-ducky.riv";
  static const artistDucky = "$_rive/ente-rewind-artist-ducky.riv";
  static const puzzleDucky = "$_rive/ente-rewind-puzzle-ducky.riv";
  static const superheroDucky = "$_rive/ente-rewind-superhero-ducky.riv";
  static const topPercent = "$_rive/ente-rewind-top-percent.riv";
  static const likesDucky = "$_rive/ente-rewind-likes-ducky.riv";
  static const detectiveDucky = "$_rive/ente-rewind-detective-ducky.riv";
  static const fire = "$_rive/ente-rewind-fire.riv";
  static const badges = "$_rive/ente-rewind-badges.riv";
}
