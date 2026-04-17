clear; close all; clc;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Geometry-based satellite trace from real TLE data and real location  %
%                                                                      %
% Output                                                               %
%   satellite_access_at_window                    % Is satellite accessible?
%   overhead_at_window                            % Is satellite overhead?
%   base_station_in_fov_at_window                 % Is base station in field of view?
%   best_satellite_elevation_degrees_per_window                        %
%   best_satellite_slant_range_meters_per_window                       %
%   satellite_propagation_delay_ms_per_window                          %
%   best_satellite_off_nadir_angles_degrees_per_window                 %
%                                                                      %
%   This script does a scan (over hours) to find a strong pass for 3   %
%   different elevation scenarios (high, mid, low) and                 %
%   generates a 60-second fine trace at those time.                    %
%                                                                      %
%   Because satellite geometry changes slowly, we sample it every one  %
%   second and smooth it out over the shorter decision windows.        %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


%
% Timing Settings
%

total_duration_seconds  = 60;
decision_window_seconds = 0.01;
num_windows             = round(total_duration_seconds / decision_window_seconds);
time_seconds_per_window = (0 : num_windows - 1).' * decision_window_seconds;


%%%%%%%%%%%%%%%%%%
% Configurations %
%%%%%%%%%%%%%%%%%%

% Default ground station location
% Lincoln, Nebraska
ground_station_latitude        = 40.8209;
ground_station_longitude       = -96.7006;
ground_station_altitude_meters = 360;

% Pass criteria
elevation_mask_degrees     = 25;  % Minimum usable elevation
overhead_threshold_degrees = 80;  % Directly overhead threshold

% Field of view
% The off-nadir angle (ONA) is measured at the satellite between
%   the satellite-to-base-station line-of-sight vector and
%   the satellite nadir direction (satellite-to-earth-center vector)
max_off_nadir_angle_degrees = 56.5;

% FCC report: https://fcc.report/IBFS/SAT-MOD-20200417-00037/2274316.pdf
% Standard latitude: minimum 25-degree elevation angle, ~ 56.5-degree max off-nadir angle (steering angle), radius = 950 km
% Higher (polar) latitudes: minimum 5-degree elevation angle, ~ 66.5-degree max off-nadir angle, radius = 2080 km

% Sampling/scanning to find the strong 60-second trace
search_horizon_hours      = 12; % How many hours ahead to search the data for a strong pass (up to 12 hours)
coarse_timestep_seconds   = 10; % Coarce sampling for the search/scanning (every 10 seconds)
fine_timestep_seconds     = 1;  % Finer sampling for the trace (every 1 second)


%%%%%%%%%%%%%%%%
% TLE Download %
%%%%%%%%%%%%%%%%

tle_url = "https://celestrak.org/NORAD/elements/gp.php?GROUP=starlink&FORMAT=tle";

tle_file        = fullfile("data", "tle", "starlink.tle");
tle_file_subset = fullfile("data", "tle", "starlink_subset.tle");
num_satellites  = 200; % Only use a subset of all satellites

% Download TLE
refresh_time_hours = 24;              % If file is more than 24 hours old, download up-to-date data
file_is_outdated = ~isfile(tle_file);
download = true;                      % Set to false if we don't want to download a new version of the dataset
if download
    if ~file_is_outdated
        directory = dir(tle_file);
        file_age_hours = (now - directory.datenum) * 24;
        file_is_outdated = file_age_hours > refresh_time_hours;
    end
    
    if file_is_outdated
        fprintf("Downloading TLE data from CelesTrack...\n");
        websave(tle_file, tle_url);
    else
        fprintf("Using cached TLE data: %s\n", tle_file);
    end
end

% Create a smaller subset TLE file
rng("default");       % Seed the random number generator to get consistent subsets
write_tle_subset(tle_file, tle_file_subset, num_satellites);


%%%%%%%%%%%%%%%%
% Scan the TLE %
%%%%%%%%%%%%%%%%

% Coarsely search the dataset to find the best-pass time (maximum
% elevations over the 12-hour horizon)
t_start = datetime("now", "TimeZone", "UTC");
t_end   = t_start + hours(search_horizon_hours);

% Create a satelliteScenario object
% It will sample satellite geometry at discrete low-res time steps
satellite_scenario_coarse = satelliteScenario(t_start, t_end, coarse_timestep_seconds);

% Create a ground station in that scenario
ground_station_coarse = groundStation(satellite_scenario_coarse, ground_station_latitude, ...
    ground_station_longitude, Altitude=ground_station_altitude_meters, ...
    MaskElevationAngle=0, Name="GS");

