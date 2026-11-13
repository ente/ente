use std::collections::BTreeMap;

use crate::city::distance_km;
use crate::{City, CityIndex, CityMatch, Coordinate, UrbanCenterIndex};

const OVERRIDE_DISTANCE_MARGIN_KM: f64 = 1.0;

impl UrbanCenterIndex {
    pub fn match_coordinates_with_cities(
        &self,
        cities: &CityIndex,
        coordinates: &[Coordinate],
        query: &str,
    ) -> Vec<CityMatch> {
        let mut matches = self.match_coordinates(coordinates, query);
        if matches.is_empty() {
            return cities.match_coordinates(coordinates, query);
        }
        let mut urban_groups = vec![usize::MAX; coordinates.len()];
        for (group_index, group) in matches.iter().enumerate() {
            for &index in &group.coordinate_indices {
                urban_groups[index as usize] = group_index;
            }
        }
        let covered_indices: Vec<u32> = urban_groups
            .iter()
            .enumerate()
            .filter_map(|(index, &group)| (group != usize::MAX).then_some(index as u32))
            .collect();
        let mut overrides = cities
            .match_override_coordinates(&coordinates_at(coordinates, &covered_indices), query);
        retain_closer_overrides(
            &mut overrides,
            &covered_indices,
            coordinates,
            &matches,
            &urban_groups,
        );
        replace_matches(&mut matches, &covered_indices, overrides, coordinates.len());
        let missing_indices: Vec<u32> = urban_groups
            .iter()
            .enumerate()
            .filter_map(|(index, &group)| (group == usize::MAX).then_some(index as u32))
            .collect();
        if missing_indices.is_empty() {
            return matches;
        }
        let nearby =
            cities.match_coordinates(&coordinates_at(coordinates, &missing_indices), query);
        append_fallback(&mut matches, &missing_indices, nearby);
        matches
    }
}

fn coordinates_at(coordinates: &[Coordinate], indices: &[u32]) -> Vec<Coordinate> {
    indices
        .iter()
        .map(|&index| coordinates[index as usize])
        .collect()
}

fn retain_closer_overrides(
    overrides: &mut Vec<CityMatch>,
    original_indices: &[u32],
    coordinates: &[Coordinate],
    urban: &[CityMatch],
    urban_groups: &[usize],
) {
    for group in overrides.iter_mut() {
        let city = &group.city;
        group.coordinate_indices.retain(|&relative_index| {
            let index = original_indices[relative_index as usize] as usize;
            distance_to_city(coordinates[index], city) + OVERRIDE_DISTANCE_MARGIN_KM
                < distance_to_city(coordinates[index], &urban[urban_groups[index]].city)
        });
    }
    overrides.retain(|group| !group.coordinate_indices.is_empty());
}

fn distance_to_city(coordinate: Coordinate, city: &City) -> f64 {
    distance_km(
        coordinate.latitude,
        coordinate.longitude,
        city.latitude,
        city.longitude,
    )
}

fn append_fallback(
    matches: &mut Vec<CityMatch>,
    original_indices: &[u32],
    mut fallback: Vec<CityMatch>,
) {
    remap_indices(&mut fallback, original_indices);
    append_matches(matches, fallback);
}

fn replace_matches(
    matches: &mut Vec<CityMatch>,
    original_indices: &[u32],
    mut replacements: Vec<CityMatch>,
    coordinate_count: usize,
) {
    remap_indices(&mut replacements, original_indices);
    let mut replaced = vec![false; coordinate_count];
    for group in &replacements {
        for &index in &group.coordinate_indices {
            replaced[index as usize] = true;
        }
    }
    for group in matches.iter_mut() {
        group
            .coordinate_indices
            .retain(|&index| !replaced[index as usize]);
    }
    matches.retain(|group| !group.coordinate_indices.is_empty());
    append_matches(matches, replacements);
}

