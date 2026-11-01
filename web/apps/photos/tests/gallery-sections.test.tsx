import { Link04Icon } from "@hugeicons/core-free-icons";
import { renderToStaticMarkup } from "react-dom/server";
import { afterEach, describe, expect, test, vi } from "vitest";
import {
    activeSectionID,
    initialNavigationState,
    navigationReducer,
} from "../src/components/gallery/navigation-state";
import type { GallerySectionProps } from "../src/components/gallery/section-types";
import {
    gallerySections,
    sectionDefinition,
    selectRailSection,
    type GallerySectionDefinition,
    type GallerySectionID,
} from "../src/components/gallery/sections";

vi.mock("../src/components/gallery/AlbumsSection", () => ({
    AlbumsSection: () => <div>Albums</div>,
}));
vi.mock("../src/components/gallery/PeopleSection", () => ({
    PeopleSection: () => <div>People</div>,
}));
vi.mock("../src/components/gallery/PlacesSection", () => ({
    PlacesSection: () => <div>Places</div>,
}));
vi.mock("../src/components/gallery/LinksSection", () => ({
    LinksSection: () => <div>Links</div>,
}));
vi.mock("../src/components/gallery/SearchSection", () => ({
    SearchSection: () => <div>Search</div>,
}));
vi.mock("../src/components/gallery/DuplicatesView", () => ({
    DuplicatesView: () => null,
}));
vi.mock("../src/components/gallery/LargeFilesView", () => ({
    LargeFilesView: () => null,
}));
vi.mock("ente-new/photos/services/ml", () => ({ isMLSupported: false }));

const fixtureID = "fixture" as GallerySectionID;
const registry = gallerySections as Record<string, GallerySectionDefinition>;
afterEach(() => {
    delete registry.fixture;
});

test("a component and one definition add a selectable section", () => {
    const Feature = vi.fn(() => <div>Fixture content</div>);
    registry.fixture = {
        View: Feature,
        hasNavigation: false,
        rail: { label: () => "Fixture", icon: Link04Icon },
    };
    const state = navigationReducer(initialNavigationState, {
        type: "openSection",
        section: fixtureID,
    });
    const selected = sectionDefinition(activeSectionID(state));
    expect(selected.rail?.label()).toBe("Fixture");
    expect(
        renderToStaticMarkup(
            <selected.View {...({} as GallerySectionProps)} />,
        ),
    ).toContain("Fixture content");
    expect(Feature).toHaveBeenCalledOnce();
    const { View } = sectionDefinition("albums");
    renderToStaticMarkup(<View {...({} as GallerySectionProps)} />);
    expect(Feature).toHaveBeenCalledOnce();
});

const entry = () => ({
    navigation: initialNavigationState,
    mobile: false,
    open: vi.fn(() => true),
    openPanel: vi.fn(),
    closeDrawer: vi.fn(),
    togglePanel: vi.fn(),
});
describe("rail entry behavior", () => {
    test("ordinary sections open and repeated selection toggles their panel", () => {
        const controls = entry();
        selectRailSection(sectionDefinition("links"), "links", controls);
        expect(controls.open).toHaveBeenCalledOnce();
        expect(controls.openPanel).toHaveBeenCalledOnce();
        controls.navigation = navigationReducer(initialNavigationState, {
            type: "showLinks",
        });
        selectRailSection(sectionDefinition("links"), "links", controls);
        expect(controls.togglePanel).toHaveBeenCalledOnce();
        expect(controls.open).toHaveBeenCalledOnce();
    });
    test("desktop People uses its consent entry without toggling the panel", () => {
        const controls = entry();
        controls.open.mockReturnValue(false);
        selectRailSection(sectionDefinition("people"), "people", controls);
        expect(controls.closeDrawer).toHaveBeenCalledOnce();
        expect(controls.open).toHaveBeenCalledOnce();
        expect(controls.openPanel).not.toHaveBeenCalled();
        expect(controls.togglePanel).not.toHaveBeenCalled();
        expect(sectionDefinition("people").rail?.available?.()).toBe(false);
    });
    test("map entry opens the mobile panel immediately", () => {
        const controls = { ...entry(), mobile: true };
        selectRailSection(sectionDefinition("places"), "places", controls);
        expect(controls.open).toHaveBeenCalledOnce();
        expect(controls.openPanel).toHaveBeenCalledOnce();
    });
    test("leaving cleanup opens Links even when it was the underlying destination", () => {
        const controls = entry();
        controls.navigation = navigationReducer(
            navigationReducer(initialNavigationState, { type: "showLinks" }),
            { type: "showCleanup", section: "duplicates" },
        );
        selectRailSection(sectionDefinition("links"), "links", controls);
        expect(controls.open).toHaveBeenCalledOnce();
        expect(controls.togglePanel).not.toHaveBeenCalled();
    });
});

test("temporary search and cleanup retain their underlying destination", () => {
    let state = navigationReducer(initialNavigationState, {
        type: "showAlbumOverview",
        albumFilter: "shared",
    });
    const origin = state.destination;
    state = navigationReducer(state, { type: "enterSearchMode" });
    expect(activeSectionID(state)).toBe("search");
    state = navigationReducer(state, {
        type: "exitSearch",
        shouldExitSearchMode: false,
    });
    expect(activeSectionID(state)).toBe("search");
    state = navigationReducer(state, { type: "exitSearch" });
    expect(state.destination).toBe(origin);
    state = navigationReducer(state, {
        type: "showCleanup",
        section: "large-files",
    });
    expect(activeSectionID(state)).toBe("large-files");
    expect(state.destination).toBe(origin);
    state = navigationReducer(state, { type: "showAll" });
    expect(activeSectionID(state)).toBe("albums");
    expect(state.overlay).toBeUndefined();
});
