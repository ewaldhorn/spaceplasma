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
        const width = 400;
        const height = 300;

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
        // Stable Multi-Touch & Mouse Tracker
        // Tracks up to 4 parallel inputs and assigns stable slots (0..3)
        // ---------------------------------------------------------------------
        const maxSlots = 4;
        const interactionSlots = new Array(maxSlots).fill(null).map(() => ({
            id: null, // unique id (e.g., 'mouse' or touch.identifier)
            active: false
        }));

        function updateStateInWasm(slotIndex, x, y, pressed, active) {
            instance.exports.set_touch_state(slotIndex, x, y, pressed, active);
        }

        function processInteraction(e) {
            e.preventDefault();
            const rect = canvas.getBoundingClientRect();
            
            // 1. Construct array of target pointer states for THIS event
            let inputs = [];
            
            if (e.touches) {
                // Collect active touches up to 4
                for (let i = 0; i < Math.min(e.touches.length, maxSlots); i++) {
                    const touch = e.touches[i];
                    inputs.push({
                        id: touch.identifier,
                        clientX: touch.clientX,
                        clientY: touch.clientY,
                        pressed: true
                    });
                }
            } else if (e.type !== "mouseleave") {
                // Normalise mouse as a single interaction
                inputs.push({
                    id: "mouse",
                    clientX: e.clientX,
                    clientY: e.clientY,
                    pressed: e.buttons > 0
                });
            }

            // 2. Reconcile input array against existing slots
            
            // Mark all current slots for deactivation/garbage collection if they left
            const foundIds = new Set(inputs.map(inp => inp.id));
            
            for (let i = 0; i < maxSlots; i++) {
                const slot = interactionSlots[i];
                if (slot.active && !foundIds.has(slot.id)) {
                    // This slot is no longer present. Park and disable it.
                    slot.active = false;
                    slot.id = null;
                    updateStateInWasm(i, -2000, -2000, false, false);
                }
            }
            
            // Assign active inputs to slots
            for (const input of inputs) {
                // A. Try to find an existing slot with this ID
                let assignedSlotIndex = interactionSlots.findIndex(s => s.active && s.id === input.id);
                
                // B. If not found, claim the first empty/inactive slot
                if (assignedSlotIndex === -1) {
                    assignedSlotIndex = interactionSlots.findIndex(s => !s.active);
                }
                
                // If all slots are full, we ignore this input
                if (assignedSlotIndex !== -1) {
                    const slot = interactionSlots[assignedSlotIndex];
                    slot.active = true;
                    slot.id = input.id;
                    
                    const mx = ((input.clientX - rect.left) / rect.width) * width;
                    const my = ((input.clientY - rect.top) / rect.height) * height;
                    
                    updateStateInWasm(assignedSlotIndex, mx, my, input.pressed, true);
                }
            }
        }

        function handleLeaveAll(e) {
            e.preventDefault();
            for (let i = 0; i < maxSlots; i++) {
                interactionSlots[i].active = false;
                interactionSlots[i].id = null;
                updateStateInWasm(i, -2000, -2000, false, false);
            }
        }

        // Mouse Listeners
        canvas.addEventListener("mousemove", processInteraction);
        canvas.addEventListener("mousedown", processInteraction);
        canvas.addEventListener("mouseup", processInteraction);
        canvas.addEventListener("mouseleave", processInteraction);

        // Touch Listeners (Mobile/Tablet support)
        canvas.addEventListener("touchstart", processInteraction, { passive: false });
        canvas.addEventListener("touchmove", processInteraction, { passive: false });
        canvas.addEventListener("touchend", processInteraction, { passive: false });
        canvas.addEventListener("touchcancel", handleLeaveAll, { passive: false });

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
