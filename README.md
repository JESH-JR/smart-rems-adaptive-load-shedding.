# RET Project v2 - Smart Renewable Energy Management System with Adaptive Load Shedding
**Group 14** | 23EEE335 Renewable Energy Technologies | Amrita School of Engineering, Coimbatore | **MATLAB R2025a**

12 flats | PV 38.4 kW (2 x 19.2 kW) | Battery 240 V / 130 kWh | Supercapacitor 10 F / 250 V | 400 V DC bus | 5-level CHB inverter

## Folder layout
| Folder | What is inside |
|---|---|
| `00_ARCHIVE_submitted/` | Exactly what was submitted on 27 Oct (PDF, LaTeX, model, synthetic weather). **Never edit.** |
| `01_model/` | **The three working models:** `microgrid_top_fixed.slx` (integrated, R-equivalent loads), `PV_Unit_day.slx` (Test 1), `CHB_inverter_v2.slx` (Test 2) |
| `01_model/_rebuild_source/` | Original `microgrid_top.slx`, only needed to rebuild the integrated model from scratch |
| `01_model/_archive/` | Backups (pre-tidy, R2025b copy, RLC option, old R2026a inverter) and PV development models |
| `02_scripts/` | Main scripts: `init_microgrid.m`, `run_test1_pv.m`, `plot_test4.m`, `build_chb_inverter.m`, `build_pv_profile_from_nasa.py` |
| `02_scripts/model_fixes/` | The fix scripts in the order they were applied (see rebuild below) |
| `02_scripts/rlc_option/` | Optional AC-side RLC load banks (not used in the final model) |
| `02_scripts/pv/` | PV helper / plotting scripts |
| `03_data/` | Weather input `pv_daily_profile.csv/.mat` (NASA POWER) + raw NASA files |
| `04_results/` | One folder per test (final results + old submitted results); **`figures_final/` = clean white-background figures for PPT + report** (from `make_figures.m`); `_checks` and `_rlc_option` are side runs |
| `05_report/` | `report_v2.tex`, figures, presentations |
| `06_admin/` | SDG/PO/PSO mapping sheet |
| `07_uploads/` | Folders already prepared for the OneDrive upload |
| `_to_delete/` | MATLAB cache files moved out of the way - safe to delete |

## How to run (MATLAB R2025a)
```matlab
cd C:\RET\RET_Project_v2
setup_paths                                   % paths + parameters
run_test1_pv('clear'); run_test1_pv('cloudy') % Test 1: PV unit
build_chb_inverter                            % Test 2: builds + tests the CHB inverter
clear; out = sim('microgrid_top_fixed'); plot_test4(out,'clear_24h')                    % Test 4 clear day
clear; DAY = 'cloudy'; out = sim('microgrid_top_fixed'); plot_test4(out,'cloudy_24h')   % Test 4 cloudy day
```
Weather: NASA POWER hourly, Coimbatore 11.02 N 76.96 E - clear 9 May 2025, partly cloudy 16 May 2025.
Time compression: 1 real hour = 0.12 s (integrated model), 0.05 s (PV unit model).

## Final results
| Test | Result |
|---|---|
| 1 PV unit (clear / cloudy) | peak 16.0 / 13.1 kW; 119.4 / 77.7 kWh per unit; 238.9 / 155.3 kWh for 2 units |
| 2 CHB inverter (new) | 225.8 V rms, 4.32 kW; peak 325.7 V (was 505 V); THD_v 0.13 % (to 50th), 1.57 % (to 10 kHz) |
| 4 Integrated, clear day | bus 392.6-413.9 V; shedding L=1 03:40-09:20; SoC min ~34 %, 98 % at 12:30, curtailment with 95-98 % hysteresis; no L2/L3 |
| 4 Integrated, cloudy day | bus 395.7-406.9 V; L=1 03:40-10:15; SoC max ~98 % at 15:00; ends 38.3 %; no L2/L3 |

## Rebuilding the integrated model from scratch (only if needed)
`02_scripts/model_fixes/` in this order: `fix_microgrid_model_v2` (runs v1 internally) -> `v2b` -> `v2c` -> `v2d` -> `v2e` -> `v2f` -> `v2g` -> `v2h`
-> `tidy_microgrid_model` -> `fix_pv_curtailment_hysteresis`. Every change is explained in `CHANGELOG.md`.
