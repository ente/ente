use std::collections::HashSet;

use anyhow::{Context, Result, ensure};
use ente_location::{Coordinate, CountryCode, normalize_search_text};
use ente_photos::{files::File, location::LocationIndex};

use crate::{
    args::{FileQuery, ListArgs},
    home,
    output::{self, CityView, CountryView},
};

pub async fn open(offline: bool) -> Result<LocationIndex> {
    let root = home::application_home()?.join("assets");
    let _download = if LocationIndex::is_downloaded(&root) {
        None
    } else {
        ensure!(
            !offline,
            "location data has not been downloaded; run the command online first"
        );
        let lock = home::lock_assets()?;
        if !LocationIndex::is_downloaded(&root) {
            eprintln!("Downloading location data.");
        }
        Some(lock)
    };
    LocationIndex::open(&root)
        .await
        .context("cannot load location data")
}

pub fn coordinate(file: &File) -> Option<Coordinate> {
    file.location
        .as_ref()
        .map(|location| Coordinate::new(location.latitude, location.longitude))
}

pub fn list(
    index: &LocationIndex,
    coordinates: &[Coordinate],
    countries: bool,
    args: &ListArgs,
    as_json: bool,
) -> Result<()> {
    if countries {
        let mut groups = index.group_countries(coordinates, None)?;
        groups.sort_by(|a, b| {
            b.coordinate_indices
                .len()
                .cmp(&a.coordinate_indices.len())
                .then_with(|| country_name(index, &a.country).cmp(country_name(index, &b.country)))
        });
        output::countries(
            groups
                .iter()
                .map(|group| CountryView::new(country_name(index, &group.country), group)),
            args,
            as_json,
        )
    } else {
        let mut groups = index.group_cities(coordinates, "");
        groups.sort_by(|a, b| {
            b.coordinate_indices
                .len()
                .cmp(&a.coordinate_indices.len())
                .then_with(|| a.city.name.cmp(&b.city.name))
                .then_with(|| a.city.country_name.cmp(&b.city.country_name))
        });
        output::cities(groups.into_iter().map(CityView::from), args, as_json)
    }
}

pub fn matching(
    index: &LocationIndex,
    query: &FileQuery,
    located: &[(i64, Coordinate)],
) -> Result<HashSet<i64>> {
    let coordinates = located
        .iter()
        .map(|&(_, coordinate)| coordinate)
        .collect::<Vec<_>>();
    let mut matched = vec![true; located.len()];
    if let Some(place) = &query.place {
        let groups = index.group_cities(&coordinates, "");
        let place = NameMatch::new(place, groups.iter().map(|group| group.city.name.as_str()));
        keep_members(
            &mut matched,
            groups
                .iter()
                .filter(|group| place.matches(&group.city.name))
                .map(|group| &group.coordinate_indices),
        );
    }
    if let Some(country) = &query.country {
        let country = CountryMatch::new(index, country)?;
        let groups = index.group_countries(&coordinates, None)?;
        keep_members(
            &mut matched,
            groups
                .iter()
                .filter(|group| country.matches(index, group.country))
                .map(|group| &group.coordinate_indices),
        );
    }
    Ok(located
        .iter()
        .zip(matched)
        .filter_map(|(&(id, _), matched)| matched.then_some(id))
        .collect())
}

fn keep_members<'a>(matched: &mut [bool], groups: impl Iterator<Item = &'a Vec<u32>>) {
    let mut members = vec![false; matched.len()];
    for &index in groups.flatten() {
        members[index as usize] = true;
    }
    for (matched, member) in matched.iter_mut().zip(members) {
        *matched &= member;
    }
}

struct NameMatch {
    text: String,
    exact: bool,
}

impl NameMatch {
    fn new<'a>(text: &str, names: impl IntoIterator<Item = &'a str>) -> Self {
        let text = normalize_search_text(text.trim());
        let exact = names
            .into_iter()
            .any(|name| normalize_search_text(name) == text);
        Self { text, exact }
    }

    fn matches(&self, name: &str) -> bool {
        let name = normalize_search_text(name);
        if self.exact {
            name == self.text
        } else {
            name.contains(&self.text)
        }
    }
}

enum CountryMatch {
    Code(CountryCode),
    Name(NameMatch),
}

impl CountryMatch {
    fn new(index: &LocationIndex, text: &str) -> Result<Self> {
        let text = text.trim();
        if text.len() != 2 || !text.bytes().all(|byte| byte.is_ascii_alphabetic()) {
            let names = index.country_names().map(|(_, name)| name);
            return Ok(Self::Name(NameMatch::new(text, names)));
        }
        let upper = text.to_ascii_uppercase();
        let code: CountryCode = if upper == "UK" { "GB" } else { &upper }.parse()?;
        ensure!(
            index.country_name(code).is_some(),
            "no country has the code {text:?}; see place list --countries"
        );
        Ok(Self::Code(code))
    }

    fn matches(&self, index: &LocationIndex, code: CountryCode) -> bool {
        match self {
            Self::Code(selected) => code == *selected,
            Self::Name(name) => name.matches(country_name(index, &code)),
        }
    }
}

fn country_name<'a>(index: &'a LocationIndex, code: &'a CountryCode) -> &'a str {
    index.country_name(*code).unwrap_or(code.as_str())
}
