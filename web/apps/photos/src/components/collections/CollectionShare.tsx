// TODO: Audit this file
/* eslint-disable @typescript-eslint/no-unnecessary-condition */
import Avatar from "@/components/Avatar";
import type { RemotePullOpts } from "@/components/gallery";
import { PublicLinkField } from "@/components/share/PublicLinkField";
import { sidebarStyles, sidebarTheme } from "@/components/sidebar/theme";
import { usePublicLinkURL } from "@/components/utils/use-public-link-url";
import { avatarTextColor } from "@/services/avatar";
import AddIcon from "@mui/icons-material/Add";
import AdminPanelSettingsIcon from "@mui/icons-material/AdminPanelSettings";
import ArrowBackIcon from "@mui/icons-material/ArrowBack";
import BlockIcon from "@mui/icons-material/Block";
import ChevronRightIcon from "@mui/icons-material/ChevronRight";
import CloseIcon from "@mui/icons-material/Close";
import CodeIcon from "@mui/icons-material/Code";
import ContentCopyIcon from "@mui/icons-material/ContentCopyOutlined";
import DoneIcon from "@mui/icons-material/Done";
import DownloadSharpIcon from "@mui/icons-material/DownloadSharp";
import ErrorOutlinedIcon from "@mui/icons-material/ErrorOutlined";
import LinkIcon from "@mui/icons-material/Link";
import ModeEditIcon from "@mui/icons-material/ModeEdit";
import Photo, { default as PhotoIcon } from "@mui/icons-material/Photo";
import PublicIcon from "@mui/icons-material/Public";
import RemoveCircleOutlinedIcon from "@mui/icons-material/RemoveCircleOutlined";
import WorkspacesIcon from "@mui/icons-material/Workspaces";
import {
    Box,
    IconButton,
    InputBase,
    Stack,
    styled,
    ThemeProvider,
    Typography,
} from "@mui/material";
import NumberAvatar from "@mui/material/Avatar";
import TextField from "@mui/material/TextField";
import type { LocalUser } from "ente-accounts/services/user";
import { LoadingButton } from "ente-base/components/mui/LoadingButton";
import {
    NestedSidebarDrawer,
    SidebarDrawer,
    SidebarDrawerTitlebar,
    TitledNestedSidebarDrawer,
} from "ente-base/components/mui/SidebarDrawer";
import {
    SidebarDrawerDepthContext,
    SidebarPanelContext,
} from "ente-base/components/mui/SidebarDrawerContext";
import {
    RowButtonGroup as BaseRowButtonGroup,
    RowButton,
    RowButtonDivider,
    RowButtonEndActivityIndicator,
    RowButtonGroupHint,
    RowButtonGroupTitle,
    RowLabel,
    RowSwitch,
} from "ente-base/components/RowButton";
import {
    v2CloseButtonSx,
    v2InputSx,
    v2SubmitButtonSx,
    v2TitleSx,
} from "ente-base/components/SingleInput.styles";
import { SingleInputDialog } from "ente-base/components/SingleInputDialog";
import type { SingleInputFormProps } from "ente-base/components/SingleInputForm";
import { useClipboardCopy } from "ente-base/components/utils/hooks";
import {
    useModalVisibility,
    type ModalVisibilityProps,
} from "ente-base/components/utils/modal";
import { isSxArray } from "ente-base/components/utils/sx";
import { RowCard } from "ente-base/components/v2/RowCard";
import { useBaseContext } from "ente-base/context";
import { deriveInteractiveKey } from "ente-base/crypto";
import { isHTTPErrorWithStatus, isMuseumHTTPError } from "ente-base/http";
import { formattedDateTime } from "ente-base/i18n-date";
import log from "ente-base/log";
import { useResolvedContactDisplay } from "ente-contacts";
import type {
    Collection,
    CollectionNewParticipantRole,
    PublicURL,
} from "ente-media/collection";
import { CollectionSubType, type CollectionUser } from "ente-media/collection";
import { useSettingsSnapshot } from "ente-new/photos/components/utils/use-snapshot";
import {
    createPublicURL,
    getCollectionByID,
    removePublicLink,
    shareCollection,
    unshareCollection,
    updateCollectionLayout,
    updatePublicURL,
    type CreatePublicURLAttributes,
    type UpdatePublicURLAttributes,
} from "ente-new/photos/services/collection";
import type { CollectionSummary } from "ente-new/photos/services/collection-summary";
import { usePhotosAppContext } from "ente-new/photos/types/context";
import { useFormik } from "formik";
import { t } from "i18next";
import React, {
    useCallback,
    useContext,
    useEffect,
    useMemo,
    useRef,
    useState,
} from "react";
import { Trans } from "react-i18next";
import { z } from "zod";

const RowButtonGroup: React.FC<React.PropsWithChildren> = ({ children }) => {
    const inPanel = !!useContext(SidebarPanelContext);
    return (
        <BaseRowButtonGroup
            data-share-group
            sx={
                inPanel
                    ? undefined
                    : {
                          bgcolor: "background.paper",
                          borderRadius: "20px",
                          overflow: "hidden",
                          "& > hr": { mx: "16px", opacity: 0.2 },
                          "& .MuiTypography-root": {
                              fontSize: 14,
                              lineHeight: "20px",
                              fontWeight: 500,
                          },
                          "& > button": { minHeight: 52 },
                          "& > button > .MuiStack-root > .MuiStack-root": {
                              py: "16px",
                              gap: "12px",
                          },
                          "& > .MuiStack-root > .MuiTypography-root": {
                              py: "16px",
                          },
                          "& .MuiSvgIcon-root": { fontSize: 20 },
                      }
            }
        >
            {children}
        </BaseRowButtonGroup>
    );
};

const ShareTitlebar: React.FC<
    React.ComponentProps<typeof SidebarDrawerTitlebar>
> = (props) => {
    const inPanel = !!useContext(SidebarPanelContext);
    if (inPanel) return <SidebarDrawerTitlebar {...props} />;
    const {
        title,
        caption,
        onClose,
        onRootClose,
        actionButton,
        showBackButton = true,
        showRootCloseButton = true,
    } = props;
    return (
        <Stack
            data-share-header
            direction="row"
            sx={{ mx: "12px", gap: "12px", alignItems: "flex-start" }}
        >
            {showBackButton && (
                <IconButton
                    aria-label="Back"
                    onClick={onClose}
                    sx={(theme) => ({
                        ...v2CloseButtonSx(theme),
                        backgroundColor: "transparent",
                        ...theme.applyStyles("dark", {
                            backgroundColor: "transparent",
                        }),
                        "&.Mui-focusVisible": {
                            backgroundColor: "fill.faintHover",
                        },
                    })}
                >
                    <ArrowBackIcon sx={{ fontSize: 18 }} />
                </IconButton>
            )}
            <Stack sx={{ flex: 1, minWidth: 0, gap: "4px" }}>
                <Typography
                    component="h2"
                    sx={{
                        ...v2TitleSx,
                        fontFamily: "'Outfit Variable', sans-serif",
                        overflowWrap: "anywhere",
                    }}
                >
                    {title}
                </Typography>
                {caption && (
                    <Typography
                        sx={{
                            fontSize: 14,
                            lineHeight: "20px",
                            fontWeight: 500,
                            color: "text.muted",
                            overflowWrap: "anywhere",
                        }}
                    >
                        {caption}
                    </Typography>
                )}
            </Stack>
            {actionButton}
            {showRootCloseButton && (
                <IconButton
                    aria-label={t("close")}
                    onClick={onRootClose}
                    sx={v2CloseButtonSx}
                >
                    <CloseIcon sx={{ fontSize: 18 }} />
                </IconButton>
            )}
        </Stack>
    );
};

const ShareNestedDrawer: React.FC<
    React.ComponentProps<typeof TitledNestedSidebarDrawer>
> = ({ open, onClose, onRootClose, anchor, maxWidth, children, ...rest }) => {
    const inPanel = !!useContext(SidebarPanelContext);
    const depth = useContext(SidebarDrawerDepthContext);
    if (inPanel) {
        return (
            <TitledNestedSidebarDrawer
                {...{ open, onClose, onRootClose, anchor, maxWidth, children }}
                {...rest}
            />
        );
    }
    return (
        <NestedSidebarDrawer
            {...{ open, onClose, onRootClose, anchor, maxWidth }}
            sx={{ "& .MuiDrawer-paper": { bgcolor: "background.paper2" } }}
        >
            <Stack
                sx={{
                    gap: "4px",
                    py: "12px",
                    "& > .MuiStack-root:not([data-share-header])": {
                        px: "12px",
                    },
                }}
            >
                <ShareTitlebar
                    {...{ onClose, onRootClose }}
                    {...rest}
                    titleInline
                />
                <SidebarDrawerDepthContext.Provider value={depth + 1}>
                    {children}
                </SidebarDrawerDepthContext.Provider>
            </Stack>
        </NestedSidebarDrawer>
    );
};

export type CollectionShareProps = ModalVisibilityProps & {
    user: LocalUser;
    collection: Collection;
    collectionSummary: CollectionSummary;
    emailByUserID: Map<number, string>;
    shareSuggestionEmails: string[];
    setBlockingLoad: (value: boolean) => void;
    onRemotePull: (opts?: RemotePullOpts) => Promise<void>;
    intent?: CollectionShareIntent;
};

export type CollectionShareIntent = "manage-link";

