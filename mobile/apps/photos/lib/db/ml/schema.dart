import 'package:photos/services/machine_learning/face_ml/face_filtering/face_filtering_constants.dart';

const facesTable = 'faces';
const fileIDColumn = 'file_id';
const objectIdColumn = 'obj_id';
const faceIDColumn = 'face_id';
const faceDetectionColumn = 'detection';
const embeddingColumn = 'embedding';
const faceScore = 'score';
const faceBlur = 'blur';
const isSideways = 'is_sideways';
const imageWidth = 'width';
const imageHeight = 'height';
const mlVersionColumn = 'ml_version';
const personIdColumn = 'person_id';
const clusterIDColumn = 'cluster_id';
const personOrClusterIdColumn = 'person_or_cluster_id';
const textQueryColumn = 'text_query';
const createdAtColumn = 'created_at';

const createFacesTable =
    '''CREATE TABLE IF NOT EXISTS $facesTable (
  $fileIDColumn	INTEGER NOT NULL,
  $faceIDColumn  TEXT NOT NULL UNIQUE,
	$faceDetectionColumn	TEXT NOT NULL,
  $embeddingColumn BLOB NOT NULL,
  $faceScore  REAL NOT NULL,
  $faceBlur REAL NOT NULL DEFAULT $kLapacianDefault,
  $isSideways	INTEGER NOT NULL DEFAULT 0,
  $imageHeight	INTEGER NOT NULL DEFAULT 0,
  $imageWidth	INTEGER NOT NULL DEFAULT 0,
  $mlVersionColumn	INTEGER NOT NULL DEFAULT -1,
  PRIMARY KEY($fileIDColumn, $faceIDColumn)
  );
  ''';

const deleteFacesTable = 'DELETE FROM $facesTable';
const faceClustersTable = 'face_clusters';

const createFaceClustersTable =
    '''
CREATE TABLE IF NOT EXISTS $faceClustersTable (
  $faceIDColumn	TEXT NOT NULL,
  $clusterIDColumn TEXT NOT NULL,
  PRIMARY KEY($faceIDColumn)
);
''';
const fcClusterIDIndex =
    '''CREATE INDEX IF NOT EXISTS idx_fcClusterID ON $faceClustersTable($clusterIDColumn);''';
const deleteFaceClustersTable = 'DELETE FROM $faceClustersTable';
const clusterPersonTable = 'cluster_person';

const createClusterPersonTable =
    '''
CREATE TABLE IF NOT EXISTS $clusterPersonTable (
  $personIdColumn	TEXT NOT NULL,
  $clusterIDColumn	TEXT NOT NULL,
  PRIMARY KEY($personIdColumn, $clusterIDColumn)
);
''';
const deleteClusterPersonTable = 'DELETE FROM $clusterPersonTable';

const clusterSummaryTable = 'cluster_summary';
const avgColumn = 'avg';
const countColumn = 'count';
const createClusterSummaryTable =
    '''
CREATE TABLE IF NOT EXISTS $clusterSummaryTable (
  $clusterIDColumn	TEXT NOT NULL,
  $avgColumn BLOB NOT NULL,
  $countColumn INTEGER NOT NULL,
  PRIMARY KEY($clusterIDColumn)
);
''';

const deleteClusterSummaryTable = 'DELETE FROM $clusterSummaryTable';

const clusterCentroidVectorIdMappingTable = 'cluster_centroid_vector_id_map';
const clusterCentroidVectorIdColumn = 'cluster_vector_id';

const createClusterCentroidVectorIdMappingTable =
    '''
CREATE TABLE IF NOT EXISTS $clusterCentroidVectorIdMappingTable (
  $clusterCentroidVectorIdColumn INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
  $clusterIDColumn TEXT NOT NULL UNIQUE
);
''';

const deleteClusterCentroidVectorIdMappingTable =
    'DELETE FROM $clusterCentroidVectorIdMappingTable';

const notPersonFeedback = 'not_person_feedback';

const createNotPersonFeedbackTable =
    '''
CREATE TABLE IF NOT EXISTS $notPersonFeedback (
  $personIdColumn	TEXT NOT NULL,
  $clusterIDColumn TEXT NOT NULL,
  PRIMARY KEY($personIdColumn, $clusterIDColumn)
);
''';
const deleteNotPersonFeedbackTable = 'DELETE FROM $notPersonFeedback';
const clipTable = 'clip';

const createClipEmbeddingsTable =
    '''
CREATE TABLE IF NOT EXISTS $clipTable ( 
  $fileIDColumn INTEGER NOT NULL,
  $embeddingColumn BLOB NOT NULL,
  $mlVersionColumn INTEGER NOT NULL,
  PRIMARY KEY ($fileIDColumn)
  );
''';

const deleteClipEmbeddingsTable = 'DELETE FROM $clipTable';

