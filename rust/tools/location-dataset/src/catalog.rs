use ente_location::TerritoryId;

pub(crate) struct DisputedAreaSource {
    pub source_id: &'static str,
    pub geometry_code: [u8; 2],
    pub territory: TerritoryId,
    pub additional_countries: &'static [[u8; 2]],
}

pub(crate) struct UkrainianRegionSource {
    pub iso_3166_2: &'static str,
    pub geometry_code: [u8; 2],
    pub territory: TerritoryId,
}

pub(crate) const WORLDVIEWS: &[([u8; 2], &str)] = &[
    (*b"AR", "ADM0_A3_AR"),
    (*b"BD", "ADM0_A3_BD"),
    (*b"BR", "ADM0_A3_BR"),
    (*b"CN", "ADM0_A3_CN"),
    (*b"DE", "ADM0_A3_DE"),
    (*b"EG", "ADM0_A3_EG"),
    (*b"ES", "ADM0_A3_ES"),
    (*b"FR", "ADM0_A3_FR"),
    (*b"GB", "ADM0_A3_GB"),
    (*b"GR", "ADM0_A3_GR"),
    (*b"IN", "ADM0_A3_IN"),
    (*b"ID", "ADM0_A3_ID"),
    (*b"IL", "ADM0_A3_IL"),
    (*b"IT", "ADM0_A3_IT"),
    (*b"JP", "ADM0_A3_JP"),
    (*b"KR", "ADM0_A3_KO"),
    (*b"MA", "ADM0_A3_MA"),
    (*b"NP", "ADM0_A3_NP"),
    (*b"NL", "ADM0_A3_NL"),
    (*b"PK", "ADM0_A3_PK"),
    (*b"PL", "ADM0_A3_PL"),
    (*b"PT", "ADM0_A3_PT"),
    (*b"PS", "ADM0_A3_PS"),
    (*b"RU", "ADM0_A3_RU"),
    (*b"SA", "ADM0_A3_SA"),
    (*b"SE", "ADM0_A3_SE"),
    (*b"TR", "ADM0_A3_TR"),
    (*b"TW", "ADM0_A3_TW"),
    (*b"UA", "ADM0_A3_UA"),
    (*b"US", "ADM0_A3_US"),
    (*b"VN", "ADM0_A3_VN"),
];

const NONE: &[[u8; 2]] = &[];
const PALESTINE: &[[u8; 2]] = &[*b"PS"];

pub(crate) const DISPUTED_AREAS: &[DisputedAreaSource] = &[
    area("B00", *b"AP", TerritoryId::ARUNACHAL_PRADESH, NONE),
    area("B01", *b"TV", TerritoryId::TIRPANI_VALLEYS, NONE),
    area("B02", *b"BH", TerritoryId::BARA_HOTII_VALLEYS, NONE),
    area("B03", *b"DM", TerritoryId::DEMCHOK, NONE),
    area("B04", *b"SV", TerritoryId::SAMDU_VALLEYS, NONE),
    area("B05", *b"KM", TerritoryId::KASHMIR, NONE),
    area("B06", *b"TK", TerritoryId::TRANS_KARAKORAM_TRACT, NONE),
    area("B07", *b"AC", TerritoryId::AKSAI_CHIN, NONE),
    area("B08", *b"GB", TerritoryId::GILGIT_BALTISTAN, NONE),
    area("B09", *b"AK", TerritoryId::AZAD_KASHMIR, NONE),
    area("B45", *b"SC", TerritoryId::SIACHEN_GLACIER, NONE),
    area("B53", *b"GZ", TerritoryId::GAZA_STRIP, NONE),
    area("B54", *b"WB", TerritoryId::WEST_BANK, NONE),
    area("B16", *b"GH", TerritoryId::GOLAN_HEIGHTS, NONE),
    area("B58", *b"SF", TerritoryId::SHEBAA_FARMS, NONE),
    area("B98", *b"EJ", TerritoryId::EAST_JERUSALEM, NONE),
    area("B78", *b"LF", TerritoryId::LATRUN_FORT, NONE),
    area("B79", *b"JN", TerritoryId::JERUSALEM_NO_MANS_LAND, NONE),
    area("B99", *b"MS", TerritoryId::MOUNT_SCOPUS, PALESTINE),
    area("B77", *b"TW", TerritoryId::TAIWAN, NONE),
    area("B89", *b"CR", TerritoryId::CRIMEA, NONE),
    area("B57", *b"KO", TerritoryId::KOSOVO, NONE),
    area(
        "B19",
        *b"WM",
        TerritoryId::WESTERN_SAHARA_MOROCCAN_AREA,
        NONE,
    ),
    area(
        "B28",
        *b"WS",
        TerritoryId::WESTERN_SAHARA_SELF_ADMINISTERED_AREA,
        NONE,
    ),
    area("B20", *b"NC", TerritoryId::NORTHERN_CYPRUS, NONE),
    area("B43", *b"CB", TerritoryId::CYPRUS_BUFFER_ZONE, NONE),
    area("B12", *b"FK", TerritoryId::FALKLAND_ISLANDS, NONE),
];

pub(crate) const UKRAINIAN_REGIONS: &[UkrainianRegionSource] = &[
    UkrainianRegionSource {
        iso_3166_2: "UA-14",
        geometry_code: *b"DO",
        territory: TerritoryId::DONETSK_REGION,
    },
    UkrainianRegionSource {
        iso_3166_2: "UA-09",
        geometry_code: *b"LU",
        territory: TerritoryId::LUHANSK_REGION,
    },
    UkrainianRegionSource {
        iso_3166_2: "UA-65",
        geometry_code: *b"KH",
        territory: TerritoryId::KHERSON_REGION,
    },
    UkrainianRegionSource {
        iso_3166_2: "UA-23",
        geometry_code: *b"ZP",
        territory: TerritoryId::ZAPORIZHZHIA_REGION,
    },
];

const fn area(
    source_id: &'static str,
    geometry_code: [u8; 2],
    territory: TerritoryId,
    additional_countries: &'static [[u8; 2]],
) -> DisputedAreaSource {
    DisputedAreaSource {
        source_id,
        geometry_code,
        territory,
        additional_countries,
    }
}