export const CollectionShare: React.FC<CollectionShareProps> = ({
    open,
    onClose,
    user,
    collection: collectionProp,
    collectionSummary,
    emailByUserID,
    shareSuggestionEmails,
    setBlockingLoad,
    onRemotePull,
    intent,
}) => {
    const inPanel = !!useContext(SidebarPanelContext);
    const { onGenericError } = useBaseContext();
    const { showLoadingBar, hideLoadingBar } = usePhotosAppContext();

    const [collection, setCollection] = useState(collectionProp);
    const hasFetchedPublicURLs = useRef(false);

    // Do not replace fetched public URLs with an older prop snapshot.
    useEffect(() => {
        if (
            !hasFetchedPublicURLs.current ||
            collectionProp?.publicURLs?.length > 0
        ) {
            setCollection(collectionProp);
        }
    }, [collectionProp]);

    // TODO: Duplicated from CollectionHeader.tsx
    const wrap = useCallback(
        (f: () => Promise<void>) => {
            const wrapped = async () => {
                showLoadingBar();
                try {
                    await f();
                } catch (e) {
                    onGenericError(e);
                } finally {
                    void onRemotePull({ silent: true });
                    hideLoadingBar();
                }
            };
            return (): void => void wrapped();
        },
        [showLoadingBar, hideLoadingBar, onGenericError, onRemotePull],
    );

    const currentSharee = collection?.sharees.find(
        (sharee) => sharee.id == user.id,
    );
    const isOwner = user.id == collection?.owner?.id;
    const isAdmin = currentSharee?.role == "ADMIN";
    const canManageParticipants = isOwner || isAdmin;
    const isSharedIncoming = collectionSummary?.type == "sharedIncoming";
    const showEmailSection = !isSharedIncoming || canManageParticipants;
    const hasPublicLink = collection?.publicURLs.length > 0;
    const showPublicShare =
        collection?.type != "uncategorized" &&
        (isOwner || (isSharedIncoming && hasPublicLink));

    const hasFetchedForSession = useRef(false);

    useEffect(() => {
        if (!open) {
            hasFetchedForSession.current = false;
            hasFetchedPublicURLs.current = false;
        }
    }, [open]);

    // Fetch once per open; the remote pull can retrigger this effect.
    useEffect(() => {
        const refreshCollection = async () => {
            const shouldFetch =
                open &&
                collection &&
                collection.type != "uncategorized" &&
                !isOwner &&
                isSharedIncoming &&
                !hasPublicLink &&
                !hasFetchedForSession.current;

            if (shouldFetch) {
                hasFetchedForSession.current = true;
                try {
                    const latestCollection = await getCollectionByID(
                        collection.id,
                    );
                    if (latestCollection.publicURLs.length > 0) {
                        hasFetchedPublicURLs.current = true;
                        setCollection(latestCollection);
                        await onRemotePull({ silent: true });
                    }
                } catch (e) {
                    log.error(
                        "[CollectionShare] Failed to refresh collection for non-owner",
                        e,
                    );
                }
            }
        };
        void refreshCollection();
    }, [
        open,
        isOwner,
        isSharedIncoming,
        hasPublicLink,
        collection,
        onRemotePull,
    ]);

    if (!collection || !collectionSummary) {
        return <></>;
    }

    return (
        <SidebarDrawer
            anchor="right"
            {...{ open, onClose }}
            sx={
                inPanel
                    ? undefined
                    : { "& .MuiDrawer-paper": { bgcolor: "background.paper2" } }
            }
        >
            <Stack sx={{ gap: "4px", py: "12px" }}>
                <ShareTitlebar
                    titleInline={!inPanel}
                    showBackButton={inPanel}
                    onClose={onClose}
                    onRootClose={onClose}
                    title={
                        canManageParticipants
                            ? t("share_album")
                            : t("sharing_details")
                    }
                    caption={collection.name}
                />
                <Stack
                    sx={{
                        py: "20px",
                        px: inPanel ? "8px" : "12px",
                        gap: "24px",
                    }}
                >
                    {showEmailSection ? (
                        <EmailShare
                            onRootClose={onClose}
                            {...{
                                user,
                                collection,
                                emailByUserID,
                                shareSuggestionEmails,
                                onRemotePull,
                                wrap,
                            }}
                        />
                    ) : null}
                    {showPublicShare ? (
                        <PublicShare
                            onRootClose={onClose}
                            {...{ collection, setBlockingLoad, onRemotePull }}
                            canManage={isOwner}
                            openManageLink={intent == "manage-link"}
                        />
                    ) : null}
                    {isSharedIncoming ? (
                        <SharingDetails
                            {...{
                                user,
                                collection,
                                collectionSummary,
                                emailByUserID,
                            }}
                        />
                    ) : null}
                </Stack>
            </Stack>
        </SidebarDrawer>
    );
};

type ResolvedEmailRowCommonProps = Pick<
    CollectionShareProps,
    "user" | "emailByUserID"
> & { email?: string; fallbackLabel?: string };

const ResolvedEmailRowLabel: React.FC<ResolvedEmailRowCommonProps> = ({
    email,
    fallbackLabel,
    user,
    emailByUserID,
}) => {
    const resolved = useResolvedContactDisplay({ email });

    return (
        <RowLabel
            startIcon={<Avatar email={email} {...{ user, emailByUserID }} />}
            label={(fallbackLabel ?? resolved.primaryLabel) || email || ""}
        />
    );
};

type ResolvedEmailRowButtonProps = ResolvedEmailRowCommonProps & {
    disabled?: boolean;
    onClick?: () => void;
    endIcon?: React.ReactNode;
};

const ResolvedEmailRowButton: React.FC<ResolvedEmailRowButtonProps> = ({
    disabled,
    email,
    endIcon,
    fallbackLabel,
    onClick,
    user,
    emailByUserID,
}) => {
    const resolved = useResolvedContactDisplay({ email });

    return (
        <RowButton
            fontWeight="regular"
            disabled={disabled}
            onClick={onClick ?? (() => undefined)}
            label={(fallbackLabel ?? resolved.primaryLabel) || email || ""}
            startIcon={<Avatar email={email} {...{ user, emailByUserID }} />}
            endIcon={endIcon}
        />
    );
};

const ResolvedEmailText: React.FC<{
    email?: string;
    fallbackLabel?: string;
}> = ({ email, fallbackLabel }) => {
    const resolved = useResolvedContactDisplay({ email });
    return <>{(fallbackLabel ?? resolved.primaryLabel) || email || ""}</>;
};

type SharingDetailsProps = Pick<
    CollectionShareProps,
    "user" | "collection" | "emailByUserID" | "collectionSummary"
>;

const SharingDetails: React.FC<SharingDetailsProps> = ({
    user,
    collection,
    collectionSummary,
    emailByUserID,
}) => {
    const isOwner = user.id == collection.owner?.id;
    const currentSharee = collection.sharees.find(
        (sharee) => sharee.id == user.id,
    );
    const isAdmin = currentSharee?.role == "ADMIN";

    const ownerEmail = isOwner ? user?.email : collection.owner?.email;

    const collaborators = collection.sharees
        .filter((sharee) => sharee.role == "COLLABORATOR")
        .map((sharee) => sharee.email)
        .filter((email) => email !== undefined);

    const admins = collection.sharees
        .filter((sharee) => sharee.role == "ADMIN")
        .map((sharee) => sharee.email)
        .filter((email) => email !== undefined);

    const viewers = collection.sharees
        .filter((sharee) => sharee.role == "VIEWER")
        .map((sharee) => sharee.email)
        .filter((email) => email !== undefined);

    if (!isOwner && isAdmin) {
        return (
            <Stack>
                <RowButtonGroupTitle icon={<AdminPanelSettingsIcon />}>
                    {t("owner")}
                </RowButtonGroupTitle>
                <RowButtonGroup>
                    <ResolvedEmailRowLabel
                        email={ownerEmail}
                        {...{ user, emailByUserID }}
                    />
                </RowButtonGroup>
            </Stack>
        );
    }

    return (
        <>
            <Stack>
                <RowButtonGroupTitle icon={<AdminPanelSettingsIcon />}>
                    {t("owner")}
                </RowButtonGroupTitle>
                <RowButtonGroup>
                    <ResolvedEmailRowLabel
                        email={ownerEmail}
                        fallbackLabel={isOwner ? t("you") : undefined}
                        {...{ user, emailByUserID }}
                    />
                </RowButtonGroup>
            </Stack>
            {admins.length > 0 && (
                <Stack>
                    <RowButtonGroupTitle icon={<AdminPanelSettingsIcon />}>
                        {t("admins")}
                    </RowButtonGroupTitle>
                    <RowButtonGroup>
                        {admins.map((email, index) => (
                            <React.Fragment key={email}>
                                <ResolvedEmailRowLabel
                                    email={email}
                                    fallbackLabel={
                                        email == user.email
                                            ? t("you")
                                            : undefined
                                    }
                                    {...{ user, emailByUserID }}
                                />
                                {index != admins.length - 1 && (
                                    <RowButtonDivider />
                                )}
                            </React.Fragment>
                        ))}
                    </RowButtonGroup>
                </Stack>
            )}
            {collectionSummary.attributes.has("sharedIncomingCollaborator") &&
                collaborators.length > 0 && (
                    <Stack>
                        <RowButtonGroupTitle icon={<ModeEditIcon />}>
                            {t("collaborators")}
                        </RowButtonGroupTitle>
                        <RowButtonGroup>
                            {collaborators.map((email, index) => (
                                <React.Fragment key={email}>
                                    <ResolvedEmailRowLabel
                                        email={email}
                                        fallbackLabel={
                                            email == user.email
                                                ? t("you")
                                                : undefined
                                        }
                                        {...{ user, emailByUserID }}
                                    />
                                    {index != collaborators.length - 1 && (
                                        <RowButtonDivider />
                                    )}
                                </React.Fragment>
                            ))}
                        </RowButtonGroup>
                    </Stack>
                )}
            {viewers.length > 0 && (
                <Stack>
                    <RowButtonGroupTitle icon={<Photo />}>
                        {t("viewers")}
                    </RowButtonGroupTitle>
                    <RowButtonGroup>
                        {viewers.map((email, index) => (
                            <React.Fragment key={email}>
                                <ResolvedEmailRowLabel
                                    email={email}
                                    fallbackLabel={
                                        email == user.email
                                            ? t("you")
                                            : undefined
                                    }
                                    {...{ user, emailByUserID }}
                                />
                                {index != viewers.length - 1 && (
                                    <RowButtonDivider />
                                )}
                            </React.Fragment>
                        ))}
                    </RowButtonGroup>
                </Stack>
            )}
        </>
    );
};

