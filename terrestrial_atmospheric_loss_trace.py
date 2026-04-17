"""
This script generates atmospheric attenuation traces for the terrestrial link.

Models used:
    * ITU-R P.676: gaseous attenuation on terrestrial paths
    * ITU-R P.838: rain specific attenuation (dB per kilometer) given a rain rate (millimeters of rain per hour)

Outputs:
    * data/atmospheric_loss_clear.mat
    * data/atmospheric_loss_moderate_rain.mat
    * data/atmospheric_loss_heavy_rain.mat

Each file contains a trace representing attenuation/loss (in decibels) over the decision time grid at different rain conditions.
    * atmospheric_loss_dB_per_window (sum of gaseous and rain-related attenuations)
    * gaseous_loss_dB_per_window
    * rain_loss_dB_per_window
    * rain_rate_mm_per_hour_per_window
    * time_seconds_per_window
    * decision_window_seconds
    * Metadata: frequency, distance, coordinates, etc.

Plots:
    * fig/atmospheric_loss_components_<regime>.png
    * fig/atmospheric_loss_regime_comparison.png

Notes:
    * The terrestrial path length is set to 200 meters.
        Attenuation scales linearly with distance
"""

import os

import numpy as np
import matplotlib.pyplot as plt
from scipy.io import savemat

import itur   # ITU-Rpy

#
# Settings
#

CARRIER_FREQUENCY_GHZ = 140.0

TERRESTRIAL_LINK_DISTANCE_METERS = 200.0

BASE_STATION_LATITUDE        = 40.8209
BASE_STATION_LONGITUDE       = -96.7006
BASE_STATION_ALTITUDE_METERS = 360.0

ATMOSPHERIC_PRESSURE_HECTOPASCALS         = 1013.25  # Sea-level atmospheric pressure
ATMOSPHERIC_TEMPERATURE_KELVIN            = 293.15   # Room temperature
WATER_VAPOR_DENSITY_GRAMS_PER_CUBIC_METER = 7.5      # Standard absolute humidity for radio propagation

TERRESTRIAL_ELEVATION_ANGLE_DEGREES = 0.0   # Horizontal path

POLARIZATION_TILT_ANGLE_DEGREES = 45.0    # Tau 

# Weather regimes
RAIN_RATES_MM_PER_HR = {
    "clear":         0.0,
    "moderate_rain": 10.0,
    "heavy_rain":    50.0,
}
RAINFALL_START_SECONDS = 30.0

# Timing grid
TOTAL_DURATION_SECONDS  = 60.0
DECISION_WINDOW_SECONDS = 0.01
NUM_WINDOWS             = round(TOTAL_DURATION_SECONDS / DECISION_WINDOW_SECONDS)
time_seconds_per_window = np.arange(NUM_WINDOWS, dtype = float) * DECISION_WINDOW_SECONDS

#
# Attenuation computations
# 

