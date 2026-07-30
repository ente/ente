import { AlbumsAppProviders } from "@/app/providers/AlbumsAppProviders";
import type { AppProps } from "next/app";

import "@/app/styles/fonts.css";
import "@/app/styles/global.css";
import "ente-gallery/styles/photoswipe.css";

type AlbumsAppProps = AppProps<Record<string, unknown>>;

const App: React.FC<AlbumsAppProps> = ({ Component, pageProps }) => {
    return (
        <AlbumsAppProviders>
            <Component {...pageProps} />
        </AlbumsAppProviders>
    );
};

export default App;