const fileDataTable = 'filedata';
const createFileDataTable =
    '''
CREATE TABLE IF NOT EXISTS $fileDataTable ( 
  $fileIDColumn INTEGER NOT NULL,
  user_id INTEGER NOT NULL,
  type TEXT NOT NULL,
  size INTEGER NOT NULL,
  $objectIdColumn TEXT,
  obj_nonce TEXT,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY ($fileIDColumn, type)
  );
''';

const deleteFileDataTable = 'DELETE FROM $fileDataTable';

const faceCacheTable = 'face_cache';

const createFaceCacheTable =
    '''
CREATE TABLE IF NOT EXISTS $faceCacheTable (
  $personOrClusterIdColumn TEXT NOT NULL UNIQUE,
  $faceIDColumn TEXT NOT NULL UNIQUE,
  PRIMARY KEY ($personOrClusterIdColumn)
);
''';

const deleteFaceCacheTable = 'DELETE FROM $faceCacheTable';

const textEmbeddingsCacheTable = 'text_embeddings_cache';

const createTextEmbeddingsCacheTable =
    '''
CREATE TABLE IF NOT EXISTS $textEmbeddingsCacheTable (
  $textQueryColumn TEXT NOT NULL,
  $embeddingColumn BLOB NOT NULL,
  $mlVersionColumn INTEGER NOT NULL,
  $createdAtColumn INTEGER NOT NULL,
  PRIMARY KEY ($textQueryColumn)
);
''';

const deleteTextEmbeddingsCacheTable = 'DELETE FROM $textEmbeddingsCacheTable';

const offlineFileKeyMapTable = 'offline_file_key_map';
const offlineFileKeyLocalIdColumn = 'local_id';
const offlineFileKeyIntIdColumn = 'local_int_id';

const createOfflineFileKeyMapTable =
    '''
CREATE TABLE IF NOT EXISTS $offlineFileKeyMapTable (
  $offlineFileKeyIntIdColumn INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
  $offlineFileKeyLocalIdColumn TEXT NOT NULL UNIQUE
);
''';

const petFaceIDColumn = 'pet_face_id';
const petBodyIDColumn = 'pet_body_id';
const speciesColumn = 'species';
const detectionColumn = 'detection';
const faceVectorIdColumn = 'face_vector_id';
const bodyVectorIdColumn = 'body_vector_id';

const petFacesTable = 'pet_faces';

const createPetFacesTable =
    '''CREATE TABLE IF NOT EXISTS $petFacesTable (
  $fileIDColumn INTEGER NOT NULL,
  $petFaceIDColumn TEXT NOT NULL UNIQUE,
  $faceDetectionColumn TEXT NOT NULL,
  $faceVectorIdColumn INTEGER UNIQUE,
  $speciesColumn INTEGER NOT NULL,
  $faceScore REAL NOT NULL,
  $imageHeight INTEGER NOT NULL DEFAULT 0,
  $imageWidth INTEGER NOT NULL DEFAULT 0,
  $mlVersionColumn INTEGER NOT NULL DEFAULT -1,
  PRIMARY KEY($fileIDColumn, $petFaceIDColumn)
);
''';

const deletePetFacesTable = 'DELETE FROM $petFacesTable';

const petBodiesTable = 'pet_bodies';
// Both tables use the SQL column "score".
const bodyScore = faceScore;

const createPetBodiesTable =
    '''CREATE TABLE IF NOT EXISTS $petBodiesTable (
  $fileIDColumn INTEGER NOT NULL,
  $petBodyIDColumn TEXT NOT NULL UNIQUE,
  $detectionColumn TEXT NOT NULL,
  $bodyVectorIdColumn INTEGER UNIQUE,
  $speciesColumn INTEGER NOT NULL,
  $bodyScore REAL NOT NULL,
  $imageHeight INTEGER NOT NULL DEFAULT 0,
  $imageWidth INTEGER NOT NULL DEFAULT 0,
  $mlVersionColumn INTEGER NOT NULL DEFAULT -1,
  PRIMARY KEY($fileIDColumn, $petBodyIDColumn)
);
''';

const deletePetBodiesTable = 'DELETE FROM $petBodiesTable';

const petFaceVectorIdMappingTable = 'pet_face_vector_id_map';
const petFaceVectorIdColumn = 'pet_face_vector_id';

const createPetFaceVectorIdMappingTable =
    '''
CREATE TABLE IF NOT EXISTS $petFaceVectorIdMappingTable (
  $petFaceVectorIdColumn INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
  $petFaceIDColumn TEXT NOT NULL UNIQUE
);
''';

const deletePetFaceVectorIdMappingTable =
    'DELETE FROM $petFaceVectorIdMappingTable';

const petBodyVectorIdMappingTable = 'pet_body_vector_id_map';
const petBodyVectorIdColumn = 'pet_body_vector_id';

const createPetBodyVectorIdMappingTable =
    '''
CREATE TABLE IF NOT EXISTS $petBodyVectorIdMappingTable (
  $petBodyVectorIdColumn INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
  $petBodyIDColumn TEXT NOT NULL UNIQUE
);
''';

const deletePetBodyVectorIdMappingTable =
    'DELETE FROM $petBodyVectorIdMappingTable';
