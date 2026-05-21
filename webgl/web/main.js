/**
 * Cybernetic Plasma Visualizer
 * WebGL Render Engine & WASM Simulation Bridge
 */

function log(msg, type = "info") {
  const prefix = type === "error" ? "[ERR]" : ">";
  console.log(`${prefix} ${msg}`); // Always mirror to the developer console!
  
  const consoleOutput = document.getElementById("console-output");
  if (consoleOutput) {
    const line = document.createElement("p");
    line.className = `log-line ${type === "error" ? "text-pink" : ""}`;
    line.innerText = `${prefix} ${msg}`;
    consoleOutput.appendChild(line);
    consoleOutput.scrollTop = consoleOutput.scrollHeight;
  }
}

// Vertex shader program: simple full-screen quad mapping
const vsSource = `
  attribute vec2 a_position;
  void main() {
    gl_Position = vec4(a_position, 0.0, 1.0);
  }
`;

// Fragment shader program: optimized high-fidelity plasma equations & compound Gaussian ripples
const fsSource = `
  #ifdef GL_ES
  precision mediump float;
  #endif

  uniform float u_time;
  uniform vec2 u_resolution;
  uniform vec3 u_touches[10];
  uniform float u_has_ripples;

  void main() {
    float x = gl_FragCoord.x;
    float y = u_resolution.y - gl_FragCoord.y; // Map WebGL bottom-up coords to top-down space

    float scale_factor = 1.0;
    float cx = x * scale_factor;
    float cy = y * scale_factor;

    // 1. Base Plasma Equations (using fast, hardware-optimized multiplications)
    float v1 = sin(cx * 0.02222222 + u_time * 1.2);
    float v2 = sin((cy * 0.02857143 + u_time * 0.9) * 1.3);
    float v3 = sin((cx + cy) * 0.02 + u_time * 1.5);
    float v4 = sin((cx + (u_resolution.y - cy)) * 0.01428571 - u_time * 1.1);

    float composite = v1 + v2 + v3 + v4;

    // 2. Interactive Gaussian Concentric Ripples (completely branchless to prevent GPU warp divergence)
    float ripple_pixel = 0.0;

    if (u_has_ripples > 0.5) {
      for (int i = 0; i < 10; i++) {
        float strength = u_touches[i].z;
        float tx = u_touches[i].x;
        float ty = u_touches[i].y;
        
        float dx = cx - tx;
        float dy = cy - ty;
        float dist_sq = dx * dx + dy * dy;

        float angle = dist_sq * 0.0008333333 - u_time * 9.0;
        float concentric_wave = sin(angle);
        float weight = 1.0 / (1.0 + dist_sq * 0.00003086419); // Fast rational decay approximation

        ripple_pixel += concentric_wave * weight * strength;
      }
    }

    composite += ripple_pixel * 4.0; // 4.0 multiplier for vibrant wave impact

    // 3. Dynamic High-Fidelity Color Palette Mapping (using hardware-accelerated float ratios)
    float ratio = clamp((composite + 4.0) * 0.125, 0.0, 1.0);
    float angle = ratio * 6.283185307179586; // 2.0 * pi

    float r = 0.50196078 + 0.49803921 * sin(angle + u_time * 1.5);
    float g = 0.50196078 + 0.49803921 * sin(angle + 2.0 - u_time);
    float b = 0.50196078 + 0.49803921 * sin(angle + 4.0 + u_time * 0.5);

    gl_FragColor = vec4(r, g, b, 1.0);
  }
`;

function createShader(gl, type, source) {
  const shader = gl.createShader(type);
  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
    const info = gl.getShaderInfoLog(shader);
    gl.deleteShader(shader);
    throw new Error(`Shader compilation failed: ${info}`);
  }
  return shader;
}

function initShaderProgram(gl, vsSource, fsSource) {
  const vertexShader = createShader(gl, gl.VERTEX_SHADER, vsSource);
  const fragmentShader = createShader(gl, gl.FRAGMENT_SHADER, fsSource);

  const shaderProgram = gl.createProgram();
  gl.attachShader(shaderProgram, vertexShader);
  gl.attachShader(shaderProgram, fragmentShader);
  gl.linkProgram(shaderProgram);

  if (!gl.getProgramParameter(shaderProgram, gl.LINK_STATUS)) {
    throw new Error(`Shader linking failed: ${gl.getProgramInfoLog(shaderProgram)}`);
  }
  return shaderProgram;
}

