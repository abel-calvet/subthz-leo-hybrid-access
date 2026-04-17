clear; close all; clc;
rng("default");

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% A script to analyze the data generated after running sweeper.
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

enable_debug_print = false;    % More detailed console output prints

% Output files

results_directory  = "data/results";
analysis_directory = "analysis";
tables_directory   = fullfile(analysis_directory, "tables");
figures_directory  = fullfile(analysis_directory, "fig");
plots_directory    = fullfile(analysis_directory, "plots");

% Create directories if they don't exist
if ~isfolder(analysis_directory)
    mkdir(analysis_directory);
end
if ~isfolder(tables_directory)
    mkdir(tables_directory);
end
if ~isfolder(figures_directory)
    mkdir(figures_directory);
end
if ~isfolder(plots_directory)
    mkdir(plots_directory);
end

% Figure defaults
set(groot, "defaultFigureColor", "w");
set(groot, "defaultAxesColor", "w");

set(groot, "defaultAxesFontName", "Helvetica");
set(groot, "defaultTextFontName", "Helvetica");
set(groot, "defaultAxesFontSize", 11);
set(groot, "defaultTextFontSize", 11);

set(groot, "defaultAxesLineWidth", 1.0);
set(groot, "defaultLineLineWidth", 1.6);

set(groot, "defaultAxesBox", "on");
set(groot, "defaultAxesTickDir", "out");
set(groot, "defaultAxesTitleFontWeight", "bold");
set(groot, "defaultLegendBox", "off");

% Force black foreground colors
set(groot, "defaultAxesXColor", "k");
set(groot, "defaultAxesYColor", "k");
set(groot, "defaultAxesZColor", "k");
set(groot, "defaultTextColor", "k");
set(groot, "defaultLegendTextColor", "k");
set(groot, "defaultColorbarColor", "k");

% Make grid readable on white background
set(groot, "defaultAxesGridColor", [0.82 0.82 0.82]);
set(groot, "defaultAxesMinorGridColor", [0.90 0.90 0.90]);

%
% Load results
%

% Results are stored as .mat files in data/results
result_files = dir(fullfile(results_directory, "results_*.mat"));

if isempty(result_files)
    error("No result files found in %s.", results_directory);
end

rows = struct([]);   % Build array of rows

for file_index = 1 : numel(result_files)

    file_path = fullfile(result_files(file_index).folder, result_files(file_index).name);

    file_data = load(file_path, "results");

    if ~isfield(file_data, "results")
        warning("Skipping file with no results struct: %s", file_path);
        continue;
    end

    results = file_data.results;
    config  = results.config;
    summary = results.summary;
    traces  = results.traces;

    row = struct();

    % File metadata
    row.file_name       = string(result_files(file_index).name);
    row.file_path       = string(file_path);
    row.last_write_time = datetime(result_files(file_index).datenum, "ConvertFrom", "datenum");
    
    % Tags
    row.run_tag        = string(get_struct_field(results, "run_tag", ""));
    row.scenario_tag   = string(get_struct_field(results, "scenario_tag", ""));
    row.region_quality = string(get_struct_field(results, "region_quality", ""));

    % Scenario config
    row.weather_regime       = string(get_struct_field(config, "weather_regime", ""));
    row.blockage_severity    = string(get_struct_field(config, "blockage_severity", ""));
    row.elevation_scenario   = string(get_struct_field(config, "elevation_scenario", ""));
    row.use_external_trigger = logical(get_struct_field(config, "use_external_trigger", false));


    % Switch / coordination policy config
    row.steering_policy       = string(get_struct_field(config, "steering_policy", ""));
    row.coordination_mode     = string(get_struct_field(config, "coordination_mode", ""));

    % Remove policy combinations not meaningful for comparisons
    % In only terrestrial / only satellite, coordination mode is not meaningful
    row.coordination_mode     = normalize_coordination_mode(row.steering_policy, row.coordination_mode);

    % Cost and stability toggles
    row.enable_stability_constraints            = logical(get_struct_field(config, "enable_stability_constraints", false));
    row.enable_handover_overhead                = logical(get_struct_field(config, "enable_handover_overhead", false));

    % Traffic config
    row.traffic_profile            = string(get_struct_field(config, "traffic_profile", ""));
    row.packet_size_bits           = double(get_struct_field(config, "packet_size_bits", NaN));
    row.average_packets_per_second = double(get_struct_field(config, "average_packets_per_second", NaN));
    row.bulk_multiplier            = double(get_struct_field(config, "bulk_multiplier", NaN));
    row.bulk_start_seconds         = double(get_struct_field(config, "bulk_start_seconds", NaN));
    row.bulk_end_seconds           = double(get_struct_field(config, "bulk_end_seconds", NaN));

    % Summary metrics
    row.num_switches         = double(get_struct_field(summary, "num_switches", NaN));
    row.num_fraction_changes = double(get_struct_field(summary, "num_fraction_changes", NaN));

    row.mean_delay_ms = double(get_struct_field(summary, "mean_delay_ms", NaN));
    row.p50_delay_ms  = double(get_struct_field(summary, "p50_delay_ms", NaN));
    row.p95_delay_ms  = double(get_struct_field(summary, "p95_delay_ms", NaN));
    row.p99_delay_ms  = double(get_struct_field(summary, "p99_delay_ms", NaN));
    row.max_delay_ms  = double(get_struct_field(summary, "max_delay_ms", NaN));

    row.final_queue_bits = double(get_struct_field(summary, "final_queue_bits", NaN));
    row.max_queue_bits   = double(get_struct_field(summary, "max_queue_bits", NaN));

    row.mean_satellite_traffic_fraction   = double(get_struct_field(summary, "mean_satellite_traffic_fraction", NaN));
    row.mean_terrestrial_traffic_fraction = double(get_struct_field(summary, "mean_terrestrial_traffic_fraction", NaN));

    row.total_served_bits_satellite   = double(get_struct_field(summary, "total_served_bits_satellite", NaN));
    row.total_served_bits_terrestrial = double(get_struct_field(summary, "total_served_bits_terrestrial", NaN));
    row.total_served_bits             = double(get_struct_field(summary, "total_served_bits", NaN));

    row.bulk_p95_ms   = double(get_struct_field(summary, "bulk_p95_ms", NaN));
    row.bulk_p99_ms   = double(get_struct_field(summary, "bulk_p99_ms", NaN));
    row.normal_p95_ms = double(get_struct_field(summary, "normal_p95_ms", NaN));
    row.normal_p99_ms = double(get_struct_field(summary, "normal_p99_ms", NaN));

    %
    % Derived metrics
    %

    % Total number of bits that arrived over the course of the entire simulation
    arriving_bits_per_window = get_struct_field(traces, "arriving_bits_per_window", []);
    if isempty(arriving_bits_per_window)
        row.total_arriving_bits = NaN;
    else
        row.total_arriving_bits = sum(double(arriving_bits_per_window), "omitnan");
    end

    % Final queue bits, max queue bits, total number of served bits
    row.final_queue_Mbits = row.final_queue_bits / 1e6;
    row.max_queue_Mbits   = row.max_queue_bits / 1e6;
    row.total_served_Mbits = row.total_served_bits / 1e6;

    % Fraction of bits served by satellite
    if isfinite(row.total_served_bits) && row.total_served_bits > 0
        row.served_bits_satellite_fraction = row.total_served_bits_satellite / row.total_served_bits;
    else
        row.served_bits_satellite_fraction = NaN;
    end

    % Delivery ratio = how much of the offered load was served
    % Undelivered ratio = fraction of bits unserved by the end of the simulation
    if isfinite(row.total_arriving_bits) && row.total_arriving_bits > 0
        row.delivery_ratio = row.total_served_bits / row.total_arriving_bits;
        row.undelivered_ratio = row.final_queue_bits / row.total_arriving_bits;
    else
        row.delivery_ratio = NaN;
        row.undelivered_ratio = NaN;
    end

    if row.coordination_mode == "binary_switching"
        row.action_count = row.num_switches;
    else
        row.action_count = row.num_fraction_changes;
    end

    % Keys for run comparisons (matched to the same settings)
    row.comparison_key            = build_comparison_key(row);
    row.stability_key             = build_stability_key(row);
    row.cost_key                  = build_cost_key(row);
    row.heatmap_key               = build_heatmap_key(row);

    if isempty(rows)
        rows = row;
    else
        rows(end + 1, 1) = row;
    end
end

% Create master table
summary_table = struct2table(rows);

if isempty(summary_table)
    error("Could not load summary table");
end

% Duplicate run_tags
summary_table = sortrows(summary_table, ["run_tag", "last_write_time"], ["ascend", "ascend"]);
[~, latest_indices] = unique(summary_table.run_tag, "last");
summary_table = summary_table(sort(latest_indices), :);

% Sort table for readability
summary_table = sortrows(summary_table, ["elevation_scenario", "weather_regime", "steering_policy", "coordination_mode", "last_write_time"]);

disp("Loaded result files: ");
disp(height(summary_table));

%
% Save master summary table to CSV file
%
writetable(summary_table, fullfile(tables_directory, "results_summary.csv"));
save(fullfile(analysis_directory, "results_summary.mat"), "summary_table");
disp("Wrote analysis/tables/results_summary.csv");


disp("=== terrestrial baseline rows ===");
disp(summary_table(summary_table.steering_policy == "terrestrial", ...
    ["run_tag", "coordination_mode", ...
     "mean_satellite_traffic_fraction", "mean_delay_ms", "p95_delay_ms"]));

disp("=== satellite baseline rows ===");
disp(summary_table(summary_table.steering_policy == "satellite", ...
    ["run_tag", "coordination_mode", ...
     "mean_satellite_traffic_fraction", "mean_delay_ms", "p95_delay_ms"]));

%
% Best and worst run tables (for switching and splitting simulations)
%

switch_split_rows = summary_table(summary_table.steering_policy == "steer", :);

