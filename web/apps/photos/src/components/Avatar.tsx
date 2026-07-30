// TODO: Audit this file
import { styled } from "@mui/material";
import type { LocalUser } from "ente-accounts/services/user";
import { useResolvedContactAvatar } from "ente-contacts-web";
import type { EnteFile } from "ente-media/file";
import {
    avatarBackgroundColor,
    avatarBackgroundColorPublicCollectedFile,
    avatarTextColor,
} from "ente-new/photos/services/avatar";
import React, { useMemo } from "react";

interface AvatarProps {
    user?: LocalUser;
    file?: EnteFile;
    email?: string;
    opacity?: number;
    emailByUserID?: Map<number, string>;
}

const AvatarBase = styled("div")<{
    colorCode: string;
    size: number;
    opacity: number | undefined;
}>`
    width: ${({ size }) => `${size}px`};
    height: ${({ size }) => `${size}px`};
    background-color: ${({ colorCode, opacity }) =>
        `${colorCode}${opacity === 100 ? "" : (opacity ?? 95)}`};
    border-radius: 50%;
    display: flex;
    justify-content: center;
    align-items: center;
    color: ${avatarTextColor};
    font-weight: bold;
    font-size: ${({ size }) => `${Math.floor(size / 2)}px`};
`;

const AvatarImage = styled("img")<{
    size: number;
    opacity: number | undefined;
}>`
    width: ${({ size }) => `${size}px`};
    height: ${({ size }) => `${size}px`};
    border-radius: 50%;
    object-fit: cover;
    opacity: ${({ opacity }) =>
        opacity === undefined ? 1 : Math.max(0, Math.min(opacity, 100)) / 100};
`;

const colorSeedFromEmail = (email: string) => {
    let seed = 0;
    for (const char of email) {
        seed += char.codePointAt(0) ?? 0;
    }
    return seed;
};

const Avatar: React.FC<AvatarProps> = ({
    user,
    file,
    email,
    opacity,
    emailByUserID,
}) => {
    const isPublicCollectedAvatar =
        !!file && !!user && file.ownerID === user.id && !!file.pubMagicMetadata;
    const uploaderName = file?.pubMagicMetadata?.data.uploaderName;

    const resolvedContact = useResolvedContactAvatar(
        file && file.ownerID !== user?.id
            ? { userID: file.ownerID, email: emailByUserID?.get(file.ownerID) }
            : { email },
    );

    const fallbackEmail = resolvedContact.actualEmail ?? email;

    const colorCode = useMemo(() => {
        if (isPublicCollectedAvatar) {
            return avatarBackgroundColorPublicCollectedFile;
        }
        if (file && file.ownerID !== user?.id) {
            return avatarBackgroundColor(file.ownerID);
        }
        if (!fallbackEmail) {
            return undefined;
        }
        if (user?.email === fallbackEmail) {
            return avatarBackgroundColorPublicCollectedFile;
        }
        const matchedID = Array.from(emailByUserID?.keys() ?? []).find(
            (key) => emailByUserID?.get(key) === fallbackEmail,
        );
        return avatarBackgroundColor(
            matchedID ?? colorSeedFromEmail(fallbackEmail),
        );
    }, [emailByUserID, fallbackEmail, file, isPublicCollectedAvatar, user]);

    const userLetter = useMemo(() => {
        if (isPublicCollectedAvatar) {
            return uploaderName?.[0]?.toUpperCase();
        }
        if (resolvedContact.source === "contact") {
            return resolvedContact.initial;
        }
        return fallbackEmail?.[0]?.toUpperCase();
    }, [
        fallbackEmail,
        isPublicCollectedAvatar,
        resolvedContact.initial,
        resolvedContact.source,
        uploaderName,
    ]);

    if (resolvedContact.avatarURL && !isPublicCollectedAvatar) {
        return (
            <AvatarImage
                size={18}
                opacity={opacity}
                src={resolvedContact.avatarURL}
            />
        );
    }

    if (!colorCode || !userLetter) {
        return <></>;
    }

    return (
        <AvatarBase size={18} colorCode={colorCode} opacity={opacity}>
            {userLetter}
        </AvatarBase>
    );
};

export default Avatar;
