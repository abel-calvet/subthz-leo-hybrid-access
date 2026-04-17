"""
This script generates atmospheric attenuation traces for the satellite link.

Models used:
    * Gas:
        ITU-R P.676: gaseous attenuation on slant (Earth-space) paths
    * Rain:
        ITU-R P.838: Rain specific attenuation gamma_R(R(t)) in dB / km given a rainfall rate R(t) (millimeters of rain per hour). Need to multiply by the distance the signal travels through the rain, i.e., the slant path length through the rain layer L_s.
        ITU-R P.618: The slant (Earth-space) path length through the rain layer L_s(el(t)), which is elevation-dependent.
        ITU-R P.839: Rain height h_R, calculated from latitude and longitude

Inputs:
    * data/satellite_geometry_<elevation_scenario>.mat
        <elevation_scenario>: high, mid, low
    * Fields:
        best_satellite_elevation_degrees_per_window
        ground_station_latitude
        ground_station_longitude
        ground_station_altitude_meters        

Outputs:
    * data/satellite_atmospheric_<elevation_scenario>_<regime>.mat
        <elevation_scenario>: high, mid, low
        <regime>:    clear, moderate_rain, heavy_rain
    * Fields:
        satellite_atmospheric_loss_dB_per_window
        satellite_gaseous_loss_dB_per_window
        satellite_rain_loss_dB_per_window
        rain_rate_mm_per_hr_per_window
        slant_path_length_in_rain_km_per_window
        elevation_degrees_per_window
        Metadata: frequency, coordinates, etc.

Plots:
    * fig/satellite_atmospheric_loss_components_<elevation>_<regime>.png
    * fig/satellite_atmospheric_loss_regime_comparison.png
"""

import os

import numpy as np
import matplotlib.pyplot as plt
from scipy.io import loadmat, savemat

import itur  # ITU-Rpy

#
# Settings
#

CARRIER_FREQUENCY_GHZ = 14.25  # Starlink uses Ku/Ka. Ku uplink = 14.0-14.5 GHz, Ka uplink = 27.5-30.0 GHz. Most likely, an uplink user will be on Ku band.

BASE_STATION_LATITUDE        = 40.8209
BASE_STATION_LONGITUDE       = -96.7006
BASE_STATION_ALTITUDE_METERS = 360.0

ATMOSPHERIC_PRESSURE_HECTOPASCALS         = 1013.25  # Sea-level atmospheric pressure
ATMOSPHERIC_TEMPERATURE_KELVIN            = 293.15   # Room temperature
WATER_VAPOR_DENSITY_GRAMS_PER_CUBIC_METER = 7.5      # Standard absolute humidity for radio propagation

POLARIZATION_TILT_ANGLE_DEGREES = 45.0   # Tau 

# Weather regimes
RAIN_RATES_MM_PER_HR = {
    "clear":         0.0,
    "moderate_rain": 10.0,
    "heavy_rain":    50.0,
}
RAINFALL_START_SECONDS = 30.0

# Geometry scenarios
ELEVATION_SCENARIOS = {
    "high": "data/satellite_geometry_high.mat",
    "mid":  "data/satellite_geometry_mid.mat",
    "low":  "data/satellite_geometry_low.mat",
}

# Timing grid
TOTAL_DURATION_SECONDS  = 60.0
DECISION_WINDOW_SECONDS = 0.01
NUM_WINDOWS             = round(TOTAL_DURATION_SECONDS / DECISION_WINDOW_SECONDS)
time_seconds_per_window = np.arange(NUM_WINDOWS, dtype = float) * DECISION_WINDOW_SECONDS

#
# Attenuation computations
# 