if ~isempty(switch_split_rows)
    
    switch_split_rows_ascending = sortrows(switch_split_rows, ["p95_delay_ms", "mean_delay_ms"], ["ascend", "ascend"]);
    switch_split_rows_descending = sortrows(switch_split_rows, ["p95_delay_ms", "mean_delay_ms"], ["descend", "descend"]);
    
    top_n = min(10, height(switch_split_rows));  % Top 10

    best_rows = switch_split_rows_ascending(1 : top_n, :);    % Top 10 lowest-delay rows
    worst_rows = switch_split_rows_descending(1 : top_n, :);  % Top 10 highest-delay rows

    writetable(best_rows, fullfile(tables_directory, "best_runs_by_p95.csv"));
    writetable(worst_rows, fullfile(tables_directory, "worst_runs_by_p95.csv"));
    
    disp("Wrote the best and worst run's table.")
end

%
% Compare steering vs. no steering (baseline)
%

% Here, we want to make sure that we get an overall gain out of switching or splitting.
% If it turns out, for example, that we had not done any switching / splitting to
% satellite and we had stayed on terrestrial the whole entire time and gotten the same or
% better performance, this means that our model has failed.

% Build the steer vs. baseline (only terrestrial, only satellite) table
steer_vs_baseline_table = build_comparison_table(summary_table);

if ~isempty(steer_vs_baseline_table)
    
    writetable(steer_vs_baseline_table, fullfile(tables_directory, "steer_vs_baseline_comparisons.csv"));
    disp("Wrote analysis/tables/steer_vs_baseline_comparisons.csv");

    % Console print out summary
    steer_vs_terrestrial_rows = steer_vs_baseline_table(steer_vs_baseline_table.baseline_policy == "terrestrial", :);
    steer_vs_satellite_rows = steer_vs_baseline_table(steer_vs_baseline_table.baseline_policy == "satellite", :);

    if ~isempty(steer_vs_terrestrial_rows)
        num_steer_vs_terrestrial_p95_wins = sum(steer_vs_terrestrial_rows.p95_delay_improvement_ms > 0);
        fprintf("Switching/splitting beats always-terrestrial in P95 delay in %d / %d matched comparisons.\n", num_steer_vs_terrestrial_p95_wins, height(steer_vs_terrestrial_rows));
    end

    if ~isempty(steer_vs_satellite_rows)
        num_steer_vs_satellite_p95_wins = sum(steer_vs_satellite_rows.p95_delay_improvement_ms > 0);
        fprintf("Switching/splitting beats always-satellite in P95 delay in %d / %d matched comparisons.\n", num_steer_vs_satellite_p95_wins, height(steer_vs_satellite_rows));
    end

else
    disp("No matched steer vs. baseline comparison available at this time.")
end

disp("=== steer vs baseline rows ===");
disp(steer_vs_baseline_table(:, ...
    ["baseline_policy", "run_tag_baseline", ...
     "baseline_mean_satellite_fraction", ...
     "baseline_mean_delay_ms", "baseline_p95_delay_ms"]));

%
% Compare stabilized switching / splitting vs. unstabilized switching / splitting
%

stability_table = build_stability_table( ...
    summary_table, "enable_stability_constraints", ...
    "stability_key", "stability");

if ~isempty(stability_table)
    writetable(stability_table, fullfile(tables_directory, "stability_comparisons.csv"));
    disp("Wrote analysis/tables/stability_comparisons.csv");

    % Console print out summary
    num_stabilized_p95_wins = sum(stability_table.p95_delay_improvement_ms > 0);
    fprintf("Stabilized beats unstabilized in P95 delay in %d / %d matched comparisons.\n", num_stabilized_p95_wins, height(stability_table));
    num_stabilized_mean_delay_wins = sum(stability_table.mean_delay_improvement_ms > 0);
    fprintf("Stabilized beats unstabilized in mean delay in %d / %d matched comparisons.\n", num_stabilized_mean_delay_wins, height(stability_table));
    
else
    disp("No matched stability pairs were found for comparison.");
end

%
% Compare physical costs vs. no physical costs
%

cost_table = build_cost_table(summary_table);

if ~isempty(cost_table)
    writetable(cost_table, fullfile(tables_directory, "cost_vs_no_cost_comparisons.csv"));
    disp("Wrote analysis/tables/cost_vs_no_cost_comparisons.csv");

    num_no_cost_p95_wins = sum(cost_table.p95_delay_improvement_ms > 0);
    fprintf("No-reconfiguration-cost runs beat cost-ful runs in P95 delay in %d / %d matched comparisons.\n", num_no_cost_p95_wins, height(cost_table));

    num_no_cost_mean_delay_wins = sum(cost_table.mean_delay_improvement_ms > 0);
    fprintf("No-reconfiguration-cost runs beat cost-ful runs in mean delay in %d / %d matched comparisons.\n", num_no_cost_mean_delay_wins, height(cost_table));
else
    disp("No matched no-cost vs. cost-ful pairs were found for comparison.");
end

%
% Build one scenario-wise comparison summary "overview" table (PNG)
%

overview_table = build_overview_table(steer_vs_baseline_table, ...
                                      stability_table, ...
                                      cost_table);

if ~isempty(overview_table)
    writetable(overview_table, fullfile(tables_directory, "comparison_overview.csv"));
    disp("Wrote analysis/tables/comparison_overview.csv");

    overview_table_rounded = round_table(overview_table, 2);

    disp("Overview summary:");
    disp(overview_table_rounded);

    overview_png_table = overview_table_rounded(:, ...
    ["label", ...
     "num_scenarios", ...
     "p95_wins", "p95_losses", "p95_ties", ...
     "mean_delay_wins", "mean_delay_losses", "mean_delay_ties", ...
     "best_p95_delta_ms", "worst_p95_delta_ms", ...
     "best_mean_delta_ms", "worst_mean_delta_ms", ...
     "best_max_queue_delta_Mbits", "worst_max_queue_delta_Mbits", ...
     "best_p95_scenario", "worst_p95_scenario", ...
     "best_p95_scenario_satellite_fraction_change", ...
     "worst_p95_scenario_satellite_fraction_change", ...
     "num_failure_scenarios"]);

    overview_headers = [ ...
        "label"
        "N"
        "p95" + newline + "wins"
        "p95" + newline + "losses"
        "p95" + newline + "ties"
        "mean" + newline + "wins"
        "mean" + newline + "losses"
        "mean" + newline + "ties"
        "best p95" + newline + "delta (ms)"
        "worst p95" + newline + "delta (ms)"
        "best mean" + newline + "delta (ms)"
        "worst mean" + newline + "delta (ms)"
        "best max q" + newline + "delta (Mb)"
        "worst max q" + newline + "delta (Mb)"
        "best p95" + newline + "scenario"
        "worst p95" + newline + "scenario"
        "best p95 sat" + newline + "frac change"
        "worst p95 sat" + newline + "frac change"
        "failure" + newline + "scenarios"
    ];

    overview_column_weights = [ ...
        1.6, ...
        0.8, ...
        0.8, 0.8, 0.8, ...
        0.9, 0.9, 0.9, ...
        1.1, 1.1, ...
        1.1, 1.1, ...
        1.2, 1.2, ...
        1.2, 1.2, ...
        1.4, 1.4, ...
        1.0];

    save_table_png(overview_png_table, ...
        {"Scenario-wise overview comparison summary", ...
        "(wins/losses and worst-case deltas across scenarios)"}, ...
        fullfile(figures_directory, "comparison_overview.png"), ...
        overview_headers, overview_column_weights);
    
    disp("Wrote analysis/fig/comparison_overview.png");
else
    disp("No overview summary could be built.");
end

%
% Build a failure-only table (PNG)
%

failure_table = build_failure_table(steer_vs_baseline_table, ...
                                    stability_table, ...
                                    cost_table);

if ~isempty(failure_table)
    writetable(failure_table, fullfile(tables_directory, "comparison_failures.csv"));
    disp("Wrote analysis/tables/comparison_failures.csv");

    failure_table_rounded = round_table(failure_table, 2);

    disp("Failure scenarios:");
    disp(failure_table_rounded(:, ["comparison", "coordination", "scenario", ...
                                   "mean_delay_delta_ms", "p95_delay_delta_ms", ...
                                   "max_queue_delta_Mbits", "mean_satellite_fraction_delta"]));

    save_table_png( ...
        failure_table_rounded(:, ["comparison", "coordination", "scenario", ...
                                  "mean_delay_delta_ms", "p95_delay_delta_ms", ...
                                  "max_queue_delta_Mbits", "mean_satellite_fraction_delta"]), ...
        {"Failure scenarios", ...
         "(rows where the tested policy loses on mean or tail delay)"}, ...
        fullfile(figures_directory, "comparison_failures.png"));

    disp("Wrote analysis/fig/comparison_failures.png");
else
    disp("No failure scenarios were found.");
end

%
% Inspect scenario effects across weather and elevation regimes
%

plot_heatmaps(summary_table, figures_directory);

disp("Created heatmap plots to visualize the effects of weather and elevation regimes");

%
% Comparison delta heatmaps
%

plot_comparison_heatmaps( ...
    steer_vs_baseline_table, ...
    stability_table, ...
    cost_table, ...
    figures_directory);

disp("Created comparison delta heatmaps over weather and elevation.");

%
% Diagnostic plots
%

plot_stability_tradeoff(summary_table, plots_directory);
plot_best_worst_steer_vs_terrestrial(summary_table, steer_vs_baseline_table, plots_directory);

%
% Debug printouts
%

