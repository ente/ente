import ArrowForwardIosIcon from "@mui/icons-material/ArrowForwardIos";
import PersonAddIcon from "@mui/icons-material/PersonAdd";
import { Skeleton, Stack, styled, Typography } from "@mui/material";
import { useIsSmallWidth } from "ente-base/components/utils/hooks";
import type { EnteFile } from "ente-media/file";
import { faceCrop, type AnnotatedFaceID } from "ente-new/photos/services/ml";
import type {
    Person,
    PreviewableFace,
} from "ente-new/photos/services/ml/people";
import { t } from "i18next";
import React, { useEffect, useState } from "react";
import { UnstyledButton } from "./UnstyledButton";

export interface SearchPeopleListProps {
    people: Person[];
    onSelectPerson: (personID: string) => void;
}

export const SearchPeopleList: React.FC<SearchPeopleListProps> = ({
    people,
    onSelectPerson,
}) => {
    const isSmallWidth = useIsSmallWidth();
    return (
        <SearchPeopleContainer>
            {people.slice(0, isSmallWidth ? 6 : 7).map((person) => (
                <SearchPersonButton
                    key={person.id}
                    onClick={() => onSelectPerson(person.id)}
                >
                    <SearchPersonAvatar>
                        <FaceCropImageView
                            faceID={person.displayFaceID}
                            file={person.displayFaceFile}
                            placeholderDimension={40}
                        />
                    </SearchPersonAvatar>
                    <Stack sx={{ flex: 1, minWidth: 0, gap: "4px" }}>
                        {person.name && (
                            <Typography
                                component="span"
                                sx={{
                                    fontSize: 14,
                                    fontWeight: 500,
                                    overflowWrap: "anywhere",
                                }}
                            >
                                {person.name}
                            </Typography>
                        )}
                        <Typography
                            component="span"
                            variant="mini"
                            sx={{
                                color: "text.muted",
                                overflowWrap: "anywhere",
                            }}
                        >
                            {`${t("people")} · ${t("photos_count", {
                                count: person.fileIDs.length,
                            })}`}
                        </Typography>
                    </Stack>
                    <ArrowForwardIosIcon
                        sx={{
                            fontSize: 12,
                            color: "text.muted",
                            flexShrink: 0,
                        }}
                    />
                </SearchPersonButton>
            ))}
        </SearchPeopleContainer>
    );
};

const SearchPeopleContainer = styled("div")`
    display: flex;
    flex-direction: column;
    gap: 8px;
    margin-block-start: 12px;
    margin-block-end: 15px;
`;

const SearchPersonButton = styled(UnstyledButton)(({ theme }) => ({
    display: "flex",
    width: "100%",
    minHeight: 56,
    alignItems: "center",
    gap: "12px",
    padding: "8px 12px 8px 8px",
    borderRadius: "12px",
    textAlign: "left",
    color: theme.vars.palette.text.base,
    backgroundColor: theme.vars.palette.background.paper,
    "&:hover": {
        backgroundColor: `color-mix(in srgb, ${theme.vars.palette.text.base} 8%, ${theme.vars.palette.background.paper})`,
    },
    "&:focus-visible": {
        outline: `2px solid color-mix(in srgb, ${theme.vars.palette.accent.main} 55%, transparent)`,
        outlineOffset: "-2px",
    },
}));

const SearchPersonAvatar = styled("div")({
    position: "relative",
    width: 40,
    height: 40,
    flexShrink: 0,
    borderRadius: "50%",
    overflow: "hidden",
    "& img": { width: "100%", height: "100%", objectFit: "cover" },
});

export interface FilePeopleListProps {
    file: EnteFile;
    annotatedFaceIDs: AnnotatedFaceID[];
    onSelectFace: (annotatedFaceID: AnnotatedFaceID) => void;
    manuallyAssignedPeople?: Person[];
    onSelectPerson?: (personID: string) => void;
    onAddPerson?: () => void;
    addPersonTitle?: string;
    addPersonLabel?: string;
}

