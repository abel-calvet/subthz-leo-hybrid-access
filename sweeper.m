clear; close all; clc;
rng("default");

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% This script calls simulation(config) over a chosen set of configuration parameter combinations.
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Values to test during the sweep
sweep = struct();

%
% Simulation scenarios
%
sweep.weather_regime       = {"clear", "moderate_rain", "heavy_rain"};              % clear, moderate_rain, heavy_rain
sweep.blockage_severity    = {"mixed_blockage"};                                    % no_blockage, mild_blockage, severe_blockage, mixed_blockage
sweep.elevation_scenario   = {"high", "mid", "low"};                                % low, mid, high
sweep.use_external_trigger = {false};                                               % true, false

%
% Switching and coordination policies
%
sweep.steering_policy       = {"steer"};        % steer, terrestrial, satellite
sweep.coordination_mode     = {"traffic_splitting"};    % binary_switching, traffic_splitting

%
% Cost and stability
%
sweep.enable_handover_overhead      = {false};                   % true, false
sweep.enable_stability_constraints  = {true};                    % true, false

%
% Traffic model
%
sweep.traffic_profile            = {"bulk_upload"};                        % bulk_upload, steady
sweep.packet_size_bits           = {100000};
sweep.average_packets_per_second = {1000};
sweep.bulk_multiplier            = {1.8};
sweep.bulk_start_seconds         = {20};
sweep.bulk_end_seconds           = {35};


%
% Build configs
%
configs = build_configs(sweep);
fprintf("Number of runs: %d\n\n", numel(configs));

%
% Remove redundant baseline runs
%

for config_index = 1 : numel(configs)
    if configs{config_index}.steering_policy ~= "steer"
        configs{config_index}.coordination_mode = "not_applicable";
    end
end

config_keys = strings(numel(configs), 1);

for config_index = 1 : numel(configs)

    c = configs{config_index};

    config_keys(config_index) = strjoin([ ...
        "weather=" + string(c.weather_regime)
        "blockage=" + string(c.blockage_severity)
        "elevation=" + string(c.elevation_scenario)
        "trigger=" + string(c.use_external_trigger)
        "steering_policy=" + string(c.steering_policy)
        "coordination_mode=" + string(c.coordination_mode)
        "handover=" + string(c.enable_handover_overhead)
        "traffic=" + string(c.traffic_profile)
        "pps=" + string(c.average_packets_per_second)
        "bulk_mult=" + string(c.bulk_multiplier)
        "bulk_start=" + string(c.bulk_start_seconds)
        "bulk_end=" + string(c.bulk_end_seconds)
    ], ",");
end

[~, unique_indices] = unique(config_keys, "stable");
configs = configs(sort(unique_indices));

%
% Run sweep
%

for run_index = 1 : numel(configs)

    config = configs{run_index};

    fprintf("============================================================\n");
    fprintf("Run %d / %d", run_index, numel(configs));
    disp(config);

    results = simulation(config);

    fprintf("Completed run with tag: %s\n", results.run_tag);
    fprintf("Mean delay = %.3f ms, P95 = %.3f ms, P99 = %.3f ms\n\n", ...
        results.summary.mean_delay_ms, ...
        results.summary.p95_delay_ms, ...
        results.summary.p99_delay_ms);
end


%
% Build the simulation config helper
%
function configs = build_configs(sweep)

% This function builds a config struct for the simulation for every
% Cartesian product combination of the parameters listed in sweep.
% If a field has an empty list, the field is omitted from the config
% which lets simulation(config) use the default value.

field_names  = fieldnames(sweep);
field_values = cell(numel(field_names), 1);
num_choices_per_field = ones(numel(field_names), 1);

for field_index = 1 : numel(field_names)

    field_values{field_index} = sweep.(field_names{field_index});  % List of values for a given config field
    
    if isempty(field_values{field_index})
        num_choices_per_field(field_index) = 1;
    else
        num_choices_per_field(field_index) = numel(field_values{field_index});
    end
end


num_configs = prod(num_choices_per_field);  % Number of configs (Cartesian product)

configs = cell(num_configs, 1);

for config_index = 1 : num_configs

    config = struct();

    remainder = config_index - 1;

    for field_index = 1 : numel(field_names)

        values = field_values{field_index};
        num_choices = num_choices_per_field(field_index);
        
        choice_index = mod(remainder, num_choices) + 1;
        remainder    = floor(remainder / num_choices);

        if isempty(values)   % Empty list of values => omit field
            continue
        end

        field_name = field_names{field_index};

        if iscell(values)
            config.(field_name) = values{choice_index};
        else
            config.(field_name) = values(choice_index);
        end
    end

    configs{config_index} = config;
end

end