if enable_debug_print

    disp("============================================================");
    disp("Debug summary");
    disp("============================================================");

    fprintf("Number of result rows loaded: %d\n", height(summary_table));

    if exist("steer_vs_baseline_table", "var") && ~isempty(steer_vs_baseline_table)
        fprintf("Matched steer-vs-baseline comparisons: %d\n", height(steer_vs_baseline_table));
    else
        fprintf("Matched steer-vs-baseline comparisons: 0\n");
    end

    if exist("stability_table", "var") && ~isempty(stability_table)
        fprintf("Matched stability comparisons: %d\n", height(stability_table));
    else
        fprintf("Matched stability comparisons: 0\n");
    end

    if exist("cost_table", "var") && ~isempty(cost_table)
        fprintf("Matched no-cost-vs-cost comparisons: %d\n", height(cost_table));
    else
        fprintf("Matched no-cost-vs-cost comparisons: 0\n");
    end

    disp(" ");
    disp("============================================================");
    disp("Overview Table");
    disp("============================================================");
    if exist("overview_table", "var") && ~isempty(overview_table)
        disp(round_table(overview_table, 3));
    else
        disp("overview_table is empty.");
    end

    disp(" ");
    disp("============================================================");
    disp("Failure table");
    disp("============================================================");
    if exist("failure_table", "var") && ~isempty(failure_table)
        disp(round_table(failure_table(:, ...
            ["comparison", "coordination", "scenario", ...
             "mean_delay_delta_ms", "p95_delay_delta_ms", ...
             "p99_delay_delta_ms", "max_queue_delta_Mbits", ...
             "mean_satellite_fraction_delta"]), 3));
    else
        disp("failure_table is empty.");
    end

    if exist("steer_vs_baseline_table", "var") && ~isempty(steer_vs_baseline_table)

        disp(" ");
        disp("============================================================");
        disp("Worst steer vs. baseline cases");
        disp("============================================================");

        sorted_rows = sortrows(steer_vs_baseline_table, "p95_delay_improvement_ms", "ascend");
        disp(round_table(sorted_rows(1 : min(12, height(sorted_rows)), ...
            ["baseline_policy", "coordination_mode", ...
             "elevation_scenario", "weather_regime", "blockage_severity", ...
             "mean_delay_improvement_ms", "p95_delay_improvement_ms", ...
             "p99_delay_improvement_ms", "max_queue_reduction_Mbits", ...
             "mean_satellite_fraction_change"]), 3));
    end

    if exist("stability_table", "var") && ~isempty(stability_table)

        disp(" ");
        disp("============================================================");
        disp("Worst stabilized vs. unstabilized cases");
        disp("============================================================");

        sorted_rows = sortrows(stability_table, "p95_delay_improvement_ms", "ascend");
        disp(round_table(sorted_rows(1 : min(12, height(sorted_rows)), ...
            ["coordination_mode", ...
             "elevation_scenario", "weather_regime", "blockage_severity", ...
             "mean_delay_improvement_ms", "p95_delay_improvement_ms", ...
             "p99_delay_improvement_ms", "max_queue_reduction_Mbits", ...
             "mean_satellite_fraction_change"]), 3));
    end

    if exist("cost_table", "var") && ~isempty(cost_table)

        disp(" ");
        disp("============================================================");
        disp("Worst (reconfiguration overhead) costless vs. cost-ful cases");
        disp("============================================================");

        sorted_rows = sortrows(cost_table, "p95_delay_improvement_ms", "ascend");
        disp(round_table(sorted_rows(1 : min(12, height(sorted_rows)), ...
            ["coordination_mode", ...
             "elevation_scenario", "weather_regime", "blockage_severity", ...
             "mean_delay_improvement_ms", "p95_delay_improvement_ms", ...
             "p99_delay_improvement_ms", "max_queue_reduction_Mbits", ...
             "mean_satellite_fraction_change"]), 3));
    end
end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 
% Helper functions
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function value = get_struct_field(s, field_name, default_value)

    if isfield(s, field_name)
        value = s.(field_name);
    else
        value = default_value;
    end

end


function coordination_mode = normalize_coordination_mode(steering_policy, coordination_mode_)

    if steering_policy == "steer"
        coordination_mode = coordination_mode_;
    else
        coordination_mode = "not_applicable";  % If only terrestrial or only satellite, coordination is N/A
    end

end


function tag = bool_to_tag(flag)

    if flag
        tag = "on";
    else
        tag = "off";
    end

end


function key = build_comparison_key(row)

    % Key for matching a steer run to its corresponding baseline runs.
    % It only matches fields shared by both steer and baseline policies.

    % This key helps us compare result rows where the only difference is the switching policy
    % (steer vs. only terrestrial or only satellite) keeping everything else the same.

    key = strjoin([ ...
        "weather=" + row.weather_regime
        "blockage=" + row.blockage_severity
        "elevation=" + row.elevation_scenario
        "trigger=" + bool_to_tag(row.use_external_trigger)
        "handover=" + bool_to_tag(row.enable_handover_overhead)
        "stable=" + bool_to_tag(row.enable_stability_constraints)
        "traffic=" + row.traffic_profile
        "pps=" + string(row.average_packets_per_second)
        "bulk_mult=" + string(row.bulk_multiplier)
        "bulk_start=" + string(row.bulk_start_seconds)
        "bulk_end=" + string(row.bulk_end_seconds)
    ], ",");

end


function key = build_stability_key(row)

    % Key for matched stabilized vs. unstabilized comparisons
    % enable_stability_constraints is excluded on purpose.

    if row.steering_policy ~= "steer"
        key = "";   % key = "" means we do not use that row for comparisons.
        return;
    end

    key = strjoin([
        "weather=" + row.weather_regime
        "blockage=" + row.blockage_severity
        "elevation=" + row.elevation_scenario
        "trigger=" + bool_to_tag(row.use_external_trigger)
        "steering_policy=" + row.steering_policy
        "coordination_mode=" + row.coordination_mode
        "handover=" + bool_to_tag(row.enable_handover_overhead)
        "traffic=" + row.traffic_profile
        "pps=" + string(row.average_packets_per_second)
        "bulk_mult=" + string(row.bulk_multiplier)
        "bulk_start=" + string(row.bulk_start_seconds)
        "bulk_end=" + string(row.bulk_end_seconds)
    ], ",");

end


function key = build_heatmap_key(row)

    % Heatmaps show weather and elevation variations for one fixed policy family.

    % We exclude weather and elevation regimes from the key on purpose.

    if row.steering_policy ~= "steer"   % Exclude rows with no switching / splitting
        key = "";
        return;
    end

    key = strjoin([
        "blockage=" + row.blockage_severity
        "trigger=" + bool_to_tag(row.use_external_trigger)
        "coordination_mode=" + row.coordination_mode
        "handover=" + bool_to_tag(row.enable_handover_overhead)
        "stable=" + bool_to_tag(row.enable_stability_constraints)
        "traffic=" + row.traffic_profile
        "pps=" + string(row.average_packets_per_second)
        "bulk_mult=" + string(row.bulk_multiplier)
    ], ",");

end

function key = build_cost_key(row)

    %
    % Key for matched comparisons between:
    %   no processing cost to switching
    %   processing cost enabled (reconfiguration overhead)
    %
    % We isolate switching cost.

    if row.steering_policy ~= "steer"
        key = "";   % Skip
        return;
    end

    key = strjoin([
        "weather=" + row.weather_regime
        "blockage=" + row.blockage_severity
        "elevation=" + row.elevation_scenario
        "trigger=" + bool_to_tag(row.use_external_trigger)
        "steering_policy=" + row.steering_policy
        "coordination_mode=" + row.coordination_mode
        "stable=" + bool_to_tag(row.enable_stability_constraints)
        "traffic=" + row.traffic_profile
        "pps=" + string(row.average_packets_per_second)
        "bulk_mult=" + string(row.bulk_multiplier)
        "bulk_start=" + string(row.bulk_start_seconds)
        "bulk_end=" + string(row.bulk_end_seconds)
    ], ",");

end


function row = get_latest_row(rows)

    if isempty(rows)
        row = rows;
        return;
    end

    if ~ismember("last_write_time", string(rows.Properties.VariableNames))
        row = rows(1, :);
        return;
    end

    [~, index] = max(rows.last_write_time);
    row = rows(index, :);

end


