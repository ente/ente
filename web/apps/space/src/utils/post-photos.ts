import type { SpaceViewerPhoto } from "components/FileViewer";
import type { SpacePostPhoto } from "services/space";

export const maxSpacePostPhotos = 10;

export const spacePostPhotos = (
    post: SpacePostPhoto & { photos?: SpacePostPhoto[] },
): SpacePostPhoto[] => (post.photos?.length ? post.photos : [post]);

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
