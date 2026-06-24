# Tenlog-vaoc

## What is VAOC?

VAOC is a **visual XY offset calibration system** for IDEX (Independent Dual EXtruder) 3D printers running Klipper firmware. It allows you to precisely measure the XY offset between your two toolheads using a camera mounted on the print bed and a clean web-based interface.

The concept is inspired by the [Rat Rig VAOC system](https://rat-rig.com), adapted and simplified for use with any IDEX printer running stock Klipper — no RatOS required.

**How it works:**
1. A camera is mounted on the print bed facing upward
2. T0 (the reference toolhead) is positioned over the camera and centered by the user
3. T1 is moved to the same theoretical position
4. The user centers T1 over the camera
5. VAOC calculates the XY delta between both positions — that delta **is** the offset
6. The calculated values are displayed clearly so you can apply them to your printer configuration

> No computer vision, no automatic detection. The camera is a viewing aid — precision comes from the user's eyes and the 0.01mm jog steps.

---

## Features

- 🎯 **Sub-millimeter precision** — jog steps down to 0.01mm
- 🔄 **SWITCH mode** — toggle between T0 and T1 to visually verify alignment
- 🌐 **Web interface** — works from any browser on the local network, including mobile
- 🔁 **Iterative calibration** — repeat the T0→T1 cycle as many times as needed
- ⚙️ **Universal** — works with any IDEX Klipper setup, regardless of how offsets are applied

---

## Requirements

- IDEX printer running **Klipper** firmware
- **Moonraker** + **Mainsail** web interface
- A camera with MJPEG stream support (USB or IP)

---

## Installation

Connect to your printer via SSH and run:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/RagDollino/Tenlog-vaoc/main/install.sh)
```

The installer will:
1. Auto-detect your Mainsail directory and nginx config
2. Show a summary and ask for confirmation before making any changes
3. Back up all files it modifies
4. Install `vaoc.cfg`, the web interface, the nginx location, and the Mainsail sidebar entry
5. Add `[include vaoc.cfg]` to your `printer.cfg`

### Manual installation

1. Copy `vaoc.cfg` to `~/printer_data/config/`
2. Add `[include vaoc.cfg]` to your `printer.cfg`
3. Create `~/mainsail/vaoc/` and copy `vaoc/index.html` into it
4. Add the nginx location block (see [nginx configuration](#nginx-configuration))
5. Add the Mainsail sidebar entry (see [Mainsail sidebar](#mainsail-sidebar))
6. Do a **Firmware Restart** in Mainsail

---

## Configuration

After installation, open `vaoc.cfg` and adjust these variables:

```ini
[gcode_macro VAOC_VARS]
variable_camera_x: 150.0    # X position of the camera on the bed
variable_camera_y: 30.0     # Y position of the camera on the bed
variable_t0_park_x: -53.0   # T0 park position (left extreme, off the bed)
variable_t1_park_x: 353.0   # T1 park position (right extreme, off the bed)
variable_safe_z: 50.0        # Z height used when switching carriages
variable_jog_speed: 10.0     # Default jog speed in mm/s
```

> **Tip:** Place the camera near the front-center of the bed, at a position reachable by both toolheads.

---

## Camera Setup

### USB Camera (recommended)

Any UVC-compatible USB camera works. For best results:
- Adjustable focus lens (to focus at ~5-10mm nozzle distance)
- Built-in LEDs for illumination
- 1080p resolution

Add to `crowsnest.conf`:

```ini
[cam 1]
mode: ustreamer
port: 8080
device: /dev/video0
resolution: 1920x1080
max_fps: 30
custom_flags: --format=MJPEG
```

> The `--format=MJPEG` flag is critical for 30fps on lower-power SBCs (CB1, Pi Zero, etc.). Without it, the CPU encodes in software and you get 3-4fps.

---

## Usage

### Opening the interface

After installation, **VAOC** appears in the Mainsail sidebar. You can also open it directly:

```
http://YOUR_PRINTER_IP/vaoc/
```

On first use, enter your printer's IP in the **Settings** panel at the bottom of the sidebar.

---

### Calibration workflow

```
1. Press START
   → Homes the printer (if needed)
   → Moves T0 to the camera position

2. Center T0
   → Jog with buttons or keyboard arrow keys
   → Recommended: start at 0.5mm steps, finish at 0.01mm
   → Center the nozzle exactly over the crosshair

3. Press SET T0
   → Saves current position as reference point
   → Activates T1 and moves it to the same position

4. Center T1
   → Jog T1 until its nozzle is over the crosshair

5. Press SET T1
   → Calculates the XY delta (the offset)
   → Displays X and Y values with copy buttons