def generate_atmospheric_loss_trace(regime: str, rain_rate_mm_per_hr: float) -> dict[str, np.ndarray]:
    
    """
    Generates A_atm(t) = A_gas(t) + A_rain(t) for one weather regime.
    Returns a dictionary ready to be saved to a .mat file.
    """
    
    # Convert to Quantity object types used by ITU-Rpy
    path_length             = (TERRESTRIAL_LINK_DISTANCE_METERS / 1000.0) * itur.u.km
    frequency               = CARRIER_FREQUENCY_GHZ * itur.u.GHz
    elevation_angle         = TERRESTRIAL_ELEVATION_ANGLE_DEGREES * itur.u.deg
    water_vapor_density     = WATER_VAPOR_DENSITY_GRAMS_PER_CUBIC_METER * itur.u.g / (itur.u.m ** 3)
    atmospheric_pressure    = ATMOSPHERIC_PRESSURE_HECTOPASCALS * itur.u.hPa
    atmospheric_temperature = ATMOSPHERIC_TEMPERATURE_KELVIN * itur.u.K

    #
    # Gaseous attenuation
    # Slow, treated as constant over the simulation
    #

    # Use ITU-R P.676 
    gaseous_attenuation = itur.models.itu676.gaseous_attenuation_terrestrial_path(
        path_length, frequency, elevation_angle, water_vapor_density,
        atmospheric_pressure, atmospheric_temperature, mode = "exact")
    
    gaseous_attenuation_dB = float(np.array(gaseous_attenuation.value).squeeze())
    
    gaseous_loss_dB_per_window = np.full_like(time_seconds_per_window, fill_value = gaseous_attenuation_dB, dtype=float)

    #
    # Rain attenuation
    # Regime-specific
    # Use ITU-R P.838
    # Specific attenuation: gamma_R (dB per km), R = rainfall rate
    # A_rain  = gamma_R * path_length_km
    #

    # Simulate rain starting at t = 30 seconds (piece-wise constant process)
    rain_rate_mm_per_hr_per_window = np.zeros_like(time_seconds_per_window, dtype=float)
    rain_rate_mm_per_hr_per_window[time_seconds_per_window >= RAINFALL_START_SECONDS] = rain_rate_mm_per_hr

    rain_specific_attenuation_per_window = itur.models.itu838.rain_specific_attenuation(
        rain_rate_mm_per_hr_per_window, frequency, TERRESTRIAL_ELEVATION_ANGLE_DEGREES,
        POLARIZATION_TILT_ANGLE_DEGREES)

    # Extract numeric values (if return type is an np.ndarray of Quantity objects)
    rain_specific_attenuation_dB_per_km_per_window = np.asarray(
        getattr(rain_specific_attenuation_per_window, "value", rain_specific_attenuation_per_window),
        dtype = float)

    rain_loss_dB_per_window = rain_specific_attenuation_dB_per_km_per_window * (TERRESTRIAL_LINK_DISTANCE_METERS / 1000.0)
    
    # Total atmospheric loss
    atmospheric_loss_dB_per_window = gaseous_loss_dB_per_window + rain_loss_dB_per_window

    # Data for MATLAB
    output_data = { 
        "time_seconds_per_window":                   time_seconds_per_window.reshape(-1, 1),
        "decision_window_seconds":                   np.array([[DECISION_WINDOW_SECONDS]], dtype = float),

        "atmospheric_loss_dB_per_window":            atmospheric_loss_dB_per_window.reshape(-1, 1),
        "gaseous_loss_dB_per_window":                gaseous_loss_dB_per_window.reshape(-1, 1),
        "rain_loss_dB_per_window":                   rain_loss_dB_per_window.reshape(-1, 1),
        "rain_rate_mm_per_hr_per_window":            rain_rate_mm_per_hr_per_window.reshape(-1, 1),

        # Metadata
        "regime":                                    np.array([regime], dtype = object),
        "regime_rain_rate_mm_per_hr":                np.array([[rain_rate_mm_per_hr]], dtype = float),
        "carrier_frequency_GHz":                     np.array([[CARRIER_FREQUENCY_GHZ]], dtype = float),
        "terrestrial_link_distance_meters":          np.array([[TERRESTRIAL_LINK_DISTANCE_METERS]], dtype = float),

        "base_station_latitude_degrees":             np.array([[BASE_STATION_LATITUDE]], dtype = float),
        "base_station_longitude_degrees":            np.array([[BASE_STATION_LONGITUDE]], dtype = float),
        "base_station_altitude_meters":              np.array([[BASE_STATION_ALTITUDE_METERS]], dtype = float),

        "atmospheric_pressure_hPa":                  np.array([[ATMOSPHERIC_PRESSURE_HECTOPASCALS]], dtype = float),
        "atmospheric_temperature_kelvin":            np.array([[ATMOSPHERIC_TEMPERATURE_KELVIN]], dtype = float),
        "water_vapor_density_grams_per_cubic_meter": np.array([[WATER_VAPOR_DENSITY_GRAMS_PER_CUBIC_METER]], dtype = float),

        "terrestrial_elevation_angle_degrees":       np.array([[TERRESTRIAL_ELEVATION_ANGLE_DEGREES]], dtype = float),
        "polarization_tilt_angle_degrees":           np.array([[POLARIZATION_TILT_ANGLE_DEGREES]], dtype = float),

        "rain_event_start_seconds":                  np.array([[RAINFALL_START_SECONDS]], dtype = float),
    }

    return output_data

#
# Plotting
#

def plot_regime(
    regime:                         str,
    gaseous_loss_dB_per_window:     np.ndarray,
    rain_loss_dB_per_window:        np.ndarray,
    atmospheric_loss_dB_per_window: np.ndarray,
    rain_rate_mm_per_hr_per_window: np.ndarray,   
) -> None:
    
    figure, axes = plt.subplots(4, 1, figsize=(10, 10), sharex = True)
    
    axes[0].plot(time_seconds_per_window, gaseous_loss_dB_per_window, linewidth = 2)
    axes[0].set_ylabel("Gaseous (dB)")
    axes[0].grid(True)
    axes[0].set_title(f"Atmospheric attenuation components: {regime} rainfall regime")

    axes[1].plot(time_seconds_per_window, rain_loss_dB_per_window, linewidth = 2)
    axes[1].set_ylabel("Rain (dB)")
    axes[1].grid(True)


    axes[2].plot(time_seconds_per_window, atmospheric_loss_dB_per_window, linewidth = 2)
    axes[2].set_ylabel("Total (dB)")
    axes[2].grid(True)

    axes[3].plot(time_seconds_per_window, rain_rate_mm_per_hr_per_window, linewidth = 2)
    axes[3].set_ylabel("Rainfall rate (millimeter per hour)")
    axes[3].set_xlabel("Time (s)")
    axes[3].grid(True)

    figure_file = os.path.join("fig", "terrestrial", "atmospheric", f"atmospheric_loss_components_{regime}.png")
    figure.tight_layout()
    figure.savefig(figure_file, dpi = 300)
    plt.close(figure)

