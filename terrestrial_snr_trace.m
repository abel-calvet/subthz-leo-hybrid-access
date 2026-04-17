clear; close all; clc;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Generate the effective SNR trace over time from the base NR PUSCH    %
% SNR, and blockage and atmospheric losses                             %
%                                                                      %
% Input:                                                               %
%   wideband_snr_dB_per_window                                         %
%   atmospheric_loss_dB_per_window                                     %
%   blockage_loss_dB_per_window                                        %
%                                                                      %
% Output:                                                              %
%   terrestrial_snr_dB_per_window                                      %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Figure defaults
set(groot, "defaultFigureColor", "w");
set(groot, "defaultAxesColor",   "w");

set(groot, "defaultAxesFontName", "Helvetica");
set(groot, "defaultTextFontName", "Helvetica");
set(groot, "defaultAxesFontSize", 12);
set(groot, "defaultTextFontSize", 12);

set(groot, "defaultAxesLineWidth", 1.0);
set(groot, "defaultLineLineWidth", 1.8);

set(groot, "defaultAxesBox",             "on");
set(groot, "defaultAxesTickDir",         "out");
set(groot, "defaultAxesTitleFontWeight", "bold");
set(groot, "defaultLegendBox",           "off");

% Force black foreground colors
set(groot, "defaultAxesXColor",      "k");
set(groot, "defaultAxesYColor",      "k");
set(groot, "defaultAxesZColor",      "k");
set(groot, "defaultTextColor",       "k");
set(groot, "defaultLegendTextColor", "k");
set(groot, "defaultColorbarColor",   "k");

% Make grid readable on white background
set(groot, "defaultAxesGridColor",      [0.82 0.82 0.82]);
set(groot, "defaultAxesMinorGridColor", [0.90 0.90 0.90]);


weather_regime    = "heavy_rain";                  % clear, moderate_rain, heavy_rain
blockage_severity = "mixed_blockage";              % no_blockage, mild_blockage, severe_blockage, mixed_blockage

snr_file = "data/terrestrial_snr_" + weather_regime + "_" + blockage_severity + ".mat";

%
% Files
%

snr_base_file         = "data/terrestrial_snr_base.mat";
atmospheric_loss_file = "data/atmospheric_loss_" + weather_regime + ".mat";
blockage_loss_file    = "data/blockage_loss_" + blockage_severity + ".mat";

external_trigger_file = "data/external_trigger_trace.mat";

%
% Load traces
%
load(snr_base_file, "wideband_snr_dB_per_window");
load(atmospheric_loss_file, "atmospheric_loss_dB_per_window");
load(blockage_loss_file, "blockage_loss_dB_per_window", "blockage_at_window");
load(external_trigger_file, "external_trigger_at_window");


%
% Timing Settings
%

total_duration_seconds  = 60;
decision_window_seconds = 0.01;
num_windows             = round(total_duration_seconds / decision_window_seconds);
time_seconds_per_window = (0 : num_windows - 1).' * decision_window_seconds;


%
% Calculate effective SNR from base SNR and losses
%

terrestrial_snr_dB_per_window = wideband_snr_dB_per_window - blockage_loss_dB_per_window - atmospheric_loss_dB_per_window;

%
% Plots
%

figure;
set(gcf, "Color", "w", "InvertHardcopy", "off");
set(gcf, "Position", [100 100 1400 400]);
grid on;
hold on;
ylim([-10, 25]);
plot(time_seconds_per_window, terrestrial_snr_dB_per_window, "LineWidth", 2);
xlabel("Time (s)");
ylabel("SNR (dB)");
title(["Terrestrial NR wideband signal-to-noise ratio over time", "(Weather regime: " + remove_underscores(weather_regime) + ", Blockage severity: " + remove_underscores(blockage_severity) +  ")"], "FontSize", 15);

y_limits = ylim;

if ~isfolder("fig/terrestrial/snr")
    mkdir("fig/terrestrial/snr");
end
exportgraphics(gcf, fullfile("fig/terrestrial/snr/terrestrial_snr_" + weather_regime + "_" + blockage_severity + ".png"), "Resolution", 400, "BackgroundColor", "white");
close(gcf);

%
% Save data
%

save(snr_file, "terrestrial_snr_dB_per_window", "time_seconds_per_window", ...
    "decision_window_seconds", "blockage_at_window", "external_trigger_at_window", ...
    "weather_regime", "blockage_severity");

disp("Wrote " + snr_file);

%
% Helper functions
%

function patch_handle = shade_intervals(time_seconds, mask, y_limits, rgb_color, window_seconds, alpha_value)
    % This function shades all contiguous "true" segments of a mask as vertical bands.
    % Returns: A handle for the plot's legend.

    time_seconds = time_seconds(:);
    mask = mask(:);

    % Find start/end indices of contiguous true segments
    edges = diff([false; mask; false]);
    segment_starts = find(edges == 1);
    segment_ends   = find(edges == -1) - 1;

    patch_handle = plot(nan, nan); % handle if no segments exist

    for segment_index = 1 : length(segment_starts)
        start_index = segment_starts(segment_index);
        end_index   = segment_ends(segment_index);

        x_start = time_seconds(start_index);
        x_end   = time_seconds(end_index) + window_seconds;

        h = patch([x_start x_end x_end x_start], [y_limits(1) y_limits(1) y_limits(2) y_limits(2)], rgb_color, "EdgeColor", "none", "FaceAlpha", alpha_value);

        % Save the first patch handle for the legend's colored box
        if segment_index == 1
            patch_handle = h;
        end
    end
end


function tag = remove_underscores(underscored_tag)
    tag = strrep(underscored_tag, "_", " ");
end