def compute_slant_path_length_below_rain_height(
    elevation_degrees_per_window: np.ndarray,
    rain_height_km:               float,
    base_station_height_km:       float,
) -> np.ndarray:
    
    """
    Computes the slant path length below the rain height.
    We use the geometry formulas used in ITU-R P.618 Step 2 (Equations 1 and 2).
    See https://www.itu.int/dms_pubrec/itu-r/rec/p/R-REC-P.618-14-202308-I!!PDF-E.pdf.
    """

    effective_earth_radius_km = 8500.0  # Effective radius used by Recommendation
    
    delta_height_km = rain_height_km - base_station_height_km
    
    if delta_height_km <= 0.0:
        return np.zeros_like(elevation_degrees_per_window, dtype = float)
    
    el = np.asarray(elevation_degrees_per_window, dtype = float)
    negative_elevation = el <= 0
    el = np.maximum(el, 0.01)  # Don't divide by zero
    sin_el = np.sin(np.deg2rad(el))

    # Equation 1
    # Valid for elevation >= 5 degrees
    slant_path_length_km_1 = delta_height_km / sin_el

    # Equation 2
    # Valid for elevation < 5 degrees
    slant_path_length_km_2 = 2.0 * delta_height_km / (np.sqrt(sin_el ** 2 + 2.0 * delta_height_km / effective_earth_radius_km) + sin_el)

    slant_path_length_km_per_window = np.where(el >= 5.0, slant_path_length_km_1, slant_path_length_km_2)
    slant_path_length_km_per_window[negative_elevation] = np.nan

    return slant_path_length_km_per_window