function comparison_table = build_comparison_table(summary_table)

    % This function builds a comparison table to compare switching/splitting
    % to a baseline (always terrestrial or always satellite) policy.
    %
    % We compare every steer run separately against the matching always-terrestrial and always-satellite baselines.
    %

    rows = struct([]);

    steer_rows = summary_table(summary_table.steering_policy == "steer", :);

    for steer_index = 1 : height(steer_rows)

        steer_row = steer_rows(steer_index, :);
        key = steer_row.comparison_key;

        matched_rows = summary_table(summary_table.comparison_key == key, :);

        baseline_policies = ["terrestrial", "satellite"];

        for baseline_index = 1 : numel(baseline_policies)

            baseline_policy = baseline_policies(baseline_index);
            baseline_row = get_latest_row(matched_rows(matched_rows.steering_policy == baseline_policy, :));

            if isempty(baseline_row)
                continue;
            end

            row = struct();

            row.comparison_key = key;

            row.weather_regime     = steer_row.weather_regime;
            row.blockage_severity  = steer_row.blockage_severity;
            row.elevation_scenario = steer_row.elevation_scenario;

            row.coordination_mode     = steer_row.coordination_mode;

            row.baseline_policy  = baseline_policy;
            row.run_tag_steer    = steer_row.run_tag;
            row.run_tag_baseline = baseline_row.run_tag;

            row.steer_mean_delay_ms            = steer_row.mean_delay_ms;
            row.baseline_mean_delay_ms         = baseline_row.mean_delay_ms;
            row.mean_delay_improvement_ms      = baseline_row.mean_delay_ms - steer_row.mean_delay_ms;
            row.mean_delay_improvement_percent = 100 * (baseline_row.mean_delay_ms - steer_row.mean_delay_ms) / max(abs(baseline_row.mean_delay_ms), eps);

            row.steer_p95_delay_ms            = steer_row.p95_delay_ms;
            row.baseline_p95_delay_ms         = baseline_row.p95_delay_ms;
            row.p95_delay_improvement_ms      = baseline_row.p95_delay_ms - steer_row.p95_delay_ms;
            row.p95_delay_improvement_percent = 100 * (baseline_row.p95_delay_ms - steer_row.p95_delay_ms) / max(abs(baseline_row.p95_delay_ms), eps);

            row.steer_p99_delay_ms            = steer_row.p99_delay_ms;
            row.baseline_p99_delay_ms         = baseline_row.p99_delay_ms;
            row.p99_delay_improvement_ms      = baseline_row.p99_delay_ms - steer_row.p99_delay_ms;
            row.p99_delay_improvement_percent = 100 * (baseline_row.p99_delay_ms - steer_row.p99_delay_ms) / max(abs(baseline_row.p99_delay_ms), eps);

            row.steer_max_queue_Mbits         = steer_row.max_queue_Mbits;
            row.baseline_max_queue_Mbits      = baseline_row.max_queue_Mbits;
            row.max_queue_reduction_Mbits     = baseline_row.max_queue_Mbits - steer_row.max_queue_Mbits;
            row.max_queue_reduction_percent   = 100 * (baseline_row.max_queue_Mbits - steer_row.max_queue_Mbits) / max(abs(baseline_row.max_queue_Mbits), eps);

            row.steer_final_queue_Mbits       = steer_row.final_queue_Mbits;
            row.baseline_final_queue_Mbits    = baseline_row.final_queue_Mbits;
            row.final_queue_reduction_Mbits   = baseline_row.final_queue_Mbits - steer_row.final_queue_Mbits;

            row.steer_action_count            = steer_row.action_count;
            row.baseline_action_count         = baseline_row.action_count;

            row.steer_mean_satellite_fraction    = steer_row.mean_satellite_traffic_fraction;
            row.baseline_mean_satellite_fraction = baseline_row.mean_satellite_traffic_fraction;
            row.mean_satellite_fraction_change   = row.steer_mean_satellite_fraction - row.baseline_mean_satellite_fraction;

            if isempty(rows)
                rows = row;
            else
                rows(end + 1, 1) = row;
            end
        end
    end

    if isempty(rows)
        comparison_table = table();
    else
        comparison_table = struct2table(rows);
        comparison_table = sortrows(comparison_table, ["baseline_policy", "coordination_mode", "elevation_scenario", "weather_regime"]);
    end

end


function comparison_table = build_stability_table(...
    summary_table, stability_toggle_field_name, key_field_name, comparison_type)

    %
    % This function builds a comparison table to compare stabilized vs. unstabilized
    % decision logic.
    %

    rows = struct([]);

    summary_table = summary_table(summary_table.steering_policy == "steer", :);

    keys = unique(summary_table.(key_field_name));

    for key_index = 1 : numel(keys)

        key = keys(key_index);
        if strlength(key) == 0
            continue;   % Skip "" keys
        end

        key_rows = summary_table(summary_table.(key_field_name) == key, :);

        off_row = get_latest_row(key_rows(~key_rows.(stability_toggle_field_name), :));
        on_row  = get_latest_row(key_rows(key_rows.(stability_toggle_field_name), :));

        if isempty(off_row) || isempty(on_row)
            continue;
        end

        row = struct();

        row.comparison_type = string(comparison_type);
        row.comparison_key  = key;

        row.weather_regime     = on_row.weather_regime;
        row.blockage_severity  = on_row.blockage_severity;
        row.elevation_scenario = on_row.elevation_scenario;

        row.coordination_mode     = on_row.coordination_mode;

        row.run_tag_off = off_row.run_tag;
        row.run_tag_on  = on_row.run_tag;

        row.mean_delay_ms_off              = off_row.mean_delay_ms;
        row.mean_delay_ms_on               = on_row.mean_delay_ms;
        row.mean_delay_improvement_ms      = off_row.mean_delay_ms - on_row.mean_delay_ms;
        row.mean_delay_improvement_percent = 100 * (off_row.mean_delay_ms - on_row.mean_delay_ms) / max(abs(off_row.mean_delay_ms), eps);

        row.p95_delay_ms_off              = off_row.p95_delay_ms;
        row.p95_delay_ms_on               = on_row.p95_delay_ms;
        row.p95_delay_improvement_ms      = off_row.p95_delay_ms - on_row.p95_delay_ms;
        row.p95_delay_improvement_percent = 100 * (off_row.p95_delay_ms - on_row.p95_delay_ms) / max(abs(off_row.p95_delay_ms), eps);

        row.p99_delay_ms_off              = off_row.p99_delay_ms;
        row.p99_delay_ms_on               = on_row.p99_delay_ms;
        row.p99_delay_improvement_ms      = off_row.p99_delay_ms - on_row.p99_delay_ms;
        row.p99_delay_improvement_percent = 100 * (off_row.p99_delay_ms - on_row.p99_delay_ms) / max(abs(off_row.p99_delay_ms), eps);

        row.max_queue_Mbits_off       = off_row.max_queue_Mbits;
        row.max_queue_Mbits_on        = on_row.max_queue_Mbits;
        row.max_queue_reduction_Mbits = off_row.max_queue_Mbits - on_row.max_queue_Mbits;

        row.action_count_off    = off_row.action_count;
        row.action_count_on     = on_row.action_count;
        row.action_count_change = on_row.action_count - off_row.action_count;

        row.mean_satellite_fraction_off    = off_row.mean_satellite_traffic_fraction;
        row.mean_satellite_fraction_on     = on_row.mean_satellite_traffic_fraction;
        row.mean_satellite_fraction_change = on_row.mean_satellite_traffic_fraction - off_row.mean_satellite_traffic_fraction;

        if isempty(rows)
            rows = row;
        else
            rows(end + 1, 1) = row;
        end
    end

    if isempty(rows)
        comparison_table = table();
    else
        comparison_table = struct2table(rows);
        comparison_table = sortrows(comparison_table, ["coordination_mode", "elevation_scenario", "weather_regime"]);
    end

end


function comparison_table = build_cost_table(summary_table)

    %
    % This function builds a table for comparing simulation runs where reconfiguration
    % overhead due to switching is modeled vs. not.
    %

    rows = struct([]);

    summary_table = summary_table(summary_table.steering_policy == "steer", :);

    keys = unique(summary_table.cost_key);

    for key_index = 1 : numel(keys)

        key = keys(key_index);
        if strlength(key) == 0
            continue;   % We skip "" keys
        end

        key_rows = summary_table(summary_table.cost_key == key, :);

        % Isolate switching cost only
        %   no switching processing cost   => enable_handover_overhead = false
        %   switch cost processing enabled => enable_handover_overhead = true
        no_cost_row = get_latest_row(key_rows(~key_rows.enable_handover_overhead, :));
        costful_row = get_latest_row(key_rows(key_rows.enable_handover_overhead, :));

        if isempty(no_cost_row) || isempty(costful_row)
            continue;
        end

        row = struct();

        row.comparison_type = "no_costs_vs_costful";
        row.comparison_key  = key;

        row.weather_regime     = no_cost_row.weather_regime;
        row.blockage_severity  = no_cost_row.blockage_severity;
        row.elevation_scenario = no_cost_row.elevation_scenario;

        row.steering_policy       = no_cost_row.steering_policy;
        row.coordination_mode     = no_cost_row.coordination_mode;

        row.run_tag_no_cost = no_cost_row.run_tag;
        row.run_tag_costful = costful_row.run_tag;

        % Positive delay improvement means the "no cost" run is better
        row.mean_delay_improvement_ms      = costful_row.mean_delay_ms - no_cost_row.mean_delay_ms;
        row.mean_delay_improvement_percent = 100 * (costful_row.mean_delay_ms - no_cost_row.mean_delay_ms) / max(abs(costful_row.mean_delay_ms), eps);

        row.p95_delay_improvement_ms      = costful_row.p95_delay_ms - no_cost_row.p95_delay_ms;
        row.p95_delay_improvement_percent = 100 * (costful_row.p95_delay_ms - no_cost_row.p95_delay_ms) / max(abs(costful_row.p95_delay_ms), eps);

        row.p99_delay_improvement_ms      = costful_row.p99_delay_ms - no_cost_row.p99_delay_ms;
        row.p99_delay_improvement_percent = 100 * (costful_row.p99_delay_ms - no_cost_row.p99_delay_ms) / max(abs(costful_row.p99_delay_ms), eps);

        row.max_queue_reduction_Mbits = costful_row.max_queue_Mbits - no_cost_row.max_queue_Mbits;

        row.action_count_no_cost = no_cost_row.action_count;
        row.action_count_costful = costful_row.action_count;
        row.action_count_change  = costful_row.action_count - no_cost_row.action_count;

        row.mean_satellite_fraction_no_cost = no_cost_row.mean_satellite_traffic_fraction;
        row.mean_satellite_fraction_costful = costful_row.mean_satellite_traffic_fraction;
        row.mean_satellite_fraction_change  = costful_row.mean_satellite_traffic_fraction - no_cost_row.mean_satellite_traffic_fraction;

        if isempty(rows)
            rows = row;
        else
            rows(end + 1, 1) = row;
        end
    end

    if isempty(rows)
        comparison_table = table();
    else
        comparison_table = struct2table(rows);
        comparison_table = sortrows(comparison_table, ["coordination_mode", "blockage_severity", "elevation_scenario", "weather_regime"]);
    end

end


