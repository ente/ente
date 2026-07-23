const apps = {
    photos: {
        packageId: "io.ente.photos",
        testFlightId: "1542026904",
        accentColor: 65280,
    },
    auth: {
        packageId: "io.ente.auth",
        testFlightId: "6444121398",
        accentColor: 8388736,
    },
    locker: {
        packageId: "io.ente.locker",
        testFlightId: "6747611956",
        accentColor: 1077759,
    },
    ensu: {
        packageId: "io.ente.ensu",
        testFlightId: "6758197006",
        accentColor: 16633363,
    },
    "photos-desktop": {
        accentColor: 65280,
    },
};

const app = process.argv[2];
const config = apps[app];
const releaseTag = process.argv[3];
if (!config || !releaseTag) {
    throw new Error(`Usage: node .github/scripts/release-notify.mjs ${Object.keys(apps).join("|")} <release-tag>`);
}

const releaseUrl = `https://github.com/ente/nightly/releases/tag/${releaseTag}`;

const env = (name) => {
    const value = process.env[name];
    if (!value) {
        throw new Error(`${name} is required`);
    }
    return value;
};

const releaseTitle = env("RELEASE_TITLE");
const releaseBodyGrouped = process.env.RELEASE_BODY_GROUPED ?? "";

let previousChanges = false;
const releaseBody = releaseBodyGrouped
    .split("\n")
    .map((line) => {
        if (line === "Previous changes:") {
            previousChanges = true;
        }
        return previousChanges && line.trim() ? `-# ${line}` : line;
    })
    .join("\n");

const releaseBodyDiscord =
    Array.from(releaseBody).length > 3000
        ? `${Array.from(releaseBody).slice(0, 3000).join("")}\n...\n-# See the GitHub release for full notes.`
        : releaseBody;

const downloadLinks = [];
if (config.packageId) {
    downloadLinks.push(`[Play Store](https://play.google.com/store/apps/details?id=${config.packageId})`);
}
if (config.testFlightId) {
    downloadLinks.push(`[TestFlight](https://appstoreconnect.apple.com/apps/${config.testFlightId}/testflight/ios)`);
}
downloadLinks.push(`[GitHub Release](${releaseUrl})`);
const downloadLine = `-# Download: ${downloadLinks.join(" | ")}`;

const heading = releaseTag.endsWith("-rc") ? "##" : "###";
const components = [{ type: 10, content: `${heading} ${releaseTitle}` }];
if (releaseBodyDiscord) {
    components.push({ type: 10, content: releaseBodyDiscord });
}
components.push({ type: 14 }, { type: 10, content: downloadLine });

const response = await fetch(`${env("DISCORD_WEBHOOK")}?with_components=true`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
        flags: 32768,
        components: [
            {
                type: 17,
                accent_color: config.accentColor,
                components,
            },
        ],
    }),
});

if (!response.ok) {
    throw new Error(`Discord notification failed: ${response.status} ${await response.text()}`);
}