def generate_atmospheric_loss_trace(elevation_scenario: str,
                                    regime: str,
                                    rain_rate_mm_per_hr: float, 
                                    geometry_data: dict[str, np.ndarray]) -> dict[str, np.ndarray]:
    
    """
    Generates A_atm(t) = A_gas(t) + A_rain(t) for one weather regime (clear, moderate_rain, heavy_rain) and one elevation scenario (high, mid, low)
    Returns a dictionary ready to be saved to a .mat file.
    """
    
    # Convert to Quantity type objects for ITU-Rpy compatibility
    frequency               = CARRIER_FREQUENCY_GHZ * itur.u.GHz
    water_vapor_density     = WATER_VAPOR_DENSITY_GRAMS_PER_CUBIC_METER * itur.u.g / (itur.u.m ** 3)
    atmospheric_pressure    = ATMOSPHERIC_PRESSURE_HECTOPASCALS * itur.u.hPa
    atmospheric_temperature = ATMOSPHERIC_TEMPERATURE_KELVIN * itur.u.K

    # Elevation angle over time
    elevation_degrees_per_window = np.asarray(geometry_data["best_satellite_elevation_degrees_per_window"]).squeeze().astype(float)
    
    #
    # Rain attenuation
    #

    # Simulate rain starting at t = 30 seconds (piece-wise constant process)
    rain_rate_mm_per_hr_per_window = np.zeros_like(time_seconds_per_window, dtype = float)
    rain_rate_mm_per_hr_per_window[time_seconds_per_window >= RAINFALL_START_SECONDS] = rain_rate_mm_per_hr

    # Rain height h_R
    # From ITU-R P.839
    # Convert Quantity object type to float
    rain_height_km = float(itur.models.itu839.rain_height(BASE_STATION_LATITUDE, BASE_STATION_LONGITUDE).value)
    base_station_height_km = BASE_STATION_ALTITUDE_METERS / 1000.0

    # Slant path length through the rain layer over time (i.e. below the rain height)
    # L_s(t) computed from ITU-R P.618 equations
    slant_path_length_km_per_window = compute_slant_path_length_below_rain_height(
        elevation_degrees_per_window = elevation_degrees_per_window,
        rain_height_km               = rain_height_km,
        base_station_height_km       = base_station_height_km,
    )

    # Rain specific attenuation gamma_R over time (dB per km), R = rainfall rate (millimeters per hour)
    # From ITU-R P.838
    rain_specific_attenuation_per_window = itur.models.itu838.rain_specific_attenuation(
        rain_rate_mm_per_hr_per_window, frequency, elevation_degrees_per_window,
        POLARIZATION_TILT_ANGLE_DEGREES)
    
    # Extract numeric values (if return type is an np.ndarray of Quantity objects)
    rain_specific_attenuation_dB_per_km_per_window = np.asarray(
        getattr(rain_specific_attenuation_per_window, "value", rain_specific_attenuation_per_window),
        dtype = float).squeeze()

    # Rain attenuation
    # # A_rain(t) = gamma_R(t) * L_s(t)
    satellite_rain_loss_dB_per_window = rain_specific_attenuation_dB_per_km_per_window * slant_path_length_km_per_window

    #
    # Gaseous attenuation
    #

    # From ITU-R P.676 
    gaseous_attenuation_per_window = itur.models.itu676.gaseous_attenuation_slant_path(
        frequency, elevation_degrees_per_window, water_vapor_density,
        atmospheric_pressure, atmospheric_temperature, mode = "exact")
    
    
    satellite_gaseous_loss_dB_per_window = np.asarray(
        getattr(gaseous_attenuation_per_window, "value", gaseous_attenuation_per_window),
        dtype = float).squeeze()

    #
    # Total atmospheric loss
    #

    satellite_atmospheric_loss_dB_per_window = satellite_gaseous_loss_dB_per_window + satellite_rain_loss_dB_per_window
    
    # Data for MATLAB
    output_data = { 
        "time_seconds_per_window":                   time_seconds_per_window.reshape(-1, 1),
        "decision_window_seconds":                   np.array([[DECISION_WINDOW_SECONDS]], dtype = float),

        "elevation_degrees_per_window":              elevation_degrees_per_window.reshape(-1, 1),
        "slant_path_length_in_rain_km_per_window":   slant_path_length_km_per_window.reshape(-1, 1),

        "satellite_atmospheric_loss_dB_per_window":  satellite_atmospheric_loss_dB_per_window.reshape(-1, 1),
        "satellite_gaseous_loss_dB_per_window":      satellite_gaseous_loss_dB_per_window.reshape(-1, 1),
        "satellite_rain_loss_dB_per_window":         satellite_rain_loss_dB_per_window.reshape(-1, 1),
        
        "rain_rate_mm_per_hr_per_window":            rain_rate_mm_per_hr_per_window.reshape(-1, 1),

        # Metadata
        "elevation_scenario":                        np.array([elevation_scenario], dtype = object),
        "regime":                                    np.array([regime], dtype = object),
        "regime_rain_rate_mm_per_hr":                np.array([[rain_rate_mm_per_hr]], dtype = float),

        "base_station_latitude_degrees":             np.array([[BASE_STATION_LATITUDE]], dtype = float),
        "base_station_longitude_degrees":            np.array([[BASE_STATION_LONGITUDE]], dtype = float),
        "base_station_altitude_meters":              np.array([[BASE_STATION_ALTITUDE_METERS]], dtype = float),

        "atmospheric_pressure_hPa":                  np.array([[ATMOSPHERIC_PRESSURE_HECTOPASCALS]], dtype = float),
        "atmospheric_temperature_kelvin":            np.array([[ATMOSPHERIC_TEMPERATURE_KELVIN]], dtype = float),
        "water_vapor_density_grams_per_cubic_meter": np.array([[WATER_VAPOR_DENSITY_GRAMS_PER_CUBIC_METER]], dtype = float),
        "carrier_frequency_GHz":                     np.array([[CARRIER_FREQUENCY_GHZ]], dtype = float),
        "polarization_tilt_angle_degrees":           np.array([[POLARIZATION_TILT_ANGLE_DEGREES]], dtype = float),

        "rain_event_start_seconds":                  np.array([[RAINFALL_START_SECONDS]], dtype = float),
    }

    return output_data

#
# Plotting
#

