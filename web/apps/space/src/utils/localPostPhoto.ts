import type { SpaceViewerPhoto } from "components/SpaceFileViewer";

export interface LocalPostPhotoDimensions {
    height: number;
    width: number;
}

export interface LocalPostPhoto {
    objectUrl: string;
    photo: SpaceViewerPhoto;
}

interface CreateLocalPostPhotoAttributes {
    avatarUrl?: string | null;
    dimensions?: LocalPostPhotoDimensions;
    file: File;
    name: string;
}

interface LocalPostPhotoAttributes extends CreateLocalPostPhotoAttributes {
    objectUrl: string;
}

const localPostPhoto = ({
    avatarUrl,
    dimensions,
    name,
    objectUrl,
}: LocalPostPhotoAttributes): LocalPostPhoto => ({
    objectUrl,
    photo: {
        alt: `${name} post`,
        avatarUrl,
        height: dimensions?.height,
        imageUrl: objectUrl,
        name,
        timestampMs: Date.now(),
        width: dimensions?.width,
    },
});

export const createLocalPostPhoto = (
    attributes: CreateLocalPostPhotoAttributes,
): LocalPostPhoto =>
    localPostPhoto({
        ...attributes,
        objectUrl: URL.createObjectURL(attributes.file),
    });

export const createLoadedLocalPostPhoto = async (
    attributes: CreateLocalPostPhotoAttributes,
): Promise<LocalPostPhoto> => {
    const objectUrl = URL.createObjectURL(attributes.file);
    try {
        return localPostPhoto({
            ...attributes,
            dimensions: await localImageDimensions(objectUrl),
            objectUrl,
        });
    } catch (error) {
        URL.revokeObjectURL(objectUrl);
        throw error;
    }
};

const localImageDimensions = (objectUrl: string) =>
    new Promise<LocalPostPhotoDimensions>((resolve, reject) => {
        const image = new Image();
        image.onload = () => {
            const { naturalHeight, naturalWidth } = image;
            if (naturalHeight <= 0 || naturalWidth <= 0) {
                reject(new Error("Image has no dimensions"));
                return;
            }

            resolve({ height: naturalHeight, width: naturalWidth });
        };
        image.onerror = () => reject(new Error("Image failed to load"));
        image.src = objectUrl;
    });