async function initApp() {
  const loadingOverlay = document.getElementById("loading-overlay");
  const fpsCounter = document.getElementById("fps-counter");
  const statusText = document.getElementById("status-text");

  log("Fetching plasma.wasm bytes...");

  try {
    const canvas = document.getElementById("plasma-canvas");
    
    // Set the native resolution
    const width = 800;
    const height = 600;

    log("Initializing WebGL graphics hardware pipeline...");
    const gl = canvas.getContext("webgl", {
      alpha: false,
      depth: false,
      antialias: false,
      stencil: false,
      preserveDrawingBuffer: false
    });

    if (!gl) {
      throw new Error("WebGL context creation failed. Your browser/hardware may not support WebGL.");
    }

    // Diagnostic: Query and output active GPU hardware details to developer console
    const debugInfo = gl.getExtension('WEBGL_debug_renderer_info');
    if (debugInfo) {
      const vendor = gl.getParameter(debugInfo.UNMASKED_VENDOR_WEBGL);
      const renderer = gl.getParameter(debugInfo.UNMASKED_RENDERER_WEBGL);
      log(`GPU Hardware Connected: ${renderer} (${vendor})`);
    } else {
      log("GPU Diagnostic Info: Not available");
    }

    log("Compiling visualizer GLSL vertex and fragment shaders...");
    const shaderProgram = initShaderProgram(gl, vsSource, fsSource);
    gl.useProgram(shaderProgram);

    // Setup uniform locations
    const uTimeLoc = gl.getUniformLocation(shaderProgram, "u_time");
    const uResolutionLoc = gl.getUniformLocation(shaderProgram, "u_resolution");
    const uTouchesLoc = gl.getUniformLocation(shaderProgram, "u_touches");
    const uHasRipplesLoc = gl.getUniformLocation(shaderProgram, "u_has_ripples");

    // Setup geometry: simple full-screen quad (two triangles)
    const positionAttributeLocation = gl.getAttribLocation(shaderProgram, "a_position");
    const positionBuffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, positionBuffer);
    const vertices = new Float32Array([
      -1.0, -1.0,
       1.0, -1.0,
      -1.0,  1.0,
      -1.0,  1.0,
       1.0, -1.0,
       1.0,  1.0,
    ]);
    gl.bufferData(gl.ARRAY_BUFFER, vertices, gl.STATIC_DRAW);

    gl.enableVertexAttribArray(positionAttributeLocation);
    gl.vertexAttribPointer(positionAttributeLocation, 2, gl.FLOAT, false, 0, 0);

    // Compile and instantiate the Zig WASM module
    log("Connecting WebAssembly runtime...");
    const response = await fetch("plasma.wasm");
    if (!response.ok) {
      throw new Error(
        `Failed to fetch WebAssembly binary: ${response.statusText}`,
      );
    }

    const bufferBytes = await response.arrayBuffer();
    log("Compiling freestanding binary...");
    const module = await WebAssembly.compile(bufferBytes);

    log("Instantiating memory segment...");
    const instance = await WebAssembly.instantiate(module, {
      env: {},
    });

    log("Wasm binary successfully linked.");

    // Initialize simulation state
    instance.exports.init();
    log("Core physics simulation subsystem ONLINE.");

    // Expose memory views for clock and multi-touch data
    const memory = instance.exports.memory;
    const touchDataPtr = instance.exports.get_touch_data_ptr();

    log(`State telemetry base address resolved: 0x${touchDataPtr.toString(16)}`);

    // Create a direct, shared array view into WASM memory space for the 10 touch points
    const touchDataView = new Float32Array(
      memory.buffer,
      touchDataPtr,
      10 * 3 // 10 touch points * 3 components [x, y, strength]
    );

    // Hide loading overlay
    if (loadingOverlay) {
      loadingOverlay.classList.add("hidden");
    }
    if (statusText) {
      statusText.innerText = "KERNEL: WEBGL ACTIVE";
    }
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

      // 1. Command Zig to process the next mathematical frame simulation.
      instance.exports.update(currentTime);

      // 2. Fetch the rigid internal clock simulation time from Zig.
      const internalTime = instance.exports.get_internal_clock();

      // 3. WebGL Draw Cycle
      gl.viewport(0, 0, width, height);
      gl.clear(gl.COLOR_BUFFER_BIT);

      // Set shader uniforms
      gl.uniform1f(uTimeLoc, internalTime);
      gl.uniform2f(uResolutionLoc, width, height);
      gl.uniform3fv(uTouchesLoc, touchDataView);

      // Fast check if any touch ripples are active to bypass pixel loops
      let hasRipples = 0.0;
      for (let i = 0; i < 10; i++) {
        if (touchDataView[i * 3 + 2] > 0.001) {
          hasRipples = 1.0;
          break;
        }
      }
      gl.uniform1f(uHasRipplesLoc, hasRipples);

      // Draw the full-screen quad
      gl.drawArrays(gl.TRIANGLES, 0, 6);

      // Repeat
      requestAnimationFrame(renderLoop);
    }

    // ---------------------------------------------------------------------
    // Stable Multi-Touch & Mouse Tracker
    // Tracks up to 10 parallel inputs and assigns stable slots (0..9)
    // ---------------------------------------------------------------------
    const maxSlots = 10;
    const interactionSlots = new Array(maxSlots).fill(null).map(() => ({
      id: null, // unique id (e.g., 'mouse' or touch.identifier)
      active: false,
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
        // Collect active touches up to maxSlots
        for (let i = 0; i < Math.min(e.touches.length, maxSlots); i++) {
          const touch = e.touches[i];
          inputs.push({
            id: touch.identifier,
            clientX: touch.clientX,
            clientY: touch.clientY,
            pressed: true,
          });
        }
      } else if (e.type !== "mouseleave") {
        // Normalise mouse as a single interaction
        inputs.push({
          id: "mouse",
          clientX: e.clientX,
          clientY: e.clientY,
          pressed: e.buttons > 0,
        });
      }

      // 2. Reconcile input array against existing slots

      // Mark all current slots for deactivation/garbage collection if they left
      const foundIds = new Set(inputs.map((inp) => inp.id));
      const isTouchEvent = !!e.touches;

      for (let i = 0; i < maxSlots; i++) {
        const slot = interactionSlots[i];
        if (slot.active && !foundIds.has(slot.id)) {
          const isSlotTouch = slot.id !== "mouse";
          // Only deactivate if this event type is responsible for this input family
          if (
            (isTouchEvent && isSlotTouch) ||
            (!isTouchEvent && !isSlotTouch)
          ) {
            slot.active = false;
            slot.id = null;
            updateStateInWasm(i, -2000, -2000, false, false);
          }
        }
      }

      // Assign active inputs to slots
      for (const input of inputs) {
        // A. Try to find an existing slot with this ID
        let assignedSlotIndex = interactionSlots.findIndex(
          (s) => s.active && s.id === input.id,
        );

        // B. If not found, claim the first empty/inactive slot
        if (assignedSlotIndex === -1) {
          assignedSlotIndex = interactionSlots.findIndex((s) => !s.active);
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
    canvas.addEventListener("touchstart", processInteraction, {
      passive: false,
    });
    canvas.addEventListener("touchmove", processInteraction, {
      passive: false,
    });
    canvas.addEventListener("touchend", processInteraction, { passive: false });
    canvas.addEventListener("touchcancel", handleLeaveAll, { passive: false });

    // Kick off loop
    requestAnimationFrame(renderLoop);
  } catch (err) {
    log(`CRITICAL BOOT ERROR: ${err.message}`, "error");
    console.error(err);
    
    const localStatusText = document.getElementById("status-text");
    if (localStatusText) {
      localStatusText.innerText = "KERNEL PANIC";
      localStatusText.style.color = "#f857a6";
    }
    const indicator = document.querySelector(".status-indicator");
    if (indicator) {
      indicator.style.backgroundColor = "#f857a6";
      indicator.style.boxShadow = "0 0 10px #f857a6";
    }
  }
}

// Reliable entrypoint that checks state to prevent race conditions with DOMContentLoaded
if (document.readyState === "loading") {
  window.addEventListener("DOMContentLoaded", initApp);
} else {
  initApp();
}
