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
  static const detectiveDucky = "$_images/ducky-detective.png";
  static const heroDucky = "$_images/ducky-hero-flying.webp";
  static const cloudsBack = "$_images/clouds-back.webp";
  static const cloudsFront = "$_images/clouds-front.webp";
  static const crowdBackTop1 = "$_images/crowd-back-top1.webp";
  static const crowdFrontTop1 = "$_images/crowd-front-top1.webp";
  static const crowdHeroTop1 = "$_images/crowd-hero-top1.webp";
  static const crowdBack = "$_images/crowd-back.webp";
  static const crowdFront = "$_images/crowd-front.webp";
  static const crowdHeroBackLeft = "$_images/crowd-hero-b0.webp";
  static const crowdHeroBackRight = "$_images/crowd-hero-b1.webp";
  static const crowdHeroLeft = "$_images/crowd-hero-left.webp";
  static const crowdHeroMiddle = "$_images/crowd-hero-mid.webp";
  static const crowdHeroRight = "$_images/crowd-hero-right.webp";
  static const crown = "$_images/crown.svg";
  static const pinkHeart = "$_images/heart-pink.svg";
  static const heartEyesSmiley = "$_images/smiley-heart-eyes.svg";
  static const whiteSparkle = "$_images/sparkle-white.svg";
  static const hundredSticker = "$_images/sticker-hundred.png";
  static const fireSticker = "$_images/sticker-fire.png";
  static const cameraOnPole = "$_images/camera-on-pole.png";
  static const compactHeader = "$_images/rewind-compact-header.png";

  static const introDucky = "$_rive/ente-rewind-intro-ducky.riv";
  static const paletteDucky = "$_rive/ente-rewind-palette-ducky.riv";
  static const globeDucky = "$_rive/ente-rewind-globe-ducky.riv";
  static const chairDucky = "$_rive/ente-rewind-chair-ducky.riv";
  static const hugDucky = "$_rive/ente-rewind-hug-ducky.riv";
  static const famDucky = "$_rive/ente-rewind-fam-ducky.riv";
  static const photosDucky = "$_rive/ente-rewind-photos-ducky.riv";
  static const cameraDucky = "$_rive/ente-rewind-camera-ducky.riv";
  static const badges = "$_rive/ente-rewind-badges.riv";
}
