clear; close all; clc;
rng("default");

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Generate measurement-based Starlink sattelite traces.                %
%                                                                      %
% Some values used here are based on direct measurements, while others %
% are estimates based on qualitative results.                          %
%                                                                      %
% See: https://spearlab.nl/papers/2024/starlinkWWW2024.pdf             %
%                                                                      %
% Output:                                                              %
%   satellite_rate_up_bps_per_window                                   %
%   satellite_rate_down_bps_per_window                                 %
%   satellite_one_way_delay_ms_per_window                              %
%   satellite_outage_at_window                                         %
%   region_quality                                                     %
%                                                                      %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%
% Reset graphics defaults
%
reset(groot);

set(groot, 'defaultFigureColor', 'w');
set(groot, 'defaultAxesColor', 'w');
set(groot, 'defaultAxesXColor', 'k');
set(groot, 'defaultAxesYColor', 'k');
set(groot, 'defaultTextColor', 'k');
set(groot, 'defaultAxesGridColor',      [0.82 0.82 0.82]);
set(groot, 'defaultAxesMinorGridColor', [0.90 0.90 0.90]);

set(groot, 'defaultTextInterpreter', 'tex');
set(groot, 'defaultAxesTickLabelInterpreter', 'tex');
set(groot, 'defaultLegendInterpreter', 'tex');

set(groot, 'defaultAxesFontName', 'LMRoman12');
set(groot, 'defaultTextFontName', 'LMRoman12');
set(groot, 'defaultUicontrolFontName', 'LMRoman12');

if ~isfolder("fig/satellite/performance")
    mkdir("fig/satellite/performance");
end

%
% Timing Settings
%

total_duration_seconds  = 60;
decision_window_seconds = 0.01;
num_windows             = round(total_duration_seconds / decision_window_seconds);
time_seconds_per_window = (0 : num_windows - 1).' * decision_window_seconds;

%
% Satellite elevation scenarios and weather regimes
%

elevation_scenarios = ["high", "mid", "low"];
weather_regimes     = ["clear", "moderate_rain", "heavy_rain"];

