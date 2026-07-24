mod align;
mod detect;
mod embed;
mod preprocess;

pub(super) use align::run_pet_face_alignment;
pub(super) use detect::{run_pet_body_detection, run_pet_face_detection};
pub(super) use embed::{run_pet_body_embedding, run_pet_face_embedding};

const PET_EMBEDDING_INPUT_SIZE: usize = 224;
const PET_EMBEDDING_CHANNELS: usize = 3;
const PET_SPECIES_DOG: u8 = 0;
const PET_SPECIES_CAT: u8 = 1;
const COCO_CAT: u8 = 15;
const COCO_DOG: u8 = 16;
