;===== PRINT_PHASE_INIT =====
SET_PRINT_STATS_INFO TOTAL_LAYER=[total_layer_count]
SET_PRINT_MAIN_STATUS MAIN_STATUS=print_start
M220 S100
M221 S100
SET_INPUT_SHAPER SHAPER_TYPE_X=mzv
SET_INPUT_SHAPER SHAPER_TYPE_Y=mzv
DISABLE_ALL_SENSOR
M1002 R1
M107
CLEAR_PAUSE
M140 S[bed_temperature_initial_layer_single]
M141 S[chamber_temperatures]
G29.0
G28

;===== BOX_PREPAR =====
BOX_PRINT_START EXTRUDER=[initial_no_support_extruder] HOTENDTEMP={nozzle_temperature_range_high[initial_tool]}
M400
EXTRUSION_AND_FLUSH HOTEND=[nozzle_temperature_initial_layer]

;===== CLEAR_NOZZLE =====
G1 Z20 F480
MOVE_TO_TRASH
G1 Y403.5 F2000
{if chamber_temperatures[0] == 0}
M106 P3 S[during_print_exhaust_fan_speed]
{else}
M106 P3 S0
{endif}
M1004
M106 S0
M109 S[nozzle_temperature_initial_layer]
G92 E0
M83
G1 E5 F80
G1 E250 F300
M400
M106 S255
G1 E-3 F1000
M104 S140
M109.1 S{nozzle_temperature_initial_layer[0]-30}
M204 S10000
G1 Y403 F2000
G1 X163 F8000
G1 X145 F5000
G1 X163 F8000
G1 X145 F5000
G1 X175 F6000
G1 X163
G1 X175
G1 X163
G1 X175
G1 X163
G1 X180 F10000
G1 Y395 F6000
G1 X188
G1 Z-0.2 F480
M106 S255
M109.1 S150
G91
G1 X15 F200
G1 Y2
G1 X-15
G1 Y-2
G1 X15
G90
G2 I0.5 J0.5 F480
G2 I0.5 J0.5
G2 I0.5 J0.5
G1 Z10
G1 Y383 F12000
G1 X116
G1 Y403
G1 X163 F8000
G1 X145 F5000
G1 X163 F8000
G1 X145 F5000
G1 X175 F6000
G1 X163
G1 X175
G1 X163
G1 X175
G1 X163
G1 X180 F10000
G1 X195 Y195
M106 S0
M190 S[bed_temperature_initial_layer_single]
M191 S[chamber_temperatures]
G1 Y0 F15000
G1 X15
G1 X3 F5000
G4 P1000
G1 X4 F1000
G1 X3 F5000
G4 P1000
G1 E-4 F1800
G1 X15 F3000
G1 X20 Y20 F15000
Z_TILT_ADJUST
G29
M1002 A1
G1 X195 Y195 Z10 F20000
G92_ Z{10 - ((nozzle_temperature_initial_layer[initial_tool] - 130) / 14 - 5.0) / 100}
G0 Y1
M109 S[nozzle_temperature_initial_layer]
ENABLE_ALL_SENSOR

;===== PRINT_START =====
; LAYER_HEIGHT: 0.2
T[initial_tool]
M140 S[bed_temperature_initial_layer_single]
M104 S[nozzle_temperature_initial_layer]
M141 S[chamber_temperatures]
G4 P3000
probe samples=1
G91
G0 Z0.6 F480
G90
G1 X175 Y1 F20000
G1 E5 F{filament_max_volumetric_speed[initial_no_support_extruder]/2/2.4053*60}
G1 X215 E20 F{filament_max_volumetric_speed[initial_no_support_extruder]/2/2.4053*60}
G1 Z1 F480
SET_PRINT_MAIN_STATUS MAIN_STATUS=printing