type EmailShareProps = {
    onRootClose: () => void;
    wrap: (f: () => Promise<void>) => () => void;
} & Pick<
    CollectionShareProps,
    | "user"
    | "collection"
    | "emailByUserID"
    | "shareSuggestionEmails"
    | "onRemotePull"
>;

const EmailShare: React.FC<EmailShareProps> = ({
    onRootClose,
    user,
    collection,
    emailByUserID,
    shareSuggestionEmails,
    wrap,
    onRemotePull,
}) => {
    const inPanel = !!useContext(SidebarPanelContext);
    const { show: showAddParticipant, props: addParticipantVisibilityProps } =
        useModalVisibility();
    const { show: showManageEmail, props: manageEmailVisibilityProps } =
        useModalVisibility();

    const [participantRole, setParticipantRole] =
        useState<CollectionNewParticipantRole>("VIEWER");

    const showAddViewer = useCallback(() => {
        setParticipantRole("VIEWER");
        showAddParticipant();
    }, [showAddParticipant]);

    const showAddCollaborator = useCallback(() => {
        setParticipantRole("COLLABORATOR");
        showAddParticipant();
    }, [showAddParticipant]);

    const showAddAdmin = useCallback(() => {
        setParticipantRole("ADMIN");
        showAddParticipant();
    }, [showAddParticipant]);

    const participantCount = collection.sharees.length;
    const currentSharee = collection.sharees.find(
        (sharee) => sharee.id == user.id,
    );
    const isOwner = user.id == collection.owner?.id;
    const isAdmin = currentSharee?.role == "ADMIN";
    const canManageParticipants = isOwner || isAdmin;

    return (
        <>
            <Stack>
                <RowButtonGroupTitle icon={<WorkspacesIcon />}>
                    {t("shared_with_people_count", { count: participantCount })}
                </RowButtonGroupTitle>
                <RowButtonGroup>
                    {participantCount > 0 ? (
                        <>
                            <RowButton
                                fontWeight="regular"
                                startIcon={
                                    <AvatarGroup
                                        {...{ user, emailByUserID }}
                                        sharees={collection.sharees}
                                    />
                                }
                                label={
                                    collection.sharees.length === 1 ? (
                                        inPanel ? (
                                            <ResolvedEmailText
                                                email={
                                                    collection.sharees[0]?.email
                                                }
                                            />
                                        ) : (
                                            collection.sharees[0]?.email
                                        )
                                    ) : null
                                }
                                endIcon={<ChevronRightIcon />}
                                onClick={showManageEmail}
                            />
                            {canManageParticipants ? (
                                <RowButtonDivider />
                            ) : null}
                        </>
                    ) : null}
                    {canManageParticipants ? (
                        <>
                            <RowButton
                                startIcon={<AddIcon />}
                                onClick={showAddViewer}
                                label={t("add_viewers")}
                            />
                            <RowButtonDivider />
                            <RowButton
                                startIcon={<AddIcon />}
                                onClick={showAddCollaborator}
                                label={t("add_collaborators")}
                            />
                            <RowButtonDivider />
                            <RowButton
                                startIcon={<AddIcon />}
                                onClick={showAddAdmin}
                                label={t("add_admins")}
                            />
                        </>
                    ) : null}
                </RowButtonGroup>
            </Stack>
            <AddParticipant
                {...addParticipantVisibilityProps}
                {...{
                    onRootClose,
                    user,
                    collection,
                    emailByUserID,
                    shareSuggestionEmails,
                    onRemotePull,
                }}
                role={participantRole}
            />
            <ManageEmailShare
                {...manageEmailVisibilityProps}
                {...{
                    onRootClose,
                    user,
                    collection,
                    emailByUserID,
                    shareSuggestionEmails,
                    participantCount,
                    wrap,
                    onRemotePull,
                    canManageParticipants,
                }}
            />
        </>
    );
};

const AvatarContainer = styled("div")({
    position: "relative",
    display: "flex",
    alignItems: "center",
    marginLeft: -5,
});

const AvatarContainerOuter = styled("div")({
    position: "relative",
    display: "flex",
    alignItems: "center",
    marginLeft: 8,
});

const AvatarCounter = styled(NumberAvatar)({
    height: 20,
    width: 20,
    fontSize: 10,
    color: avatarTextColor,
});

const SHAREE_AVATAR_LIMIT = 6;

interface AvatarGroupProps {
    user?: LocalUser;
    emailByUserID?: Map<number, string>;
    sharees: Collection["sharees"];
}

const AvatarGroup: React.FC<AvatarGroupProps> = ({
    sharees,
    user,
    emailByUserID,
}) => {
    const hasShareesOverLimit = sharees?.length > SHAREE_AVATAR_LIMIT;
    const countOfShareesOverLimit = sharees?.length - SHAREE_AVATAR_LIMIT;

    return (
        <AvatarContainerOuter>
            {sharees?.slice(0, 6).map((sharee) => (
                <AvatarContainer key={sharee.email}>
                    <Avatar
                        {...{ user, emailByUserID }}
                        key={sharee.email}
                        email={sharee.email}
                        opacity={100}
                    />
                </AvatarContainer>
            ))}
            {hasShareesOverLimit && (
                <AvatarContainer key="extra-count">
                    <AvatarCounter>+{countOfShareesOverLimit}</AvatarCounter>
                </AvatarContainer>
            )}
        </AvatarContainerOuter>
    );
};

type AddParticipantProps = ModalVisibilityProps & {
    onRootClose: () => void;
    role: CollectionNewParticipantRole;
} & Pick<
        CollectionShareProps,
        | "user"
        | "collection"
        | "emailByUserID"
        | "shareSuggestionEmails"
        | "onRemotePull"
    >;

const AddParticipant: React.FC<AddParticipantProps> = ({
    open,
    onClose,
    onRootClose,
    user,
    collection,
    emailByUserID,
    shareSuggestionEmails,
    role,
    onRemotePull,
}) => {
    const eligibleEmails = useMemo(() => {
        const ownerEmail = collection.owner?.email;
        return shareSuggestionEmails.filter(
            (email) =>
                email != user.email &&
                email != ownerEmail &&
                !collection?.sharees?.find((value) => value.email == email),
        );
    }, [
        user.email,
        shareSuggestionEmails,
        collection.sharees,
        collection.owner?.email,
    ]);

    const handleRootClose = () => {
        onClose();
        onRootClose();
    };

    const title =
        role == "VIEWER"
            ? t("add_viewers")
            : role == "COLLABORATOR"
              ? t("add_collaborators")
              : t("add_admins");

    const collectionShare: AddParticipantFormProps["onSubmit"] = async (
        emailOrEmails,
        setEmailFieldError,
    ) => {
        let emails: string[];
        if (typeof emailOrEmails == "string") {
            const email = emailOrEmails;
            if (email == user.email) {
                setEmailFieldError(t("sharing_with_self"));
                return;
            } else if (
                collection.owner?.email &&
                email == collection.owner.email
            ) {
                setEmailFieldError(
                    t("sharing_already_shared", { email: email }),
                );
                return;
            } else if (
                collection?.sharees?.find((value) => value.email === email)
            ) {
                setEmailFieldError(
                    t("sharing_already_shared", { email: email }),
                );
                return;
            }
            emails = [email];
        } else {
            emails = emailOrEmails;
        }

        for (const email of emails) {
            try {
                await shareCollection(collection, email, role);
            } catch (e) {
                if (isHTTPErrorWithStatus(e, 402)) {
                    setEmailFieldError(t("sharing_disabled_for_free_accounts"));
                    return;
                }

                if (isHTTPErrorWithStatus(e, 404)) {
                    setEmailFieldError(t("sharing_user_does_not_exist"));
                    return;
                }

                throw e;
            }
        }

        if (emails.length) {
            await onRemotePull({ silent: true });
        }

        onClose();
    };

    return (
        <ShareNestedDrawer
            anchor="right"
            {...{ open, onClose }}
            onRootClose={handleRootClose}
            title={title}
            caption={collection.name}
        >
            <AddParticipantForm
                {...{ user, emailByUserID }}
                existingEmails={eligibleEmails}
                submitButtonTitle={title}
                onSubmit={collectionShare}
            />
        </ShareNestedDrawer>
    );
};

type AddParticipantFormProps = {
    submitButtonTitle: string;
    existingEmails: string[];
    onSubmit: (
        emailOrEmails: string | string[],
        setEmailFieldError: (message: string) => void,
    ) => Promise<void>;
} & Pick<CollectionShareProps, "user" | "emailByUserID">;