function plot_heatmaps(summary_table, figures_directory)

    steer_rows = summary_table(summary_table.steering_policy == "steer", :);
    if isempty(steer_rows)  % We only care about switching / splitting
        return;
    end

    keys = unique(steer_rows.heatmap_key);
    keys = keys(strlength(keys) > 0);

    weather_regimes     = ["clear", "moderate_rain", "heavy_rain"];
    elevation_scenarios = ["low", "mid", "high"];

    for key_index = 1 : numel(keys)

        key = keys(key_index);
        rows = steer_rows(steer_rows.heatmap_key == key, :);
        if isempty(rows)
            continue;
        end

        % Create heatmap matrices
        mean_delay_matrix         = build_metric_matrix(rows, "mean_delay_ms", elevation_scenarios, weather_regimes);
        p95_delay_matrix          = build_metric_matrix(rows, "p95_delay_ms", elevation_scenarios, weather_regimes);
        p99_delay_matrix          = build_metric_matrix(rows, "p99_delay_ms", elevation_scenarios, weather_regimes);
        max_queue_matrix          = build_metric_matrix(rows, "max_queue_Mbits", elevation_scenarios, weather_regimes);
        satellite_fraction_matrix = 100 * build_metric_matrix(rows, "mean_satellite_traffic_fraction", elevation_scenarios, weather_regimes);
        action_count_matrix       = build_metric_matrix(rows, "action_count", elevation_scenarios, weather_regimes);

        % Plot all heatmaps
        figure;
        set(gcf, 'Color', 'w', 'MenuBar', 'none', 'ToolBar', 'none');
        set(gcf, "Position", [100 100 1400 850]);

        tiledlayout(2, 3, "Padding", "compact", "TileSpacing", "compact");

        nexttile;
        plot_heatmap(mean_delay_matrix, weather_regimes, elevation_scenarios, "Mean delay (ms)", "%.1f", false);

        nexttile;
        plot_heatmap(p95_delay_matrix, weather_regimes, elevation_scenarios, "P95 delay (ms)", "%.1f", false);

        nexttile;
        plot_heatmap(p99_delay_matrix, weather_regimes, elevation_scenarios, "P99 delay (ms)", "%.1f", false);

        nexttile;
        plot_heatmap(max_queue_matrix, weather_regimes, elevation_scenarios, "Max queue (Mbits)", "%.2f", false);

        nexttile;
        plot_heatmap(satellite_fraction_matrix, weather_regimes, elevation_scenarios, "Mean satellite fraction (%)", "%.1f", false);

        nexttile;
        plot_heatmap(action_count_matrix, weather_regimes, elevation_scenarios, "Number of switches / split-fraction changes", "%.0f", false);

        sgtitle({"Scenario heatmaps", char(prettify_key_label(key))}, "Interpreter", "none", "Color", "k");

        figure_file = fullfile( ...
            figures_directory, ...
            build_short_file_stem("heatmaps", get_latest_row(rows)) + ".png");

        exportgraphics(gcf, figure_file, "Resolution", 500, "BackgroundColor", "white");
        close(gcf);
    end

end


function metric_matrix = build_metric_matrix(rows, metric_name, elevation_scenarios, weather_regimes)

    metric_matrix = nan(numel(elevation_scenarios), numel(weather_regimes));

    for e = 1 : numel(elevation_scenarios)

        for w = 1 : numel(weather_regimes)

            row = get_latest_row(rows(rows.elevation_scenario == elevation_scenarios(e) & rows.weather_regime == weather_regimes(w), :));

            if ~isempty(row)
                metric_matrix(e, w) = row.(metric_name);
            end
        end
    end

end


function plot_heatmap(metric_matrix, x_labels, y_labels, subtitle, number_format_string, use_diverging_colormap)

    imagesc(metric_matrix, "AlphaData", ~isnan(metric_matrix));
    ax = gca;
    set(ax, ...
        "Color", "w", ...
        "XColor", "k", ...
        "YColor", "k", ...
        "GridColor", [0.85 0.85 0.85], ...
        "MinorGridColor", [0.92 0.92 0.92]);

    xticks(1 : numel(x_labels));
    xticklabels(remove_underscores(x_labels));

    yticks(1 : numel(y_labels));
    yticklabels(remove_underscores(y_labels));

    xlabel("Weather regime", "Color", "k");
    ylabel("Elevation scenario", "Color", "k");
    title(subtitle, "Interpreter", "none", "Color", "k");

    xlim([0.5, numel(x_labels) + 0.5]);
    ylim([0.5, numel(y_labels) + 0.5]);

    % Cell borders
    hold on;
    for x = 0.5 : 1 : (numel(x_labels) + 0.5)
        xline(x, "-", "Color", [0.85 0.85 0.85], "LineWidth", 0.8);
    end
    for y = 0.5 : 1 : (numel(y_labels) + 0.5)
        yline(y, "-", "Color", [0.85 0.85 0.85], "LineWidth", 0.8);
    end

    finite_values = metric_matrix(isfinite(metric_matrix));

    if isempty(finite_values)
        clim(ax, [0 1]);
        colormap(ax, gray(256));
    else
        if use_diverging_colormap
            max_abs = max(abs(finite_values));
            if max_abs < eps
                max_abs = 1;
            end
            clim(ax, [-max_abs, max_abs]);
            colormap(ax, blue_white_red_colormap(256));
        else
            value_min = min(finite_values);
            value_max = max(finite_values);
            if abs(value_max - value_min) < eps
                value_max = value_min + 1;
            end
            clim(ax, [value_min, value_max]);
            colormap(ax, parula(256));
        end
    end

    cb = colorbar;
    cb.TickDirection = "out";
    cb.FontSize = 10;

    for r = 1 : size(metric_matrix, 1)
        for c = 1 : size(metric_matrix, 2)

            value = metric_matrix(r, c);

            if isnan(value)
                label = "N/A";
                text_color = [0.25 0.25 0.25];
            else
                label = sprintf(number_format_string, value);

                clim_values = ax.CLim;
                normalized_value = (value - clim_values(1)) / max(clim_values(2) - clim_values(1), eps);

                if normalized_value < 0.18 || normalized_value > 0.82
                    text_color = [1 1 1];
                else
                    text_color = [0 0 0];
                end
            end

            text(c, r, label, ...
                "HorizontalAlignment", "center", ...
                "VerticalAlignment", "middle", ...
                "FontWeight", "bold", ...
                "FontSize", 10, ...
                "Color", text_color);
        end
    end

    hold off;

end


function filename = sanitize_filename(text)

    filename = string(text);
    filename = regexprep(filename, "[^a-zA-Z0-9_]", "_");
    filename = regexprep(filename, "_+", "_");

end


function label = prettify_key_label(key)

    label = string(key);
    label = strrep(label, "_", " ");
    label = strrep(label, ",", " | ");
    label = strrep(label, "=", ": ");

end