% Loop over elevation scenarios and weather regimes
for elevation_index = 1 : numel(elevation_scenarios)

    elevation_scenario = elevation_scenarios(elevation_index);
    geometry_file      = "data/satellite_geometry_" + elevation_scenario + ".mat";

    if ~isfile(geometry_file)
        fprintf("Skipping elevation scenario '%s': missing %s\n", elevation_scenario, geometry_file);
        continue;
    end

    load(geometry_file, "satellite_access_at_window", "base_station_in_fov_at_window", "satellite_propagation_delay_ms_per_window");
    satellite_propagation_delay_ms_per_window = satellite_propagation_delay_ms_per_window(:);
    satellite_access_at_window                = satellite_access_at_window(:);
    base_station_in_fov_at_window             = base_station_in_fov_at_window(:);

    for regime_index = 1 : numel(weather_regimes)

        weather_regime = weather_regimes(regime_index);
        atmospheric_file = "data/satellite_atmospheric_loss_" + elevation_scenario + "_" + weather_regime + ".mat";

        if ~isfile(atmospheric_file)
            fprintf("Skipping weather regime '%s' for elevation scenario '%s': missing %s\n", weather_regime, elevation_scenario, atmospheric_file);
            continue;
        end

        load(atmospheric_file, "satellite_atmospheric_loss_dB_per_window");
        satellite_atmospheric_loss_dB_per_window = satellite_atmospheric_loss_dB_per_window(:);

        rng(100 + 10 * elevation_index + regime_index);   % Use one deterministic seed per combo

        fprintf("\nGenerating satellite performance: elevation scenario = %s, weather regime = %s\n", elevation_scenario, weather_regime);
        
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % Region / coverage quality %
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        
        region_quality = "good";         % Configure region quality here 
        
        %{
        
        good    =>     stable service  typical mid lattitude, with dense ground stations and points of presence
        okay    =>     more variance
        bad     =>     intermittent    high lattitude, with sparce ground infrastucture
        
        %}
        
        % Note: These are not direct measurements from the paper, but rather
        % assumptions/estimates based off of qualitative results from the paper.
        
        switch region_quality
            case "good"
                ground_infrastructure_extra_delay_ms      = 0;          % GS + PoP routing
                jitter_std_ms                             = 11;         % Using Zoom example from the paper 
                outage_rate_per_second                    = 0.002;      % rare
                outage_duration_seconds_range             = [0.2 1.0];
            case "okay"
                ground_infrastructure_extra_delay_ms      = 25;
                jitter_std_ms                             = 14;
                outage_rate_per_second                    = 0.01;
                outage_duration_seconds_range             = [0.3 1.5];
            case "bad"
                ground_infrastructure_extra_delay_ms      = 40;
                jitter_std_ms                             = 25;
                outage_rate_per_second                    = 0.03;       % intermittent
                outage_duration_seconds_range             = [0.5 3.0];
            otherwise
                error("Unknown region quality: %s", region_quality);
        end
        
        %%%%%%%%%%%%%%%%%%%%%%%%%
        % Atmospheric modifiers %
        %%%%%%%%%%%%%%%%%%%%%%%%%
        
        % Rate reduction
        % multiplier = 10^(-alpha_rate * loss / 10)
        alpha_rate          = 0.35;        % 10 dB loss =>  10 ^ (-3.5 / 10) = 0.45x rate
        min_rate_multiplier = 0.02;
        
        % Outage probability inflation
        % multiplier = exp(beta_outage * loss)
        beta_outage           = 0.12;      % 10 dB loss => exp(1.2) = 3.3x outage prob
        max_outage_multiplier = 20;
        
        % Jitter inflation
        % multiplier = 1 + gamma_jitter * loss
        gamma_jitter          = 0.00;     % 10 dB loss => +50% jitter std      % @Disabling: Previous value was 0.05 dB^-1
        max_jitter_multiplier = 3.0;
        
        % Multipliers
        rate_multiplier_per_window = 10 .^ (-(alpha_rate .* satellite_atmospheric_loss_dB_per_window) / 10);
        rate_multiplier_per_window = max(rate_multiplier_per_window, min_rate_multiplier);
        
        outage_multiplier_per_window = exp(beta_outage .* satellite_atmospheric_loss_dB_per_window);
        outage_multiplier_per_window = min(max_outage_multiplier, outage_multiplier_per_window);
        
        jitter_multiplier_per_window = 1 + gamma_jitter .* satellite_atmospheric_loss_dB_per_window;
        jitter_multiplier_per_window = min(max_jitter_multiplier, jitter_multiplier_per_window);
        
        
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % Baseline (bent-pipe) delay %
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        
        % 40-ms RTT => 20-ms one-way
        % Propagation delay to satellite ~ 2 ms
        base_one_way_delay_ms = 18 + satellite_propagation_delay_ms_per_window + ground_infrastructure_extra_delay_ms;
        
        % Jitter
        jitter_ms_per_window = (jitter_std_ms .* jitter_multiplier_per_window) .* randn(num_windows, 1);
        satellite_one_way_delay_ms_per_window = base_one_way_delay_ms + jitter_ms_per_window;
        
        % Clip to a sensible minimum delay for windows during which a satellite is accessible
        satellite_one_way_delay_ms_per_window = max(satellite_one_way_delay_ms_per_window, 5);
        
        
        %%%%%%%%%%%%%%%%%%%%%%%%%
        % Goodput distributions %
        %%%%%%%%%%%%%%%%%%%%%%%%%
        
        % Uplink typical is 4-12 Mbps (centered at 8 Mbps)
        satellite_rate_up_Mbps = zeros(num_windows, 1);
        for window_index = 1 : num_windows
             if  rand() < 0.90
                 satellite_rate_up_Mbps(window_index) = 4 + (12 - 4) * rand();
             else
                 satellite_rate_up_Mbps(window_index) = 12 + (20 - 12) * rand();   % Occasionally higher
             end
        end
        
        % Downlink typical is 50-100 Mbps, with a tail to 220 Mbps
        satellite_rate_down_Mbps = zeros(num_windows, 1);
        for window_index = 1 : num_windows
            random_number = rand();
            if random_number < 0.85
                satellite_rate_down_Mbps(window_index) = 50 + (100 - 50) * rand();
            elseif random_number < 0.98
                satellite_rate_down_Mbps(window_index) = 100 + (150 - 100) * rand();
            else
                satellite_rate_down_Mbps(window_index) = 150 + (220 - 150) * rand();
            end
        end
        
        satellite_rate_up_bps_per_window   = satellite_rate_up_Mbps   * 1e6;
        satellite_rate_down_bps_per_window = satellite_rate_down_Mbps * 1e6;
        
        % Apply atmospheric-based rate reduction
        satellite_rate_up_bps_per_window   = satellite_rate_up_bps_per_window .* rate_multiplier_per_window;
        satellite_rate_down_bps_per_window = satellite_rate_down_bps_per_window .* rate_multiplier_per_window;
           
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % 15-second periodic reconfiguration artifacts %
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        
        % The Starlink paper reports globally synchronized 15-second intervals causing substantial latency/throughput variations.
        artifact_period_seconds = 15;
        
        % Model the reconfiguration artifact as a short window at the start of each period
        artifact_window_seconds = 0.3;     % 300-ms window
        artifact_mask = (mod(time_seconds_per_window, artifact_period_seconds) < artifact_window_seconds);
        
        % During the artifact: throughput dip + delay spike
        rate_dip = 0.6 + (0.9 - 0.6) * rand(nnz(artifact_mask), 1);    % 60-90%
        satellite_rate_up_bps_per_window(artifact_mask) = satellite_rate_up_bps_per_window(artifact_mask) .* rate_dip;
        satellite_rate_down_bps_per_window(artifact_mask) = satellite_rate_down_bps_per_window(artifact_mask) .* rate_dip;
        
        delay_spike_ms = 10 + (40 - 10) * rand(nnz(artifact_mask), 1); % +10-40 ms one-way
        satellite_one_way_delay_ms_per_window(artifact_mask) = satellite_one_way_delay_ms_per_window(artifact_mask) + delay_spike_ms; 
        
        %%%%%%%%%%%
        % Outages %
        %%%%%%%%%%%
        
        satellite_outage_at_window    = false(num_windows, 1);
        
        per_window_outage_probability = (outage_rate_per_second * decision_window_seconds) .* outage_multiplier_per_window;
        per_window_outage_probability = min(1, max(0, per_window_outage_probability));   % Clip to [0, 1]
        
        window_index = 1;
        while window_index <= num_windows
        
            if rand() < per_window_outage_probability(window_index) % Outage
                outage_duration_seconds = outage_duration_seconds_range(1) + (outage_duration_seconds_range(2) - outage_duration_seconds_range(1)) * rand();
                outage_duration_windows = max(1, round(outage_duration_seconds / decision_window_seconds));
                end_window_index = min(num_windows, window_index + outage_duration_windows - 1);
                satellite_outage_at_window(window_index : end_window_index) = true;
                window_index = end_window_index + 1;
            else                                      % No outage
                window_index = window_index + 1;
            end
        end
        
        % When there is an outage, rate goes to 0 (service is unavailable)
        satellite_rate_up_bps_per_window(satellite_outage_at_window)      = 0;
        satellite_rate_down_bps_per_window(satellite_outage_at_window)    = 0;
        satellite_one_way_delay_ms_per_window(satellite_outage_at_window) = Inf;
        
        %%%%%%%%%%%%%%%%%%%%%%%%%%%
        % Lack of physical access %
        %%%%%%%%%%%%%%%%%%%%%%%%%%%
        
        % Satellite link is unusable if there's an outage, no satellite is
        % accessible (above elevation mask), and the base station is outside
        % the field of view
        satellite_unavailable_at_window = satellite_outage_at_window | ~satellite_access_at_window | ~base_station_in_fov_at_window;


        % If there is no access to a satellite (elevation is below threshold)
        % Treat this like an outage: rate goes to zero and delay goes to infinity
        satellite_rate_up_bps_per_window(satellite_unavailable_at_window)      = 0;
        satellite_rate_down_bps_per_window(satellite_unavailable_at_window)    = 0;
        satellite_one_way_delay_ms_per_window(satellite_unavailable_at_window) = Inf;
        
        %%%%%%%%%
        % Plots %
        %%%%%%%%%
        
        % Plot rate, delay, availability
        figure('Color', 'w');
        set(gcf, "Position", [100 100 1100 800]);
        
        % Don't plot infinity delay
        satellite_one_way_delay_ms_finite = satellite_one_way_delay_ms_per_window;
        satellite_one_way_delay_ms_finite(~isfinite(satellite_one_way_delay_ms_finite)) = NaN;
        
        % Smooth trend lines for visualization only
        trend_window_seconds = 0.5;
        trend_window_samples = max(1, round(trend_window_seconds / decision_window_seconds));
        
        satellite_rate_up_Mbps_per_window = satellite_rate_up_bps_per_window / 1e6;
        
        satellite_rate_up_Mbps_trend = smoothdata(satellite_rate_up_Mbps_per_window, "movmean", trend_window_samples);
        satellite_one_way_delay_ms_trend = smoothdata(satellite_one_way_delay_ms_finite, "movmean", trend_window_samples, "omitnan");

        subplot(3,1,1);
        plot(time_seconds_per_window, satellite_rate_up_Mbps_per_window, "LineWidth", 0.8);
        hold on;
        plot(time_seconds_per_window, satellite_rate_up_Mbps_trend, "LineWidth", 2.5);
        grid on;
        ylabel("Uplink rate (Mbps)");
        title("Satellite performance trace (" + remove_underscores(elevation_scenario) + " elevation, " + remove_underscores(weather_regime) + ")");
        
        subplot(3,1,2);
        plot(time_seconds_per_window, satellite_one_way_delay_ms_finite, "LineWidth", 0.8);
        hold on;
        plot(time_seconds_per_window, satellite_one_way_delay_ms_trend, "LineWidth", 2.5);
        grid on;
        ylabel("One-way delay (ms)");
        
        subplot(3,1,3);
        stairs(time_seconds_per_window, double(satellite_unavailable_at_window), "LineWidth", 1.5);
        grid on;
        ylabel("Unavailable");
        xlabel("Time (s)");
        ylim([-0.05 1.05]);
        
        figure_file = "fig/satellite/performance/satellite_performance_" + elevation_scenario + "_" + weather_regime + ".png";
        exportgraphics(gcf, figure_file, "Resolution", 300);
        close(gcf);

        %%%%%%%%%%%%%%%%%%%%%%%
        % Save generated data %
        %%%%%%%%%%%%%%%%%%%%%%%
        
        output_file = "data/satellite_performance_" + elevation_scenario + "_" + weather_regime + ".mat";
        
        save(output_file, ...
            "time_seconds_per_window", "decision_window_seconds", ...
            "satellite_rate_up_bps_per_window", "satellite_rate_down_bps_per_window", ...
            "satellite_one_way_delay_ms_per_window", "satellite_outage_at_window", ...
            "satellite_unavailable_at_window", "region_quality", ...
            "elevation_scenario", "weather_regime", ...
            "satellite_atmospheric_loss_dB_per_window", ...
            "rate_multiplier_per_window", "outage_multiplier_per_window", "jitter_multiplier_per_window", ...
            "per_window_outage_probability", ...
            "alpha_rate", "beta_outage", "gamma_jitter", ...
            "min_rate_multiplier", "max_outage_multiplier", "max_jitter_multiplier");
        
        disp("Wrote " + output_file);
    end
end

function tag = remove_underscores(underscored_tag)
    tag = strrep(underscored_tag, "_", " ");
end