const AddParticipantForm: React.FC<AddParticipantFormProps> = ({
    user,
    emailByUserID,
    existingEmails,
    submitButtonTitle,
    onSubmit,
}) => {
    const inPanel = !!useContext(SidebarPanelContext);
    const formik = useFormik({
        initialValues: { email: "", selectedEmails: new Array<string>() },
        onSubmit: async ({ email, selectedEmails }, { setFieldError }) => {
            const setEmailFieldError = (message: string) =>
                setFieldError("email", message);
            try {
                if (email) {
                    if (!z.email().safeParse(email).success) {
                        setEmailFieldError(t("invalid_email_error"));
                        return;
                    }

                    await onSubmit(email, setEmailFieldError);
                } else {
                    await onSubmit(selectedEmails, setEmailFieldError);
                }
            } catch (e) {
                log.error("Could not add participant", e);
                setEmailFieldError(t("generic_error"));
            }
        },
    });

    const resetExistingSelection = () =>
        void formik.setFieldValue("selectedEmails", []);

    const createToggleEmail = (email: string) => {
        return () => {
            const emails = formik.values.selectedEmails;
            void formik.setFieldValue(
                "selectedEmails",
                emails.includes(email)
                    ? emails.filter((e) => e != email)
                    : emails.concat(email),
            );
        };
    };

    return (
        <form onSubmit={formik.handleSubmit}>
            <Stack
                sx={{
                    gap: inPanel ? 1 : "20px",
                    py: "20px",
                    px: inPanel ? 2 : "12px",
                }}
            >
                <div>
                    <RowButtonGroupTitle>
                        {t("add_new_email")}
                    </RowButtonGroupTitle>
                    {inPanel ? (
                        <TextField
                            name="email"
                            type="email"
                            label={t("enter_email")}
                            margin="none"
                            value={formik.values.email}
                            onChange={formik.handleChange}
                            error={!!formik.errors.email}
                            helperText={formik.errors.email ?? " "}
                            disabled={formik.isSubmitting}
                            onClick={resetExistingSelection}
                            fullWidth
                        />
                    ) : (
                        <>
                            <InputBase
                                name="email"
                                type="email"
                                inputProps={{ "aria-label": t("enter_email") }}
                                placeholder={t("enter_email")}
                                value={formik.values.email}
                                onChange={formik.handleChange}
                                error={!!formik.errors.email}
                                disabled={formik.isSubmitting}
                                onClick={resetExistingSelection}
                                fullWidth
                                sx={[
                                    ...(isSxArray(v2InputSx)
                                        ? v2InputSx
                                        : [v2InputSx]),
                                    (theme) => ({
                                        boxSizing: "border-box",
                                        borderColor: "rgba(0, 0, 0, 0.16)",
                                        ...theme.applyStyles("dark", {
                                            bgcolor: "#303030",
                                            borderColor:
                                                "rgba(255, 255, 255, 0.18)",
                                        }),
                                        "&.Mui-focused": {
                                            borderColor: "accent.main",
                                        },
                                        "&.Mui-error": {
                                            borderColor: "critical.main",
                                        },
                                    }),
                                ]}
                            />
                            {formik.errors.email && (
                                <Typography
                                    role="alert"
                                    sx={{
                                        mt: "8px",
                                        fontSize: 12,
                                        lineHeight: "16px",
                                        color: "critical.main",
                                    }}
                                >
                                    {formik.errors.email}
                                </Typography>
                            )}
                        </>
                    )}
                </div>

                {existingEmails.length > 0 && (
                    <div>
                        <RowButtonGroupTitle>
                            {t("or_add_existing")}
                        </RowButtonGroupTitle>
                        <RowButtonGroup>
                            {existingEmails.map((email, index) => (
                                <React.Fragment key={email}>
                                    <ResolvedEmailRowButton
                                        email={email}
                                        onClick={createToggleEmail(email)}
                                        {...{ user, emailByUserID }}
                                        endIcon={
                                            formik.values.selectedEmails.includes(
                                                email,
                                            ) ? (
                                                <DoneIcon />
                                            ) : null
                                        }
                                    />
                                    {index != existingEmails.length - 1 && (
                                        <RowButtonDivider />
                                    )}
                                </React.Fragment>
                            ))}
                        </RowButtonGroup>
                    </div>
                )}
                <LoadingButton
                    type="submit"
                    color="accent"
                    loading={formik.isSubmitting}
                    fullWidth
                    sx={
                        inPanel
                            ? { my: 6 }
                            : [
                                  v2SubmitButtonSx,
                                  { flex: "none", minHeight: 52 },
                              ]
                    }
                >
                    {submitButtonTitle}
                </LoadingButton>
            </Stack>
        </form>
    );
};

type ManageEmailShareProps = ModalVisibilityProps & {
    onRootClose: () => void;
    participantCount: number;
    wrap: (f: () => Promise<void>) => () => void;
    canManageParticipants: boolean;
} & Pick<
        CollectionShareProps,
        | "user"
        | "collection"
        | "emailByUserID"
        | "shareSuggestionEmails"
        | "onRemotePull"
    >;

const ManageEmailShare: React.FC<ManageEmailShareProps> = ({
    open,
    onClose,
    onRootClose,
    user,
    collection,
    emailByUserID,
    shareSuggestionEmails,
    participantCount,
    wrap,
    onRemotePull,
    canManageParticipants,
}) => {
    const { show: showAddParticipant, props: addParticipantVisibilityProps } =
        useModalVisibility();
    const {
        show: showManageParticipant,
        props: manageParticipantVisibilityProps,
    } = useModalVisibility();

    const [participantRole, setParticipantRole] =
        useState<CollectionNewParticipantRole>("VIEWER");
    const [selectedParticipant, setSelectedParticipant] = useState<
        CollectionUser | undefined
    >(undefined);

    const showAddViewer = useCallback(() => {
        setParticipantRole("VIEWER");
        showAddParticipant();
    }, [showAddParticipant]);

    const showAddCollaborator = useCallback(() => {
        setParticipantRole("COLLABORATOR");
        showAddParticipant();
    }, [showAddParticipant]);

    const showAddAdmin = useCallback(() => {
        setParticipantRole("ADMIN");
        showAddParticipant();
    }, [showAddParticipant]);

    const selectAndManageParticipant = useCallback(
        (email: string) => {
            if (!canManageParticipants || email == user.email) return;
            setSelectedParticipant(
                collection.sharees.find((sharee) => sharee.email == email),
            );
            showManageParticipant();
        },
        [collection, showManageParticipant, canManageParticipants, user.email],
    );

    const handleRootClose = () => {
        onClose();
        onRootClose();
    };

    const ownerEmail =
        user.id == collection.owner?.id ? user.email : collection.owner?.email;

    const isOwner = user.id == collection.owner?.id;

    const collaborators = collection.sharees
        .filter((sharee) => sharee.role == "COLLABORATOR")
        .map((sharee) => sharee.email)
        .filter((email) => email !== undefined);

    const admins = collection.sharees
        .filter((sharee) => sharee.role == "ADMIN")
        .map((sharee) => sharee.email)
        .filter((email) => email !== undefined);
    const currentSharee = collection.sharees.find(
        (sharee) => sharee.email == user.email,
    );
    if (
        currentSharee?.role == "ADMIN" &&
        user.email &&
        !admins.includes(user.email)
    ) {
        admins.unshift(user.email);
    }

    const viewers = collection.sharees
        .filter((sharee) => sharee.role == "VIEWER")
        .map((sharee) => sharee.email)
        .filter((email) => email !== undefined);

    return (
        <>
            <ShareNestedDrawer
                anchor="right"
                {...{ open, onClose }}
                onRootClose={handleRootClose}
                title={collection.name}
                caption={t("participants_count", { count: participantCount })}
            >
                <Stack sx={{ gap: 3, py: "20px", px: "12px" }}>
                    <Stack>
                        <RowButtonGroupTitle icon={<AdminPanelSettingsIcon />}>
                            {t("owner")}
                        </RowButtonGroupTitle>
                        <RowButtonGroup>
                            <ResolvedEmailRowLabel
                                email={ownerEmail}
                                fallbackLabel={isOwner ? t("you") : undefined}
                                {...{ user, emailByUserID }}
                            />
                        </RowButtonGroup>
                    </Stack>
                    {(admins.length > 0 || canManageParticipants) && (
                        <Stack>
                            <RowButtonGroupTitle
                                icon={<AdminPanelSettingsIcon />}
                            >
                                {t("admins")}
                            </RowButtonGroupTitle>
                            <RowButtonGroup>
                                {admins.map((item, index) => {
                                    const isSelf = item == user.email;
                                    const canManageThis =
                                        canManageParticipants && !isSelf;
                                    return (
                                        <React.Fragment key={item}>
                                            <ResolvedEmailRowButton
                                                email={item}
                                                disabled={!canManageThis}
                                                onClick={() => {
                                                    if (canManageThis) {
                                                        selectAndManageParticipant(
                                                            item,
                                                        );
                                                    }
                                                }}
                                                fallbackLabel={
                                                    isSelf
                                                        ? t("you")
                                                        : undefined
                                                }
                                                {...{ user, emailByUserID }}
                                                endIcon={
                                                    canManageThis ? (
                                                        <ChevronRightIcon />
                                                    ) : undefined
                                                }
                                            />
                                            {(index < admins.length - 1 ||
                                                canManageParticipants) && (
                                                <RowButtonDivider />
                                            )}
                                        </React.Fragment>
                                    );
                                })}
                                {canManageParticipants ? (
                                    <RowButton
                                        startIcon={<AddIcon />}
                                        onClick={showAddAdmin}
                                        label={
                                            admins?.length
                                                ? t("add_more")
                                                : t("add_admins")
                                        }
                                    />
                                ) : null}
                            </RowButtonGroup>
                        </Stack>
                    )}
                    <Stack>
                        <RowButtonGroupTitle icon={<ModeEditIcon />}>
                            {t("collaborators")}
                        </RowButtonGroupTitle>
                        <RowButtonGroup>
                            {collaborators.map((item, index) => {
                                const canManageThis =
                                    canManageParticipants && item != user.email;
                                return (
                                    <React.Fragment key={item}>
                                        <ResolvedEmailRowButton
                                            email={item}
                                            disabled={!canManageThis}
                                            onClick={() => {
                                                if (canManageThis) {
                                                    selectAndManageParticipant(
                                                        item,
                                                    );
                                                }
                                            }}
                                            {...{ user, emailByUserID }}
                                            endIcon={
                                                canManageThis ? (
                                                    <ChevronRightIcon />
                                                ) : undefined
                                            }
                                        />
                                        {(index < collaborators.length - 1 ||
                                            canManageParticipants) && (
                                            <RowButtonDivider />
                                        )}
                                    </React.Fragment>
                                );
                            })}

                            {canManageParticipants ? (
                                <RowButton
                                    startIcon={<AddIcon />}
                                    onClick={showAddCollaborator}
                                    label={
                                        collaborators?.length
                                            ? t("add_more")
                                            : t("add_collaborators")
                                    }
                                />
                            ) : null}
                        </RowButtonGroup>
                    </Stack>
                    <Stack>
                        <RowButtonGroupTitle icon={<Photo />}>
                            {t("viewers")}
                        </RowButtonGroupTitle>
                        <RowButtonGroup>
                            {viewers.map((item, index) => {
                                const canManageThis =
                                    canManageParticipants && item != user.email;
                                return (
                                    <React.Fragment key={item}>
                                        <ResolvedEmailRowButton
                                            email={item}
                                            disabled={!canManageThis}
                                            onClick={() => {
                                                if (canManageThis) {
                                                    selectAndManageParticipant(
                                                        item,
                                                    );
                                                }
                                            }}
                                            {...{ user, emailByUserID }}
                                            endIcon={
                                                canManageThis ? (
                                                    <ChevronRightIcon />
                                                ) : undefined
                                            }
                                        />
                                        {(index < viewers.length - 1 ||
                                            canManageParticipants) && (
                                            <RowButtonDivider />
                                        )}
                                    </React.Fragment>
                                );
                            })}
                            {canManageParticipants ? (
                                <RowButton
                                    startIcon={<AddIcon />}
                                    onClick={showAddViewer}
                                    label={
                                        viewers?.length
                                            ? t("add_more")
                                            : t("add_viewers")
                                    }
                                />
                            ) : null}
                        </RowButtonGroup>
                    </Stack>
                </Stack>
            </ShareNestedDrawer>
            <AddParticipant
                {...addParticipantVisibilityProps}
                {...{
                    user,
                    collection,
                    emailByUserID,
                    shareSuggestionEmails,
                    onRootClose,
                    onRemotePull,
                }}
                role={participantRole}
            />
            <ManageParticipant
                {...manageParticipantVisibilityProps}
                {...{ onRootClose, wrap, collection, onRemotePull }}
                participant={selectedParticipant}
            />
        </>
    );
};