6. Verify (optional but recommended)
   → Press SWITCH to go back to T0
   → Check T0 is still centered
   → Press SWITCH again to go to T1
   → Repeat SET T0 → SET T1 for more accuracy

7. Press ACCEPT
   → Reports the final values in the Mainsail console
   → Values remain visible in the interface for copying

8. Apply the values to your printer configuration
   → See "Applying the offset" below
```

> **CANCEL** aborts at any point. No changes are made to your configuration.

---

### Applying the offset

VAOC calculates and displays the offset — how you apply it depends on your printer setup.

**If your T1 macro uses `SET_GCODE_OFFSET` directly:**
```gcode
SET_GCODE_OFFSET X=<value shown by VAOC> Y=<value shown by VAOC>
```

**If your toolchange macro reads from a variable:**
Update the variable with the values VAOC reports. Refer to your specific macro documentation.

---

### Button reference

| Button | When available | Action |
|--------|---------------|--------|
| **START** | Always | Home + move T0 to camera position |
| **SET T0** | T0 active | Save T0 position as reference, activate T1 |
| **SET T1** | T1 active + control point set | Calculate XY offset |
| **SWITCH** | After SET T0 | Toggle between T0 and T1 at centered positions |
| **ACCEPT** | After SET T1 | Report offset values and end session |
| **CANCEL** | During calibration | Abort — no changes made |

### Jog increments

| Step | Use for |
|------|---------|
| **1.0 mm** | Initial rough positioning |
| **0.5 mm** | Getting close |
| **0.1 mm** | Fine approach |
| **0.05 mm** | Precision alignment |
| **0.01 mm** | Final sub-mm adjustment |

**Keyboard:** Arrow keys control X/Y jog when the browser is focused.

---

### Klipper console commands

```
VAOC_START                       # Start session
VAOC_MOVE X=0.1                  # Jog X+0.1mm
VAOC_MOVE Y=-0.05                # Jog Y-0.05mm
VAOC_MOVE Z=1.0                  # Jog Z (focus only, not saved)
VAOC_SET_T0                      # Save T0 reference point
VAOC_SET_T1                      # Calculate offset
VAOC_SWITCH                      # Toggle T0/T1 for verification
VAOC_ACCEPT                      # Report values and end session
VAOC_CANCEL                      # Cancel without changes
```

---

## Troubleshooting

**"Move out of range" during VAOC_START**
Check `variable_t0_park_x`, `variable_t1_park_x`, and `variable_safe_z` in `vaoc.cfg`.

**Camera stream not visible**
Open the stream URL directly in a browser tab to confirm it works. If it works in a tab but not in VAOC, try using the printer IP directly (not a hostname).

**Low FPS on USB camera**
Add `custom_flags: --format=MJPEG` to your camera section in `crowsnest.conf`.

**SWITCH puts T1 at the wrong position**
Press **SET T1** at least once before using SWITCH. If SWITCH is used before SET T1, T1 falls back to the T0 control point.

---

## Manual nginx and sidebar configuration

### nginx configuration

Add inside the `server { }` block of your nginx config:

```nginx
location /vaoc/ {
    alias /home/YOUR_USER/mainsail/vaoc/;
    index index.html;
    try_files $uri $uri/ /vaoc/index.html;
}
```

Reload nginx:
```bash
sudo nginx -t && sudo systemctl reload nginx
```

### Mainsail sidebar

Create or edit `~/printer_data/config/.theme/navi.json`:

```json
[
  {
    "title": "VAOC",
    "href": "/vaoc/",
    "target": "_self",
    "icon": "M9,3L7.17,5H4A2,2 0 0,0 2,7V19A2,2 0 0,0 4,21H20A2,2 0 0,0 22,19V7A2,2 0 0,0 20,5H16.83L15,3H9M12,8A5,5 0 0,1 17,13A5,5 0 0,1 12,18A5,5 0 0,1 7,13A5,5 0 0,1 12,8M12,10A3,3 0 0,0 9,13A3,3 0 0,0 12,16A3,3 0 0,0 15,13A3,3 0 0,0 12,10Z",
    "position": 85
  }
]
```

Reload Mainsail (F5).

---

## Project structure

```
Tenlog-vaoc/
├── install.sh       # Automatic installer
├── vaoc.cfg         # Klipper macros
├── vaoc/
│   └── index.html   # Web interface
└── README.md
```

---

## Contributing

Issues and pull requests are welcome. This project is designed to be printer-agnostic — if you adapt it for a specific IDEX printer, feel free to open a PR.

---

## License

[GNU General Public License v3.0](LICENSE)

---

## Acknowledgements

- Inspired by the [Rat Rig VAOC system](https://rat-rig.com)
- Built for my **Tenlog TL-D3 Pro** 
- Thanks to the Klipper, Moonraker, and Mainsail communities
  