% Load satellites from the TLE file into the scenario
satellites_coarse = satellite(satellite_scenario_coarse, tle_file_subset);

% Compute azimuth, elevation, range from ground station to every satellite
% over time
[azimuths_degrees_coarse, elevations_degrees_coarse, ...
    slant_ranges_meters_coarse] = aer(ground_station_coarse, satellites_coarse);

% Transpose if array orientation isn't num_satellites x num_timesteps
if size(elevations_degrees_coarse, 1) ~= numel(satellites_coarse)
    elevations_degrees_coarse = elevations_degrees_coarse.';
end

% At each timestep, pick the best satellite (the satellite our base station can communicate with)
[best_elevations_degrees_coarse, best_satellites_indices_coarse] = max(elevations_degrees_coarse, [], 1);

num_timesteps_coarse = numel(best_elevations_degrees_coarse);
time_utc_coarse = satellite_scenario_coarse.StartTime + seconds(coarse_timestep_seconds * (0 : num_timesteps_coarse - 1));

%
% Pick 3 elevation scenario times: high, mid, low
%

% HIGH: elevation greater than 80 degrees
% Find the time we see our first satellite overhead (or the maximum elevation) and pick that time for our "high" scenario
high_elevation_time_index = find(best_elevations_degrees_coarse >= overhead_threshold_degrees, 1, "first");
if isempty(high_elevation_time_index)
    [~, high_elevation_time_index] = max(best_elevations_degrees_coarse);
end

% MID: elevation close to 50 degrees (40 - 60 degrees)
mid_elevation_target_degrees = 50;
mid_elevation_mask = (best_elevations_degrees_coarse >= 40) & (best_elevations_degrees_coarse <= 60);
if any(mid_elevation_mask)
    mid_elevation_time_indices = find(mid_elevation_mask);
    [~, index] = min(abs(best_elevations_degrees_coarse(mid_elevation_time_indices) - mid_elevation_target_degrees));
    mid_elevation_time_index = mid_elevation_time_indices(index);
else
    [~, mid_elevation_time_index] = min(abs(best_elevations_degrees_coarse - mid_elevation_target_degrees));
end

% LOW: elevation below access mask (i.e., less than 25 degrees)
low_elevation_mask = best_elevations_degrees_coarse < elevation_mask_degrees;
if any(low_elevation_mask)
    low_elevation_time_indices = find(low_elevation_mask);
    [~, index] = max(best_elevations_degrees_coarse(low_elevation_time_indices));
    low_elevation_time_index = low_elevation_time_indices(index);
else
    % Worst elevation we can find
    [~, low_elevation_time_index] = min(best_elevations_degrees_coarse);
end

best_times = struct( ...
    "elevation_scenario", {"high", "mid", "low"}, ...
    "utc", {time_utc_coarse(high_elevation_time_index), time_utc_coarse(mid_elevation_time_index), time_utc_coarse(low_elevation_time_index)});

elevation_scenario_time_indices = [high_elevation_time_index mid_elevation_time_index low_elevation_time_index];

for index = 1 : numel(best_times)
    fprintf("Elevation scenario: %s, Selected time: %s UTC (best elevation =  %.1f degrees)\n", ...
        best_times(index).elevation_scenario, string(best_times(index).utc), ...
        best_elevations_degrees_coarse(elevation_scenario_time_indices(index)));
end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Generate the geometry traces and save data %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