type ManageParticipantProps = ModalVisibilityProps & {
    onRootClose: () => void;
    wrap: (f: () => Promise<void>) => () => void;
    // open implies participant is set.
    participant: CollectionUser | undefined;
} & Pick<CollectionShareProps, "collection" | "onRemotePull">;

const ManageParticipant: React.FC<ManageParticipantProps> = ({
    open,
    onClose,
    onRootClose,
    collection,
    participant,
    wrap,
    onRemotePull,
}) => {
    const { showMiniDialog } = useBaseContext();

    const handleRootClose = () => {
        onClose();
        onRootClose();
    };

    const unshare = wrap(() =>
        unshareCollection(collection.id, participant!.email!),
    );

    const handleRemove = () => {
        unshare();
        onClose();
    };

    const confirmChangeRolePermission = useCallback(
        (
            selectedEmail: string,
            newRole: CollectionNewParticipantRole,
            action: () => Promise<void>,
        ) => {
            let message: React.ReactNode;
            let buttonText: string;

            if (newRole == "VIEWER") {
                message = (
                    <Trans
                        i18nKey="change_permission_to_viewer"
                        values={{ selectedEmail }}
                    />
                );
                buttonText = t("confirm_convert_to_viewer");
            } else if (newRole == "COLLABORATOR") {
                message = t("change_permission_to_collaborator", {
                    selectedEmail,
                });
                buttonText = t("confirm_convert_to_collaborator");
            } else {
                message = t("change_permission_to_admin", { selectedEmail });
                buttonText = t("confirm_convert_to_admin");
            }

            showMiniDialog({
                title: t("change_permission_title"),
                message: message,
                continue: { text: buttonText, color: "critical", action },
            });
        },
        [showMiniDialog],
    );

    const updateCollectionRole = async (
        selectedEmail: string,
        newRole: CollectionNewParticipantRole,
    ) => {
        await shareCollection(collection, selectedEmail, newRole);
        participant!.role = newRole;
        await onRemotePull({ silent: true });
    };

    const createOnRoleChange = (role: CollectionNewParticipantRole) => () => {
        if (role == participant!.role) return;
        const email = participant!.email!;
        confirmChangeRolePermission(email, role, () =>
            updateCollectionRole(email, role),
        );
    };

    const removeParticipant = () => {
        showMiniDialog({
            title: t("remove_participant_title"),
            message: (
                <Trans
                    i18nKey="remove_participant_message"
                    values={{ selectedEmail: participant!.email! }}
                />
            ),
            continue: {
                text: t("confirm_remove"),
                color: "critical",
                action: handleRemove,
            },
        });
    };

    const participantDisplay = useResolvedContactDisplay({
        userID: participant?.id,
        email: participant?.email,
    });

    if (!participant) {
        return <></>;
    }

    return (
        <ShareNestedDrawer
            anchor="right"
            {...{ open, onClose }}
            onRootClose={handleRootClose}
            title={t("manage")}
            caption={participantDisplay.primaryLabel || participant.email || ""}
        >
            <Stack sx={{ gap: "32px", py: "20px", px: "8px" }}>
                <Stack>
                    <Typography
                        variant="small"
                        sx={{ color: "text.muted", padding: 1 }}
                    >
                        {t("added_as")}
                    </Typography>

                    <RowButtonGroup>
                        <RowButton
                            fontWeight="regular"
                            onClick={createOnRoleChange("ADMIN")}
                            label={t("admin")}
                            startIcon={<AdminPanelSettingsIcon />}
                            endIcon={
                                participant.role === "ADMIN" && <DoneIcon />
                            }
                        />
                        <RowButtonDivider />
                        <RowButton
                            fontWeight="regular"
                            onClick={createOnRoleChange("COLLABORATOR")}
                            label={t("collaborator")}
                            startIcon={<ModeEditIcon />}
                            endIcon={
                                participant.role === "COLLABORATOR" && (
                                    <DoneIcon />
                                )
                            }
                        />
                        <RowButtonDivider />

                        <RowButton
                            fontWeight="regular"
                            onClick={createOnRoleChange("VIEWER")}
                            label={t("viewer")}
                            startIcon={<PhotoIcon />}
                            endIcon={
                                participant.role == "VIEWER" && <DoneIcon />
                            }
                        />
                    </RowButtonGroup>

                    <Typography
                        variant="small"
                        sx={{ color: "text.muted", padding: 1 }}
                    >
                        {t("collaborator_hint")}
                    </Typography>

                    <Stack sx={{ py: "30px" }}>
                        <Typography
                            variant="small"
                            sx={{ color: "text.muted", padding: 1 }}
                        >
                            {t("remove_participant")}
                        </Typography>

                        <RowButtonGroup>
                            <RowButton
                                color="critical"
                                fontWeight="regular"
                                onClick={removeParticipant}
                                label={t("remove")}
                                startIcon={<BlockIcon />}
                            />
                        </RowButtonGroup>
                    </Stack>
                </Stack>
            </Stack>
        </ShareNestedDrawer>
    );
};

type PublicShareProps = {
    onRootClose: () => void;
    canManage: boolean;
    openManageLink: boolean;
} & Pick<
    CollectionShareProps,
    "collection" | "setBlockingLoad" | "onRemotePull"
>;

const PublicShare: React.FC<PublicShareProps> = ({
    collection,
    onRootClose,
    setBlockingLoad,
    onRemotePull,
    canManage,
    openManageLink,
}) => {
    const { customDomain } = useSettingsSnapshot();

    const [shareState, setShareState] = useState({
        collection,
        publicURL: collection.publicURLs[0],
    });
    const publicURL =
        shareState.collection === collection
            ? shareState.publicURL
            : collection.publicURLs[0];
    const setPublicURL = (publicURL: PublicURL | undefined) =>
        setShareState({ collection, publicURL });
    const { resolvedURL, isLoading, error } = usePublicLinkURL(
        collection,
        publicURL,
        canManage ? customDomain : undefined,
    );

    return publicURL && resolvedURL ? (
        canManage ? (
            <ManagePublicShare
                openOnMount={openManageLink}
                {...{
                    onRootClose,
                    collection,
                    publicURL,
                    setPublicURL,
                    resolvedURL,
                    setBlockingLoad,
                    onRemotePull,
                }}
            />
        ) : (
            <ReadOnlyPublicShare resolvedURL={resolvedURL} />
        )
    ) : publicURL ? (
        <Typography role="status" color="text.muted">
            {error ? t("generic_error") : isLoading ? t("loading") : null}
        </Typography>
    ) : canManage ? (
        <EnablePublicShareOptions
            {...{ collection, onRemotePull, setPublicURL }}
        />
    ) : null;
};

type EnablePublicShareOptionsProps = {
    setPublicURL: (value: PublicURL) => void;
} & Pick<CollectionShareProps, "collection" | "onRemotePull">;

