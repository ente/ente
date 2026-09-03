import "package:photos/services/machine_learning/ml_model.dart";

class FaceDetectionModel extends MlModelAsset {
  static const remoteFileName = "yolov5s_face_640_640_static_b1.onnx";
  static const _sha256 =
      "e047647409403d52696035ecd445792173e50d7fbdcccac97b958a585db9aa3d";

  FaceDetectionModel._();
  static final instance = FaceDetectionModel._();

  @override
  String get modelRemotePath => kModelBucketEndpoint + remoteFileName;

  @override
  String get modelSha256 => _sha256;
}

class FaceEmbeddingModel extends MlModelAsset {
  static const remoteFileName = "mobilefacenet_portable_static_b1.onnx";
  static const _sha256 =
      "0763fc33f54e138476194da95987e133b3e976075a6b1d3e1b2caedb251b1a36";

  FaceEmbeddingModel._();
  static final instance = FaceEmbeddingModel._();

  @override
  String get modelRemotePath => kModelBucketEndpoint + remoteFileName;

  @override
  String get modelSha256 => _sha256;
}

class ClipImageModel extends MlModelAsset {
  static const remoteFileName = "mobileclip_s2_image_gelu_opset20.onnx";
  static const _sha256 =
      "205a430af825e501c5138e5bb9abea942482a7a4fd4a680e98e47cf0830dce7e";

  ClipImageModel._();
  static final instance = ClipImageModel._();

  @override
  String get modelRemotePath => kModelBucketEndpoint + remoteFileName;

  @override
  String get modelSha256 => _sha256;
}

class ClipTextModel extends MlModelAsset {
  static const remoteFileName = "mobileclip_s2_text_opset18_quant.onnx";
  static const _sha256 =
      "d92f33dfcff83077fc2e0d3414250710efbb51795dfd89767bdbefb5fdc47322";
  static const _vocabFileName = "bpe_simple_vocab_16e6.txt";
  static const _vocabSha256 =
      "67603cfda2e032ad77b5f8808af37789d590db664b26df8705d2bf8b3c553fc8";

  ClipTextModel._();
  static final instance = ClipTextModel._();

  @override
  String get modelRemotePath => kModelBucketEndpoint + remoteFileName;

  @override
  String get modelSha256 => _sha256;

  String get vocabRemotePath => kModelBucketEndpoint + _vocabFileName;
  String get vocabSha256 => _vocabSha256;
}

class PetFaceDetectionModel extends MlModelAsset {
  static const remoteFileName = "yolov5s_pet_face_fp16_V2.onnx";
  static const _sha256 =
      "7876d97992eeb5f3a9f3b35eff5e0e133012928172a8b005093108d8c3ad2d1c";

  PetFaceDetectionModel._();
  static final instance = PetFaceDetectionModel._();

  @override
  String get modelRemotePath => kModelBucketEndpoint + remoteFileName;

  @override
  String get modelSha256 => _sha256;
}

class PetFaceEmbeddingDogModel extends MlModelAsset {
  static const remoteFileName = "dog_face_embedding128.onnx";
  static const _sha256 =
      "fb04d781eb1f7adf6ce3432dc0c5873f16cc051b5c98c14c754afb39e2b92462";

  PetFaceEmbeddingDogModel._();
  static final instance = PetFaceEmbeddingDogModel._();

  @override
  String get modelRemotePath => kModelBucketEndpoint + remoteFileName;

  @override
  String get modelSha256 => _sha256;
}

class PetFaceEmbeddingCatModel extends MlModelAsset {
  static const remoteFileName = "cat_face_embedding128.onnx";
  static const _sha256 =
      "32b10694a27f6404d2beaddbd64f07ad555f72dccb12ee60a7afe5dcf6aad6cd";

  PetFaceEmbeddingCatModel._();
  static final instance = PetFaceEmbeddingCatModel._();

  @override
  String get modelRemotePath => kModelBucketEndpoint + remoteFileName;

  @override
  String get modelSha256 => _sha256;
}

class PetBodyDetectionModel extends MlModelAsset {
  static const remoteFileName = "yolov5s_object_fp16.onnx";
  static const _sha256 =
      "113f0c18632eb2c4f6deebcd40eb01c676492e9b43923c2d336e1b4012fce9ef";

  PetBodyDetectionModel._();
  static final instance = PetBodyDetectionModel._();

  @override
  String get modelRemotePath => kModelBucketEndpoint + remoteFileName;

  @override
  String get modelSha256 => _sha256;
}

class PetBodyEmbeddingDogModel extends MlModelAsset {
  static const remoteFileName = "dog_body_embedding192.onnx";
  static const _sha256 =
      "1d85aa20358137e30f11c2d0baa9a2248b9997928d501fe15365d1fc57522770";

  PetBodyEmbeddingDogModel._();
  static final instance = PetBodyEmbeddingDogModel._();

  @override
  String get modelRemotePath => kModelBucketEndpoint + remoteFileName;

  @override
  String get modelSha256 => _sha256;
}

class PetBodyEmbeddingCatModel extends MlModelAsset {
  static const remoteFileName = "cat_body_embedding192.onnx";
  static const _sha256 =
      "62fb5891e61be69a96510d8ec56e7525a9541b0283e54574d27c86c9b4a26ddf";

  PetBodyEmbeddingCatModel._();
  static final instance = PetBodyEmbeddingCatModel._();

  @override
  String get modelRemotePath => kModelBucketEndpoint + remoteFileName;

  @override
  String get modelSha256 => _sha256;
}

class OcrDetectionModel extends MlModelAsset {
  static const remoteFileName = "PP-OCRv5/det.onnx";
  static const _sha256 =
      "d7fe3ea74652890722c0f4d02458b7261d9f5ae6c92904d05707c9eb155c7924";

  OcrDetectionModel._();
  static final instance = OcrDetectionModel._();

  @override
  String get modelRemotePath => kModelBucketEndpoint + remoteFileName;

  @override
  String get modelSha256 => _sha256;
}

class OcrClassificationModel extends MlModelAsset {
  static const remoteFileName = "PP-OCRv5/cls.onnx";
  static const _sha256 =
      "f4bb53707100c5f3d59ba834eb05bb400369f20aed35d4b26807b1bfadd2a70e";

  OcrClassificationModel._();
  static final instance = OcrClassificationModel._();

  @override
  String get modelRemotePath => kModelBucketEndpoint + remoteFileName;

  @override
  String get modelSha256 => _sha256;
}

class OcrRecognitionModel extends MlModelAsset {
  static const remoteFileName = "PP-OCRv5/rec.onnx";
  static const _sha256 =
      "bf66820f48fa99f779974c4df78e5274a9d8e0458c4137e8c5357e40e2c3faf2";

  OcrRecognitionModel._();
  static final instance = OcrRecognitionModel._();

  @override
  String get modelRemotePath => kModelBucketEndpoint + remoteFileName;

  @override
  String get modelSha256 => _sha256;
}

class OcrDictionaryAsset extends MlModelAsset {
  static const remoteFileName = "PP-OCRv5/ppocrv5_dict.txt";
  static const _sha256 =
      "d1979e9f794c464c0d2e0b70a7fe14dd978e9dc644c0e71f14158cdf8342af1b";

  OcrDictionaryAsset._();
  static final instance = OcrDictionaryAsset._();

  @override
  String get modelRemotePath => kModelBucketEndpoint + remoteFileName;

  @override
  String get modelSha256 => _sha256;
}
