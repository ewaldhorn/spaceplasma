import { mkdir, rm, copyFile, readFile, writeFile } from "fs/promises";
import { join } from "path";
import CleanCSS from "clean-css";
import * as htmlMinifier from "html-minifier-terser";
import { build as esbuild } from "esbuild";

const WEB_DIR = "./web";
const DIST_DIR = "./dist";

async function build() {
    console.log("");
    console.log("🌌 === Starting Cybernetic Dist Compression ===");

    // 1. Clean and create dist directory
    try {
        await rm(DIST_DIR, { recursive: true, force: true });
    } catch (e) { }
    await mkdir(DIST_DIR, { recursive: true });

    // 2. Bundle and minify JavaScript with esbuild
    console.log("\t⚡ Compressing JavaScript driver via esbuild...");
    try {
        await esbuild({
            entryPoints: [join(WEB_DIR, "main.js")],
            outfile: join(DIST_DIR, "main.js"),
            minify: true,
            bundle: true,
            format: "esm",
        });
    } catch (err) {
        console.error(`\t❌ Failed to build JavaScript bundle:`, err);
        process.exit(1);
    }

    // 3. Minify CSS using CleanCSS
    console.log("\t🎨 Compressing cybernetic CSS stylesheet...");
    const cssContent = await readFile(join(WEB_DIR, "style.css"), "utf-8");
    const minifiedCSS = new CleanCSS({}).minify(cssContent);
    await writeFile(join(DIST_DIR, "style.css"), minifiedCSS.styles);

    // 4. Minify HTML
    console.log("\t📰 Compressing primary index.html wrapper...");
    const htmlContent = await readFile(join(WEB_DIR, "index.html"), "utf-8");
    const minifiedHTML = await htmlMinifier.minify(htmlContent, {
        collapseWhitespace: true,
        removeComments: true,
        minifyJS: true,
        minifyCSS: true,
    });
    await writeFile(join(DIST_DIR, "index.html"), minifiedHTML);

    // 5. Copy the WASM engine
    console.log("\t🧬 Injecting high-optimization WASM core binary...");
    await copyFile(join(WEB_DIR, "plasma.wasm"), join(DIST_DIR, "plasma.wasm"));

    console.log("");
    console.log("🚀 === Compression Pipeline Success ===");
    console.log(`\tPackage stored in native directory: ${DIST_DIR}`);
    console.log("");
}

build().catch((err) => {
    console.error("❌ CRITICAL COMPRESSION FAILURE:", err);
    process.exit(1);
});