const EnablePublicShareOptions: React.FC<EnablePublicShareOptionsProps> = ({
    collection,
    onRemotePull,
    setPublicURL,
}) => {
    const [pending, setPending] = useState("");
    const [errorMessage, setErrorMessage] = useState("");

    const create = (attributes?: CreatePublicURLAttributes) => {
        setErrorMessage("");
        setPending(attributes ? "collect" : "link");

        void (async () => {
            try {
                const publicURL = await createPublicURL(collection.id, {
                    enableJoin: false,
                    ...attributes,
                });
                setPending("");
                setPublicURL(publicURL);
                void onRemotePull({ silent: true });
            } catch (e: unknown) {
                log.error("Could not create public link", e);
                setErrorMessage(
                    isHTTPErrorWithStatus(e, 402)
                        ? t("sharing_disabled_for_free_accounts")
                        : t("generic_error"),
                );
                setPending("");
            }
        })();
    };

    return (
        <Stack>
            <RowButtonGroupTitle icon={<PublicIcon />}>
                {t("share_link_section_title")}
            </RowButtonGroupTitle>
            <RowButtonGroup>
                <RowButton
                    label={t("create_public_link")}
                    startIcon={<LinkIcon />}
                    disabled={!!pending}
                    endIcon={
                        pending == "link" && <RowButtonEndActivityIndicator />
                    }
                    onClick={() => create()}
                />
                <RowButtonDivider />
                <RowButton
                    label={t("collect_photos")}
                    startIcon={<DownloadSharpIcon />}
                    disabled={!!pending}
                    endIcon={
                        pending == "collect" && (
                            <RowButtonEndActivityIndicator />
                        )
                    }
                    onClick={() => create({ enableCollect: true })}
                />
            </RowButtonGroup>
            {errorMessage && (
                <Typography
                    variant="small"
                    sx={{
                        color: "critical.main",
                        mt: 0.5,
                        textAlign: "center",
                    }}
                >
                    {errorMessage}
                </Typography>
            )}
        </Stack>
    );
};

type ManagePublicShareProps = { onRootClose: () => void } & Pick<
    ManagePublicShareOptionsProps,
    "publicURL" | "setPublicURL" | "resolvedURL"
> &
    Pick<
        CollectionShareProps,
        "collection" | "setBlockingLoad" | "onRemotePull"
    > & { openOnMount: boolean };

const ManagePublicShare: React.FC<ManagePublicShareProps> = ({
    onRootClose,
    collection,
    publicURL,
    setPublicURL,
    resolvedURL,
    setBlockingLoad,
    onRemotePull,
    openOnMount,
}) => {
    const {
        show: showManagePublicShare,
        props: managePublicShareVisibilityProps,
    } = useModalVisibility();

    const inPanel = !!useContext(SidebarPanelContext);
    const [copied, handleCopyLink] = useClipboardCopy(resolvedURL);

    useEffect(() => {
        if (openOnMount) showManagePublicShare();
    }, [openOnMount, showManagePublicShare]);

    const handleManagePublicShareClose = useCallback(() => {
        managePublicShareVisibilityProps.onClose();
        if (openOnMount) onRootClose();
    }, [managePublicShareVisibilityProps, openOnMount, onRootClose]);

    return (
        <>
            <Stack>
                <RowButtonGroupTitle
                    icon={inPanel ? <PublicIcon /> : <LinkIcon />}
                >
                    {t("public_link_enabled")}
                </RowButtonGroupTitle>
                {!inPanel && !isLinkExpired(publicURL.validTill) && (
                    <Stack sx={{ mb: "16px" }}>
                        <PublicLinkField url={resolvedURL} variant="dialog" />
                    </Stack>
                )}
                <RowButtonGroup>
                    {isLinkExpired(publicURL.validTill) ? (
                        <RowButton
                            disabled
                            startIcon={<ErrorOutlinedIcon />}
                            color="critical"
                            onClick={showManagePublicShare}
                            label={t("link_expired")}
                        />
                    ) : inPanel ? (
                        <RowButton
                            startIcon={
                                copied ? (
                                    <DoneIcon sx={{ color: "accent.main" }} />
                                ) : (
                                    <ContentCopyIcon />
                                )
                            }
                            onClick={handleCopyLink}
                            disabled={isLinkExpired(publicURL.validTill)}
                            label={t("copy_link")}
                        />
                    ) : null}
                    {(inPanel || isLinkExpired(publicURL.validTill)) && (
                        <RowButtonDivider />
                    )}
                    <RowButton
                        startIcon={<LinkIcon />}
                        endIcon={<ChevronRightIcon />}
                        onClick={showManagePublicShare}
                        label={t("manage_link")}
                    />
                </RowButtonGroup>
            </Stack>
            <ManagePublicShareOptions
                {...managePublicShareVisibilityProps}
                onClose={handleManagePublicShareClose}
                {...{
                    onRootClose,
                    collection,
                    publicURL,
                    resolvedURL,
                    setPublicURL,
                    setBlockingLoad,
                    onRemotePull,
                }}
            />
        </>
    );
};

const isLinkExpired = (validTill: number) =>
    validTill > 0 && validTill < Date.now() * 1000;

const ReadOnlyPublicShare: React.FC<{ resolvedURL: string }> = ({
    resolvedURL,
}) => {
    const inPanel = !!useContext(SidebarPanelContext);
    const [copied, handleCopyLink] = useClipboardCopy(resolvedURL);
    return (
        <Stack>
            <RowButtonGroupTitle icon={inPanel ? <PublicIcon /> : <LinkIcon />}>
                {t("public_link_enabled")}
            </RowButtonGroupTitle>
            <RowButtonGroup>
                {!inPanel ? (
                    <PublicLinkField url={resolvedURL} />
                ) : (
                    <RowButton
                        startIcon={
                            copied ? (
                                <DoneIcon sx={{ color: "accent.main" }} />
                            ) : (
                                <ContentCopyIcon />
                            )
                        }
                        onClick={handleCopyLink}
                        label={t("copy_link")}
                    />
                )}
            </RowButtonGroup>
        </Stack>
    );
};

type ManagePublicShareOptionsProps = {
    publicURL: PublicURL;
    setPublicURL: (publicURL: PublicURL | undefined) => void;
    resolvedURL: string;
} & Pick<
    CollectionShareProps,
    "collection" | "setBlockingLoad" | "onRemotePull"
> &
    (
        | ({
              variant?: "drawer";
              onRootClose: () => void;
          } & ModalVisibilityProps)
        | { variant: "inline" }
    );

export const ManagePublicShareOptions: React.FC<
    ManagePublicShareOptionsProps
