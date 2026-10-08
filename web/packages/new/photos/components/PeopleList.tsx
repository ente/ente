import PersonAddIcon from "@mui/icons-material/PersonAdd";
import { Box, Skeleton, styled, Typography } from "@mui/material";
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
        <Box
            sx={{
                display: "grid",
                gridTemplateColumns: `repeat(${isSmallWidth ? 6 : 7}, minmax(0, 1fr))`,
                gap: "8px",
            }}
        >
            {people.slice(0, isSmallWidth ? 6 : 7).map((person) => (
                <UnstyledButton
                    key={person.id}
                    onClick={() => onSelectPerson(person.id)}
                    aria-label={person.name ?? t("unnamed_person")}
                    sx={{
                        minWidth: 0,
                        display: "flex",
                        flexDirection: "column",
                        alignItems: "center",
                        gap: "8px",
                        borderRadius: "8px",
                        "&:focus-visible": {
                            outline: "2px solid",
                            outlineColor: "accent.main",
                        },
                    }}
                >
                    <Box
                        sx={{
                            width: "100%",
                            maxWidth: isSmallWidth ? 44 : 52,
                            aspectRatio: "1",
                            borderRadius: "50%",
                            overflow: "hidden",
                            "& img, & .MuiSkeleton-root": {
                                width: "100% !important",
                                height: "100% !important",
                                objectFit: "cover",
                            },
                        }}
                    >
                        <FaceCropImageView
                            faceID={person.displayFaceID}
                            file={person.displayFaceFile}
                            placeholderDimension={isSmallWidth ? 44 : 52}
                        />
                    </Box>
                    <Typography variant="mini" noWrap sx={{ maxWidth: "100%" }}>
                        {person.name ?? t("unnamed_person")}
                    </Typography>
                </UnstyledButton>
            ))}
        </Box>
    );
};

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
                    {annotatedFaceID.personName}
                </Typography>
            </AnnotatedFaceButton>
        ))}
        {manuallyAssignedPeople?.map((person) => (
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
                    {person.name}
                </Typography>
            </ManuallyAssignedPersonButton>
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
