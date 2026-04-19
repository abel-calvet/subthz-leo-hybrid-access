# Sub-THz Terrestrial and LEO Satellite Communications Hybrid-Access Controller

## How to Cite

If you use this repository to build on this work, please cite:

> A. Calvet and S. Nie, "Adaptive Traffic Switching and Splitting Between Sub-THz Microcells and LEO Satellite Links Under Network Dynamics," *Proceedings of the 7th International Conference on Communications, Signal Processing, and their Applications (ICCSPA 2026)*, June, 2026, Alcalá de Henares, Spain, pp. 1--6

> **DOI**: To Be Added After Official Publication

### BibTeX

```bibtex
@inproceedings{calvet2026adaptive,
  author    = {Abel Calvet and Shuai Nie},
  title     = {Adaptive Traffic Switching and Splitting Between Sub-THz Microcells and LEO Satellite Links Under Network Dynamics},
  booktitle = {Proceedings of the 7th International Conference on Communications, Signal Processing, and their Applications (ICCSPA 2026)},
  address   = {Alcalá de Henares, Spain},
  month     = jun,
  year      = {2026},
  pages     = {1--6},
  note      = {DOI to be added after official publication}
}
```

## The Project

We simulate a hybrid terrestrial-satellite uplink where a forwarding node (e.g., a base station) can steer traffic over:

1. A high-capacity but fragile **terrestrial** link, modeled as a 140-GHz (sub-terahertz) uplink SNR trace
2. A lower-rate and higher-delay but more robust and reliable LEO **satellite** link, modeled using real Starlink TLE geometry data, ITU atmospheric attenuation models, and a measurement-based Starlink performance trace

This project attempts to answer the question:

Based on current queue state, arrival rate, predicted link conditions, and physical constraints, when should traffic stay on the terrestrial link, switch to the non-terrestrial link, or be split across both links?

The switching / splitting controller must take into account queueing delay at the output buffer, access-link delay, throughput, satellite outages and availability, switching or splitting stability, and physical switching costs.

The pipeline splits up the problem into 2 layers:

1. **Physical Link**
    * Terrestrial side: terrestrial atmospheric attenuation, terrestrial blockage loss, effective terrestrial SNR, NR MCS BLER lookup table
    * Satellite side: satellite geometry trace, satellite atmospheric attenuation, satellite throughput, delay, outage trace
2. **System Simulation**
    * Packet arrivals and FIFO queue
    * Binary switching or traffic splitting: costly or cost-free decisions, stability-constrained or -unconstrained decisions

## Goals

1. Model terrestrial-link degradation (multipath fading and Doppler + atmospheric attenuation + blockage events)
2. Model satellite-link behavior (Starlink orbital geometry from TLE data + elevation-angle-dependent propagation delay + elevation-angle-dependent atmospheric attenuation + weather-dependent throughput, jitter, and outage behavior)
3. Evaluate switching and splitting rules under different scenarios (weather regimes, satellite elevation scenarios, blockage severity, external trigger overrides, switching vs. splitting mode, switching costs, stability parameters)
4. Produce output metrics useful for comparisons and analysis
    * Backlog (queue) evolution
    * P50, P95, P99 latency
    * Switch count or split-fraction change count
    * Mean satellite traffic fraction (fraction of total served traffic carried on satellite)

## File Structure Overview

### `base_terrestrial_snr_trace.m`

Run this script to generate a **base terrestrial NR wideband SNR trace** from a physical NR uplink waveform simulation. This will save:

* `wideband_snr_dB_per_window`
* `snr_dB_per_resource_block_per_window`

to `data/terrestrial_snr_base.mat`.

Physical-layer configuration:

* Carrier frequency: **140 GHz**
* Subcarrier spacing: **60 kHz**
* Number of resource blocks: **132**
* User speed: **0.1 km/h**
* Delay profile: **TDL-D**
* Rician K-factor: **10**

This gives us a base terrestrial-link quality trace before we apply atmospheric loss and blockage effects on it.

---

### `terrestrial_atmospheric_loss.py`

Run this script to generate **terrestrial atmospheric attenuation traces** using ITU propagation models. This will save:

