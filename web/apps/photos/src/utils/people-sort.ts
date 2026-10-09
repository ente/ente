import type { Person } from "ente-new/photos/services/ml/people";

export type PeopleSortBy =
    "count-desc" | "count-asc" | "name-asc" | "name-desc";

export const sortPeople = (people: Person[], sortBy: PeopleSortBy): Person[] =>
    [...people].sort(personComparator(sortBy));

const personComparator =
    (sortBy: PeopleSortBy) =>
    (a: Person, b: Person): number => {
        if (a.isPinned !== b.isPinned) {
            return a.isPinned ? -1 : 1;
        }

        const sectionRankDiff = personSectionRank(a) - personSectionRank(b);

        if (sortBy.startsWith("name")) {
            const aName = a.name?.trim();
            const bName = b.name?.trim();
            if (!!aName !== !!bName) {
                return aName ? -1 : 1;
            }
            if (aName && bName) {
                const cmp = aName.localeCompare(bName, undefined, {
                    sensitivity: "base",
                });
                if (cmp) {
                    return sortBy === "name-asc" ? cmp : -cmp;
                }
            }
            return b.fileIDs.length - a.fileIDs.length;
        }

        if (sectionRankDiff) {
            return sectionRankDiff;
        }

        const countDiff = a.fileIDs.length - b.fileIDs.length;
        if (countDiff) {
            return sortBy === "count-asc" ? countDiff : -countDiff;
        }

        const aName = a.name?.trim();
        const bName = b.name?.trim();
        if (!!aName !== !!bName) {
            return aName ? -1 : 1;
        }
        if (aName && bName) {
            return aName.localeCompare(bName, undefined, {
                sensitivity: "base",
            });
        }
        return 0;
    };

const personSectionRank = (person: Person) =>
    person.type === "cgroup" ? 0 : 1;
