clear; close all; clc;
rng("default");

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Generate terrestrial blockage loss trace                             %
%                                                                      %
% Output:                                                              %
%   blockage_loss_dB_per_window                                        %
%   blockage_at_window                                                 %
%                                                                      %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

no_blockage_file      = "data/blockage_loss_no_blockage.mat";
mild_blockage_file    = "data/blockage_loss_mild_blockage.mat";
mixed_blockage_file   = "data/blockage_loss_mixed_blockage.mat";
severe_blockage_file  = "data/blockage_loss_severe_blockage.mat";

blockage_severities = struct( ...
    "severity", {"no_blockage",   "mild_blockage",    "mixed_blockage",    "severe_blockage"}, ...
    "file",     {no_blockage_file, mild_blockage_file, mixed_blockage_file, severe_blockage_file});

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

%
% Timing Settings
%

total_duration_seconds  = 60;
decision_window_seconds = 0.01;
num_windows             = round(total_duration_seconds / decision_window_seconds);
time_seconds_per_window = (0 : num_windows - 1).' * decision_window_seconds;


%
% Blockage Loss
%

for severity_index = 1 : numel(blockage_severities)

    blockage_severity  = blockage_severities(severity_index).severity;
    blockage_loss_file = blockage_severities(severity_index).file;
    
    % Outputs
    blockage_loss_dB_per_window = zeros(num_windows, 1);
    blockage_at_window          = false(num_windows, 1);
    
    % Blockage Settings
    if blockage_severity == "no_blockage"
        enable_random_blockage          = false;
        average_blockages_per_second    = 0;
        blockage_loss_dB_range          = [0 0];
        blockage_duration_seconds_range = [0 0];
    
        enable_forced_blockage          = false;
        forced_loss_dB                  = 0;
        forced_start_time_seconds       = 0;
        forced_duration_seconds         = 0;
    
    elseif blockage_severity == "mild_blockage"
        % Random blockage
        enable_random_blockage          = true;
        average_blockages_per_second    = 0.1;                % One blockage event on average every 10 seconds
        blockage_loss_dB_range          = [20 45];            % SNR drops anywhere from 20 to 45 dB
        blockage_duration_seconds_range = [0.3 2.0];          % Blockage lasts anywhere from 300 ms to 2 seconds
        
        % Forced/hardcoded blockage event
        enable_forced_blockage          = true;
        forced_loss_dB                  = 35;                 % Add a long forced blockage event from t = 45 s to t = 50 s (5 seconds)
        forced_start_time_seconds       = 45;
        forced_duration_seconds         = 5;
    
    elseif blockage_severity == "severe_blockage"
        % Severe blockages (more frequent, longer, and deeper)
        enable_random_blockage          = true;
        average_blockages_per_second    = 0.2;                % One blockage event on average every 5 seconds
        blockage_loss_dB_range          = [30 50];
        blockage_duration_seconds_range = [0.8 4.0];
        
        enable_forced_blockage          = true;
        forced_loss_dB                  = 45;
        forced_start_time_seconds       = 42;                 % slightly earlier
        forced_duration_seconds         = 8;                  % longer
    
    elseif blockage_severity == "mixed_blockage"

    % This is the most important blockage scenario to showcase our controller capabilities.
    % We want a mix of the following types of blockages:
    %   * long deep blockages that warrant moving to satellite
    %   * medium partial dips that degrade terrestrial service but do not kill it
    %   * short-lived fades happening at the decision-window timescale, where stability rules should help prevent over-switching

        enable_random_blockage          = false;     % Use per-type blockages instead
        average_blockages_per_second    = 0;
        blockage_loss_dB_range          = [0 0];
        blockage_duration_seconds_range = [0 0];

        enable_forced_blockage          = false;
        forced_loss_dB                  = 0;
        forced_start_time_seconds       = 0;
        forced_duration_seconds         = 0;

        % Blockage rates per blockage type
        average_long_blockages_per_second   = 0.05;   % severe and longer,  about 3  over 60 seconds
        average_medium_dips_per_second      = 0.15;   % partial dips,       about 9  over 60 seconds
        average_short_fades_per_second      = 0.35;   % short fluctuations, about 21 over 60 seconds

        % Blockage depth and duration per blockage type
        long_blockage_loss_dB_range          = [17 22];
        long_blockage_duration_seconds_range = [0.4 1.8];

        medium_dip_loss_dB_range             = [7 14];
        medium_dip_duration_seconds_range    = [0.08 0.60];

        short_fade_loss_dB_range             = [13 19];
        short_fade_duration_seconds_range    = [0.02 0.08];
    else
        error("Unknown blockage severity: %s", blockage_severity);
    end
    

    %
    % Random blockage events
    %

    if blockage_severity ~= "mixed_blockage"

        blockage_probability_per_window = average_blockages_per_second * decision_window_seconds;

        if enable_random_blockage
            for window_index = 1 : num_windows

                if rand() < blockage_probability_per_window
                    loss_dB = blockage_loss_dB_range(1) + (blockage_loss_dB_range(2) - blockage_loss_dB_range(1)) * rand();

                    duration_seconds = blockage_duration_seconds_range(1) + (blockage_duration_seconds_range(2) - blockage_duration_seconds_range(1)) * rand();

                    duration_windows = max(1, round(duration_seconds / decision_window_seconds));
                    shape = "flat";

                    [blockage_loss_dB_per_window, blockage_at_window] = add_blockage_event( ...
                        blockage_loss_dB_per_window, blockage_at_window, ...
                        window_index, duration_windows, loss_dB, shape);
                end
            end
        end

    else

        long_blockage_probability_per_window = average_long_blockages_per_second * decision_window_seconds;
        medium_dip_probability_per_window    = average_medium_dips_per_second    * decision_window_seconds;
        short_fade_probability_per_window    = average_short_fades_per_second    * decision_window_seconds;

        for window_index = 1 : num_windows

            % Long deep blockages.
            if rand() < long_blockage_probability_per_window
                loss_dB = long_blockage_loss_dB_range(1) + (long_blockage_loss_dB_range(2) - long_blockage_loss_dB_range(1)) * rand();

                duration_seconds = long_blockage_duration_seconds_range(1) + (long_blockage_duration_seconds_range(2) - long_blockage_duration_seconds_range(1)) * rand();

                duration_windows = max(1, round(duration_seconds / decision_window_seconds));

                % Mostly flat, sometimes smooth-edged.
                if rand() < 0.75
                    shape = "flat";
                else
                    shape = "smooth";
                end

                [blockage_loss_dB_per_window, blockage_at_window] = add_blockage_event( ...
                    blockage_loss_dB_per_window, blockage_at_window, ...
                    window_index, duration_windows, loss_dB, shape);
            end

            % Medium partial dips
            if rand() < medium_dip_probability_per_window
                loss_dB = medium_dip_loss_dB_range(1) + (medium_dip_loss_dB_range(2) - medium_dip_loss_dB_range(1)) * rand();

                duration_seconds = medium_dip_duration_seconds_range(1) + (medium_dip_duration_seconds_range(2) - medium_dip_duration_seconds_range(1)) * rand();

                duration_windows = max(1, round(duration_seconds / decision_window_seconds));

                if rand() < 0.5
                    shape = "triangular";
                else
                    shape = "smooth";
                end

                [blockage_loss_dB_per_window, blockage_at_window] = add_blockage_event( ...
                    blockage_loss_dB_per_window, blockage_at_window, ...
                    window_index, duration_windows, loss_dB, shape);
            end

            % Short fades. Only a few windows long. Intended to test our controller's stability.
            if rand() < short_fade_probability_per_window
                loss_dB = short_fade_loss_dB_range(1) + (short_fade_loss_dB_range(2) - short_fade_loss_dB_range(1)) * rand();

                duration_seconds = short_fade_duration_seconds_range(1) + (short_fade_duration_seconds_range(2) - short_fade_duration_seconds_range(1)) * rand();

                duration_windows = max(1, round(duration_seconds / decision_window_seconds));
                shape = "smooth";

                [blockage_loss_dB_per_window, blockage_at_window] = add_blockage_event( ...
                    blockage_loss_dB_per_window, blockage_at_window, ...
                    window_index, duration_windows, loss_dB, shape);
            end
        end

        % Add a few deterministic events so the trace is guaranteed to contain a mix of behaviors across the 60-second simulation.
        forced_events = struct( ...
            "start_time_seconds", {24.0, 28.1, 29.0, 33.0, 45.0}, ...
            "duration_seconds",   {0.60, 0.05, 0.25, 0.70, 5.00}, ...
            "loss_dB",            {9,    16,    12,   8,    20}, ...
            "shape",              {"smooth", "smooth", "triangular", "triangular", "flat"});

        for event_index = 1 : numel(forced_events)
            start_window_index = max(1, round(forced_events(event_index).start_time_seconds / decision_window_seconds) + 1);
            duration_windows   = max(1, round(forced_events(event_index).duration_seconds / decision_window_seconds));

            [blockage_loss_dB_per_window, blockage_at_window] = add_blockage_event( ...
                blockage_loss_dB_per_window, blockage_at_window, ...
                start_window_index, duration_windows, ...
                forced_events(event_index).loss_dB, forced_events(event_index).shape);
        end

    end

    %
    % Forced blockage event
    %
    
    if enable_forced_blockage
        start_window_index = max(1, round(forced_start_time_seconds / decision_window_seconds) + 1);
        duration_windows   = max(1, round(forced_duration_seconds / decision_window_seconds));
        end_window_index   = min(num_windows, start_window_index + duration_windows - 1);
    
        blockage_loss_dB_per_window(start_window_index : end_window_index) = ...
            blockage_loss_dB_per_window(start_window_index : end_window_index) + forced_loss_dB;
    
        blockage_at_window(start_window_index : end_window_index) = true;
    end
    
    %
    % Plots
    %
    
    figure;
    grid on;
    hold on;
    set(gcf, "Color", "w", "InvertHardcopy", "off");
    plot(time_seconds_per_window, blockage_loss_dB_per_window, "LineWidth", 2);
    xlabel("Time (s)");
    ylabel("Blockage loss (dB)");
    title("Terrestrial blockage loss over time (Blockage severity: " + remove_underscores(blockage_severity) + ")");
    
    if ~isfolder("fig/terrestrial/blockage")
        mkdir("fig/terrestrial/blockage");
    end
    saveas(gcf, "fig/terrestrial/blockage/blockages_" + blockage_severity + ".png");
    close(gcf);

    %
    % Save data
    %
    
    save(blockage_loss_file, ...
        "blockage_loss_dB_per_window", "blockage_at_window", "time_seconds_per_window", ...
        "decision_window_seconds", ...
        "enable_random_blockage", "average_blockages_per_second", ...
        "blockage_loss_dB_range", "blockage_duration_seconds_range", ...
        "enable_forced_blockage", ...
        "forced_loss_dB", "forced_start_time_seconds", "forced_duration_seconds", ...
        "blockage_severity");
    
    disp("Wrote " + blockage_loss_file);