def plot_regimes(atmospheric_loss_dB_by_regime: dict[str, np.ndarray]) -> None:
    
    figure = plt.figure(figsize = (10, 5))
    for regime, atmospheric_loss_dB_per_window in atmospheric_loss_dB_by_regime.items():
        plt.plot(time_seconds_per_window, atmospheric_loss_dB_per_window, linewidth = 2, label = regime)
    plt.grid(True)
    plt.xlabel("Time (s)")
    plt.ylabel("Atmospheric attenuation (dB)")
    plt.title("Atmospheric attenuation comparison across different rainfall regimes")
    plt.legend(loc = "best")

    figure_file = os.path.join("fig", "terrestrial", "atmospheric", f"atmospheric_loss_regime_comparison.png")
    figure.tight_layout()
    figure.savefig(figure_file, dpi = 300)
    plt.close(figure)    

#
# Main loop
#

def main() -> None:

    os.makedirs("fig",  exist_ok = True)
    os.makedirs("data", exist_ok = True)

    print("Atmospheric attenuation settings:")
    print(f"  Carrier frequency: {CARRIER_FREQUENCY_GHZ} GHz")
    print(f"  Terrestrial-link distance: {TERRESTRIAL_LINK_DISTANCE_METERS} meters")
    print(f"  P.676 inputs: P = {ATMOSPHERIC_PRESSURE_HECTOPASCALS} hPa, T = {ATMOSPHERIC_TEMPERATURE_KELVIN} degrees Kelvin, Absolute humidity (rho) = {WATER_VAPOR_DENSITY_GRAMS_PER_CUBIC_METER} g / m ** 3")
    print(f"  P.838 inputs: tau = {POLARIZATION_TILT_ANGLE_DEGREES} degrees, elevation = {TERRESTRIAL_ELEVATION_ANGLE_DEGREES} degress\n")
    print(f"  Rain event starts at t = {RAINFALL_START_SECONDS} seconds")
    print("")

    atmospheric_loss_dB_by_regime = {}

    for regime, rain_rate_mm_per_hr in RAIN_RATES_MM_PER_HR.items():
        
        print("Generating an atmospheric attenuation trace...")
        print(f"   Regime: {regime}, Rain rate: {rain_rate_mm_per_hr} millimeters per hour")
        print("")

        output_data = generate_atmospheric_loss_trace(
            regime                = regime,
            rain_rate_mm_per_hr   = rain_rate_mm_per_hr,
        )

        # Save .mat file
        mat_file = os.path.join("data", f"atmospheric_loss_{regime}.mat")
        savemat(mat_file, output_data)

        gaseous_loss_dB_per_window     = output_data["gaseous_loss_dB_per_window"].squeeze()
        rain_loss_dB_per_window        = output_data["rain_loss_dB_per_window"].squeeze()
        atmospheric_loss_dB_per_window = output_data["atmospheric_loss_dB_per_window"].squeeze()
        rain_rate_mm_per_hr_per_window = output_data["rain_rate_mm_per_hr_per_window"].squeeze()
        
        print(f"   Wrote {mat_file}")
        print("")
        print(f"   Gaseous loss (dB): {gaseous_loss_dB_per_window[0]:.4f} dB")
        print(f"   Rain loss (dB): Minimum = {rain_loss_dB_per_window.min():.4f} dB, Maximum = {rain_loss_dB_per_window.max():.4f} dB")
        print(f"   Total (maximum) loss (dB): {atmospheric_loss_dB_per_window.max():.4f} dB")
        print("")

        # Plot regime
        plot_regime(
            regime                         = regime,
            gaseous_loss_dB_per_window     = gaseous_loss_dB_per_window,
            rain_loss_dB_per_window        = rain_loss_dB_per_window,
            atmospheric_loss_dB_per_window = atmospheric_loss_dB_per_window,
            rain_rate_mm_per_hr_per_window = rain_rate_mm_per_hr_per_window,
        )

        atmospheric_loss_dB_by_regime[regime] = atmospheric_loss_dB_per_window

    # Compare regimes
    plot_regimes(atmospheric_loss_dB_by_regime)

    print("Plots written to: fig/")
    print("MAT files written to: data/")


if __name__ == "__main__":
    main()