def plot_regime(
    elevation_scenario:              str,
    regime:                          str,
    elevation_degrees_per_window:    np.ndarray,
    slant_path_length_km_per_window: np.ndarray, 
    gaseous_loss_dB_per_window:      np.ndarray,
    rain_loss_dB_per_window:         np.ndarray,
    atmospheric_loss_dB_per_window:  np.ndarray,
    rain_rate_mm_per_hr_per_window:  np.ndarray,   
) -> None:
    
    figure, axes = plt.subplots(6, 1, figsize=(10, 12), sharex = True)
    
    axes[0].plot(time_seconds_per_window, elevation_degrees_per_window, linewidth = 2)
    axes[0].set_ylabel("Elevation (degrees)")
    axes[0].grid(True)
    axes[0].set_title(f"Satellite atmospheric attenuation components: {elevation_scenario} elevation, {regime} rainfall regime")

    axes[1].plot(time_seconds_per_window, slant_path_length_km_per_window, linewidth = 2)
    axes[1].set_ylabel("Slant path length through the rain layer (km)")
    axes[1].grid(True)

    axes[2].plot(time_seconds_per_window, gaseous_loss_dB_per_window, linewidth = 2)
    axes[2].set_ylabel("Gaseous (dB)")
    axes[2].grid(True)

    axes[3].plot(time_seconds_per_window, rain_loss_dB_per_window, linewidth = 2)
    axes[3].set_ylabel("Rain (dB)")
    axes[3].grid(True)

    axes[4].plot(time_seconds_per_window, atmospheric_loss_dB_per_window, linewidth = 2)
    axes[4].set_ylabel("Total (dB)")
    axes[4].grid(True)

    axes[5].plot(time_seconds_per_window, rain_rate_mm_per_hr_per_window, linewidth = 2)
    axes[5].set_ylabel("Rainfall rate (millimeter per hour)")
    axes[5].set_xlabel("Time (s)")
    axes[5].grid(True)

    figure_file = os.path.join("fig", "satellite", "atmospheric", f"{elevation_scenario}", f"satellite_atmospheric_loss_components_{elevation_scenario}_{regime}.png")
    os.makedirs(os.path.dirname(figure_file), exist_ok = True)
    figure.tight_layout()
    figure.savefig(figure_file, dpi = 300)
    plt.close(figure)


def plot_regimes(elevation_scenario: str,
                 atmospheric_loss_dB_by_regime: dict[str, np.ndarray],
                 elevation_degrees_per_window: np.ndarray) -> None:
    
    figure, axes = plt.subplots(2, 1, figsize = (10, 7), sharex = True)

    axes[0].plot(time_seconds_per_window, elevation_degrees_per_window, linewidth = 2)
    axes[0].set_ylabel("Elevation (degrees)")
    axes[0].grid(True)
    axes[0].set_title(f"Satellite atmospheric attenuation comparison across different rainfall regimes: {elevation_scenario} elevation")
    
    for regime, atmospheric_loss_dB_per_window in atmospheric_loss_dB_by_regime.items():
        axes[1].plot(time_seconds_per_window, atmospheric_loss_dB_per_window, linewidth = 2, label = regime)
    
    axes[1].grid(True)
    axes[1].set_xlabel("Time (s)")
    axes[1].set_ylabel("Atmospheric attenuation (dB)")
    axes[1].legend(loc = "best")

    figure_file = os.path.join("fig", "satellite", "atmospheric", f"{elevation_scenario}", f"satellite_atmospheric_loss_regime_comparison_{elevation_scenario}.png")
    os.makedirs(os.path.dirname(figure_file), exist_ok = True)
    figure.tight_layout()
    figure.savefig(figure_file, dpi = 300)
    plt.close(figure)    

#
# Main loop
#

