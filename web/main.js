/**
 * Cybernetic Plasma Visualizer
 * Wasm Interface Loader & Animation Loop
 */

const consoleOutput = document.getElementById("console-output");
const loadingOverlay = document.getElementById("loading-overlay");
const fpsCounter = document.getElementById("fps-counter");
const statusText = document.getElementById("status-text");

function log(msg, type = "info") {
    const prefix = type === "error" ? "[ERR]" : ">";
    const line = document.createElement("p");
    line.className = `log-line ${type === 'error' ? 'text-pink' : ''}`;
    line.innerText = `${prefix} ${msg}`;
    consoleOutput.appendChild(line);
    consoleOutput.scrollTop = consoleOutput.scrollHeight;
}

async function initApp() {
    log("Fetching plasma.wasm bytes...");
    
    try {
        const canvas = document.getElementById("plasma-canvas");
        const ctx = canvas.getContext("2d", { alpha: false });
        
        // Set the native resolution of the WASM engine buffer
        const width = 800;
        const height = 600;

        // Compile and instantiate the Zig WASM module
        log("Connecting WebAssembly runtime...");
        const response = await fetch("plasma.wasm");
        if (!response.ok) {
            throw new Error(`Failed to fetch WebAssembly binary: ${response.statusText}`);
        }
        
        const buffer = await response.arrayBuffer();
        log("Compiling freestanding binary...");
        const module = await WebAssembly.compile(buffer);
        
        log("Instantiating memory segment...");
        const instance = await WebAssembly.instantiate(module, {
            env: {}
        });

        log("Wasm binary successfully linked.");
        
        // Initialize state
        instance.exports.init();
        log("Core graphics subsystem ONLINE.");

        // Setup direct memory bridge for frame drawing
        const memory = instance.exports.memory;
        const bufferPtr = instance.exports.get_buffer_ptr();
        
        log(`Buffer base address resolved: 0x${bufferPtr.toString(16)}`);

        // Create a direct, shared view into WebAssembly memory space
        const pixelData = new Uint8ClampedArray(
            memory.buffer,
            bufferPtr,
            width * height * 4
        );

        // Image data container for canvas blitting
        const imageData = new ImageData(pixelData, width, height);

        // Hide loading state
        loadingOverlay.classList.add("hidden");
        statusText.innerText = "KERNEL: RENDERING";
        log("Visualizer synchronization achieved. Loop start.");

        // Tracking performance stats
        let lastTime = performance.now();
        let frameCount = 0;
        let fpsTimer = 0;

        function renderLoop(currentTime) {
            // Calculate real delta time for FPS metrics
            const realDt = (currentTime - lastTime) / 1000.0;
            lastTime = currentTime;

            // Update telemetry
            frameCount++;
            fpsTimer += realDt;
            if (fpsTimer >= 0.5) {
                const currentFps = Math.round(frameCount / fpsTimer);
                fpsCounter.innerText = `${currentFps} FPS`;
                frameCount = 0;
                fpsTimer = 0;
            }

            // 1. Command Zig to process the next mathematical frame.
            // Note: The WASM module utilizes its own rigid internal clock for physics.
            instance.exports.update(currentTime);

            // 2. Direct Blit: Push the shared WASM pixel buffer directly to the primary canvas!
            // No offscreen canvases, no drawImage overhead, completely stall-free!
            // The browser GPU scales this 400x300 natively using CSS pixelated rules.
            ctx.putImageData(imageData, 0, 0);

            // Repeat
            requestAnimationFrame(renderLoop);
        }

        // ---------------------------------------------------------------------
        // Mouse & Touch Interaction Interface
        // Scales viewport coordinates directly into engine's internal 800x600 space
        // ---------------------------------------------------------------------
        function pipeInteraction(e, pressed) {
            e.preventDefault();
            const rect = canvas.getBoundingClientRect();
            
            let clientX, clientY;
            if (e.touches && e.touches.length > 0) {
                clientX = e.touches[0].clientX;
                clientY = e.touches[0].clientY;
            } else {
                clientX = e.clientX;
                clientY = e.clientY;
            }
            
            // Translate client coord space to local 800x600 matrix
            const mx = ((clientX - rect.left) / rect.width) * width;
            const my = ((clientY - rect.top) / rect.height) * height;
            
            instance.exports.set_mouse_state(mx, my, pressed);
        }

        function parkCursor() {
            // Secure pointer coordinates far outside boundary to fade ripple
            instance.exports.set_mouse_state(-2000, -2000, false);
        }

        // Mouse Listeners
        canvas.addEventListener("mousemove", (e) => pipeInteraction(e, e.buttons > 0));
        canvas.addEventListener("mousedown", (e) => pipeInteraction(e, true));
        canvas.addEventListener("mouseup", (e) => pipeInteraction(e, false));
        canvas.addEventListener("mouseleave", parkCursor);

        // Touch Listeners (Mobile/Tablet support)
        canvas.addEventListener("touchstart", (e) => pipeInteraction(e, true), { passive: false });
        canvas.addEventListener("touchmove", (e) => pipeInteraction(e, true), { passive: false });
        canvas.addEventListener("touchend", (e) => {
            if (e.touches.length === 0) parkCursor();
            else pipeInteraction(e, false);
        }, { passive: false });
        canvas.addEventListener("touchcancel", parkCursor);

        // Kick off loop
        requestAnimationFrame(renderLoop);

    } catch (err) {
        log(`CRITICAL BOOT ERROR: ${err.message}`, "error");
        statusText.innerText = "KERNEL PANIC";
        statusText.style.color = "#f857a6";
        document.querySelector(".status-indicator").style.backgroundColor = "#f857a6";
        document.querySelector(".status-indicator").style.boxShadow = "0 0 10px #f857a6";
        console.error(err);
    }
}

// Initialize once DOM is ready
window.addEventListener("DOMContentLoaded", initApp);