export const FilePeopleList: React.FC<FilePeopleListProps> = ({
    file,
    annotatedFaceIDs,
    onSelectFace,
    manuallyAssignedPeople,
    onSelectPerson,
    onAddPerson,
    addPersonTitle,
    addPersonLabel,
}) => (
    <FilePeopleList_>
        {manuallyAssignedPeople
            ?.toSorted((a, b) => {
                const an = (a.name ?? "").toLowerCase();
                const bn = (b.name ?? "").toLowerCase();
                return an < bn ? -1 : an > bn ? 1 : 0;
            })
            .map((person) => (
                <ManuallyAssignedPersonButton
                    key={person.id}
                    onClick={() => onSelectPerson?.(person.id)}
                >
                    <FaceCropImageView
                        faceID={person.displayFaceID}
                        file={person.displayFaceFile}
                        placeholderDimension={65}
                    />
                    <Typography variant="small" sx={{ color: "text.muted" }}>
                        {person.type == "cgroup" && person.isHidden
                            ? `(${t("ignored")})`
                            : person.name}
                    </Typography>
                </ManuallyAssignedPersonButton>
            ))}
        {annotatedFaceIDs.map((annotatedFaceID) => (
            <AnnotatedFaceButton
                key={annotatedFaceID.faceID}
                onClick={() => onSelectFace(annotatedFaceID)}
            >
                <FaceCropImageView
                    faceID={annotatedFaceID.faceID}
                    file={file}
                    placeholderDimension={65}
                />
                <Typography variant="small" sx={{ color: "text.muted" }}>
                    {annotatedFaceID.isIgnored
                        ? `(${t("ignored")})`
                        : annotatedFaceID.personName}
                </Typography>
            </AnnotatedFaceButton>
        ))}
        {onAddPerson && (
            <AddPersonButton
                onClick={onAddPerson}
                title={addPersonTitle}
                aria-label={addPersonTitle}
            >
                <AddPersonAvatar>
                    <PersonAddIcon />
                </AddPersonAvatar>
                <Typography variant="small" sx={{ color: "text.muted" }}>
                    {addPersonLabel}
                </Typography>
            </AddPersonButton>
        )}
    </FilePeopleList_>
);

const FilePeopleList_ = styled("div")`
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    margin-block-end: 5px;
`;

const AnnotatedFaceButton = styled(UnstyledButton)(
    ({ theme }) => `
    width: 65px;
    display: flex;
    flex-direction: column;
    gap: 2px;
    & > img {
        width: 100%;
        aspect-ratio: 1;
        border-radius: 50%;
        overflow: hidden;
    }
    & > img:hover {
        outline: 1px solid ${theme.vars.palette.stroke.faint};
        outline-offset: 2px;
    }
`,
);

const ManuallyAssignedPersonButton = AnnotatedFaceButton;

const AddPersonButton = styled(UnstyledButton)(
    ({ theme }) => `
    width: 65px;
    display: flex;
    flex-direction: column;
    gap: 2px;
    & > div {
        width: 100%;
        aspect-ratio: 1;
        border-radius: 50%;
        overflow: hidden;
    }
    & > div:hover {
        outline: 1px solid ${theme.vars.palette.stroke.faint};
        outline-offset: 2px;
    }
`,
);

const AddPersonAvatar = styled("div")(
    ({ theme }) => `
    display: flex;
    align-items: center;
    justify-content: center;
    color: ${theme.vars.palette.text.muted};
    border: 1px dashed ${theme.vars.palette.stroke.faint};
`,
);

export interface SuggestionFaceListProps {
    faces: PreviewableFace[];
}

export const SuggestionFaceList: React.FC<SuggestionFaceListProps> = ({
    faces,
}) => {
    return (
        <SuggestionFaceList_>
            {faces.map(({ file, faceID }) => (
                <SuggestionFace key={faceID}>
                    <FaceCropImageView
                        placeholderDimension={87}
                        {...{ file, faceID }}
                    />
                </SuggestionFace>
            ))}
        </SuggestionFaceList_>
    );
};

const SuggestionFaceList_ = styled("div")`
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
`;

const SuggestionFace = styled("div")`
    width: 87px;
    height: 87px;
    border-radius: 50%;
    overflow: hidden;
    & > img {
        width: 100%;
        height: 100%;
    }
`;

type FaceCropImageViewProps = PreviewableFace & {
    placeholderDimension: number;
};

// Missing local crops are regenerated from the associated file.
const FaceCropImageView: React.FC<FaceCropImageViewProps> = ({
    faceID,
    file,
    placeholderDimension,
}) => {
    const [url, setURL] = useState<string | undefined>();

    useEffect(() => {
        let didCancel = false;

        void faceCrop(faceID, file).then((url) => !didCancel && setURL(url));

        return () => {
            didCancel = true;
        };
    }, [faceID, file]);

    return url ? (
        <img style={{ objectFit: "cover" }} src={url} />
    ) : (
        <Skeleton
            variant="circular"
            animation="wave"
            sx={{ backgroundColor: "background.paper2" }}
            width={placeholderDimension}
            height={placeholderDimension}
        />
    );
};
