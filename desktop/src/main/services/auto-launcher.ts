import AutoLaunch from "auto-launch";
import { app } from "electron/main";

class AutoLauncher {
    private autoLaunch?: AutoLaunch;

    constructor() {
        if (process.platform != "darwin") {
            this.autoLaunch = new AutoLaunch({ name: "ente", isHidden: true });
        }
    }

    async isEnabled() {
        const autoLaunch = this.autoLaunch;
        if (autoLaunch) {
            return await autoLaunch.isEnabled();
        } else {
            return app.getLoginItemSettings().openAtLogin;
        }
    }

    async toggleAutoLaunch() {
        const wasEnabled = await this.isEnabled();
        const autoLaunch = this.autoLaunch;
        if (autoLaunch) {
            if (wasEnabled) await autoLaunch.disable();
            else await autoLaunch.enable();
        } else {
            const openAtLogin = !wasEnabled;
            app.setLoginItemSettings({ openAtLogin });
        }
    }

    wasAutoLaunched() {
        if (this.autoLaunch) {
            return app.commandLine.hasSwitch("hidden");
        } else {
            return app.getLoginItemSettings().wasOpenedAtLogin;
        }
    }
}

export default new AutoLauncher();
