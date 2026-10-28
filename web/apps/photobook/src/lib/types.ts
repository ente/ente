import type { PrintSelection } from "./printProducts";

type PhotoSource = "local" | "ente";
export type PhotoOriginalStatus = "pending" | "ready" | "failed";
type EnteOriginalMediaKind = "image" | "live-photo";

interface EntePhotoOriginalData {
    downloadOrigin: string;
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
    dateTaken: number;
    source?: PhotoSource;
    originalStatus?: PhotoOriginalStatus;
    originalError?: string;
    enteOriginal?: EntePhotoOriginalData;
    thumbnailUrl?: string;
    fullUrl?: string;
}

type TextStyle = "title" | "body";
type TextAlignment = "left" | "center" | "right";

export interface TextBlock {
    id: string;
    text: string;
    x: number;
    y: number;
    width: number;
    height: number;
    style: TextStyle;
    alignment: TextAlignment;
    color?: string;
    rotation?: number;
    fontSize?: number;
}

export interface PhotoSlot {
    id: string;
    photoId: string | null;
    x: number;
    y: number;
    width: number;
    height: number;
    cropX: number;
    cropY: number;
    cropZoom: number;
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
    currentSpreadIndex: number;
    printSelection?: PrintSelection;
}

export type AppView = "start" | "edit" | "results";