> = (props) => {
    const {
        collection,
        publicURL,
        setPublicURL,
        resolvedURL,
        setBlockingLoad,
        onRemotePull,
    } = props;
    const inPanel = !!useContext(SidebarPanelContext);
    const panelRef = useRef<HTMLDivElement>(null);
    const [errorMessage, setErrorMessage] = useState("");
    const { embedURL: embedBaseURL } = useSettingsSnapshot();

    const [copied, handleCopyLink] = useClipboardCopy(resolvedURL);

    const embedURL = resolvedURL
        ? resolvedURL.replace(
              new URL(resolvedURL).origin,
              embedBaseURL || "https://embed.ente.com",
          )
        : undefined;
    const iframeHTML = embedURL
        ? `<iframe src="${embedURL}" width="800" height="600" frameborder="0" allowfullscreen></iframe>`
        : "";
    const [embedCopied, handleCopyEmbedLink] = useClipboardCopy(iframeHTML);

    const onRootClose = () => {
        if (props.variant != "inline") props.onRootClose();
    };
    const onClose = () => {
        if (props.variant != "inline") props.onClose();
    };
    const handleRootClose = () => {
        onClose();
        onRootClose();
    };

    const handlePublicURLUpdate = async (
        updates: UpdatePublicURLAttributes,
    ) => {
        setBlockingLoad(true);
        setErrorMessage("");
        try {
            setPublicURL(await updatePublicURL(collection.id, updates));
            void onRemotePull({ silent: true });
        } catch (e) {
            log.error("Could not update public link", e);
            if (await isMuseumHTTPError(e, 403, "LINK_EDIT_NOT_ALLOWED")) {
                setErrorMessage(t("link_edit_disabled_for_free_accounts"));
            } else {
                setErrorMessage(t("generic_error"));
            }
        } finally {
            setBlockingLoad(false);
        }
    };
    const handleRemovePublicLink = async () => {
        setBlockingLoad(true);
        setErrorMessage("");
        try {
            await removePublicLink(collection);
            setPublicURL(undefined);
            void onRemotePull({ silent: true });
            if (
                collection.magicMetadata?.data.subType ==
                    CollectionSubType.quicklink &&
                collection.sharees.length === 0
            ) {
                handleRootClose();
            } else {
                onClose();
            }
        } catch (e) {
            log.error("Failed to remove public link", e);
            setErrorMessage(t("generic_error"));
        } finally {
            setBlockingLoad(false);
        }
    };

    const content = (
        <Stack sx={{ gap: 3, py: "20px", px: "8px" }}>
            <Stack
                sx={
                    inPanel
                        ? { gap: 3 }
                        : {
                              bgcolor: "background.paper",
                              borderRadius: "20px",
                              overflow: "hidden",
                              "& [data-share-group]": {
                                  bgcolor: "transparent",
                                  borderRadius: 0,
                              },
                              "& > * + *": {
                                  position: "relative",
                                  "&::before": {
                                      content: '""',
                                      position: "absolute",
                                      top: 0,
                                      left: 16,
                                      right: 16,
                                      borderTop: "1px solid",
                                      borderColor: "divider",
                                      opacity: 0.2,
                                      pointerEvents: "none",
                                  },
                              },
                          }
                }
            >
                <ManageLayout
                    {...{
                        collection,
                        onRootClose,
                        onRemotePull,
                        setBlockingLoad,
                    }}
                />
                <ManagePublicCollect
                    {...{ publicURL }}
                    onUpdate={handlePublicURLUpdate}
                />
                <ManageLinkExpiry
                    {...{ onRootClose, publicURL }}
                    onUpdate={handlePublicURLUpdate}
                />
                <RowButtonGroup>
                    <ManageDeviceLimit
                        {...{ onRootClose, publicURL }}
                        onUpdate={handlePublicURLUpdate}
                    />
                    <RowButtonDivider />
                    <ManageDownloadAccess
                        {...{ publicURL }}
                        onUpdate={handlePublicURLUpdate}
                    />
                    <RowButtonDivider />
                    <ManageJoinAlbum
                        {...{ publicURL }}
                        onUpdate={handlePublicURLUpdate}
                    />
                    <RowButtonDivider />
                    <ManageLinkPassword
                        {...{ publicURL }}
                        onUpdate={handlePublicURLUpdate}
                    />
                </RowButtonGroup>
            </Stack>
            <RowButtonGroup>
                <RowButton
                    startIcon={
                        copied ? (
                            <DoneIcon sx={{ color: "accent.main" }} />
                        ) : (
                            <ContentCopyIcon />
                        )
                    }
                    onClick={handleCopyLink}
                    label={t("copy_link")}
                />
                <RowButtonDivider />
                <RowButton
                    startIcon={
                        embedCopied ? (
                            <DoneIcon sx={{ color: "accent.main" }} />
                        ) : (
                            <CodeIcon />
                        )
                    }
                    onClick={handleCopyEmbedLink}
                    label={t("copy_embed_html")}
                />
            </RowButtonGroup>
            <RowButtonGroup>
                <RowButton
                    color="critical"
                    startIcon={<RemoveCircleOutlinedIcon />}
                    onClick={handleRemovePublicLink}
                    label={t("remove_link")}
                />
            </RowButtonGroup>
            {errorMessage && (
                <Typography
                    variant="small"
                    sx={{ color: "critical.main", textAlign: "center" }}
                >
                    {errorMessage}
                </Typography>
            )}
        </Stack>
    );

    if (props.variant == "inline") {
        return (
            <ThemeProvider theme={sidebarTheme}>
                <Stack
                    ref={panelRef}
                    component="section"
                    aria-label={t("manage_link")}
                    sx={[
                        sidebarStyles,
                        {
                            gap: 2,
                            position: "relative",
                            minWidth: 0,
                            borderRadius: 3,
                            overflow: "hidden",
                        },
                    ]}
                >
                    <Box sx={{ minWidth: 0, p: 1 }}>
                        <SidebarPanelContext.Provider
                            value={() => panelRef.current}
                        >
                            <SidebarDrawerDepthContext.Provider value={1}>
                                <Stack sx={{ gap: 1 }}>
                                    <ManageLayout
                                        variant="inline"
                                        {...{
                                            collection,
                                            onRootClose,
                                            onRemotePull,
                                        }}
                                    />
                                    <ManagePublicCollect
                                        variant="inline"
                                        publicURL={publicURL}
                                        onUpdate={handlePublicURLUpdate}
                                    />
                                    <ManageLinkExpiry
                                        variant="inline"
                                        {...{ onRootClose, publicURL }}
                                        onUpdate={handlePublicURLUpdate}
                                    />
                                    <ManageDeviceLimit
                                        variant="inline"
                                        {...{ onRootClose, publicURL }}
                                        onUpdate={handlePublicURLUpdate}
                                    />
                                    <ManageDownloadAccess
                                        variant="inline"
                                        publicURL={publicURL}
                                        onUpdate={handlePublicURLUpdate}
                                    />
                                    <ManageJoinAlbum
                                        variant="inline"
                                        publicURL={publicURL}
                                        onUpdate={handlePublicURLUpdate}
                                    />
                                    <ManageLinkPassword
                                        variant="inline"
                                        publicURL={publicURL}
                                        onUpdate={handlePublicURLUpdate}
                                    />
                                </Stack>
                                <Stack sx={{ mt: 2, gap: 1 }}>
                                    <RowCard
                                        title={t("copy_link")}
                                        onClick={handleCopyLink}
                                        endIcon={
                                            copied ? (
                                                <DoneIcon />
                                            ) : (
                                                <ContentCopyIcon />
                                            )
                                        }
                                    />
                                    <RowCard
                                        title={t("copy_embed_html")}
                                        onClick={handleCopyEmbedLink}
                                        endIcon={
                                            embedCopied ? (
                                                <DoneIcon />
                                            ) : (
                                                <CodeIcon />
                                            )
                                        }
                                    />
                                </Stack>
                            </SidebarDrawerDepthContext.Provider>
                        </SidebarPanelContext.Provider>
                    </Box>
                    {errorMessage && (
                        <Typography
                            variant="small"
                            sx={{ px: 2, color: "critical.main" }}
                        >
                            {errorMessage}
                        </Typography>
                    )}
                </Stack>
            </ThemeProvider>
        );
    }

    return (
        <ShareNestedDrawer
            anchor="right"
            open={props.open}
            onClose={onClose}
            onRootClose={handleRootClose}
            title={t("manage_link")}
            caption={collection.name}
        >
            {content}
        </ShareNestedDrawer>
    );
};

interface ManagePublicLinkSettingProps {
    variant?: "inline";
    publicURL: PublicURL;
    onUpdate: (req: UpdatePublicURLAttributes) => Promise<void>;
}

type ManagePublicLinkSettingDrawerProps = ManagePublicLinkSettingProps & {
    onRootClose: () => void;
};

const ManagePublicCollect: React.FC<ManagePublicLinkSettingProps> = ({
    variant,
    publicURL,
    onUpdate,
}) => {
    const handleCollectSetting = () => {
        void onUpdate({ enableCollect: !publicURL.enableCollect });
    };

    const handleCommentSetting = () => {
        void onUpdate({ enableComment: !publicURL.enableComment });
    };

    if (variant == "inline") {
        return (
            <Stack sx={{ gap: 1 }}>
                <PublicLinkSwitch
                    variant={variant}
                    label={t("allow_adding_photos")}
                    checked={publicURL.enableCollect}
                    onClick={handleCollectSetting}
                />
                <PublicLinkSwitch
                    variant={variant}
                    label={t("enable_comments")}
                    checked={publicURL.enableComment}
                    onClick={handleCommentSetting}
                />
            </Stack>
        );
    }

    return (
        <Stack>
            <RowButtonGroup>
                <RowSwitch
                    label={t("allow_adding_photos")}
                    checked={publicURL.enableCollect}
                    onClick={handleCollectSetting}
                />
                <RowButtonDivider />
                <RowSwitch
                    label={t("enable_comments")}
                    checked={publicURL.enableComment}
                    onClick={handleCommentSetting}
                />
            </RowButtonGroup>
        </Stack>
    );
};

const ManageLinkExpiry: React.FC<ManagePublicLinkSettingDrawerProps> = ({
    variant,
    onRootClose,
    publicURL,
    onUpdate,
}) => {
    const { show: showExpiryOptions, props: expiryOptionsVisibilityProps } =
        useModalVisibility();

    const options = useMemo(() => shareExpiryOptions(), []);

    const changeShareExpiryValue = (value: number) => async () => {
        await onUpdate({ validTill: value });
        expiryOptionsVisibilityProps.onClose();
    };

    return (
        <>
            {variant == "inline" ? (
                <RowCard
                    title={
                        <Box
                            component="span"
                            sx={{
                                color: isLinkExpired(publicURL.validTill)
                                    ? "critical.main"
                                    : "text.base",
                            }}
                        >
                            {t("link_expiry")}
                        </Box>
                    }
                    subtitle={
                        isLinkExpired(publicURL.validTill)
                            ? t("link_expired")
                            : publicURL.validTill
                              ? formattedDateTime(publicURL.validTill, {
                                    omitWeekdayWhenYearIncluded: true,
                                })
                              : t("never")
                    }
                    onClick={showExpiryOptions}
                />
            ) : (
                <RowButtonGroup>
                    <RowButton
                        onClick={showExpiryOptions}
                        endIcon={<ChevronRightIcon />}
                        label={t("link_expiry")}
                        color={
                            isLinkExpired(publicURL.validTill)
                                ? "critical"
                                : "primary"
                        }
                        caption={
                            isLinkExpired(publicURL.validTill)
                                ? t("link_expired")
                                : publicURL.validTill
                                  ? formattedDateTime(publicURL.validTill, {
                                        omitWeekdayWhenYearIncluded: true,
                                    })
                                  : t("never")
                        }
                    />
                </RowButtonGroup>
            )}
            <ShareNestedDrawer
                anchor="right"
                {...expiryOptionsVisibilityProps}
                onRootClose={onRootClose}
                title={t("link_expiry")}
            >
                <Stack sx={{ gap: "32px", py: "20px", px: "8px" }}>
                    <RowButtonGroup>
                        {options.map(({ label, value }, index) => (
                            <React.Fragment key={value()}>
                                <RowButton
                                    fontWeight="regular"
                                    onClick={changeShareExpiryValue(value())}
                                    label={label}
                                />
                                {index != options.length - 1 && (
                                    <RowButtonDivider />
                                )}
                            </React.Fragment>
                        ))}
                    </RowButtonGroup>
                </Stack>
            </ShareNestedDrawer>
        </>
    );
};

const shareExpiryOptions = () => [
    { label: t("never"), value: () => 0 },
    { label: t("after_time.hour"), value: () => microsecsAfter("hour") },
    { label: t("after_time.day"), value: () => microsecsAfter("day") },
    { label: t("after_time.week"), value: () => microsecsAfter("week") },
    { label: t("after_time.month"), value: () => microsecsAfter("month") },
    { label: t("after_time.year"), value: () => microsecsAfter("year") },
];

const microsecsAfter = (after: "hour" | "day" | "week" | "month" | "year") => {
    let date = new Date();
    switch (after) {
        case "hour":
            date = new Date(date.getTime() + 60 * 60 * 1000);
            break;
        case "day":
            date.setDate(date.getDate() + 1);
            break;
        case "week":
            date.setDate(date.getDate() + 7);
            break;
        case "month":
            date.setMonth(date.getMonth() + 1);
            break;
        case "year":
            date.setFullYear(date.getFullYear() + 1);
            break;
    }
    return date.getTime() * 1000;
};