for elevation_scenario_index = 1 : numel(best_times)

    elevation_scenario = best_times(elevation_scenario_index).elevation_scenario;
    best_time_utc      = best_times(elevation_scenario_index).utc;

    fprintf("\nGenerating fine trace for elevation scenario '%s' around %s UTC\n", ...
        elevation_scenario, string(best_time_utc));

    % Generate a 60-second trace around best_time_utc
    time_start = best_time_utc - seconds(total_duration_seconds / 2);
    time_end   = time_start + seconds(total_duration_seconds);
    
    % Create a satelliteScenario object
    % It will sample satellite geometry at discrete high-res time steps
    satellite_scenario_fine = satelliteScenario(time_start, time_end, fine_timestep_seconds);
    
    % Create a ground station in that scenario
    ground_station_fine = groundStation(satellite_scenario_fine, ground_station_latitude, ...
        ground_station_longitude, Altitude=ground_station_altitude_meters, ...
        MaskElevationAngle=0, Name="GS");
    
    % Load satellites from the TLE file into the scenario
    satellites_fine = satellite(satellite_scenario_fine, tle_file_subset);
    
    % Compute azimuth, elevation, range from ground station to every satellite
    % over time
    [azimuths_degrees_fine, elevations_degrees_fine, ...
        slant_ranges_meters_fine] = aer(ground_station_fine, satellites_fine);
    
    % Transpose if array orientation isn't num_satellites x num_timesteps
    if size(elevations_degrees_fine, 1) ~= numel(satellites_fine)
        elevations_degrees_fine = elevations_degrees_fine.';
        slant_ranges_meters_fine = slant_ranges_meters_fine.';
    end
    
    % At each timestep, pick the best satellite
    [best_elevations_degrees_fine, best_satellites_indices_fine] = max(elevations_degrees_fine, [], 1);
    num_timesteps_fine = numel(best_elevations_degrees_fine);
    
    % Field of view check with off-nadir angle
    
    % Get ECEF position of ground station using WGS84
    base_station_ecef_position_meters = lla2ecef( ...
        [ground_station_latitude, ground_station_longitude, ...
        ground_station_altitude_meters], "WGS84");
    
    % Ground station distance from earth center
    base_station_to_earth_center_meters = norm(base_station_ecef_position_meters);
    
    % Satellite ECEF positions 
    % 3 x num_timesteps_fine x num_satellites
    satellite_ecef_positions_meters_fine = states(satellites_fine, CoordinateFrame="ECEF");
    
    % Best satellite distance from earth center at every timestep
    best_satellite_to_earth_center_meters = zeros(1, num_timesteps_fine);
    for time_index = 1 : num_timesteps_fine
        best_satellite_index = best_satellites_indices_fine(time_index);
        best_satellite_ecef_position_meters = satellite_ecef_positions_meters_fine(:, time_index, best_satellite_index);
        best_satellite_to_earth_center_meters(time_index) = norm(best_satellite_ecef_position_meters);
    end
    
    % Convert elevation angle to off-nadir angle using spherical geometry
    % sin(off-nadir angle) = (GS-to-earth-center distance / satellite-to-earth-center distance) * cos(elevation angle)
    sine_off_nadir_angles = (base_station_to_earth_center_meters ./ best_satellite_to_earth_center_meters) .* cosd(best_elevations_degrees_fine);
    
    % Clamp to [-1, 1]
    sine_off_nadir_angles = max(-1, min(1, sine_off_nadir_angles));
    
    % Off-nadir angle
    off_nadir_angles_degrees = asind(sine_off_nadir_angles);
    
    % Is the base station in the satellite's field of view?
    base_station_in_fov = off_nadir_angles_degrees <= max_off_nadir_angle_degrees;
    
    
    % Pick the slant range corresponding to the best satellite at each timestep
    best_slant_ranges_meters_fine = ...
        slant_ranges_meters_fine(sub2ind(size(slant_ranges_meters_fine), ...
                                         best_satellites_indices_fine, ...
                                         1 : num_timesteps_fine));
    
    % Propagation delay
    c = physconst("lightspeed");
    propagation_delay_ms_fine = (best_slant_ranges_meters_fine / c) * 1000;
    
    time_utc_fine = satellite_scenario_fine.StartTime + seconds(fine_timestep_seconds * (0 : num_timesteps_fine - 1));
    time_seconds_fine = seconds(time_utc_fine - satellite_scenario_fine.StartTime);
    
    % Resample to 10-ms decision grid (and smooth out the curves)
    time_seconds_per_window = time_seconds_per_window(:);
    
    best_satellite_elevation_degrees_per_window = interp1(time_seconds_fine, best_elevations_degrees_fine(:), time_seconds_per_window, "pchip", "extrap");
    best_satellite_slant_range_meters_per_window = interp1(time_seconds_fine, best_slant_ranges_meters_fine(:), time_seconds_per_window, "pchip", "extrap");
    satellite_propagation_delay_ms_per_window = interp1(time_seconds_fine, propagation_delay_ms_fine(:), time_seconds_per_window, "pchip", "extrap");
    
    best_satellite_off_nadir_angles_degrees_per_window = interp1( ...
        time_seconds_fine, off_nadir_angles_degrees(:), ...
        time_seconds_per_window, "pchip", "extrap");
    
    satellite_access_at_window = best_satellite_elevation_degrees_per_window >= elevation_mask_degrees;
    overhead_at_window = best_satellite_elevation_degrees_per_window >= overhead_threshold_degrees;
    
    base_station_in_fov_at_window = best_satellite_off_nadir_angles_degrees_per_window <= max_off_nadir_angle_degrees;
    
    %
    % Save data
    %
    output_file = "data/satellite_geometry_" + elevation_scenario + ".mat";
    
    save(output_file, ...
         "satellite_access_at_window", "overhead_at_window", ...
         "best_satellite_elevation_degrees_per_window", ...
         "best_satellite_slant_range_meters_per_window", ...
         "satellite_propagation_delay_ms_per_window", ...
         "ground_station_latitude", "ground_station_longitude", ...
         "ground_station_altitude_meters", "max_off_nadir_angle_degrees", ...
         "best_satellite_off_nadir_angles_degrees_per_window", ...
         "base_station_in_fov_at_window");
    
    disp("Wrote " + output_file);
    
    %
    % Plots
    %

    figure;
    grid on;
    hold on;
    plot(time_seconds_per_window, best_satellite_elevation_degrees_per_window, "LineWidth", 1.5);
    yline(elevation_mask_degrees, "--", "Accessible");
    yline(overhead_threshold_degrees, "--", "Overhead");
    xlabel("Time (s)");
    ylabel( "Elevation (degrees)");
    title("Satellite elevation over time (" + elevation_scenario + ")");
    if ~isfolder("fig/satellite/geometry")
        mkdir("fig/satellite/geometry");
    end
    saveas(gcf, "fig/satellite/geometry/satellite_geometry_elevation_" + elevation_scenario + ".png");
    
    
    figure;
    grid on;
    hold on;
    plot(time_seconds_per_window, satellite_propagation_delay_ms_per_window, "LineWidth", 1.5);
    xlabel("Title (s)");
    ylabel("Propagation delay (ms)");
    title("Propagation delay from base station to nearest satellite over time (" + elevation_scenario + ")");
    saveas(gcf, "fig/satellite/geometry/satellite_geometry_propagation_delay_" + elevation_scenario + ".png");


    figure;
    grid on;
    hold on;
    
    plot(time_seconds_per_window, best_satellite_elevation_degrees_per_window, "LineWidth", 1.5);
    plot(time_seconds_per_window, best_satellite_off_nadir_angles_degrees_per_window, "LineWidth", 1.5);
    
    yline(elevation_mask_degrees, "--", "Minimum elevation (ABOVE: satellite is accessible)");
    yline(max_off_nadir_angle_degrees, "--", "Maximum off-nadir (BELOW: base station is in field of view)");
    
    xlabel("Time (s)");
    ylabel("Degrees");
    legend("Elevation angle", "Off-nadir angle", Location="best");
    title("Satellite elevation and off-nadir angles over time (" + elevation_scenario + ")");
    saveas(gcf, "fig/satellite/geometry/satellite_geometry_angles_" + elevation_scenario + ".png");