* `data/atmospheric_loss_clear.mat`
* `data/atmospheric_loss_moderate_rain.mat`
* `data/atmospheric_loss_heavy_rain.mat`

Each file contains:

* `atmospheric_loss_dB_per_window`
* `gaseous_loss_dB_per_window`
* `rain_loss_dB_per_window`
* `rain_rate_mm_per_hr_per_window`

What it models:

* **Gaseous attenuation** using [ITU-R P.676](https://www.itu.int/rec/R-REC-P.676)
* **Rain specific attenuation** using [ITU-R P.838](https://www.itu.int/rec/R-REC-P.838)

Assumptions:

* Terrestrial path length: **200 m**
* Carrier frequency: **140 GHz**
* Rain starts at **t = 30 s**
* Weather regimes:
    * `clear`
    * `moderate_rain`
    * `heavy_rain`

---

### `blockage_loss_trace.m`

Run this script to generate **terrestrial blockage-loss traces**. It saves:

* `data/blockage_loss_no_blockage.mat`
* `data/blockage_loss_mild_blockage.mat`
* `data/blockage_loss_severe_blockage.mat`

Each file contains:

* `blockage_loss_dB_per_window`
* `blockage_at_window`

Current blockage severity levels:

* `no_blockage`: All zero
* `mild_blockage`: Random blockage events and one forced event
* `severe_blockage`: Deeper, longer, and more frequent blockage events than the mild case
* `mixed_blockage`: A mix of mild and severe blockages, along with transient short-lived events

---

### `external_trigger_trace.m`

Run this script to generate an **external-trigger mask**. It saves:

* `data/external_trigger_trace.mat`

containing:

* `external_trigger_at_window`
* `external_triggers`

This mask represents external events (which are hardcoded) that may force a switch to the NTN independently of the physical terrestrial channel's condition. For example, such external events might include weather alerts, administrative or policy triggers, interference events, security-related triggers, etc.

---

### `terrestrial_snr_trace.m`

Run this script to generate the **effective terrestrial SNR trace**. This script combines the base terrestrial NR SNR, atmospheric attenuation, and blockage loss, and saves:

* `data/terrestrial_snr_<weather_regime>_<blockage_severity>.mat`

containing:

* `terrestrial_snr_dB_per_window`

The effective terrestrial SNR is computed as:

```
terrestrial_snr_dB = base_snr_dB - blockage_loss_dB - atmospheric_loss_dB
```

This is the terrestrial-link input trace used by the simulation.

---

### `terrestrial_bler_table.m`

Run this script to generate a **cached NR PUSCH MCS SNR-to-BLER lookup table**. This will save:

* `data/bler_table.mat`

with fields:

* `bler_table.snrs_dB`
* `bler_table.mcs_indices`
* `bler_table.modulations`
* `bler_table.target_code_rates`
* `bler_table.transport_block_sizes_bits_per_slot`
* `bler_table.bler`
* `bler_table.slot_duration_seconds`
* `bler_table.subcarrier_spacing_hz`
* `bler_table.num_resource_blocks`
* `bler_table.num_layers`
* `bler_table.snr_step_dB`
* `bler_table.channel`

Here's a brief description of how this table is generated:

For each MCS index and SNR value, we generate a UL-SCH transport block, we encode and map it to PUSCH resource elements, we OFDM-modulate the waveform, we pass it through the same NR TDL channel model, we add AWGN in the resource-grid domain, we estimate the channel, equalize, decode, and count block errors, and finally we compute the block error rate (BLER) as the fraction of failed transport blocks.

This BLER table is then used in the simulation to map measured terrestrial SNR to a predicted BLER, a selected MCS index, and terrestrial goodput.

---

### `satellite_geometry_trace.m`

Run this script to generate **geometry-based satellite traces** from real Starlink TLE data. It saves:

* `data/satellite_geometry_high.mat`
* `data/satellite_geometry_mid.mat`
* `data/satellite_geometry_low.mat`

Each file contains:

* `satellite_access_at_window`
* `overhead_at_window`
* `base_station_in_fov_at_window`
* `best_satellite_elevation_degrees_per_window`
* `best_satellite_slant_range_meters_per_window`
* `satellite_propagation_delay_ms_per_window`
* `best_satellite_off_nadir_angles_degrees_per_window`
* Ground-station metadata

Here's a brief description of how this is done:

* We download current Starlink TLE data from [CelesTrak](https://celestrak.org/NORAD/elements/gp.php?FORMAT=tle&GROUP=starlink), scan the next 12 hours of geometry at a coarse time resolution, selects three representative elevation scenarios:
    * `high`: near overhead
    * `mid`: accessible, mid elevation
    * `low`: low-elevation, near accessibility threshold

We generate a fine 60-second trace around each selected time, compute slant range and convert it to propagation delay, and compute an off-nadir angle and field-of-view mask

The ground-station location is Avery Hall in Lincoln, Nebraska.

Access assumptions:
* Accessibile threshold: **25 degrees** minimum elevation angle
* "Overhead" threshold: **80 degrees** minimum elevation angle
* Field-of-view threshold: **56.5 degrees** maximum off-nadir angle

Elevation and off-nadir constraints are motivated by Starlink public filings. See [SpaceX FCC filing SAT-MOD-20200417-00037](https://fcc.report/IBFS/SAT-MOD-20200417-00037/2274316.pdf).

---

### `satellite_atmospheric_loss.py`

Run this script to generate **satellite atmospheric attenuation traces** for every combination of elevation scenario (high, mid, low) and weather regime (clear, moderate rain, heavy rain). It saves:

* `data/satellite_atmospheric_loss_<elevation_scenario>_<weather_regime>.mat`

Each file contains:

* `satellite_atmospheric_loss_dB_per_window`
* `satellite_gaseous_loss_dB_per_window`
* `satellite_rain_loss_dB_per_window`
* `rain_rate_mm_per_hr_per_window`
* `slant_path_length_in_rain_km_per_window`

What it models:

* **Slant-path gaseous attenuation** using [ITU-R P.676](https://www.itu.int/rec/R-REC-P.676)
* **Rain specific attenuation** using [ITU-R P.838](https://www.itu.int/rec/R-REC-P.838)
* **Earth-space slant path through the rain layer** using [ITU-R P.618](https://www.itu.int/rec/R-REC-P.618)
* **Rain height** using [ITU-R P.839](https://www.itu.int/rec/R-REC-P.839)

The main difference from the terrestrial atmospheric attenuation script is that the rain path length depends on the elevation angle.

---

### `satellite_performance_trace.m`

Run this script to generate **satellite performance traces** for all 3 × 3 combinations of elevation scenario (high, mid, low) and weather regime (clear, moderate rain, heavy rain). It saves the files:

* `data/satellite_performance_<elevation_scenario>_<weather_regime>.mat`

Each file contains:

* `satellite_rate_up_bps_per_window`
* `satellite_rate_down_bps_per_window`
* `satellite_one_way_delay_ms_per_window`
* `satellite_outage_at_window`

What it models:

* **Geometry-dependent propagation delay**: imported from `satellite_geometry_<elevation_scenario>.mat`
* **Atmospheric-loss-driven modifiers**: throughput multiplier and outage-probability multiplier
* **Measurement-based Starlink behavior**: baseline bent-pipe one-way delay, Gaussian jitter, uplink and downlink goodput distributions, random outages, periodic 15-second reconfiguration artifacts.

The measurement-inspired behavior is based on:
* [Mohan et al., “A Multifaceted Look at Starlink Performance,” WWW 2024](https://spearlab.nl/papers/2024/starlinkWWW2024.pdf)

That paper reports globally synchronized 15-second reconfiguration intervals, around 40-ms bent-pipe round-trip time in dense Starlink shells, uplink vs. downlink performance, qualitative geography-dependent differences in service performance.

---

### `simulation.m`

Run this script, with a chosen configuration, to run the hybrid terrestrial-satellite traffic switching/splitting simulation.

This script loads:

* effective terrestrial SNR
* NR BLER table
* external-trigger mask
* satellite performance trace
* satellite geometry trace

And it simulates packet arrivals, a FIFO queue, terrestrial and satellite service capacities, binary switching or traffic splitting, physical switching costs, and stability-constrained decision logic.

The script takes a config argument to set its simulation parameters:

* **Scenario:**
    * `weather_regime`
    * `blockage_severity`
    * `elevation_scenario`
    * `use_external_trigger`

* **Steering policies:**
    * `steering_policy`
        * `switch`
        * `terrestrial`
        * `satellite`
    * `coordination_mode`
        * `binary_switching`
        * `traffic_splitting`

* **Switching cost and stability:**
    * `enable_handover_overhead`
    * `enable_stability_constraints`

* **Traffic parameters:**
    * `traffic_profile`
    * `packet_size_bits`
    * `average_packets_per_second`
    * `bulk_multiplier`
    * `bulk_start_seconds`
    * `bulk_end_seconds`

After running simulation, we output some figures and save:

* `data/results/results_<run_tag>.mat`

---

### `sweeper.m`

This script is provided to automate running `simulation.m` over a Cartesian product of configuration parameters, which can be set at the top of the script.

---

### `analyzer.m`

This script is provided to automate the analysis and evaluation of the model's performance. Run it to generate a comparison and failure table, heatmaps, and plots from the simulation results.

## Example Results

### Adpative steering vs. single-path baseline

#### Sweep settings

Scenario:
* Weather regime: `clear`
* Blockage severity: `mixed_blockage`
* Elevation scenario: `high`
* External trigger: `false`

Traffic:
* Profile: `bulk_upload`
* Average arrival rate: 100 Mbps
* Bulk-upload arrival-rate multiplier: 1.8x
* Bulk-upload interval: 20 s to 35 s

Policies tested:
* `steering_policy`: `steer`, `terrestrial`, `satellite`
* `coordination_mode`: `binary_switching`, `traffic_splitting`

Controller:
* Cost-free
* Stability constrained

#### Baseline single-path results

Always-terrestrial:
* Mean delay: **536 ms**
* P95 delay: **2,955 ms**
* Maximum queue size: **486 Mbits**

Always-satellite:
* Mean delay: **27,412 ms**
* P95 delay: **52,123 ms**
* Maximum queue size: **6,653 Mbits**

#### Adaptive policy results

Binary switching:
* Mean delay: **508 ms**
* P95 delay: **2725 ms**
* Maximum queue size: **456 Mbits**

Traffic splitting:
* Mean delay: **490 ms**
* P95 delay: **2645 ms**
* Maximum queue size: **446 Mbits**

#### Interpretation

The controller logic performs well compared against the single-path baseline. Both binary switching and traffic splitting reduce queue growth and tail latency relative to always-terrestrial. Always-satellite remains a lot worse, as we expect, because of the satellite link's much larger one-way delay and lower service capacity for this workload.

## References

* ITU-R propagation recommendations used in the atmospheric-loss scripts:
    * [ITU-R P.676: Attenuation by atmospheric gases and related effects](https://www.itu.int/rec/R-REC-P.676)
    * [ITU-R P.838: Specific attenuation model for rain for use in prediction methods](https://www.itu.int/rec/R-REC-P.838)
    * [ITU-R P.618: Propagation data and prediction methods required for the design of Earth-space telecommunication systems](https://www.itu.int/rec/R-REC-P.618)
    * [ITU-R P.839: Rain height model for prediction methods](https://www.itu.int/rec/R-REC-P.839)

* Satellite orbit and geometry data source:
    * [CelesTrak TLE feed for Starlink](https://celestrak.org/NORAD/elements/gp.php?FORMAT=tle&GROUP=starlink)

* Public Starlink reference (off-nadir and elevation angle):
    * [SpaceX FCC filing SAT-MOD-20200417-00037](https://fcc.report/IBFS/SAT-MOD-20200417-00037/2274316.pdf)

* Measurement-based Starlink behavior:
    * [Nitinder Mohan et al., “A Multifaceted Look at Starlink Performance,” WWW 2024](https://spearlab.nl/papers/2024/starlinkWWW2024.pdf)

* ATSSS traffic steering background:
    * [ETSI TS 124 193 / 3GPP TS 24.193: Access Traffic Steering, Switching and Splitting (ATSSS)](https://www.etsi.org/deliver/etsi_ts/124100_124199/124193/19.05.00_60/ts_124193v190500p.pdf)
