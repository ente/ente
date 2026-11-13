use std::sync::OnceLock;

use moxcms::{
    Chromaticity, ColorProfile, DataColorSpace, LutDataType, LutStore, LutType, LutWarehouse,
    Matrix3d, ProfileClass,
};

pub(crate) fn key_only_profile() -> Vec<u8> {
    static PROFILE: OnceLock<Vec<u8>> = OnceLock::new();
    PROFILE.get_or_init(encode_key_only_profile).clone()
}

fn encode_key_only_profile() -> Vec<u8> {
    let black_below_white = (0..8)
        .flat_map(|index| [0, 0, 0, if index < 4 { u16::MAX } else { 0 }])
        .collect();
    let mut profile = ColorProfile::default();
    profile.profile_class = ProfileClass::OutputDevice;
    profile.color_space = DataColorSpace::Cmyk;
    profile.pcs = DataColorSpace::Lab;
    profile.white_point = Chromaticity::D50.to_xyzd();
    profile.lut_b_to_a_perceptual = Some(LutWarehouse::Lut(LutDataType {
        num_input_channels: 3,
        num_output_channels: 4,
        num_clut_grid_points: 2,
        matrix: Matrix3d::IDENTITY,
        num_input_table_entries: 2,
        num_output_table_entries: 2,
        input_table: LutStore::Store16([0, u16::MAX].repeat(3)),
        clut_table: LutStore::Store16(black_below_white),
        output_table: LutStore::Store16([0, u16::MAX].repeat(4)),
        lut_type: LutType::Lut16,
    }));
    profile.encode().unwrap()
}