end

function tag = remove_underscores(underscored_tag)
    tag = strrep(underscored_tag, "_", " ");
end

function [blockage_loss_dB_per_window, blockage_at_window] = add_blockage_event(blockage_loss_dB_per_window, ...
                                                                                blockage_at_window,          ...
                                                                                start_window_index,          ...
                                                                                duration_windows,            ...
                                                                                peak_loss_dB,                ...
                                                                                shape)

    num_windows      = length(blockage_loss_dB_per_window);
    end_window_index = min(num_windows, start_window_index + duration_windows - 1);

    event_num_windows = end_window_index - start_window_index + 1;

    if event_num_windows <= 0
        return;
    end

    switch shape
        case "flat"
            shape_profile = ones(event_num_windows, 1);        % rectangular, abrupt dip

        case "triangular"
            if event_num_windows == 1
                shape_profile = 1;
            else
                x = linspace(-1, 1, event_num_windows).';
                shape_profile = 1 - abs(x);                    % triangle shape dip
            end

        case "smooth"
            if event_num_windows == 1
                shape_profile = 1;
            else
                x = linspace(0, 1, event_num_windows).';
                shape_profile = sin(pi * x) .^ 1.5;            % smooth rise and fall
            end

        otherwise
            error("Unknown blockage-event shape: %s", shape);
    end

    event_loss_dB = peak_loss_dB * shape_profile;

    blockage_loss_dB_per_window(start_window_index : end_window_index) = blockage_loss_dB_per_window(start_window_index : end_window_index) + event_loss_dB;
    blockage_at_window(start_window_index : end_window_index)          = blockage_at_window(start_window_index : end_window_index) | (event_loss_dB > 0.5);
end