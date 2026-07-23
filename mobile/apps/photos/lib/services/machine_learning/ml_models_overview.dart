import "package:photos/services/machine_learning/ml_model.dart";
import "package:photos/services/machine_learning/ml_model_assets.dart";

enum MLModels {
  faceDetection,
  faceEmbedding,
  clipImageEncoder,
  clipTextEncoder,
  petFaceDetection,
  petFaceEmbeddingDog,
  petFaceEmbeddingCat,
  petBodyDetection,
  petBodyEmbeddingDog,
  petBodyEmbeddingCat,
}

Iterable<MLModels> get petIndexingModels => const <MLModels>[
  MLModels.petFaceDetection,
  MLModels.petFaceEmbeddingDog,
  MLModels.petFaceEmbeddingCat,
  MLModels.petBodyDetection,
  MLModels.petBodyEmbeddingDog,
  MLModels.petBodyEmbeddingCat,
];

Iterable<MLModels> get coreIndexingModels => MLModels.values.where(
  (model) => model.isIndexingModel && !model.isPetIndexingModel,
);

Iterable<MLModels> get nonIndexingModels =>
    MLModels.values.where((model) => !model.isIndexingModel);

extension MLModelsExtension on MLModels {
  MlModelAsset get model {
    switch (this) {
      case MLModels.faceDetection:
        return FaceDetectionModel.instance;
      case MLModels.faceEmbedding:
        return FaceEmbeddingModel.instance;
      case MLModels.clipImageEncoder:
        return ClipImageModel.instance;
      case MLModels.clipTextEncoder:
        return ClipTextModel.instance;
      case MLModels.petFaceDetection:
        return PetFaceDetectionModel.instance;
      case MLModels.petFaceEmbeddingDog:
        return PetFaceEmbeddingDogModel.instance;
      case MLModels.petFaceEmbeddingCat:
        return PetFaceEmbeddingCatModel.instance;
      case MLModels.petBodyDetection:
        return PetBodyDetectionModel.instance;
      case MLModels.petBodyEmbeddingDog:
        return PetBodyEmbeddingDogModel.instance;
      case MLModels.petBodyEmbeddingCat:
        return PetBodyEmbeddingCatModel.instance;
    }
  }

  bool get isIndexingModel {
    switch (this) {
      case MLModels.faceDetection:
      case MLModels.faceEmbedding:
      case MLModels.clipImageEncoder:
      case MLModels.petFaceDetection:
      case MLModels.petFaceEmbeddingDog:
      case MLModels.petFaceEmbeddingCat:
      case MLModels.petBodyDetection:
      case MLModels.petBodyEmbeddingDog:
      case MLModels.petBodyEmbeddingCat:
        return true;
      case MLModels.clipTextEncoder:
        return false;
    }
  }

  bool get isPetIndexingModel => petIndexingModels.contains(this);
}