fn remap_indices(matches: &mut [CityMatch], original_indices: &[u32]) {
    for group in matches {
        for index in &mut group.coordinate_indices {
            *index = original_indices[*index as usize];
        }
    }
}

fn append_matches(matches: &mut Vec<CityMatch>, additions: Vec<CityMatch>) {
    let mut positions: BTreeMap<u32, usize> = matches
        .iter()
        .enumerate()
        .map(|(index, group)| (group.city.source_id, index))
        .collect();
    for group in additions {
        if let Some(&position) = positions.get(&group.city.source_id) {
            matches[position]
                .coordinate_indices
                .extend(group.coordinate_indices);
            matches[position].coordinate_indices.sort_unstable();
        } else {
            positions.insert(group.city.source_id, matches.len());
            matches.push(group);
        }
    }
}

#[cfg(test)]
mod tests {
    use crate::CountryCode;

    use super::*;

    #[test]
    fn fallback_indices_are_mapped_back_to_the_original_coordinates() {
        let mut matches = vec![city_match(1, "Metropolis", vec![0, 2])];
        let nearby = vec![
            city_match(2, "Small Town", vec![0]),
            city_match(3, "Rural Place", vec![1]),
        ];

        append_fallback(&mut matches, &[1, 3], nearby);

        assert_eq!(label(&matches, 0), "Metropolis");
        assert_eq!(label(&matches, 1), "Small Town");
        assert_eq!(label(&matches, 2), "Metropolis");
        assert_eq!(label(&matches, 3), "Rural Place");
    }

    #[test]
    fn fallback_with_the_same_canonical_city_is_merged() {
        let mut matches = vec![city_match(1, "Zürich", vec![0])];
        let nearby = vec![city_match(1, "Zürich", vec![0])];

        append_fallback(&mut matches, &[1], nearby);

        assert_eq!(matches.len(), 1);
        assert_eq!(matches[0].coordinate_indices, [0, 1]);
    }

    #[test]
    fn curated_city_replaces_the_urban_center_for_its_coordinates() {
        let mut matches = vec![city_match(1, "Metropolis", vec![0, 1, 2])];
        let prominent = vec![city_match(2, "Edge City", vec![1])];

        replace_matches(&mut matches, &[0, 2], prominent, 3);

        assert_eq!(label(&matches, 0), "Metropolis");
        assert_eq!(label(&matches, 1), "Metropolis");
        assert_eq!(label(&matches, 2), "Edge City");
    }

    #[test]
    fn override_must_be_materially_closer_than_the_urban_center() {
        let urban = vec![city_match_at(1, "Metropolis", 0.0, 0.0, vec![0, 1])];
        let mut overrides = vec![city_match_at(2, "Edge City", 0.0, 0.1, vec![0, 1])];

        retain_closer_overrides(
            &mut overrides,
            &[0, 1],
            &[Coordinate::new(0.0, 0.01), Coordinate::new(0.0, 0.09)],
            &urban,
            &[0, 0],
        );

        assert_eq!(overrides[0].coordinate_indices, [1]);
    }

    fn label(matches: &[CityMatch], coordinate_index: u32) -> &str {
        &matches
            .iter()
            .find(|group| group.coordinate_indices.contains(&coordinate_index))
            .unwrap()
            .city
            .name
    }

    fn city_match(source_id: u32, name: &str, coordinate_indices: Vec<u32>) -> CityMatch {
        city_match_at(source_id, name, 0.0, 0.0, coordinate_indices)
    }

    fn city_match_at(
        source_id: u32,
        name: &str,
        latitude: f64,
        longitude: f64,
        coordinate_indices: Vec<u32>,
    ) -> CityMatch {
        CityMatch {
            city: City {
                point_index: 0,
                source_id,
                name: name.to_owned(),
                country_name: String::new(),
                country_code: CountryCode::from_bytes(*b"AA").unwrap(),
                latitude,
                longitude,
                rank: 0,
            },
            coordinate_indices,
        }
    }
}
