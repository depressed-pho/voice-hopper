import * as fs from "node:fs";
import { cp, mkdir, rm, unlink, writeFile } from "node:fs/promises";
import * as os from "node:os";
import * as path from "node:path";
import gulp from "gulp";
import { bundle } from "luabundle";

const DISTFILES = {
    "Scripts/Utility/Voice Hopper.lua": {bundle: "main.lua"},
};

export async function clean(): Promise<void> {
    await rm("dist", {force: true, recursive: true});
}

export async function build(): Promise<void> {
    await clean();

    for (const [file, how] of Object.entries(DISTFILES)) {
        if (how.bundle !== undefined) {
            const srcFile  = path.join("src", how.bundle);
            const destFile = path.join("dist", file);
            const bundled  = bundle(srcFile, {
                expressionHandler: (module, expression) => {
                    const start = expression.loc!.start;
                    console.error(`ERROR: Non-literal require found in \`${module.name}' at ${start.line}:${start.column}`);
                },
                luaVersion: "LuaJIT",
                paths: [
                    "lib/?.lua",
                ],
            });

            await mkdir(path.dirname(destFile), {recursive: true});
            await writeFile(destFile, bundled);
            console.info(`Created a Lua bundle: ${destFile}`);
        }
        else {
            console.error("Don't know how to process this file:", {file: how});
        }
    }
}

function getFusionRootPath(): string {
    switch (os.platform()) {
        case "darwin":
            return path.join(os.homedir(), "Library", "Application Support", "Blackmagic Design", "DaVinci Resolve", "Fusion");
        case "linux":
            return path.join(os.homedir(), ".local", "share", "DaVinciResolve", "Fusion");
        case "win32":
            return path.join(process.env.APPDATA!, "Blackmagic Design", "DaVinci Resolve", "Fusion");
        default:
            throw new Error(`Don't know how to locate the Fusion root path on this platform: ${os.platform()}`);
    }
}

export async function install(): Promise<void> {
    await build();

    const root = getFusionRootPath();
    for (const file of Object.keys(DISTFILES)) {
        const srcFile  = path.join("dist", file);
        const destFile = path.join(root, file);
        await mkdir(path.dirname(destFile), {recursive: true});
        await cp(srcFile, destFile);
        console.info(`Installed: ${destFile}`);
    }
}

export async function uninstall(): Promise<void> {
    const root = getFusionRootPath();
    for (const file of Object.keys(DISTFILES)) {
        const destFile = path.join(root, file);
        if (fs.existsSync(destFile)) {
            await unlink(destFile);
            console.info(`Uninstalled: ${destFile}`);
        }
    }
}

export function watch() {
    gulp.watch([
        "lib/**",
        "src/**",
    ], {ignoreInitial: false}, install);
};

export default build;
