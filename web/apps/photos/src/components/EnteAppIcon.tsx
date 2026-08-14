import type React from "react";

type EnteApp = "photos" | "auth" | "locker";

interface EnteAppIconProps {
    size?: number;
}

interface AppIconProps extends EnteAppIconProps {
    app: EnteApp;
}

const AppIcon: React.FC<AppIconProps> = ({ app, size = 24 }) => (
    <img
        src={`/images/app-icons/${app}.png`}
        srcSet={`/images/app-icons/2.0x/${app}.png 2x, /images/app-icons/3.0x/${app}.png 3x`}
        width={size}
        height={size}
        alt=""
        aria-hidden
        draggable={false}
        style={{ display: "block", objectFit: "contain" }}
    />
);

export const EntePhotosIcon: React.FC<EnteAppIconProps> = (props) => (
    <AppIcon app="photos" {...props} />
);

export const EnteAuthIcon: React.FC<EnteAppIconProps> = (props) => (
    <AppIcon app="auth" {...props} />
);

export const EnteLockerIcon: React.FC<EnteAppIconProps> = (props) => (
    <AppIcon app="locker" {...props} />
);
