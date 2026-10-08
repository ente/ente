import type { SpaceViewerPhoto } from "components/FileViewer";
import type { SpacePostPhoto } from "services/space";
import { minimumPostPhotoFrameAspectRatio } from "../styles/tiles";

export const maxSpacePostPhotos = 10;

export const spacePostPhotos = (
    post: SpacePostPhoto & { photos?: SpacePostPhoto[] },
): SpacePostPhoto[] => (post.photos?.length ? post.photos : [post]);

export const spacePostFrameAspectRatio = (
    photos: Pick<SpacePostPhoto, "width" | "height">[],
) => {
    const firstPhoto = photos[0]!;
    const aspectRatio =
        firstPhoto.width && firstPhoto.height
            ? firstPhoto.width / firstPhoto.height
            : 1;
    if (photos.length == 1)
        return Math.max(minimumPostPhotoFrameAspectRatio, aspectRatio);

    return photos.every(
        (photo) =>
            photo.width &&
            photo.height &&
            Math.abs(photo.width / photo.height / aspectRatio - 1) < 0.01,
    )
        ? aspectRatio
        : 1;
};

export const viewerPhotosFromPost = (
    post: Omit<SpaceViewerPhoto, "imageUrl"> & {
        imageUrl?: string;
        photos?: SpacePostPhoto[];
    },
): SpaceViewerPhoto[] => {
    const photos = spacePostPhotos(post);
    return photos.map((photo, index) => ({
        ...post,
        ...photo,
        height: photo.height ?? (index == 0 ? post.height : undefined),
        imageUrl: photo.imageUrl || (index == 0 ? post.imageUrl : "") || "",
        postPhotoIndex: index,
        postPhotoCount: photos.length,
        width: photo.width ?? (index == 0 ? post.width : undefined),
    }));
};

export const movePostPhoto = <T>(
    photos: T[],
    from: number,
    to: number,
): T[] => {
    const reordered = [...photos];
    const [photo] = reordered.splice(from, 1);
    reordered.splice(to, 0, photo!);
    return reordered;
};