def main() -> None:

    os.makedirs("fig",  exist_ok = True)
    os.makedirs("data", exist_ok = True)

    print("Satellite atmospheric attenuation settings:")
    print(f"  Carrier frequency: {CARRIER_FREQUENCY_GHZ} GHz")
    print(f"  P.676 inputs: P = {ATMOSPHERIC_PRESSURE_HECTOPASCALS} hPa, T = {ATMOSPHERIC_TEMPERATURE_KELVIN} degrees Kelvin, Absolute humidity (rho) = {WATER_VAPOR_DENSITY_GRAMS_PER_CUBIC_METER} g / m ** 3")
    print(f"  P.838 inputs: tau = {POLARIZATION_TILT_ANGLE_DEGREES} degrees")
    print(f"  Rain event starts at t = {RAINFALL_START_SECONDS} seconds")
    print("")

    atmospheric_loss_dB_by_regime = {}

    for elevation_scenario, geometry_mat_file in ELEVATION_SCENARIOS.items():
        
        if not os.path.isfile(geometry_mat_file):
            print(f"Skipping elevation scenario '{elevation_scenario}': missing {geometry_mat_file}")
            continue

        geometry_data = loadmat(geometry_mat_file)
        elevation_degrees_per_window = np.asarray(geometry_data["best_satellite_elevation_degrees_per_window"]).squeeze().astype(float)

        print(f"Elevation scenario: {elevation_scenario} ({geometry_mat_file})")
        print("")

        atmospheric_loss_dB_by_regime = {}

        for regime, rain_rate_mm_per_hr in RAIN_RATES_MM_PER_HR.items():
            
            print("Generating an atmospheric attenuation trace...")
            print(f"   Regime: {regime}, Rain rate: {rain_rate_mm_per_hr} millimeters per hour")
            print("")

            output_data = generate_atmospheric_loss_trace(
                elevation_scenario  = elevation_scenario,
                regime              = regime,
                rain_rate_mm_per_hr = rain_rate_mm_per_hr,
                geometry_data       = geometry_data,
            )

            # Save .mat file
            mat_file = os.path.join("data", f"satellite_atmospheric_loss_{elevation_scenario}_{regime}.mat")
            savemat(mat_file, output_data)

            gaseous_loss_dB_per_window      = output_data["satellite_gaseous_loss_dB_per_window"].squeeze()
            rain_loss_dB_per_window         = output_data["satellite_rain_loss_dB_per_window"].squeeze()
            atmospheric_loss_dB_per_window  = output_data["satellite_atmospheric_loss_dB_per_window"].squeeze()
            rain_rate_mm_per_hr_per_window  = output_data["rain_rate_mm_per_hr_per_window"].squeeze()
            slant_path_length_km_per_window = output_data["slant_path_length_in_rain_km_per_window"].squeeze()

            print(f"   Wrote {mat_file}")
            print("")
            print(f"   Gaseous loss (dB): Minimum = {gaseous_loss_dB_per_window.min():.4f} dB, Maximum = {gaseous_loss_dB_per_window.max():.4f} dB")
            print(f"   Rain loss (dB): Minimum = {rain_loss_dB_per_window.min():.4f} dB, Maximum = {rain_loss_dB_per_window.max():.4f} dB")
            print(f"   Total loss (dB): Minimum = {atmospheric_loss_dB_per_window.min():.4f} dB, Maximum = {atmospheric_loss_dB_per_window.max():.4f} dB")
            print("")

            # Plot regime at a given elevation scenario
            plot_regime(
                elevation_scenario              = elevation_scenario,
                regime                          = regime,
                elevation_degrees_per_window    = elevation_degrees_per_window,
                slant_path_length_km_per_window = slant_path_length_km_per_window,
                gaseous_loss_dB_per_window      = gaseous_loss_dB_per_window,
                rain_loss_dB_per_window         = rain_loss_dB_per_window,
                atmospheric_loss_dB_per_window  = atmospheric_loss_dB_per_window,
                rain_rate_mm_per_hr_per_window  = rain_rate_mm_per_hr_per_window,
            )

            atmospheric_loss_dB_by_regime[regime] = atmospheric_loss_dB_per_window

        # Compare regimes at a given elevation scenario
        plot_regimes(elevation_scenario, atmospheric_loss_dB_by_regime, elevation_degrees_per_window)

    print("Plots written to: fig/")
    print("MAT files written to: data/")


if __name__ == "__main__":
    main()