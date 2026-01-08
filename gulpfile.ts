import { spawn } from "node:child_process";
import * as fs from "node:fs";
import { cp, mkdir, readdir, rm, unlink, writeFile } from "node:fs/promises";
import * as os from "node:os";
import * as path from "node:path";
import * as process from "node:process";
import * as util from "node:util";
import gulp from "gulp";
import { bundle } from "luabundle";
import which from "which";

const DISTFILES = {
    "Scripts/Utility/Voice Hopper.lua": {bundle: "main.lua"},
};

export async function test(): Promise<void> {
    await lint({allowMissing: true});

    const luaProg = "luajit";
    const luaPath = await which(luaProg, {nothrow: true});
    if (luaPath == null) {
        throw new Error(`${luaProg} not found in PATH: ${process.env.PATH}`);
    }

    const libDir  = "lib";
    const testDir = "test";
    for (const file of await readdir("test")) {
        if (path.extname(file) != ".lua")
            continue;

        const filePath = path.join(testDir, file);
        console.info(`Running ${filePath}...`);

        const child = spawn(luaPath, [filePath], {
            env: {
                ...process.env,
                "LUA_PATH": path.join(libDir, "?.lua") + ";" + path.join(testDir, "lib", "?.lua")
            }
        });
        child.stdout.on("data", buf => console.log (buf.toString().trimEnd()));
        child.stderr.on("data", buf => console.warn(buf.toString().trimEnd()));
        await new Promise((resolve, reject) => {
            child.on("close", code => {
                if (code == 0)
                    resolve(undefined);
                else
                    reject(new Error(`${luaProg} exited with status ${code}`));
            });
        });
    }
}

interface LintOptions {
    allowMissing?: boolean;
    permissive?: boolean;
    verbose?: boolean;
}
export async function lint(opts?: LintOptions) {
    opts = opts ?? {};

    const lintProg = 'luacheck';
    const lintPath = await which(lintProg, {nothrow: true});
    if (lintPath == null) {
        if (opts.allowMissing)
            return;
        else
            throw new Error(`${lintProg} not found in PATH: ${process.env.PATH}`);
    }

    const args = [
        "--cache", ".luacheckcache",
        "lib",
        "src",
    ];
    if (!opts.verbose) {
        args.push("--quiet");
    }

    const child = spawn(lintPath, args);
    child.stdout.on("data", buf => console.log (buf.toString().trimEnd()));
    child.stderr.on("data", buf => console.warn(buf.toString().trimEnd()));
    await new Promise((resolve, reject) => {
        child.on("close", code => {
            if (code == 0) {
                resolve(undefined);
            }
            else {
                if (opts.permissive && code == 1) {
                    // No errors, only warnings. Ignore them.
                    resolve(undefined);
                }
                else {
                    reject(new Error(`${lintProg} exited with status ${code}`));
                }
            }
        });
    });
}

export async function clean(): Promise<void> {
    await rm("dist", {force: true, recursive: true});
}

export async function build(): Promise<void> {
    await lint({allowMissing: true, permissive: true});
    await clean();

    for (const [file, how] of Object.entries(DISTFILES)) {
        if (how.bundle !== undefined) {
            const srcFile  = path.join("src", how.bundle);
            const destFile = path.join("dist", file);
            const bundled  = bundle(srcFile, {
                expressionHandler: (module, expression) => {
                    const start = expression.loc!.start;
                    throw new Error(`Non-literal require found in \`${module.name}' at ${start.line}:${start.column}`);
                },
                luaVersion: "LuaJIT",
                paths: [
                    "lib/?.lua",
                    "src/?.lua",
                ],
            });

            await mkdir(path.dirname(destFile), {recursive: true});
            await writeFile(destFile, bundled);
            console.info(`Created a Lua bundle: ${destFile}`);
        }
        else {
            throw new Error(`Don't know how to process this file: ${util.inspect({file: how})}`);
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