end

%%%%%%%%%%%%%%%%%%%%
% Helper functions %
%%%%%%%%%%%%%%%%%%%%

% From the full TLE dataset, extract a random num_satellites number of TLEs
function write_tle_subset(tle_file, tle_subset_file, num_satellites)

    lines = readlines(tle_file);
    lines = strip(lines);
    lines(lines == "") = [];

    % TLE format: 2-line vs 3-line (with a header containing the name)
    % Example TLE entry:
    % 
    % ISS (ZARYA)                                                             <== Optional
    % 1 25544U 98067A   20331.01187177  .00003392  00000-0  69526-4 0  9990
    % 2 25544  51.6456 267.7478 0001965  82.1336  12.7330 15.49066632257107
    %
    header   = ~(startsWith(lines(1), "1 ") || startsWith(lines(1), "2 ")); % 1 if header (name line), 0 otherwise
    tle_size = 2 + header;

    num_tles = floor(numel(lines) / tle_size);
    if num_tles == 0
        error("Error: TLE format not recognized or TLE dataset empty: %s", tle_file);
    end
    fprintf("Full TLE contains %d satellites (%d lines per entry)\n", num_tles, tle_size);

    num_tles_subset = min(num_satellites, num_tles);
    tle_indices = sort(randperm(num_tles, num_tles_subset));

    output_lines = strings(0, 1);
    for i = 1 : numel(tle_indices)
        tle_index = tle_indices(i);
        start_line_index = (tle_index - 1) * tle_size + 1;
        output_lines = [output_lines; lines(start_line_index : start_line_index + tle_size - 1)];
    end

    writelines(output_lines, tle_subset_file);
    fprintf("Wrote subset TLE: %s (%d satellites)\n", tle_subset_file, num_tles_subset);
end