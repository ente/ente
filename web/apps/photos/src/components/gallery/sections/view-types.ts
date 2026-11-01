import type { AlbumFilter } from "@/utils/album-filters";
import type { Collection } from "ente-media/collection";
import type { CollectionSummary } from "ente-new/photos/services/collection-summary";
import type { Person } from "ente-new/photos/services/ml/people";
export type GalleryView =
    | { type: "links"; selectedLinkID: number | undefined }
    | { type: "album-overview"; albumFilter: AlbumFilter }
    | {
          type: "albums" | "hidden-albums" | "archive-albums";
          activeCollectionSummaryID: number;
          activeCollection: Collection | undefined;
          activeCollectionSummary: CollectionSummary;
      }
    | {
          type: "people";
          visiblePeople: Person[];
          people: Person[];
          activePerson: Person | undefined;
      };
