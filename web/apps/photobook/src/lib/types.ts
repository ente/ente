import type { PrintSelection } from "./printProducts";

type PhotoSource = "local" | "ente";
export type PhotoOriginalStatus = "pending" | "ready" | "failed";
type EnteOriginalMediaKind = "image" | "live-photo";

interface EntePhotoOriginalData {
    apiOrigin: string;
    albumsOrigin: string;
    accessToken: string;
    accessTokenJWT?: string;
    enteFileId: number;
    mediaKind: EnteOriginalMediaKind;
    fileKey: string;
    fileDecryptionHeader: string;
}

export interface Photo {
    id: string;
    fileName: string;
    width: number;
    height: number;
    dateTaken: number; // timestamp
    source?: PhotoSource;
    originalStatus?: PhotoOriginalStatus;
    originalError?: string;
    enteOriginal?: EntePhotoOriginalData;
    thumbnailUrl?: string; // runtime only, object URL
    fullUrl?: string; // runtime only, object URL
}

type TextStyle = "title" | "body";
type TextAlignment = "left" | "center" | "right";

export interface TextBlock {
    id: string;
    text: string;
    x: number; // percentage 0-100
    y: number;
    width: number;
    height: number;
    style: TextStyle;
    alignment: TextAlignment;
    color?: string; // hex color, default "#555555"
    rotation?: number; // degrees, default 0
    fontSize?: number; // percentage of page height, default 2.5 (body) or 4 (title)
}

export interface PhotoSlot {
    id: string;
    photoId: string | null;
    x: number; // percentage 0-100
    y: number;
    width: number;
    height: number;
    cropX: number; // pan offset within frame (0-1)
    cropY: number;
    cropZoom: number; // 1 = fit, >1 = zoomed in
}

export interface BookPage {
    id: string;
    slots: PhotoSlot[];
    textBlocks: TextBlock[];
    topCaption: string;
    bottomCaption: string;
    centerText?: string;
    layoutVariant?: string;
}

export interface BookState {
    title?: string;
    pages: BookPage[];
    currentSpreadIndex: number; // first real book-page index in the visible spread
    printSelection?: PrintSelection;
}

export type AppView = "start" | "edit" | "results";