function cmap = blue_white_red_colormap(n)

    half_n = floor(n / 2);

    blue_to_white = [linspace(0.15, 1.0, half_n)' ...
                    linspace(0.30, 1.0, half_n)' ...
                    linspace(1.00, 1.00, half_n)'];

    white_to_red  = [linspace(1.00, 1.00, half_n)' ...
                    linspace(1.0, 0.30, n - half_n)' ...
                    linspace(1.0, 0.15, n - half_n)'];

    cmap = [blue_to_white; white_to_red];

end


function overview_table = build_overview_table( ...
    steer_vs_baseline_table, ...
    stability_table, ...
    cost_table)

    rows = struct([]);

    % First add switching / splitting vs. baselines overview rows
    if ~isempty(steer_vs_baseline_table)
        
        baseline_policies = unique(steer_vs_baseline_table.baseline_policy);
        coordination_modes = unique(steer_vs_baseline_table.coordination_mode);

        for baseline_index = 1 : numel(baseline_policies)   % always terrestrial, always satellite

            for coordination_index = 1 : numel(coordination_modes)   % binary switching, traffic splitting

                subtable = steer_vs_baseline_table(...
                    steer_vs_baseline_table.baseline_policy == baseline_policies(baseline_index) & ...
                    steer_vs_baseline_table.coordination_mode == coordination_modes(coordination_index), :);

                if isempty(subtable)
                    continue;
                end

                row = build_overview_row(subtable, ...
                    "steer vs " + baseline_policies(baseline_index), ...
                    coordination_modes(coordination_index));

                if isempty(rows)
                    rows = row;
                else
                    rows(end + 1, 1) = row;
                end
            end
        end
    end

    % Add cost and stability rows
    rows = append_overview_rows(rows, stability_table, "stabilized vs unstabilized");
    rows = append_overview_rows(rows, cost_table, "no reconfiguration cost vs reconfiguration cost");

    % Return overview table
    if isempty(rows)
        overview_table = table();
    else
        overview_table = struct2table(rows);
        overview_table = sortrows(overview_table, ["comparison", "coordination"]);
    end

end


function rows = append_overview_rows(rows, comparison_table, comparison_name)

    if isempty(comparison_table)
        return;
    end

    coordination_modes = unique(comparison_table.coordination_mode);

    for coordination_index = 1 : numel(coordination_modes)

        subtable = comparison_table(comparison_table.coordination_mode == coordination_modes(coordination_index), :);
        if isempty(subtable)
            continue;
        end

        row = build_overview_row(subtable, comparison_name, coordination_modes(coordination_index));
        
        if isempty(rows)
            rows = row;
        else
            rows(end + 1, 1) = row;
        end
    end

end


function row = build_overview_row(subtable, comparison_name, coordination_mode)

    % For each comparison type:
    %   steer vs terrestrial
    %   steer vs satellite
    %   stabilized vs unstabilized
    %   no reconfiguration cost vs reconfiguration cost
    % And for each coordination type:
    %   binary switching
    %   traffic splitting
    % We show a useful overview summary of model performance, such as:
    %   Number of mean- and tail-delay wins, losses, and ties
    %   Best and worst mean and tail delays
    %       Scenarios with the best and worst tail delays
    %       Satellite fraction delta for the best and worst scenario
    %   Best and worst maximum queue sizes
    %   Number of failure-case scenarios

    row = struct();

    row.comparison = comparison_name;      % (1) steer vs terrestrial, (2) steer vs satellite, (3) stabilized vs unstabilized (4) no reconfiguration cost vs reconfiguration cost
    row.coordination = coordination_mode;  % binary_switching or traffic_splitting
    row.label = comparison_name + " | " + remove_underscores(coordination_mode);

    row.num_scenarios = height(subtable);

    row.p95_wins   = sum(subtable.p95_delay_improvement_ms > 0);
    row.p95_losses = sum(subtable.p95_delay_improvement_ms < 0);
    row.p95_ties   = sum(subtable.p95_delay_improvement_ms == 0);

    row.mean_delay_wins   = sum(subtable.mean_delay_improvement_ms > 0);
    row.mean_delay_losses = sum(subtable.mean_delay_improvement_ms < 0);
    row.mean_delay_ties   = sum(subtable.mean_delay_improvement_ms == 0);

    row.best_p95_delta_ms   = max(subtable.p95_delay_improvement_ms, [], "omitnan");
    row.worst_p95_delta_ms  = min(subtable.p95_delay_improvement_ms, [], "omitnan");
    row.best_mean_delta_ms  = max(subtable.mean_delay_improvement_ms, [], "omitnan");
    row.worst_mean_delta_ms = min(subtable.mean_delay_improvement_ms, [], "omitnan");

    row.best_max_queue_delta_Mbits  = max(subtable.max_queue_reduction_Mbits, [], "omitnan");
    row.worst_max_queue_delta_Mbits = min(subtable.max_queue_reduction_Mbits, [], "omitnan");

    p95_delay_improvements_ms = subtable.p95_delay_improvement_ms;

    if all(isnan(p95_delay_improvements_ms))   % Make sure not all tail-delay deltas are NaN
        row.best_p95_scenario = "N/A";
        row.worst_p95_scenario = "N/A";
        row.best_p95_scenario_satellite_fraction_change = NaN;
        row.worst_p95_scenario_satellite_fraction_change = NaN;
    else
        [~, best_p95_index]  = max(p95_delay_improvements_ms, [], "omitnan");
        [~, worst_p95_index] = min(p95_delay_improvements_ms, [], "omitnan");

        row.best_p95_scenario  = build_failure_scenario_label(subtable(best_p95_index, :));
        row.worst_p95_scenario = build_failure_scenario_label(subtable(worst_p95_index, :));

        row.best_p95_scenario_satellite_fraction_change  = subtable.mean_satellite_fraction_change(best_p95_index);
        row.worst_p95_scenario_satellite_fraction_change = subtable.mean_satellite_fraction_change(worst_p95_index);
    end

    failure_mask = (subtable.p95_delay_improvement_ms < 0) | (subtable.mean_delay_improvement_ms < 0);
    row.num_failure_scenarios = sum(failure_mask);

end


function tag = remove_underscores(underscored_tag)
    tag = strrep(underscored_tag, "_", " ");
end


function table = round_table(unrounded_table, num_digits)

    % Round the raw table for the numbers in it to be displayed with 2 decimal places.

    table = unrounded_table;

    for column_index = 1 : width(table)
        column_name = table.Properties.VariableNames{column_index};
        if isnumeric(table.(column_name))
            table.(column_name) = round(table.(column_name), num_digits);
        end
    end

end


function failure_table = build_failure_table( ...
    steer_vs_baseline_table, ...
    stability_table, ...
    cost_table)

    rows = struct([]);

    % Steer (switch / split) vs. baselines (always terrestrial / always satellite) comparisons
    if ~isempty(steer_vs_baseline_table)
        baseline_policies   = unique(steer_vs_baseline_table.baseline_policy);

        for baseline_index = 1 : numel(baseline_policies)
            
            subtable = steer_vs_baseline_table( ...
                steer_vs_baseline_table.baseline_policy == baseline_policies(baseline_index), :);
            rows = append_failure_rows(rows, subtable, "steer vs " + baseline_policies(baseline_index));
        end
    end

    % Cost and stability comparisons
    rows = append_failure_rows(rows, stability_table, "stabilized vs unstabilized");
    rows = append_failure_rows(rows, cost_table, "no reconfiguration cost vs reconfiguration cost");

    if isempty(rows)
        failure_table = table();
    else
        failure_table = struct2table(rows);
        failure_table = sortrows(failure_table, ["comparison", "coordination", "p95_delay_delta_ms"], ["ascend", "ascend", "ascend"]);
    end

end


function rows = append_failure_rows(rows, comparison_table, comparison_name)

    if isempty(comparison_table)
        return;
    end

    coordination_modes = unique(comparison_table.coordination_mode);

    for coordination_index = 1 : numel(coordination_modes)
        subtable = comparison_table(comparison_table.coordination_mode == coordination_modes(coordination_index), :);
        rows = build_and_append_failure_rows(rows, subtable, comparison_name, coordination_modes(coordination_index));
    end

end


function rows = build_and_append_failure_rows(rows, subtable, comparison_name, coordination_mode)

    % For each comparison type:
    %   steer vs terrestrial
    %   steer vs satellite
    %   stabilized vs unstabilized
    %   no reconfiguration cost vs reconfiguration cost
    % And for each coordination type:
    %   binary switching
    %   traffic splitting
    % We show one row for each failure-case scenario, i.e., each run of the simulation
    % where the mean or delay got worse.

    if isempty(subtable)
        return;
    end

    failure_mask = (subtable.p95_delay_improvement_ms < 0) | (subtable.mean_delay_improvement_ms < 0);
    failure_rows = subtable(failure_mask, :);

    for row_index = 1 : height(failure_rows)

        failure_row = failure_rows(row_index, :);

        row = struct();

        row.comparison   = comparison_name;
        row.coordination = coordination_mode;

        row.weather_regime     = failure_row.weather_regime;
        row.blockage_severity  = failure_row.blockage_severity;
        row.elevation_scenario = failure_row.elevation_scenario;
        row.scenario           = build_failure_scenario_label(failure_row);

        row.mean_delay_delta_ms   = failure_row.mean_delay_improvement_ms;
        row.p95_delay_delta_ms    = failure_row.p95_delay_improvement_ms;
        row.p99_delay_delta_ms    = failure_row.p99_delay_improvement_ms;
        row.max_queue_delta_Mbits = failure_row.max_queue_reduction_Mbits;

        row.mean_satellite_fraction_delta = failure_row.mean_satellite_fraction_change;

        % Candidate runs should perform better than the reference runs
        if ismember("run_tag_steer", failure_rows.Properties.VariableNames)
            row.run_tag_candidate = failure_row.run_tag_steer;               % Switch / split
            row.run_tag_reference = failure_row.run_tag_baseline;            % Always terrestrial / always satellite
        elseif ismember("run_tag_off", failure_rows.Properties.VariableNames)
            row.run_tag_candidate = failure_row.run_tag_on;                  % Stabilized
            row.run_tag_reference = failure_row.run_tag_off;                 % Unstabilized
        elseif ismember("run_tag_no_cost", failure_rows.Properties.VariableNames)
            row.run_tag_candidate = failure_row.run_tag_no_cost;             % No cost
            row.run_tag_reference = failure_row.run_tag_costful;             % Cost-ful
        else
            row.run_tag_candidate = "";
            row.run_tag_reference = "";
        end

        if isempty(rows)
            rows = row;
        else
            rows(end + 1, 1) = row;
        end
    end

end

function label = build_failure_scenario_label(row)

    label = remove_underscores(row.elevation_scenario) + " | " + ...
            remove_underscores(row.weather_regime) + " | " + ...
            remove_underscores(row.blockage_severity);

end

function plot_comparison_heatmaps( ...
    steer_vs_baseline_table, ...
    stability_table, ...
    cost_table, ...
    figures_directory)

    % Steer vs baselines
    if ~isempty(steer_vs_baseline_table)
        baseline_policies   = unique(steer_vs_baseline_table.baseline_policy);

        for baseline_index = 1 : numel(baseline_policies)

            subtable = steer_vs_baseline_table( ...
                steer_vs_baseline_table.baseline_policy == baseline_policies(baseline_index), :);

            if isempty(subtable)
                continue;
            end

            plot_comparison_heatmaps_( ...
                subtable, ...
                "steer vs " + baseline_policies(baseline_index), ...
                figures_directory);
        end
    end

    % Stability constraints
    plot_comparison_heatmaps_( ...
        stability_table, ...
        "stabilized vs unstabilized", ...
        figures_directory);

    % Reconfiguration cost
    plot_comparison_heatmaps_( ...
        cost_table, ...
        "no reconfiguration cost vs reconfiguration cost", ...
        figures_directory);

end


function plot_comparison_heatmaps_(comparison_table, comparison_name, figures_directory)

    if isempty(comparison_table)
        return;
    end

    coordination_modes  = unique(comparison_table.coordination_mode);
    blockage_severities = unique(comparison_table.blockage_severity);

    for blockage_index = 1 : numel(blockage_severities)
        
        for coordination_index = 1 : numel(coordination_modes)

            subtable = comparison_table( ...
                comparison_table.blockage_severity == blockage_severities(blockage_index) & ...
                comparison_table.coordination_mode == coordination_modes(coordination_index), :);

            if isempty(subtable)
                continue;
            end

            plot_comparison_heatmap( ...
                subtable, comparison_name, blockage_severities(blockage_index), ...
                coordination_modes(coordination_index), figures_directory);
        end
    end

end


function plot_comparison_heatmap( ...
    subtable, ...
    comparison_name, ...
    blockage_severity, ...
    coordination_mode, ...
    figures_directory)

    % This heatmap shows the effects of weather and elevation on the deltas (mean and tail delay and maximum queue)
    % for different comparisons, blockage severities, and coordination modes (switching or splitting).

    weather_regimes     = ["clear", "moderate_rain", "heavy_rain"];
    elevation_scenarios = ["low", "mid", "high"];

    mean_delta_matrix      = build_metric_matrix(subtable, "mean_delay_improvement_ms", elevation_scenarios, weather_regimes);
    p95_delta_matrix       = build_metric_matrix(subtable, "p95_delay_improvement_ms", elevation_scenarios, weather_regimes);
    p99_delta_matrix       = build_metric_matrix(subtable, "p99_delay_improvement_ms", elevation_scenarios, weather_regimes);
    max_queue_delta_matrix = build_metric_matrix(subtable, "max_queue_reduction_Mbits", elevation_scenarios, weather_regimes);

    figure;
    set(gcf, 'Color', 'w', 'MenuBar', 'none', 'ToolBar', 'none');
    set(gcf, "Position", [100 100 1200 850]);

    tiledlayout(2, 2, "Padding", "compact", "TileSpacing", "compact");

    nexttile;
    plot_heatmap(mean_delta_matrix, weather_regimes, elevation_scenarios, "Mean delay delta (ms)", "%+.1f", true);

    nexttile;
    plot_heatmap(p95_delta_matrix, weather_regimes, elevation_scenarios, "P95 delay delta (ms)", "%+.1f", true);

    nexttile;
    plot_heatmap(p99_delta_matrix, weather_regimes, elevation_scenarios, "P99 delay delta (ms)", "%+.1f", true);

    nexttile;
    plot_heatmap(max_queue_delta_matrix, weather_regimes, elevation_scenarios, "Max queue delta (Mbits)", "%+.2f", true);

    sgtitle({ ...
        char(comparison_name), ...
        char(remove_underscores(blockage_severity) + " | " + remove_underscores(coordination_mode)), ...
        "Positive delta means the first choice is better" ...
        }, "Interpreter", "none", "Color", "k");

    figure_file = fullfile( ...
        figures_directory, ...
        build_short_comparison_file_stem("comparison_heatmaps", comparison_name, blockage_severity, coordination_mode) + ".png");

    exportgraphics(gcf, figure_file, "Resolution", 500, "BackgroundColor", "white");
    close(gcf);

    disp("Wrote " + figure_file);

end


function save_table_png(table, title_lines, file_path, headers_override, column_weights_override)

    if nargin < 4
        headers_override = [];
    end
    if nargin < 5
        column_weights_override = [];
    end

    if ischar(title_lines) || isstring(title_lines)
        title_lines = cellstr(title_lines);
    end

    if isempty(headers_override)
        headers = wrap_strings_for_png(prettify_table_headers(table.Properties.VariableNames), 16);
    else
        headers = string(headers_override);
    end

    cell_strings = wrap_strings_for_png(table_to_display_strings(table), 22);

    num_rows = size(cell_strings, 1);
    num_cols = size(cell_strings, 2);

    if isempty(column_weights_override)
        column_weights = zeros(1, num_cols);
        for c = 1 : num_cols
            max_len = max_visible_line_length(headers(c));
            for r = 1 : num_rows
                max_len = max(max_len, max_visible_line_length(cell_strings(r, c)));
            end
            column_weights(c) = max(8, double(max_len));
        end
    else
        column_weights = column_weights_override;
    end

    column_widths = column_weights / sum(column_weights);
    x_edges = [0, cumsum(column_widths)];

    line_counts = ones(num_rows + 1, 1);  % header and data rows

    for c = 1 : num_cols
        line_counts(1) = max(line_counts(1), numel(splitlines(headers(c))));
    end

    for r = 1:num_rows
        max_lines_this_row = 1;
        for c = 1:num_cols
            max_lines_this_row = max(max_lines_this_row, numel(splitlines(cell_strings(r, c))));
        end
        line_counts(r + 1) = max_lines_this_row;
    end

    height_units  = sum(line_counts) + 0.5 * numel(line_counts);
    figure_height = max(650, 120 + 42 * height_units);

    figure_handle = figure( ...
        "Visible", "off", ...
        "Color", "w", ...
        "Position", [100 100 3400 figure_height]);

    annotation(figure_handle, "textbox", [0.02 0.92 0.96 0.06], ...
        "String", title_lines, ...
        "Interpreter", "none", ...
        "EdgeColor", "none", ...
        "HorizontalAlignment", "center", ...
        "FontWeight", "bold", ...
        "FontSize", 13, ...
        "Color", "k");

    ax = axes(figure_handle, "Position", [0.02 0.02 0.96 0.88]);
    axis(ax, [0 1 0 1]);
    axis(ax, "off");
    hold(ax, "on");

    row_heights = line_counts / sum(line_counts);
    y_tops      = 1 - [0; cumsum(row_heights(1 : end - 1))];

    % Header row
    header_height = row_heights(1);
    header_y0 = y_tops(1) - header_height;

    for c = 1 : num_cols
        x0 = x_edges(c);
        w  = x_edges(c + 1) - x0;

        rectangle(ax, ...
            "Position", [x0, header_y0, w, header_height], ...
            "FaceColor", [0.88 0.88 0.88], ...
            "EdgeColor", [0.70 0.70 0.70], ...
            "LineWidth", 1.0);

        text(ax, x0 + w / 2, header_y0 + header_height / 2, headers(c), ...
            "HorizontalAlignment", "center", ...
            "VerticalAlignment", "middle", ...
            "FontWeight", "bold", ...
            "FontSize", 10, ...
            "Interpreter", "none", ...
            "Color", "k");
    end

    % Data rows
    for r = 1 : num_rows

        row_height = row_heights(r + 1);
        y0 = y_tops(r + 1) - row_height;

        if mod(r, 2) == 1
            bg_color = [1.00 1.00 1.00];
        else
            bg_color = [0.97 0.97 0.97];
        end

        for c = 1 : num_cols
            x0 = x_edges(c);
            w  = x_edges(c + 1) - x0;

            rectangle(ax, ...
                "Position", [x0, y0, w, row_height], ...
                "FaceColor", bg_color, ...
                "EdgeColor", [0.82 0.82 0.82], ...
                "LineWidth", 0.8);

            left_align_columns = [1, 15, 16];

            if ismember(c, left_align_columns)
                x_text = x0 + 0.01 * w;
                horizontal_alignment = "left";
            else
                x_text = x0 + w / 2;
                horizontal_alignment = "center";
            end

            text(ax, x_text, y0 + row_height / 2, cell_strings(r, c), ...
                "HorizontalAlignment", horizontal_alignment, ...
                "VerticalAlignment", "middle", ...
                "FontSize", 10, ...
                "Interpreter", "none", ...
                "Color", "k");
        end
    end

    hold(ax, "off");

    exportgraphics(figure_handle, file_path, "Resolution", 500, "BackgroundColor", "white");
    close(figure_handle);

end


function headers = prettify_table_headers(variable_names)

    headers = string(variable_names);
    headers = strrep(headers, "_", " ");

end


function cell_strings = table_to_display_strings(table)

    num_rows = height(table);
    num_cols = width(table);
    cell_strings = strings(num_rows, num_cols);

    for c = 1 : num_cols
        variable_name = table.Properties.VariableNames{c};
        column_data   = table.(variable_name);

        for r = 1 : num_rows
            cell_strings(r, c) = value_to_display_string(column_data(r));
        end
    end

end


function s = value_to_display_string(value)

    if isstring(value)
        s = value;
    elseif isnumeric(value) && (isempty(value) || ~isfinite(value)) 
        s = "N/A";
    else
        s = string(value);
    end

end


function wrapped_strings = wrap_strings_for_png(strings_in, max_chars)

    wrapped_strings = strings(size(strings_in));

    for i = 1 : numel(strings_in)
        wrapped_strings(i) = wrap_one_string_for_png(string(strings_in(i)), max_chars);
    end

end


function s_out = wrap_one_string_for_png(s_in, max_chars)

    s = string(s_in);

    % Line break at useful separators
    s = strrep(s, " | ", newline);
    s = strrep(s, ", ", "," + newline);

    parts         = splitlines(s);
    wrapped_parts = strings(0, 1);

    for p = 1 : numel(parts)

        line = strtrim(parts(p));

        while strlength(line) > max_chars

            text = char(line);
            search_end = min(max_chars, length(text));

            break_index = find(text(1:search_end) == ' ', 1, "last");

            if isempty(break_index)

                next_end = min(length(text), max_chars + 12);

                if next_end <= max_chars
                    break;
                end

                temp = find(text(max_chars+1:next_end) == ' ', 1, "first");

                if isempty(temp)
                    break;
                end

                break_index = max_chars + temp;
            end

            if break_index <= 1
                break;
            end

            wrapped_parts(end + 1, 1) = string(strtrim(text(1 : break_index - 1)));
            line = string(strtrim(text(break_index + 1 : end)));
        end

        wrapped_parts(end + 1, 1) = line;
    end

    s_out = strjoin(wrapped_parts, newline);

end


function max_len = max_visible_line_length(s)

    lines = splitlines(string(s));
    max_len = 0;

    for i = 1 : numel(lines)
        max_len = max(max_len, strlength(lines(i)));
    end

end


function plot_stability_tradeoff(summary_table, plots_directory)

    % This function creates and saves two scatter plots:
    %   Tail delay vs. the number of switches
    %   Tail delay vs. the number of split fraction changes
    % This is to show whether or not we observe a tradeoff between stability (fewer switches or split fraction changes) and performance (delay).

    rows = summary_table(summary_table.steering_policy == "steer", :);    % We only care about switching / splitting
    rows = rows(~isnan(rows.action_count) & ~isnan(rows.p95_delay_ms), :);  % Make sure that we have a valid switch / split fraction change count and tail delay

    if isempty(rows)
        return;
    end

    switch_rows = rows(rows.coordination_mode == "binary_switching", :);
    split_rows  = rows(rows.coordination_mode == "traffic_splitting", :);

    figure;
    set(gcf, 'Color', 'w', 'MenuBar', 'none', 'ToolBar', 'none');
    set(gcf, "Position", [100 100 1000 650]);

    tiledlayout(1, 2, "Padding", "compact", "TileSpacing", "compact");

    nexttile;
    plot_stability_panel(switch_rows, "Number of switches", "Binary switching");

    nexttile;
    plot_stability_panel(split_rows, "Number of split-fraction changes", "Traffic splitting");

    sgtitle({"Stability-performance tradeoff", ...
            "P95 delay versus decision churn"}, ...
            "Interpreter", "none", "Color", "k");

    figure_file = fullfile(plots_directory, "stability_tradeoff_scatter_plot.png");
    exportgraphics(gcf, figure_file, "Resolution", 500, "BackgroundColor", "white");
    close(gcf);

    disp("Wrote analysis/plots/stability_tradeoff_scatter_plot.png");

end


function plot_stability_panel(rows, x_label_text, title_text)

    hold on;
    grid on;

    if isempty(rows)
        text(0.5, 0.5, "No data", ...
            "Units", "normalized", ...
            "HorizontalAlignment", "center", ...
            "VerticalAlignment", "middle", ...
            "Color", "k");
        xlabel(x_label_text, "Color", "k");
        ylabel("P95 delay (ms)", "Color", "k");
        title(title_text, "Color", "k");
        hold off;
        return;
    end

    scatter(rows.action_count, rows.p95_delay_ms, 65, ...
        "filled", ...
        "MarkerFaceAlpha", 0.75, ...
        "MarkerEdgeAlpha", 0.75);

    % Add a trend line
    if height(rows) >= 2 && numel(unique(rows.action_count)) >= 2
        coefficients = polyfit(rows.action_count, rows.p95_delay_ms, 1);
        x_fit = linspace(min(rows.action_count), max(rows.action_count), 100);
        y_fit = polyval(coefficients, x_fit);
        plot(x_fit, y_fit, "k--", "LineWidth", 1.5);
    end

    xlabel(x_label_text, "Color", "k");
    ylabel("P95 delay (ms)", "Color", "k");
    title(title_text, "Color", "k");

    hold off;

end


function plot_best_worst_steer_vs_terrestrial(summary_table, steer_vs_baseline_table, plots_directory)

    if isempty(steer_vs_baseline_table) || ~ismember("baseline_policy", string(steer_vs_baseline_table.Properties.VariableNames))
        return;
    end

    rows = steer_vs_baseline_table(steer_vs_baseline_table.baseline_policy == "terrestrial", :);
    if isempty(rows)
        return;
    end
    rows = sortrows(rows, "p95_delay_improvement_ms", "descend");

    best_row =  rows(1, :);   % Lowest tail delay
    worst_row = rows(end, :); % Highest tail delay

    plot_steer_vs_terrestrial(summary_table, best_row, plots_directory, "best_steer_vs_terrestrial", "Best steer-vs-terrestrial matched runs");
    plot_steer_vs_terrestrial(summary_table, worst_row, plots_directory, "worst_steer_vs_terrestrial", "Worst steer-vs-terrestrial matched runs");

end


function plot_steer_vs_terrestrial(summary_table, comparison_row, plots_directory, file_stem, title_string)

    steer_row    = summary_table(summary_table.run_tag == comparison_row.run_tag_steer, :);
    baseline_row = summary_table(summary_table.run_tag == comparison_row.run_tag_baseline, :);

    if isempty(steer_row) || isempty(baseline_row)
        return;
    end

    steer_data    = load(char(steer_row.file_path), "results");
    baseline_data = load(char(baseline_row.file_path), "results");

    steer_results    = steer_data.results;
    baseline_results = baseline_data.results;

    time_seconds = steer_results.traces.time_seconds_per_window;

    bulk_start = get_struct_field(steer_results.config, "bulk_start_seconds", NaN);
    bulk_end   = get_struct_field(steer_results.config, "bulk_end_seconds", NaN);

    figure;
    set(gcf, 'Color', 'w', 'MenuBar', 'none', 'ToolBar', 'none');
    set(gcf, "Position", [100 100 1150 820]);

    tiledlayout(2, 1, "Padding", "compact", "TileSpacing", "compact");

    % Plot average delay over time
    nexttile;
    hold on;
    grid on;

    delay_floor_ms = 1e-3;   % Can't plot 0 on log scale

    h_baseline_delay = plot(time_seconds, ...
        max(baseline_results.traces.average_delay_ms_per_window, delay_floor_ms), "-", ...
        "Color", "#ff8800", "LineWidth", 1.8);

    h_steer_delay = plot(time_seconds, ...
        max(steer_results.traces.average_delay_ms_per_window, delay_floor_ms), "-", ...
        "Color", "#800080", "LineWidth", 1.8);

    set(gca, "YScale", "log");
    current_limits = ylim(gca);
    ylim(gca, [10, max(10, current_limits(2))]);

    h_bulk_delay = gobjects(0);
    if isfinite(bulk_start) && isfinite(bulk_end)
        h_bulk_delay = add_bulk_window_patch(gca, bulk_start, bulk_end);
    end

    ylabel("Average delay (ms)", "Color", "k");

    if isempty(h_bulk_delay)
        legend([h_baseline_delay, h_steer_delay], ...
            {"Always terrestrial", "Steer"}, ...
            "Location", "best");
    else
        legend([h_baseline_delay, h_steer_delay, h_bulk_delay], ...
            {"Always terrestrial", "Steer", "Bulk interval"}, ...
            "Location", "best");
    end


    % Plot queue evolution over time
    nexttile;
    hold on;
    grid on;

    queue_floor_Mbits = 1e-6;   % Can't plot 0 on log scale

    h_baseline_queue = plot(time_seconds, ...
        max(baseline_results.traces.queue_bits_per_window / 1e6, queue_floor_Mbits), "-", ...
        "Color", "#ff8800", "LineWidth", 1.8);

    h_steer_queue = plot(time_seconds, ...
        max(steer_results.traces.queue_bits_per_window / 1e6, queue_floor_Mbits), "-", ...
        "Color", "#800080", "LineWidth", 1.8);

    set(gca, "YScale", "log");

    h_bulk_queue = gobjects(0);
    if isfinite(bulk_start) && isfinite(bulk_end)
        h_bulk_queue = add_bulk_window_patch(gca, bulk_start, bulk_end);
    end

    ylabel("Queue size (Mbits)", "Color", "k");
    xlabel("Time (s)", "Color", "k");

    if isempty(h_bulk_queue)
        legend([h_baseline_queue, h_steer_queue], ...
            {"Always terrestrial", "Steer"}, ...
            "Location", "best");
    else
        legend([h_baseline_queue, h_steer_queue, h_bulk_queue], ...
            {"Always terrestrial", "Steer", "Bulk interval"}, ...
            "Location", "best");
    end


    sgtitle({ ...
        char(title_string), ...
        char(build_failure_scenario_label(comparison_row)), ...
        char("P95 delay improvement = " + sprintf("%.2f", comparison_row.p95_delay_improvement_ms) + " ms") ...
        }, ...
        "Interpreter", "none", "Color", "k");

    figure_file = fullfile(plots_directory, file_stem + ".png");
    exportgraphics(gcf, figure_file, "Resolution", 500, "BackgroundColor", "white");
    close(gcf);

    disp("Wrote " + figure_file);
end


function patch_handle = add_bulk_window_patch(ax, bulk_start, bulk_end)

    if ~isfinite(bulk_start) || ~isfinite(bulk_end) || bulk_end <= bulk_start
        patch_handle = gobjects(0);
        return;
    end

    axes(ax);
    y_limits = ylim(ax);

    patch_handle = patch(ax, ...
        [bulk_start bulk_end bulk_end bulk_start], ...
        [y_limits(1) y_limits(1) y_limits(2) y_limits(2)], ...
        [0.92 0.92 0.92], ...
        "EdgeColor", "none", ...
        "FaceAlpha", 0.45);

    uistack(patch_handle, "bottom");

end


%
% Helpers to shorten file names
%

function tag = bool_to_01(flag)

    if flag
        tag = "1";
    else
        tag = "0";
    end

end


function short_text = short_label(text)

    short_text = string(text);

    short_text = strrep(short_text, "binary_switching", "switching");
    short_text = strrep(short_text, "traffic_splitting", "splitting");
    short_text = strrep(short_text, "moderate_rain", "moderate");
    short_text = strrep(short_text, "heavy_rain", "heavy");
    short_text = strrep(short_text, "mild_blockage", "mild");
    short_text = strrep(short_text, "mixed_blockage", "mixed");
    short_text = strrep(short_text, "severe_blockage", "severe");
    short_text = strrep(short_text, "no_blockage", "none");
    short_text = strrep(short_text, "not_applicable", "na");

    short_text = strrep(short_text, "steer vs terrestrial", "steer_vs_terr");
    short_text = strrep(short_text, "steer vs satellite", "steer_vs_sat");
    short_text = strrep(short_text, "stabilized vs unstabilized", "stabilized_vs_not");
    short_text = strrep(short_text, "no reconfiguration cost vs reconfiguration cost", "costless_vs_costful");

    short_text = sanitize_filename(short_text);

end


function file_stem = build_short_file_stem(prefix, row)

    file_stem = prefix + "_" + ...
        short_label(row.blockage_severity) + "_" + ...
        short_label(row.coordination_mode) + "_" + ...
        "trigger" + bool_to_01(row.use_external_trigger) + "_" + ...
        "reconfig" + bool_to_01(row.enable_handover_overhead) + "_" + ...
        "stable" + bool_to_01(row.enable_stability_constraints) + "_" + ...
        short_label(row.traffic_profile) + "_" + ...
        "pps" + string(row.average_packets_per_second) + "_" + ...
        "bulk_mult" + string(row.bulk_multiplier);

    file_stem = sanitize_filename(file_stem);

end


function file_stem = build_short_comparison_file_stem(prefix, comparison_name, blockage_severity, coordination_mode)

    file_stem = prefix + "_" + ...
        short_label(comparison_name) + "_" + ...
        short_label(blockage_severity) + "_" + ...
        short_label(coordination_mode);

    file_stem = sanitize_filename(file_stem);

end