const ManageDeviceLimit: React.FC<ManagePublicLinkSettingDrawerProps> = ({
    variant,
    onRootClose,
    publicURL,
    onUpdate,
}) => {
    const { show: showDeviceOptions, props: deviceOptionsVisibilityProps } =
        useModalVisibility();

    const options = useMemo(() => deviceLimitOptions(), []);

    const changeDeviceLimitValue = (value: number) => async () => {
        await onUpdate({ deviceLimit: value });
        deviceOptionsVisibilityProps.onClose();
    };

    return (
        <>
            {variant == "inline" ? (
                <RowCard
                    title={t("device_limit")}
                    subtitle={
                        publicURL.deviceLimit == 0
                            ? t("none")
                            : publicURL.deviceLimit.toString()
                    }
                    onClick={showDeviceOptions}
                />
            ) : (
                <RowButton
                    label={t("device_limit")}
                    caption={
                        publicURL.deviceLimit == 0
                            ? t("none")
                            : publicURL.deviceLimit.toString()
                    }
                    onClick={showDeviceOptions}
                    endIcon={<ChevronRightIcon />}
                />
            )}
            <ShareNestedDrawer
                anchor="right"
                {...deviceOptionsVisibilityProps}
                onRootClose={onRootClose}
                title={t("device_limit")}
            >
                <Stack sx={{ gap: "32px", py: "20px", px: "8px" }}>
                    <RowButtonGroup>
                        {options.map(({ label, value }, index) => (
                            <React.Fragment key={label}>
                                <RowButton
                                    fontWeight="regular"
                                    onClick={changeDeviceLimitValue(value)}
                                    label={label}
                                />
                                {index != options.length - 1 && (
                                    <RowButtonDivider />
                                )}
                            </React.Fragment>
                        ))}
                    </RowButtonGroup>
                </Stack>
            </ShareNestedDrawer>
        </>
    );
};

const deviceLimitOptions = () =>
    [0, 2, 5, 10, 25, 50].map((i) => ({
        label: i == 0 ? t("none") : i.toString(),
        value: i,
    }));

const ManageDownloadAccess: React.FC<ManagePublicLinkSettingProps> = ({
    variant,
    publicURL,
    onUpdate,
}) => {
    const { showMiniDialog } = useBaseContext();

    const handleFileDownloadSetting = () => {
        if (publicURL.enableDownload) {
            showMiniDialog({
                title: t("disable_file_download"),
                message: <Trans i18nKey={"disable_file_download_message"} />,
                continue: {
                    text: t("disable"),
                    color: "critical",
                    action: () => onUpdate({ enableDownload: false }),
                },
            });
        } else {
            // TODO: Various calls to onUpdate return promises. The UI should
            // handle the in-progress states where needed.
            void onUpdate({ enableDownload: true });
        }
    };

    return (
        <PublicLinkSwitch
            variant={variant}
            label={t("allow_downloads")}
            checked={publicURL.enableDownload}
            onClick={handleFileDownloadSetting}
        />
    );
};

const ManageJoinAlbum: React.FC<ManagePublicLinkSettingProps> = ({
    variant,
    publicURL,
    onUpdate,
}) => {
    const handleJoinSetting = () => {
        void onUpdate({ enableJoin: !publicURL.enableJoin });
    };

    return (
        <PublicLinkSwitch
            variant={variant}
            label={t("allow_joining_album")}
            checked={publicURL.enableJoin}
            onClick={handleJoinSetting}
        />
    );
};

const ManageLinkPassword: React.FC<ManagePublicLinkSettingProps> = ({
    variant,
    publicURL,
    onUpdate,
}) => {
    const { showMiniDialog } = useBaseContext();
    const { show: showSetPassword, props: setPasswordVisibilityProps } =
        useModalVisibility();

    const handlePasswordChangeSetting = () => {
        if (publicURL.passwordEnabled) {
            showMiniDialog({
                title: t("disable_password"),
                message: t("disable_password_message"),
                continue: {
                    text: t("disable"),
                    color: "critical",
                    action: () => onUpdate({ disablePassword: true }),
                },
            });
        } else {
            showSetPassword();
        }
    };

    return (
        <>
            <PublicLinkSwitch
                variant={variant}
                label={t("password_lock")}
                checked={publicURL.passwordEnabled}
                onClick={handlePasswordChangeSetting}
            />
            <SetPublicLinkPassword
                {...setPasswordVisibilityProps}
                {...{ publicURL, onUpdate }}
            />
        </>
    );
};

const PublicLinkSwitch: React.FC<
    React.ComponentProps<typeof RowSwitch> & { variant?: "inline" }
> = ({ variant, label, checked, onClick }) =>
    variant == "inline" ? (
        <RowCard
            title={label}
            toggle={{ checked: !!checked, onChange: onClick }}
        />
    ) : (
        <RowSwitch {...{ label, checked, onClick }} />
    );

type SetPublicLinkPasswordProps = ModalVisibilityProps &
    Omit<ManagePublicLinkSettingProps, "variant">;

const SetPublicLinkPassword: React.FC<SetPublicLinkPasswordProps> = ({
    open,
    onClose,
    publicURL,
    onUpdate,
}) => {
    const savePassword: SingleInputFormProps["onSubmit"] = async (password) => {
        await enablePublicUrlPassword(password);
        publicURL.passwordEnabled = true;
    };

    const enablePublicUrlPassword = async (password: string) => {
        const kek = await deriveInteractiveKey(password);
        return onUpdate({
            passHash: kek.key,
            nonce: kek.salt,
            opsLimit: kek.opsLimit,
            memLimit: kek.memLimit,
        });
    };

    return (
        <SingleInputDialog
            {...{ open, onClose }}
            title={t("password_lock")}
            inputType="password"
            label={t("password")}
            submitButtonTitle={t("lock")}
            onSubmit={savePassword}
        />
    );
};

interface ManageLayoutProps {
    variant?: "inline";
    onRootClose: () => void;
    collection: Collection;
    onRemotePull: (opts?: RemotePullOpts) => Promise<void>;
}

const ManageLayout: React.FC<ManageLayoutProps> = ({
    variant,
    onRootClose,
    collection,
    onRemotePull,
}) => {
    const { show: showLayoutOptions, props: layoutOptionsVisibilityProps } =
        useModalVisibility();
    const [errorMessage, setErrorMessage] = useState("");
    const [loadingLayout, setLoadingLayout] = useState<string | null>(null);
    const [selectedLayout, setSelectedLayout] = useState<string | null>(null);

    const options = useMemo(() => layoutOptions(), []);

    const currentLayout = normalizedLayoutValue(
        collection.pubMagicMetadata?.data?.layout,
    );

    const changeLayoutValue = (value: string) => async () => {
        if (value === currentLayout) return;

        setLoadingLayout(value);
        setSelectedLayout(value);
        setErrorMessage("");
        try {
            await updateCollectionLayout(collection, value);
            await onRemotePull({ silent: true });
        } catch (e) {
            log.error("Could not update collection layout", e);
            setErrorMessage(t("generic_error"));
            setSelectedLayout(null);
        } finally {
            setLoadingLayout(null);
        }
    };

    return (
        <>
            {variant == "inline" ? (
                <RowCard
                    title={t("album_layout")}
                    subtitle={layoutLabel(currentLayout)}
                    onClick={showLayoutOptions}
                />
            ) : (
                <RowButtonGroup>
                    <RowButton
                        label={t("album_layout")}
                        caption={layoutLabel(currentLayout)}
                        onClick={showLayoutOptions}
                        endIcon={<ChevronRightIcon />}
                    />
                </RowButtonGroup>
            )}
            <ShareNestedDrawer
                anchor="right"
                {...layoutOptionsVisibilityProps}
                onRootClose={onRootClose}
                title={t("album_layout")}
                titleInline={variant == "inline"}
            >
                <Stack sx={{ py: "20px", px: "8px" }}>
                    <RowButtonGroup>
                        {options.map(({ label, value }, index) => (
                            <React.Fragment key={value}>
                                <RowButton
                                    fontWeight="regular"
                                    onClick={changeLayoutValue(value)}
                                    label={label}
                                    disabled={loadingLayout !== null}
                                    endIcon={
                                        loadingLayout === value ? (
                                            <RowButtonEndActivityIndicator />
                                        ) : (selectedLayout === null &&
                                              currentLayout === value) ||
                                          (selectedLayout === value &&
                                              !loadingLayout) ? (
                                            <DoneIcon />
                                        ) : undefined
                                    }
                                />
                                {index != options.length - 1 && (
                                    <RowButtonDivider />
                                )}
                            </React.Fragment>
                        ))}
                    </RowButtonGroup>
                    {currentLayout === "trip" && !loadingLayout && (
                        <RowButtonGroupHint>
                            {t("maps_privacy_notice")}
                        </RowButtonGroupHint>
                    )}
                    {errorMessage && (
                        <Typography
                            variant="small"
                            sx={{
                                color: "critical.main",
                                mt: 0.5,
                                textAlign: "center",
                            }}
                        >
                            {errorMessage}
                        </Typography>
                    )}
                </Stack>
            </ShareNestedDrawer>
        </>
    );
};

const layoutOptions = () => [
    { label: layoutLabel("masonry"), value: "masonry" },
    { label: t("trip"), value: "trip" },
    { label: t("grouped"), value: "grouped" },
];

const normalizedLayoutValue = (layout: string | undefined) => {
    if (layout === "continuous") {
        return "masonry";
    }
    if (layout === "grouped" || layout === "trip" || layout === "masonry") {
        return layout;
    }
    return "masonry";
};

const layoutLabel = (layout: string) =>
    layout === "masonry"
        ? t("masonry", { defaultValue: "Masonry" })
        : t(layout);
