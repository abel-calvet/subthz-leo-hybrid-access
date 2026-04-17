%========================================================================
% Hybrid Terrestrial-Satellite Switching / Splitting Algorithm
%
% Input:
%   terrestrial link quality:      SNR(t)
%   satellite   link performance:  delay(t), rate(t)
%
% Outputs:
%   chosen link over time        (0 = terrestrial, 1 = satellite)
%   traffic fraction over time   (when using traffic splitting)
%   queue evolution over time
%   average delay over time
%   mean, max, and tail delay
%========================================================================

function results = simulation(config)

close all; clc;
rng("default");

if nargin < 1
    config = struct();   % Create default config if one wasn't passed
end

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
% Timing settings
%

TOTAL_DURATION_SECONDS  = 60;                           % Duration of signal
dt = 0.01;                                              % 10-ms decision windows
NUM_WINDOWS = round(TOTAL_DURATION_SECONDS / dt);
t = (0 : NUM_WINDOWS - 1).' * dt;


%
% Default-run config
%

% Simulation scenario selection
config = set_default(config, "weather_regime",       "clear");              % clear, moderate_rain, heavy_rain
config = set_default(config, "blockage_severity",    "mixed_blockage");     % no_blockage, mild_blockage, severe_blockage, mixed_blockage
config = set_default(config, "elevation_scenario",   "high");               % high, mid, low
config = set_default(config, "use_external_trigger",  false);               % true, false

% Switching and coordination
config = set_default(config, "steering_policy",       "steer");             % steer, terrestrial, satellite
                                                                            % steer:                 Switching / steering allowed
                                                                            % terrestrial:           Use terrestrial always only
                                                                            % satellite:             Use satellite always only

config = set_default(config, "coordination_mode",     "traffic_splitting");  % binary_switching, traffic_splitting
                                                                            % binary_switching:      Choose one link per window
                                                                            % traffic_splitting:     Route traffic into two lower-layer queues and serve them in parallel

% Cost and stability
config = set_default(config, "enable_handover_overhead", false);            % true = costly switching, false = cost-free switching
config = set_default(config, "enable_stability_constraints", true);        % true = stability-constrained, false = not stability-constrained

% Traffic model
config = set_default(config, "traffic_profile", "bulk_upload");             % bulk_upload:           Uses a higher rate of packet arrivals from t = bulk_start_seconds to t = bulk_end_seconds
                                                                            % steady:                Uses a constant rate throughout
config = set_default(config, "packet_size_bits",           100000);
config = set_default(config, "average_packets_per_second", 1000);           % The rate at which packets arrive at the switch (100 Mbps on average)
config = set_default(config, "bulk_multiplier",            1.8);              % During the bulk period, arrival rate goes to 200 Mbps
config = set_default(config, "bulk_start_seconds",         20);             % Simulate a bulk upload from t = 20 s to t = 35 s (28.8 Mbps)
config = set_default(config, "bulk_end_seconds",           35);

if config.steering_policy ~= "steer"
    config.coordination_mode     = "not_applicable";
end

USE_SHARED_QUEUE_ONLY = (config.steering_policy ~= "steer") || (config.coordination_mode == "binary_switching");
USE_TRAFFIC_SPLITTING = (config.steering_policy == "steer") && (config.coordination_mode == "traffic_splitting");

%
% Output File Naming
%

scenario_tag = config.elevation_scenario + "_" + config.weather_regime + "_" + config.blockage_severity;

policy_tag = config.steering_policy + "_" + config.coordination_mode;

controller_tag = "reconfig_" + bool_to_tag(config.enable_handover_overhead) + "_" + "stability_" + bool_to_tag(config.enable_stability_constraints);

trigger_tag = "external_trigger_" + bool_to_tag(config.use_external_trigger);

traffic_tag = config.traffic_profile;

run_tag = scenario_tag + "__" + policy_tag + "__" + controller_tag + "__" + trigger_tag + "__" + traffic_tag;

data_results_directory = "data/results";
fig_results_directory  = "fig/results";
fig_debug_directory    = "fig/debug";

if ~isfolder(data_results_directory)
    mkdir(data_results_directory);
end

if ~isfolder(fig_results_directory)
    mkdir(fig_results_directory);
end

if ~isfolder(fig_debug_directory)
    mkdir(fig_debug_directory);
end


%
% Load data
%

weather_regime       = config.weather_regime;
blockage_severity    = config.blockage_severity;
elevation_scenario   = config.elevation_scenario;
use_external_trigger = config.use_external_trigger;

% Terrestrial effective SNR trace (includes blockage and atmospheric losses)
terrestrial_snr_file = "data/terrestrial_snr_" + weather_regime + "_" + blockage_severity + ".mat";
if ~isfile(terrestrial_snr_file)
    error("Missing terrestrial SNR file: %s", terrestrial_snr_file);
end

load(terrestrial_snr_file, "terrestrial_snr_dB_per_window");
terrestrial_snr_dB_per_window = terrestrial_snr_dB_per_window(:);

% External trigger
external_trigger_at_window = false(NUM_WINDOWS, 1);
if use_external_trigger
    external_trigger_file = "data/external_trigger_trace.mat";
    if isfile(external_trigger_file)
        load(external_trigger_file, "external_trigger_at_window");
        external_trigger_at_window = external_trigger_at_window(:);
    else
        warning("Missing %s. External trigger disabled for this run.", external_trigger_file);
    end
end

% Satellite performance (includes propagation delay and weather effects)
satellite_performance_file = "data/satellite_performance_" + elevation_scenario + "_" + weather_regime + ".mat";
if ~isfile(satellite_performance_file)
    error("Missing satellite performance file: %s", satellite_performance_file);
end

load(satellite_performance_file, ...
    "satellite_rate_up_bps_per_window", ...
    "satellite_one_way_delay_ms_per_window", ...
    "satellite_outage_at_window", ...
    "region_quality");
satellite_rate_up_bps_per_window      = satellite_rate_up_bps_per_window(:);
satellite_one_way_delay_ms_per_window = satellite_one_way_delay_ms_per_window(:);
satellite_outage_at_window            = satellite_outage_at_window(:);

% Satellite geometry (for access and field-of-view masks and plotting and debugging)
satellite_geometry_file = "data/satellite_geometry_" + elevation_scenario + ".mat";
if isfile(satellite_geometry_file)
    load(satellite_geometry_file, ...
        "satellite_access_at_window", ...
        "base_station_in_fov_at_window");
    satellite_access_at_window    = satellite_access_at_window(:);
    base_station_in_fov_at_window = base_station_in_fov_at_window(:);
else
    error("Missing satellite geometry data: %s", satellite_geometry_file);
end

% MCS BLER mapping
load("data/bler_table.mat", "bler_table");

% Globals
global BLER_TARGET BLER_INTERPOLATION_METHOD
global SNR_dB_SWITCH_TO_SATELLITE SNR_dB_SWITCH_BACK_TO_TERRESTRIAL SNR_dB_FORCE_SATELLITE
global SPLIT_FRACTION_SEARCH_GRID_STEP
global DECISION_HORIZON_seconds
global HANDOVER_FREEZE_TIME_seconds
global SPLIT_REQUEUEING_DELAY_ms PREDICTED_TIME_SWITCH_MARGIN_ms SATELLITE_BENEFIT_MARGIN_ms
global ENABLE_HANDOVER_OVERHEAD
global SUBQUEUE_TARGET_NUM_WINDOWS

%
% Terrestrial link model
%

% MCS BLER mapping
BLER_TARGET               = 0.10;
BLER_INTERPOLATION_METHOD = "pchip";   % "linear" (triangular) or "pchip" (more sigmoid-like)

% Terrestrial one-way delay model
TERRESTRIAL_ONE_WAY_DELAY_BASE_ms = 5;      % Lower baseline latency than satellite

%
% Satellite link model
%

% Satellite throughput and delay models are loaded from data/satellite_performance_*.mat
%     satellite_rate_up_bps_per_window       (uplink rate, i.e. user connects to the internet)
%     satellite_oneway_delay_ms_per_window

% Costs and stability

% Steering (switching / splitting) comes with a cost in the form of overhead due to
% reconfiguring at the base station leading to a freeze.
ENABLE_HANDOVER_OVERHEAD         = config.enable_handover_overhead;
HANDOVER_FREEZE_TIME_seconds     = 0.05;  % Service interruption time during a handover
SPLIT_PROCESSING_DELAY_ms        = 0.2;   % Small extra controller processing delay when traffic is dispatched into the lower-layer queues
SPLIT_REQUEUEING_DELAY_ms        = 50;    % Time a packet may remain stuck in an unavailable lower-layer queue before it is re-added to the common queue

ENABLE_STABILITY_CONSTRAINTS = config.enable_stability_constraints;

%
% Traffic Model
%

% Rate at which packets arrive at the switch
% Load can be adjusted
PACKET_SIZE_bits                  = config.packet_size_bits;
AVERAGE_PACKETS_PER_SECOND        = config.average_packets_per_second;
AVERAGE_PACKETS_PER_WINDOW_NORMAL = AVERAGE_PACKETS_PER_SECOND * dt;
AVERAGE_PACKETS_PER_WINDOW_BULK   = AVERAGE_PACKETS_PER_WINDOW_NORMAL * config.bulk_multiplier;

switch config.traffic_profile
    case "bulk_upload"
        % Simulate a bulk upload from t = bulk_start_seconds to t = bulk_end_seconds
        AVERAGE_PACKETS_PER_WINDOW = AVERAGE_PACKETS_PER_WINDOW_NORMAL * ones(NUM_WINDOWS, 1);
        for window_index = 1 : NUM_WINDOWS
            if t(window_index) >= config.bulk_start_seconds && t(window_index) <= config.bulk_end_seconds
                AVERAGE_PACKETS_PER_WINDOW(window_index) = AVERAGE_PACKETS_PER_WINDOW_BULK;
            end
        end
    case "steady"
        AVERAGE_PACKETS_PER_WINDOW = AVERAGE_PACKETS_PER_WINDOW_NORMAL * ones(NUM_WINDOWS, 1);
    otherwise
        error("Unknown traffic_profile: %s", config.traffic_profile);
end

AVERAGE_BPS_NORMAL = AVERAGE_PACKETS_PER_WINDOW_NORMAL * PACKET_SIZE_bits / dt;
AVERAGE_BPS_BULK   = AVERAGE_PACKETS_PER_WINDOW_BULK   * PACKET_SIZE_bits / dt;
fprintf("Load normal = %.1f Mbps, bulk = %.1f Mbps\n", AVERAGE_BPS_NORMAL / 1e6, AVERAGE_BPS_BULK / 1e6);

%
% Binary Switching Parameters
%

% SNR-based thresholds
% Hysteresis:
%   If SNR drops below low threshold, switch to satellite
%   If SNR rises above high threshold, switch back to terrestrial
SNR_dB_SWITCH_TO_SATELLITE        = 5;
SNR_dB_SWITCH_BACK_TO_TERRESTRIAL = 8;

% Delay-based (backlog-clearance time) controller
% Decision = do nothing, switch, or change split
DECISION_HORIZON_seconds       = 0.4;   % Short horizon
PREDICTED_TIME_SWITCH_MARGIN_ms = 5;     % Require a real improvement before changing links
SATELLITE_BENEFIT_MARGIN_ms    = 5;     % Satellite must buy at least this much queue-delay relief before we switch to it

% Smoothed terrestrial-rate estimate for future backlog-drain prediction,
ALPHA_TERRESTRIAL_FUTURE_DRAIN = 0.85;

% If terrestrial SNR is catastrophically low (unusable), force switch to satellite even when not in SNR-based mode
SNR_dB_FORCE_SATELLITE = -Inf;    % -inf => turned off

% Persistence rule for binary switching:
% a switch request must persist for this long before it is allowed.
if ENABLE_STABILITY_CONSTRAINTS
    SWITCH_PERSISTENCE_TIME_seconds = 0.05;
else
    SWITCH_PERSISTENCE_TIME_seconds = 0;
end

SWITCH_PERSISTENCE_WINDOWS = max(0, round(SWITCH_PERSISTENCE_TIME_seconds / dt));

%
% Traffic Splitting Parameters
%

if ENABLE_STABILITY_CONSTRAINTS
    ALPHA_SPLIT_FRACTION                    = 0.8;     % Smoothing for interior fraction updates
    MAX_SPLIT_FRACTION_STEP_PER_WINDOW      = 0.15;    % Interior fraction step limit
    MAX_SPLIT_FRACTION_STEP_TO_ENDPOINT     = 0.40;    % Larger step allowed when the desired split is exactly 0 or 1
    SPLIT_ENDPOINT_CAPTURE_THRESHOLD        = 0.05;    % Once sufficiently close to 0 or 1, clamp there
    SPLIT_FRACTION_CHANGE_THRESHOLD         = 0.02;    % Ignore tiny requests
    SPLIT_PERSISTENCE_TIME_seconds          = 0.05;     % The requested direction of change must persist this long
else
    ALPHA_SPLIT_FRACTION                    = 0;
    MAX_SPLIT_FRACTION_STEP_PER_WINDOW      = Inf;
    MAX_SPLIT_FRACTION_STEP_TO_ENDPOINT     = Inf;
    SPLIT_ENDPOINT_CAPTURE_THRESHOLD        = 0;
    SPLIT_FRACTION_CHANGE_THRESHOLD         = 0;
    SPLIT_PERSISTENCE_TIME_seconds          = 0;
end

SPLIT_PERSISTENCE_WINDOWS = max(0, round(SPLIT_PERSISTENCE_TIME_seconds / dt));

% Optimization-mode split fraction search grid
SPLIT_FRACTION_SEARCH_GRID_STEP = 0.05;         % Candidate fractions evaluated every 0.05

SUBQUEUE_TARGET_NUM_WINDOWS = 1;                % Keep lower-layer subqueues shallow, i.e. only stage about one window's worth of service

%
% State variables and outputs
%

%// Outputs

chosen_link_per_window                    = zeros(NUM_WINDOWS, 1);   % 0 = terrestrial, 1 = satellite
split_fraction_per_window                 = zeros(NUM_WINDOWS, 1);   % Fraction of upper-layer traffic assigned to the satellite lower-layer subqueue
satellite_fraction_per_window             = nan(NUM_WINDOWS, 1);     % Fraction of served traffic sent over the satellite link in this window
terrestrial_fraction_per_window           = nan(NUM_WINDOWS, 1);     % Fraction of served traffic sent over the terrestrial link in this window

served_bits_satellite_per_window   = zeros(NUM_WINDOWS, 1);
served_bits_terrestrial_per_window = zeros(NUM_WINDOWS, 1);

queue_bits_per_window                = zeros(NUM_WINDOWS, 1);        % Total backlog across all queues
shared_queue_bits_per_window         = zeros(NUM_WINDOWS, 1);        % Backlog for main upper-layer shared queue
terrestrial_subqueue_bits_per_window = zeros(NUM_WINDOWS, 1);        % Backlog of terrestrial subqueue
satellite_subqueue_bits_per_window   = zeros(NUM_WINDOWS, 1);        % Backlog of satellite subqueue
average_delay_ms_per_window          = nan(NUM_WINDOWS, 1);          % Average delay of the bits that got served this window. @Important: If no bits get served this window, the delay is NaN. This means that this metric should only be used for visualization, not delay comparison across runs.

num_switches             = 0;                                        % Binary switching
num_fraction_changes     = 0;                                        % Traffic splitting
num_requeues_terrestrial = 0;                                        % Number of times the terrestrial subqueue timed out and returned its packets to the main shared queue
num_requeues_satellite   = 0;                                        % Number of times the satellite subqueue timed out and returned its packets to the main shared queue

% Extra outputs for logging and debugging
arriving_bits_per_window                        = zeros(NUM_WINDOWS, 1);
selected_terrestrial_mcs_index_per_window       = nan(NUM_WINDOWS, 1);
predicted_terrestrial_bler_per_window           = nan(NUM_WINDOWS, 1);
satellite_available_at_window                   = false(NUM_WINDOWS, 1);
switch_event_at_window                          = false(NUM_WINDOWS, 1);
fraction_change_at_window                       = false(NUM_WINDOWS, 1);

%// State variables

% Note: The shared, common queue represents packets not yet committed to a lower-layer link subqueue.
% In traffic splitting mode, packets are first placed in the shared queue, then assigned
% to a terrestrial or satellite lower-layer queue according to the split fraction.

shared_queue_bits = 0;              
shared_queue_chunks_bits = [];                                % At every window, we keep track of chunks of bits that arrived at the shared queue together.
shared_queue_original_arrival_times_seconds = [];             % When the chunk first arrived to the system

terrestrial_subqueue_bits = 0;                                % Lower-layer terrestrial subqueue used only in traffic splitting mode
terrestrial_subqueue_chunks_bits = [];
terrestrial_subqueue_assignment_times_seconds = [];
terrestrial_subqueue_original_arrival_times_seconds = [];

satellite_subqueue_bits = 0;                                  % Lower-layer satellite subqueue used only in traffic splitting mode
satellite_subqueue_chunks_bits = [];
satellite_subqueue_assignment_times_seconds = [];
satellite_subqueue_original_arrival_times_seconds = [];

current_link_is_satellite = false;                            % Current link being used (start on terrestrial)
split_fraction = 0.0;                                         % Start on terrestrial link (0 = full terrestrial, 1 = full satellite)
previous_split_fraction = split_fraction;
handover_freeze_remaining_seconds = 0;                        % How many seconds are left when in a reconfiguration freeze due to switching / splitting

pending_desired_link_is_satellite = current_link_is_satellite;
num_windows_same_switch_request   = 0;    % How many windows has it been with same requested switch?

pending_split_request_direction   = 0;    % -1 = decrease split, +1 = increase split
num_windows_same_split_request    = 0;    % How many windows has it been with the requested split in the same direction?

terrestrial_future_drain_rate_bps = NaN;   % EWMA used for future backlog-drain rate prediction

% Bit-weighted latency accumulators for summary stats
latency_values_ms           = [];
latency_weights_bits        = [];
bulk_latency_values_ms      = [];
bulk_latency_weights_bits   = [];
normal_latency_values_ms    = [];
normal_latency_weights_bits = [];

sum_latency_values_times_weights = 0;
total_served_bits = 0;

% For plotting
satellite_rate_bits_per_second_per_window          = nan(NUM_WINDOWS, 1);  % Throughput for current window
terrestrial_rate_bits_per_second_per_window        = nan(NUM_WINDOWS, 1);

estimated_satellite_benefit_ms_per_window             = nan(NUM_WINDOWS, 1);
estimated_satellite_backlog_reduction_bits_per_window = nan(NUM_WINDOWS, 1);
desired_split_fraction_per_window                     = nan(NUM_WINDOWS, 1);
requeued_bits_terrestrial_per_window                  = zeros(NUM_WINDOWS, 1);
requeued_bits_satellite_per_window                    = zeros(NUM_WINDOWS, 1);

%
% Main Loop
%

for window_index = 1 : NUM_WINDOWS

    current_time_seconds = t(window_index);

    % Read current terrestrial SNR
    snr_dB = terrestrial_snr_dB_per_window(window_index);

    is_satellite_available = ...
        ~satellite_outage_at_window(window_index)                && ...
        satellite_access_at_window(window_index)                 && ...
        base_station_in_fov_at_window(window_index)              && ...
        (satellite_rate_up_bps_per_window(window_index) > 0)     && ...
        isfinite(satellite_one_way_delay_ms_per_window(window_index));

    % Packet arrivals
    num_arrivals = poissrnd(AVERAGE_PACKETS_PER_WINDOW(window_index));
    arriving_bits = num_arrivals * PACKET_SIZE_bits;
    current_arrival_rate_bps = AVERAGE_PACKETS_PER_WINDOW(window_index) * PACKET_SIZE_bits / dt;

    % Add arrivals to shared upper-layer queue
    shared_queue_bits = shared_queue_bits + arriving_bits;
    if arriving_bits > 0
        shared_queue_chunks_bits(end + 1, 1) = arriving_bits;
        shared_queue_original_arrival_times_seconds(end + 1, 1) = current_time_seconds;
    end

    %
    % Link metrics
    %

    % Predicted terrestrial rate (from MCS SNR-to-BLER table)
    [terrestrial_rate_bits_per_second, terrestrial_mcs_index, predicted_terrestrial_bler] = rate_from_bler(snr_dB, bler_table);

    % Effective one-way delay experienced in the simulation
    terrestrial_one_way_delay_ms = TERRESTRIAL_ONE_WAY_DELAY_BASE_ms;

    if window_index == 1 || isnan(terrestrial_future_drain_rate_bps)
        terrestrial_future_drain_rate_bps = terrestrial_rate_bits_per_second;
    else
        terrestrial_future_drain_rate_bps = ALPHA_TERRESTRIAL_FUTURE_DRAIN * terrestrial_future_drain_rate_bps + (1 - ALPHA_TERRESTRIAL_FUTURE_DRAIN) * terrestrial_rate_bits_per_second;
    end

    if ~is_satellite_available
        satellite_rate_bits_per_second = 0;
        satellite_one_way_delay_ms     = Inf;
    else
        satellite_rate_bits_per_second = satellite_rate_up_bps_per_window(window_index);
        satellite_one_way_delay_ms     = satellite_one_way_delay_ms_per_window(window_index);
    end

    %
    % Traffic-splitting requeuing: We move packets back to the shared queue if they have
    % waited too long in a lower-layer subqueue whose link is currently unavailable.
    %

    if USE_TRAFFIC_SPLITTING

        % If a lower-layer queue is stuck on a currently unusable link for too long,
        % move the packets (chunk by chunk) back to the shared queue. The packet keeps its original
        % arrival time so its end-to-end delay still includes the time already spent waiting.

        bits_requeued_from_terrestrial = 0;
        if external_trigger_at_window(window_index) || terrestrial_rate_bits_per_second <= 0
            while ~isempty(terrestrial_subqueue_chunks_bits)   % Empty the subqueue

                time_waiting_seconds = current_time_seconds - terrestrial_subqueue_assignment_times_seconds(1);   % Start with the packets that have been in the queue the longest
                if time_waiting_seconds < SPLIT_REQUEUEING_DELAY_ms / 1000
                    break;    % We haven't timed out yet!
                end

                bits_to_requeue = terrestrial_subqueue_chunks_bits(1);
                original_arrival_time_seconds = terrestrial_subqueue_original_arrival_times_seconds(1);

                shared_queue_bits = shared_queue_bits + bits_to_requeue;
                shared_queue_chunks_bits(end + 1, 1) = bits_to_requeue;
                shared_queue_original_arrival_times_seconds(end + 1, 1) = original_arrival_time_seconds;

                terrestrial_subqueue_bits = terrestrial_subqueue_bits - bits_to_requeue;
                bits_requeued_from_terrestrial = bits_requeued_from_terrestrial + bits_to_requeue;

                terrestrial_subqueue_chunks_bits(1)                    = [];
                terrestrial_subqueue_assignment_times_seconds(1)       = [];
                terrestrial_subqueue_original_arrival_times_seconds(1) = [];
            end
        end

        bits_requeued_from_satellite = 0;
        if ~is_satellite_available || satellite_rate_bits_per_second <= 0
            while ~isempty(satellite_subqueue_chunks_bits)

                time_waiting_seconds = current_time_seconds - satellite_subqueue_assignment_times_seconds(1);
                if time_waiting_seconds < SPLIT_REQUEUEING_DELAY_ms / 1000
                    break;
                end

                bits_to_requeue = satellite_subqueue_chunks_bits(1);
                original_arrival_time_seconds = satellite_subqueue_original_arrival_times_seconds(1);

                shared_queue_bits = shared_queue_bits + bits_to_requeue;
                shared_queue_chunks_bits(end + 1, 1) = bits_to_requeue;
                shared_queue_original_arrival_times_seconds(end + 1, 1) = original_arrival_time_seconds;

                satellite_subqueue_bits = satellite_subqueue_bits - bits_to_requeue;
                bits_requeued_from_satellite = bits_requeued_from_satellite + bits_to_requeue;

                satellite_subqueue_chunks_bits(1)                    = [];
                satellite_subqueue_assignment_times_seconds(1)       = [];
                satellite_subqueue_original_arrival_times_seconds(1) = [];
            end
        end

        if bits_requeued_from_terrestrial > 0
            num_requeues_terrestrial = num_requeues_terrestrial + 1;
        end
        if bits_requeued_from_satellite > 0
            num_requeues_satellite = num_requeues_satellite + 1;
        end
    else
        bits_requeued_from_terrestrial = 0;
        bits_requeued_from_satellite   = 0;
    end

    total_backlog_bits = shared_queue_bits + terrestrial_subqueue_bits + satellite_subqueue_bits;

    % Service capacity for this decision window for each link
    % These are used both by the decision logic and later by the service logic.
    
    if is_satellite_available
        satellite_service_capacity_bits = max(0, round(satellite_rate_bits_per_second * dt));
    else
        satellite_service_capacity_bits = 0;
    end

    % External-trigger hard override for traffic splitting:
    % The terrestrial link must not receive or serve any traffic in this window.
    if ~external_trigger_at_window(window_index)
        terrestrial_service_capacity_bits = max(0, round(terrestrial_rate_bits_per_second * dt));
    else
        terrestrial_service_capacity_bits = 0;
    end

    if is_satellite_available

        [estimated_satellite_benefit_ms, estimated_satellite_backlog_reduction_bits] = estimate_satellite_benefit_ms(current_arrival_rate_bps, ...
                                                                                                                     terrestrial_rate_bits_per_second, ...
                                                                                                                     satellite_rate_bits_per_second, ...
                                                                                                                     terrestrial_future_drain_rate_bps, ...
                                                                                                                     terrestrial_one_way_delay_ms, ...
                                                                                                                     satellite_one_way_delay_ms + (USE_TRAFFIC_SPLITTING) * SPLIT_PROCESSING_DELAY_ms);
    else
        estimated_satellite_benefit_ms             = -Inf;
        estimated_satellite_backlog_reduction_bits = 0;
    end

    %
    % Decide how to use the two access links
    %

    if config.steering_policy ~= "steer"    % Baseline policies

        current_link_is_satellite = (config.steering_policy == "satellite");
        split_fraction = double(current_link_is_satellite);
        desired_split_fraction_per_window(window_index) = split_fraction;

    elseif USE_SHARED_QUEUE_ONLY     % Binary switching

        % Choose the single desired link
        if external_trigger_at_window(window_index) || (snr_dB < SNR_dB_FORCE_SATELLITE)
            desired_link_is_satellite = true;
        else

            if current_link_is_satellite
                stay_predicted_backlog_clearance_time_ms = predict_backlog_clearance_time( ...
                    total_backlog_bits, current_arrival_rate_bps, ...
                    satellite_rate_bits_per_second, satellite_one_way_delay_ms);

                switch_predicted_backlog_clearance_time_ms = predict_backlog_clearance_time( ...
                    total_backlog_bits, current_arrival_rate_bps, ...
                    terrestrial_rate_bits_per_second, terrestrial_one_way_delay_ms);

                desired_link_is_satellite = ~(switch_predicted_backlog_clearance_time_ms + PREDICTED_TIME_SWITCH_MARGIN_ms < stay_predicted_backlog_clearance_time_ms);
            else
                stay_predicted_backlog_clearance_time_ms = predict_backlog_clearance_time( ...
                    total_backlog_bits, current_arrival_rate_bps, ...
                    terrestrial_rate_bits_per_second, terrestrial_one_way_delay_ms);

                switch_predicted_backlog_clearance_time_ms = predict_backlog_clearance_time( ...
                    total_backlog_bits, current_arrival_rate_bps, ...
                    satellite_rate_bits_per_second, satellite_one_way_delay_ms);

                desired_link_is_satellite = ...
                    (switch_predicted_backlog_clearance_time_ms + PREDICTED_TIME_SWITCH_MARGIN_ms < stay_predicted_backlog_clearance_time_ms) && ...
                    (estimated_satellite_benefit_ms > SATELLITE_BENEFIT_MARGIN_ms);
            end
        end

        % If satellite is unavailable, do not switch onto it
        if ~is_satellite_available
            desired_link_is_satellite = false;
        end

        we_want_to_switch = desired_link_is_satellite ~= current_link_is_satellite;

        if we_want_to_switch

            if desired_link_is_satellite == pending_desired_link_is_satellite
                num_windows_same_switch_request = num_windows_same_switch_request + 1;
            else
                pending_desired_link_is_satellite = desired_link_is_satellite;
                num_windows_same_switch_request = 1;
            end

            % Enforce persistence
            persistence_is_satisfied = (SWITCH_PERSISTENCE_WINDOWS == 0) || (num_windows_same_switch_request >= SWITCH_PERSISTENCE_WINDOWS);

            if persistence_is_satisfied
                current_link_is_satellite = desired_link_is_satellite;

                switch_event_at_window(window_index) = true;
                num_switches = num_switches + 1;

                pending_desired_link_is_satellite = current_link_is_satellite;
                num_windows_same_switch_request = 0;
            end

        else
            pending_desired_link_is_satellite = current_link_is_satellite;
            num_windows_same_switch_request = 0;
        end

        split_fraction = double(current_link_is_satellite);
        desired_split_fraction_per_window(window_index) = split_fraction;

        % Reconfiguration overhead
        shift = abs(split_fraction - previous_split_fraction);  % How much traffic assignment changed this window

        if ENABLE_HANDOVER_OVERHEAD && (shift > 0)
            handover_freeze_remaining_seconds = handover_freeze_remaining_seconds + HANDOVER_FREEZE_TIME_seconds * shift;
        end

        previous_split_fraction = split_fraction;

    elseif USE_TRAFFIC_SPLITTING

        desired_split_fraction = decide_split_fraction( ...
            terrestrial_rate_bits_per_second, satellite_rate_bits_per_second, ...
            is_satellite_available, external_trigger_at_window(window_index), ...
            snr_dB, split_fraction, ...
            shared_queue_bits, terrestrial_subqueue_bits, satellite_subqueue_bits, ...
            terrestrial_service_capacity_bits, satellite_service_capacity_bits, ...
            terrestrial_one_way_delay_ms + SPLIT_PROCESSING_DELAY_ms, satellite_one_way_delay_ms + SPLIT_PROCESSING_DELAY_ms, ...
            current_arrival_rate_bps, estimated_satellite_benefit_ms);

        % Stability controls
        if ~is_satellite_available

            desired_split_fraction          = 0;
            split_fraction                  = 0;
            pending_split_request_direction = 0;
            num_windows_same_split_request  = 0;

        else

            requested_split_change = desired_split_fraction - split_fraction;
            split_fraction_change = abs(requested_split_change);
            is_split_fraction_change_significant = split_fraction_change >= SPLIT_FRACTION_CHANGE_THRESHOLD;

            if is_split_fraction_change_significant

                requested_split_direction = sign(requested_split_change);

                if requested_split_direction == pending_split_request_direction
                    num_windows_same_split_request = num_windows_same_split_request + 1;
                else
                    pending_split_request_direction = requested_split_direction;
                    num_windows_same_split_request = 1;
                end

                persistence_is_satisfied = (SPLIT_PERSISTENCE_WINDOWS == 0) || (num_windows_same_split_request >= SPLIT_PERSISTENCE_WINDOWS);

                if persistence_is_satisfied

                    if desired_split_fraction == 0 || desired_split_fraction == 1
                        target_split_fraction = desired_split_fraction;
                        max_fraction_step_this_window = MAX_SPLIT_FRACTION_STEP_TO_ENDPOINT;
                    else
                        target_split_fraction = ALPHA_SPLIT_FRACTION * split_fraction + (1 - ALPHA_SPLIT_FRACTION) * desired_split_fraction;
                        max_fraction_step_this_window = MAX_SPLIT_FRACTION_STEP_PER_WINDOW;
                    end

                    delta = target_split_fraction - split_fraction;
                    delta = max(-max_fraction_step_this_window, min(max_fraction_step_this_window, delta));

                    new_split_fraction = split_fraction + delta;
                    new_split_fraction = max(0, min(1, new_split_fraction));

                    if desired_split_fraction == 0 && new_split_fraction <= SPLIT_ENDPOINT_CAPTURE_THRESHOLD
                        new_split_fraction = 0;
                    elseif desired_split_fraction == 1 && new_split_fraction >= 1 - SPLIT_ENDPOINT_CAPTURE_THRESHOLD
                        new_split_fraction = 1;
                    end

                    if new_split_fraction ~= split_fraction

                        split_fraction = new_split_fraction;

                        fraction_change_at_window(window_index) = true;
                        num_fraction_changes = num_fraction_changes + 1;

                        pending_split_request_direction = 0;
                        num_windows_same_split_request = 0;
                    end
                end

            else
                pending_split_request_direction = 0;
                num_windows_same_split_request = 0;
            end
        end

        desired_split_fraction_per_window(window_index) = desired_split_fraction;

        % Reconfiguration overhead
        satellite_becomes_active   = (previous_split_fraction == 0) && (split_fraction > 0);
        terrestrial_becomes_active = (previous_split_fraction == 1) && (split_fraction < 1);

        if ENABLE_HANDOVER_OVERHEAD && (satellite_becomes_active || terrestrial_becomes_active)
            handover_freeze_remaining_seconds = handover_freeze_remaining_seconds + HANDOVER_FREEZE_TIME_seconds;
        end

        previous_split_fraction = split_fraction;

        current_link_is_satellite = (split_fraction >= 0.5);  % For plotting/debugging
    else
        error("Unknown coordination mode: %s", config.coordination_mode);
    end

    % For plotting / debugging
    terrestrial_rate_bits_per_second_per_window(window_index)        = terrestrial_rate_bits_per_second;
    satellite_rate_bits_per_second_per_window(window_index)          = satellite_rate_bits_per_second;

    %
    % Service the queues
    % Binary switching:  Single shared queue
    % Traffic Splitting: Shared queue feeding two lower-layer subqueues
    %

    % Reconfiguration freeze
    % During handover (switching or split fraction update), service capacity is reduced.
    if ENABLE_HANDOVER_OVERHEAD && (handover_freeze_remaining_seconds > 0)

        % Portion of this decision window when service is interrupted
        freeze_fraction = min(1, handover_freeze_remaining_seconds / dt);

        terrestrial_service_capacity_bits = round(terrestrial_service_capacity_bits * (1 - freeze_fraction));
        satellite_service_capacity_bits   = round(satellite_service_capacity_bits   * (1 - freeze_fraction));

        handover_freeze_remaining_seconds = max(0, handover_freeze_remaining_seconds - dt);
    end

    % If we are in splitting mode, dispatch the shared queue into the two lower-layer subqueues.
    % Assigned traffic is bounded by the link's capacity so that the subqueues remain shallow and backlog accumulates in the shared queue only.
    num_bits_to_dispatch = 0;
    num_bits_to_dispatch_to_terrestrial = 0;
    num_bits_to_dispatch_to_satellite   = 0;

    if USE_TRAFFIC_SPLITTING && shared_queue_bits > 0

        terrestrial_subqueue_target_bits = SUBQUEUE_TARGET_NUM_WINDOWS * terrestrial_service_capacity_bits;
        satellite_subqueue_target_bits   = SUBQUEUE_TARGET_NUM_WINDOWS * satellite_service_capacity_bits;

        terrestrial_subqueue_available_bits = max(0, terrestrial_subqueue_target_bits - terrestrial_subqueue_bits);
        satellite_subqueue_available_bits   = max(0, satellite_subqueue_target_bits   - satellite_subqueue_bits);

        if split_fraction <= 0
            num_bits_to_dispatch = min(shared_queue_bits, terrestrial_subqueue_available_bits);

            num_bits_to_dispatch_to_satellite   = 0;
            num_bits_to_dispatch_to_terrestrial = num_bits_to_dispatch;

        elseif split_fraction >= 1
            num_bits_to_dispatch = min(shared_queue_bits, satellite_subqueue_available_bits);

            num_bits_to_dispatch_to_satellite   = num_bits_to_dispatch;
            num_bits_to_dispatch_to_terrestrial = 0;

        else
            num_bits_to_dispatch = min(shared_queue_bits, terrestrial_subqueue_available_bits + satellite_subqueue_available_bits);

            num_bits_to_dispatch_to_satellite   = min(satellite_subqueue_available_bits,   round(split_fraction * num_bits_to_dispatch));
            num_bits_to_dispatch_to_terrestrial = min(terrestrial_subqueue_available_bits, num_bits_to_dispatch - num_bits_to_dispatch_to_satellite);

            remaining_bits_to_dispatch = num_bits_to_dispatch - num_bits_to_dispatch_to_satellite - num_bits_to_dispatch_to_terrestrial;

            if remaining_bits_to_dispatch > 0
                extra_bits_to_dispatch_to_terrestrial = min(remaining_bits_to_dispatch, terrestrial_subqueue_available_bits - num_bits_to_dispatch_to_terrestrial);
                num_bits_to_dispatch_to_terrestrial = num_bits_to_dispatch_to_terrestrial + extra_bits_to_dispatch_to_terrestrial;
                remaining_bits_to_dispatch = remaining_bits_to_dispatch - extra_bits_to_dispatch_to_terrestrial;

                extra_bits_to_dispatch_to_satellite = min(remaining_bits_to_dispatch, satellite_subqueue_available_bits - num_bits_to_dispatch_to_satellite);
                num_bits_to_dispatch_to_satellite = num_bits_to_dispatch_to_satellite + extra_bits_to_dispatch_to_satellite;
            end
        end

        remaining_bits_to_dispatch_to_terrestrial = num_bits_to_dispatch_to_terrestrial;
        remaining_bits_to_dispatch_to_satellite   = num_bits_to_dispatch_to_satellite;

        while (remaining_bits_to_dispatch_to_terrestrial > 0 || remaining_bits_to_dispatch_to_satellite > 0) && ~isempty(shared_queue_chunks_bits)

            current_chunk_bits = shared_queue_chunks_bits(1);
            current_chunk_bits_to_dispatch = min(current_chunk_bits, remaining_bits_to_dispatch_to_terrestrial + remaining_bits_to_dispatch_to_satellite);
            current_chunk_original_arrival_time_seconds = shared_queue_original_arrival_times_seconds(1);

            if (remaining_bits_to_dispatch_to_terrestrial + remaining_bits_to_dispatch_to_satellite) > 0
                satellite_chunk_bits = min(remaining_bits_to_dispatch_to_satellite, round(current_chunk_bits_to_dispatch * remaining_bits_to_dispatch_to_satellite / (remaining_bits_to_dispatch_to_terrestrial + remaining_bits_to_dispatch_to_satellite)));
            else
                satellite_chunk_bits = 0;
            end
            terrestrial_chunk_bits = min(remaining_bits_to_dispatch_to_terrestrial, current_chunk_bits_to_dispatch - satellite_chunk_bits);

            if terrestrial_chunk_bits > 0
                terrestrial_subqueue_bits = terrestrial_subqueue_bits + terrestrial_chunk_bits;
                terrestrial_subqueue_chunks_bits(end + 1, 1) = terrestrial_chunk_bits;
                terrestrial_subqueue_assignment_times_seconds(end + 1, 1) = current_time_seconds;
                terrestrial_subqueue_original_arrival_times_seconds(end + 1, 1) = current_chunk_original_arrival_time_seconds;
                remaining_bits_to_dispatch_to_terrestrial = remaining_bits_to_dispatch_to_terrestrial - terrestrial_chunk_bits;
            end

            if satellite_chunk_bits > 0
                satellite_subqueue_bits = satellite_subqueue_bits + satellite_chunk_bits;
                satellite_subqueue_chunks_bits(end + 1, 1) = satellite_chunk_bits;
                satellite_subqueue_assignment_times_seconds(end + 1, 1) = current_time_seconds;
                satellite_subqueue_original_arrival_times_seconds(end + 1, 1) = current_chunk_original_arrival_time_seconds;
                remaining_bits_to_dispatch_to_satellite = remaining_bits_to_dispatch_to_satellite - satellite_chunk_bits;
            end

            shared_queue_bits = shared_queue_bits - terrestrial_chunk_bits - satellite_chunk_bits;
            shared_queue_chunks_bits(1) = shared_queue_chunks_bits(1) - terrestrial_chunk_bits - satellite_chunk_bits;

            if shared_queue_chunks_bits(1) == 0
                shared_queue_chunks_bits(1) = [];
                shared_queue_original_arrival_times_seconds(1) = [];
            end
        end
    end

    % Serve queue(s)
    served_bits_terrestrial = 0;
    served_bits_satellite   = 0;
    weighted_window_latency_sum_ms = 0;
    departure_time_seconds = current_time_seconds + dt;

    is_bulk_window = (current_time_seconds >= config.bulk_start_seconds) && (current_time_seconds <= config.bulk_end_seconds);

    if USE_SHARED_QUEUE_ONLY

        % Serve queue on chosen link
        if current_link_is_satellite
            bits_to_serve_from_shared_queue = min(shared_queue_bits, satellite_service_capacity_bits);
            link_latency_ms = satellite_one_way_delay_ms;
        else
            bits_to_serve_from_shared_queue = min(shared_queue_bits, terrestrial_service_capacity_bits);
            link_latency_ms = terrestrial_one_way_delay_ms;
        end

        served_bits_this_window = bits_to_serve_from_shared_queue;
        remaining_bits_to_serve = bits_to_serve_from_shared_queue;

        while remaining_bits_to_serve > 0 && ~isempty(shared_queue_chunks_bits)
            bits_from_chunk = min(remaining_bits_to_serve, shared_queue_chunks_bits(1));
            queuing_delay_ms = 1000 * (departure_time_seconds - shared_queue_original_arrival_times_seconds(1));
            packet_latency_ms = queuing_delay_ms + link_latency_ms;

            weighted_window_latency_sum_ms = weighted_window_latency_sum_ms + packet_latency_ms * bits_from_chunk;

            if isfinite(packet_latency_ms) && isfinite(bits_from_chunk) && bits_from_chunk > 0
                sum_latency_values_times_weights = sum_latency_values_times_weights + packet_latency_ms * bits_from_chunk;
                total_served_bits = total_served_bits + bits_from_chunk;

                latency_values_ms(end + 1, 1) = packet_latency_ms;
                latency_weights_bits(end + 1, 1) = bits_from_chunk;

                if is_bulk_window
                    bulk_latency_values_ms(end + 1, 1) = packet_latency_ms;
                    bulk_latency_weights_bits(end + 1, 1) = bits_from_chunk;
                else
                    normal_latency_values_ms(end + 1, 1) = packet_latency_ms;
                    normal_latency_weights_bits(end + 1, 1) = bits_from_chunk;
                end
            end

            remaining_bits_to_serve = remaining_bits_to_serve - bits_from_chunk;
            shared_queue_chunks_bits(1) = shared_queue_chunks_bits(1) - bits_from_chunk;
            shared_queue_bits = shared_queue_bits - bits_from_chunk;

            if shared_queue_chunks_bits(1) == 0
                shared_queue_chunks_bits(1) = [];
                shared_queue_original_arrival_times_seconds(1) = [];
            end
        end

        if current_link_is_satellite
            served_bits_satellite = served_bits_this_window;
        else
            served_bits_terrestrial = served_bits_this_window;
        end

    elseif USE_TRAFFIC_SPLITTING

        % Serve terrestrial lower-layer queue
        remaining_terrestrial_bits_to_serve = min(terrestrial_subqueue_bits, terrestrial_service_capacity_bits);
        served_bits_terrestrial = remaining_terrestrial_bits_to_serve;
        while remaining_terrestrial_bits_to_serve > 0 && ~isempty(terrestrial_subqueue_chunks_bits)
            bits_from_chunk = min(remaining_terrestrial_bits_to_serve, terrestrial_subqueue_chunks_bits(1));
            queuing_delay_ms = 1000 * (departure_time_seconds - terrestrial_subqueue_original_arrival_times_seconds(1));
            packet_latency_ms = queuing_delay_ms + terrestrial_one_way_delay_ms + SPLIT_PROCESSING_DELAY_ms;

            weighted_window_latency_sum_ms = weighted_window_latency_sum_ms + packet_latency_ms * bits_from_chunk;

            if isfinite(packet_latency_ms) && isfinite(bits_from_chunk) && bits_from_chunk > 0
                sum_latency_values_times_weights = sum_latency_values_times_weights + packet_latency_ms * bits_from_chunk;
                total_served_bits = total_served_bits + bits_from_chunk;

                latency_values_ms(end + 1, 1) = packet_latency_ms;
                latency_weights_bits(end + 1, 1) = bits_from_chunk;

                if is_bulk_window
                    bulk_latency_values_ms(end + 1, 1) = packet_latency_ms;
                    bulk_latency_weights_bits(end + 1, 1) = bits_from_chunk;
                else
                    normal_latency_values_ms(end + 1, 1) = packet_latency_ms;
                    normal_latency_weights_bits(end + 1, 1) = bits_from_chunk;
                end
            end

            remaining_terrestrial_bits_to_serve = remaining_terrestrial_bits_to_serve - bits_from_chunk;
            terrestrial_subqueue_chunks_bits(1) = terrestrial_subqueue_chunks_bits(1) - bits_from_chunk;
            terrestrial_subqueue_bits = terrestrial_subqueue_bits - bits_from_chunk;

            if terrestrial_subqueue_chunks_bits(1) == 0
                terrestrial_subqueue_chunks_bits(1) = [];
                terrestrial_subqueue_assignment_times_seconds(1) = [];
                terrestrial_subqueue_original_arrival_times_seconds(1) = [];
            end
        end

        % Serve satellite lower-layer queue
        remaining_satellite_bits_to_serve = min(satellite_subqueue_bits, satellite_service_capacity_bits);
        served_bits_satellite = remaining_satellite_bits_to_serve;

        while remaining_satellite_bits_to_serve > 0 && ~isempty(satellite_subqueue_chunks_bits)
            bits_from_chunk = min(remaining_satellite_bits_to_serve, satellite_subqueue_chunks_bits(1));
            queuing_delay_ms = 1000 * (departure_time_seconds - satellite_subqueue_original_arrival_times_seconds(1));
            packet_latency_ms = queuing_delay_ms + satellite_one_way_delay_ms + SPLIT_PROCESSING_DELAY_ms;

            weighted_window_latency_sum_ms = weighted_window_latency_sum_ms + packet_latency_ms * bits_from_chunk;

            if isfinite(packet_latency_ms) && isfinite(bits_from_chunk) && bits_from_chunk > 0
                sum_latency_values_times_weights = sum_latency_values_times_weights + packet_latency_ms * bits_from_chunk;
                total_served_bits = total_served_bits + bits_from_chunk;

                latency_values_ms(end + 1, 1)    = packet_latency_ms;
                latency_weights_bits(end + 1, 1) = bits_from_chunk;

                if is_bulk_window
                    bulk_latency_values_ms(end + 1, 1)    = packet_latency_ms;
                    bulk_latency_weights_bits(end + 1, 1) = bits_from_chunk;
                else
                    normal_latency_values_ms(end + 1, 1)    = packet_latency_ms;
                    normal_latency_weights_bits(end + 1, 1) = bits_from_chunk;
                end
            end

            remaining_satellite_bits_to_serve = remaining_satellite_bits_to_serve - bits_from_chunk;
            satellite_subqueue_chunks_bits(1) = satellite_subqueue_chunks_bits(1) - bits_from_chunk;
            satellite_subqueue_bits = satellite_subqueue_bits - bits_from_chunk;

            if satellite_subqueue_chunks_bits(1) == 0
                satellite_subqueue_chunks_bits(1) = [];
                satellite_subqueue_assignment_times_seconds(1) = [];
                satellite_subqueue_original_arrival_times_seconds(1) = [];
            end
        end

    else
        error("Unknown coordination mode: %s", config.coordination_mode);
    end

    served_bits_this_window = served_bits_terrestrial + served_bits_satellite;

    if served_bits_this_window > 0
        average_delay_ms_per_window(window_index)     = weighted_window_latency_sum_ms / served_bits_this_window;
        satellite_fraction_per_window(window_index)   = served_bits_satellite   / served_bits_this_window;
        terrestrial_fraction_per_window(window_index) = served_bits_terrestrial / served_bits_this_window;
    end

    %
    % Log outputs
    %

    chosen_link_per_window(window_index) = current_link_is_satellite;
    split_fraction_per_window(window_index) = split_fraction;

    if USE_TRAFFIC_SPLITTING
        if num_bits_to_dispatch > 0
            split_fraction_per_window(window_index) = num_bits_to_dispatch_to_satellite / num_bits_to_dispatch;   % Split fraction is the fraction of shared queue traffic assigned to satellite that window
        else
            split_fraction_per_window(window_index) = NaN;
        end
    end

    served_bits_satellite_per_window(window_index)   = served_bits_satellite;
    served_bits_terrestrial_per_window(window_index) = served_bits_terrestrial;

    queue_bits_per_window(window_index)                = shared_queue_bits + terrestrial_subqueue_bits + satellite_subqueue_bits;
    shared_queue_bits_per_window(window_index)         = shared_queue_bits;
    terrestrial_subqueue_bits_per_window(window_index) = terrestrial_subqueue_bits;
    satellite_subqueue_bits_per_window(window_index)   = satellite_subqueue_bits;

    arriving_bits_per_window(window_index)                  = arriving_bits;
    selected_terrestrial_mcs_index_per_window(window_index) = terrestrial_mcs_index;
    predicted_terrestrial_bler_per_window(window_index)     = predicted_terrestrial_bler;
    satellite_available_at_window(window_index)             = is_satellite_available;

    estimated_satellite_benefit_ms_per_window(window_index)             = estimated_satellite_benefit_ms;
    estimated_satellite_backlog_reduction_bits_per_window(window_index) = estimated_satellite_backlog_reduction_bits;
    requeued_bits_terrestrial_per_window(window_index)                  = bits_requeued_from_terrestrial;
    requeued_bits_satellite_per_window(window_index)                    = bits_requeued_from_satellite;

end


%
% Plots
%

% Main figure
figure;
set(gcf, "Color", "w", "InvertHardcopy", "off");
set(gcf, "Position", [100 80 1280 930]);
main_layout = tiledlayout(4, 1, "TileSpacing", "compact", "Padding", "compact");
sgtitle(main_layout, "Hybrid Terrestrial-Satellite Switching", "Interpreter", "none", "FontSize", 16, "FontWeight", "bold");

nexttile;
plot(t, terrestrial_snr_dB_per_window, "LineWidth", 1.8);
grid on;
ylabel("Terrestrial 5G SNR (dB)");
title("Terrestrial link quality", "FontSize", 14);

nexttile;
if USE_SHARED_QUEUE_ONLY
    stairs(t, chosen_link_per_window, "LineWidth", 2.0);
    ylabel("Link (0=Terr, 1=Sat)");
    title("Chosen access link", "FontSize", 14);
else
    hold on;
    plot(t, satellite_fraction_per_window, "LineWidth", 2.0);
    ylim([-0.05 1.05]);
    ylabel("Satellite fraction");
    title("Satellite traffic usage vs. assigned split", "FontSize", 14);
end
grid on;

nexttile;
plot(t, queue_bits_per_window / 1e6, "LineWidth", 1.8);
grid on;
ylabel("Queue size (Mbits)");
title("Total backlog", "FontSize", 14);

nexttile;
plot(t, average_delay_ms_per_window, "LineWidth", 1.8);
grid on;
xlabel("Time (s)");
ylabel("Average delay (ms)");
title("Average delay of served traffic", "FontSize", 14);

exportgraphics(gcf, fullfile(fig_results_directory, "main_" + run_tag + ".png"), "Resolution", 300, "BackgroundColor", "white");
close(gcf);

%
% Latency summary statistics
%

valid_latency_mask = isfinite(latency_values_ms) & isfinite(latency_weights_bits) & (latency_weights_bits > 0);

latency_values_ms    = latency_values_ms(valid_latency_mask);
latency_weights_bits = latency_weights_bits(valid_latency_mask);

if total_served_bits <= 0 || isempty(latency_values_ms)
    disp("No packets served. Latency statistics undefined.");

    p50_ms          = NaN;
    p95_ms          = NaN;
    p99_ms          = NaN;
    max_latency_ms  = NaN;
    mean_latency_ms = NaN;

    bulk_p95_ms   = NaN;
    bulk_p99_ms   = NaN;
    normal_p95_ms = NaN;
    normal_p99_ms = NaN;
else
    mean_latency_ms = sum_latency_values_times_weights / total_served_bits;
    p50_ms          = weighted_percentile(latency_values_ms, latency_weights_bits, 50);
    p95_ms          = weighted_percentile(latency_values_ms, latency_weights_bits, 95);
    p99_ms          = weighted_percentile(latency_values_ms, latency_weights_bits, 99);
    max_latency_ms  = max(latency_values_ms);

    disp("Average delay: " + string(mean_latency_ms) + " ms");

    fprintf("Latency percentiles: P50 = %.2f ms, P95 = %.2f ms, P99 = %.2f, max = %.2f ms\n", ...
        p50_ms, p95_ms, p99_ms, max_latency_ms);

    if isempty(bulk_latency_values_ms)
        bulk_p95_ms = NaN;
        bulk_p99_ms = NaN;
    else
        bulk_p95_ms = weighted_percentile(bulk_latency_values_ms, bulk_latency_weights_bits, 95);
        bulk_p99_ms = weighted_percentile(bulk_latency_values_ms, bulk_latency_weights_bits, 99);
        fprintf("Bulk traffic period delay: P95 = %.2f ms, P99 = %.2f ms\n", bulk_p95_ms, bulk_p99_ms);
    end

    if isempty(normal_latency_values_ms)
        normal_p95_ms = NaN;
        normal_p99_ms = NaN;
    else
        normal_p95_ms = weighted_percentile(normal_latency_values_ms, normal_latency_weights_bits, 95);
        normal_p99_ms = weighted_percentile(normal_latency_values_ms, normal_latency_weights_bits, 99);
        fprintf("Normal traffic period delay: P95 = %.2f ms, P99 = %.2f ms\n", normal_p95_ms, normal_p99_ms);
    end

end

%%%%%%%%%%%%%%%%
% Save results %
%%%%%%%%%%%%%%%%

results = struct();

results.config         = config;
results.run_tag        = run_tag;
results.scenario_tag   = scenario_tag;
results.region_quality = region_quality;

results.summary = struct();
results.summary.num_switches                      = num_switches;
results.summary.num_fraction_changes              = num_fraction_changes;
results.summary.num_requeues_terrestrial          = num_requeues_terrestrial;
results.summary.num_requeues_satellite            = num_requeues_satellite;
results.summary.mean_delay_ms                     = mean_latency_ms;
results.summary.p50_delay_ms                      = p50_ms;
results.summary.p95_delay_ms                      = p95_ms;
results.summary.p99_delay_ms                      = p99_ms;
results.summary.max_delay_ms                      = max_latency_ms;
results.summary.final_queue_bits                  = queue_bits_per_window(end);
results.summary.max_queue_bits                    = max(queue_bits_per_window);
results.summary.total_served_bits_satellite       = sum(served_bits_satellite_per_window);
results.summary.total_served_bits_terrestrial     = sum(served_bits_terrestrial_per_window);
results.summary.total_served_bits                 = results.summary.total_served_bits_satellite + results.summary.total_served_bits_terrestrial;
results.summary.bulk_p95_ms                       = bulk_p95_ms;
results.summary.bulk_p99_ms                       = bulk_p99_ms;
results.summary.normal_p95_ms                     = normal_p95_ms;
results.summary.normal_p99_ms                     = normal_p99_ms;

if results.summary.total_served_bits > 0
    results.summary.mean_satellite_traffic_fraction = results.summary.total_served_bits_satellite / results.summary.total_served_bits;
    results.summary.mean_terrestrial_traffic_fraction = results.summary.total_served_bits_terrestrial / results.summary.total_served_bits;
else
    results.summary.mean_satellite_traffic_fraction = NaN;
    results.summary.mean_terrestrial_traffic_fraction = NaN;
end

results.summary.window_average_satellite_traffic_fraction   = mean(satellite_fraction_per_window, "omitnan");
results.summary.window_average_terrestrial_traffic_fraction = mean(terrestrial_fraction_per_window, "omitnan");

results.traces = struct();
results.traces.time_seconds_per_window                     = t;
results.traces.chosen_link_per_window                      = chosen_link_per_window;
results.traces.split_fraction_per_window                   = split_fraction_per_window;
results.traces.satellite_traffic_fraction_per_window       = satellite_fraction_per_window;
results.traces.terrestrial_traffic_fraction_per_window     = terrestrial_fraction_per_window;
results.traces.arriving_bits_per_window                    = arriving_bits_per_window;
results.traces.served_bits_satellite_per_window            = served_bits_satellite_per_window;
results.traces.served_bits_terrestrial_per_window          = served_bits_terrestrial_per_window;
results.traces.queue_bits_per_window                       = queue_bits_per_window;
results.traces.shared_queue_bits_per_window                = shared_queue_bits_per_window;
results.traces.terrestrial_subqueue_bits_per_window        = terrestrial_subqueue_bits_per_window;
results.traces.satellite_subqueue_bits_per_window          = satellite_subqueue_bits_per_window;
results.traces.average_delay_ms_per_window                 = average_delay_ms_per_window;
results.traces.terrestrial_rate_bits_per_second_per_window = terrestrial_rate_bits_per_second_per_window;
results.traces.satellite_rate_bits_per_second_per_window   = satellite_rate_bits_per_second_per_window;
results.traces.selected_terrestrial_mcs_index_per_window   = selected_terrestrial_mcs_index_per_window;
results.traces.predicted_terrestrial_bler_per_window       = predicted_terrestrial_bler_per_window;
results.traces.switch_event_at_window                      = switch_event_at_window;
results.traces.fraction_change_at_window                   = fraction_change_at_window;
results.traces.requeued_bits_terrestrial_per_window        = requeued_bits_terrestrial_per_window;
results.traces.requeued_bits_satellite_per_window          = requeued_bits_satellite_per_window;

% Debugging
results.traces.estimated_satellite_benefit_ms_per_window             = estimated_satellite_benefit_ms_per_window;
results.traces.estimated_satellite_backlog_reduction_bits_per_window = estimated_satellite_backlog_reduction_bits_per_window;
results.traces.desired_split_fraction_per_window                     = desired_split_fraction_per_window;    % Desired fraction before smoothing and before applying service-capacity cap

results_file = fullfile(data_results_directory, "results_" + run_tag + ".mat");
save(results_file, "results");
disp("Wrote " + results_file);

% @Note: Important prints
% mean latency, P95 latency, peak queue size, mean satellite Traffic Fraction
disp("Metrics for the paper...");
disp("Mean latency (ms): " + string(mean_latency_ms));
disp("P95 latency (ms): " + string(p95_ms));
disp("Peak queue size (Mbits): " + string(max(queue_bits_per_window) / 1000000));
disp("Mean satellite traffic fraction (%): " + string(100 * results.summary.total_served_bits_satellite / results.summary.total_served_bits));
if USE_SHARED_QUEUE_ONLY
    disp("Number of switches: " + string(num_switches));
elseif USE_TRAFFIC_SPLITTING
    disp("Number of fraction changes: " + string(num_fraction_changes));
end

end

%//
%// Helper functions
%//

function config = set_default(config, field_name, default_value)
    if ~isfield(config, field_name)
        config.(field_name) = default_value;
    end
end


function tag = bool_to_tag(flag)
    if flag
        tag = "on";
    else
        tag = "off";
    end
end


function desired_link_is_satellite = decide_link_snr(snr_dB, current_link_is_satellite, external_trigger)

    global SNR_dB_SWITCH_TO_SATELLITE SNR_dB_SWITCH_BACK_TO_TERRESTRIAL

    % snr-based switching logic

    if external_trigger
        desired_link_is_satellite = true;
        return;
    end

    if current_link_is_satellite
        % Stay on satellite until terrestrial SNR recovers above high threshold
        desired_link_is_satellite = (snr_dB <= SNR_dB_SWITCH_BACK_TO_TERRESTRIAL);
    else
        % Switch to satellite if terrestrial SNR drops below low threshold
        desired_link_is_satellite = (snr_dB < SNR_dB_SWITCH_TO_SATELLITE);
    end

end


function [rate_bits_per_second, mcs_index, predicted_bler] = rate_from_bler(snr_dB, bler_table)

    global BLER_TARGET BLER_INTERPOLATION_METHOD

    % Calculate the projected terrestrial uplink rate using a BLER table lookup

    % Expected BLER table fields:
    % bler_table.snrs_dB
    % bler_table.mcs_indices
    % bler_table.transport_block_sizes_bits_per_slot
    % bler_table.bler
    % bler_table.slot_duration_seconds

    snrs_dB = bler_table.snrs_dB;
    num_mcs_indices = length(bler_table.mcs_indices);

    bler_at_snr = nan(num_mcs_indices, 1);
    goodputs_bits_per_slot = nan(num_mcs_indices, 1);

    for index = 1 : num_mcs_indices
        bler_per_snr = bler_table.bler(index, :);

        % Clamp interpolation to edges of our SNR grid
        snr_dB_clamped = min(max(snr_dB, snrs_dB(1)), snrs_dB(end));
        bler_at_snr_at_mcs_index = interp1(snrs_dB, bler_per_snr, snr_dB_clamped, BLER_INTERPOLATION_METHOD);

        bler_at_snr_at_mcs_index = min(max(bler_at_snr_at_mcs_index, 0), 1);
        bler_at_snr(index) = bler_at_snr_at_mcs_index;

        goodputs_bits_per_slot(index) = (1 - bler_at_snr_at_mcs_index) * bler_table.transport_block_sizes_bits_per_slot(index);
    end

    % Link adaptation: Choose the highest goodput among those meeting the BLER target
    mcs_meeting_target_bler = (bler_at_snr <= BLER_TARGET);

    if any(mcs_meeting_target_bler)
        [~, index] = max(goodputs_bits_per_slot .* mcs_meeting_target_bler);
    else
        % If nothing meets target, just pick the settings that give the most robust BLER
        [~, index] = min(bler_at_snr);
    end

    mcs_index = bler_table.mcs_indices(index);
    predicted_bler = bler_at_snr(index);
    rate_bits_per_second = goodputs_bits_per_slot(index) / bler_table.slot_duration_seconds;

end


function predicted_time_ms = predict_backlog_clearance_time(queue_bits, arrival_rate_bps, rate_bps, one_way_delay_ms)

    global DECISION_HORIZON_seconds

    %if rate_bps <= 0 || isinf(one_way_delay_ms)
    %    predicted_time_ms = Inf;
    %    return;
    %end

    remaining_queue_bits = max(0, queue_bits + arrival_rate_bps * DECISION_HORIZON_seconds - rate_bps * DECISION_HORIZON_seconds);  % How many bits remain after a short horizon assuming the arrival rate and link rate remain constant?

    predicted_time_ms = 1000 * (remaining_queue_bits / max(1, rate_bps)) + one_way_delay_ms;
end


function desired_split_fraction = decide_split_fraction( ...
    terrestrial_rate_bits_per_second, satellite_rate_bits_per_second, ...
    is_satellite_available, external_trigger, ...
    snr_dB, current_split_fraction, ...
    shared_queue_bits, terrestrial_subqueue_bits, satellite_subqueue_bits, ...
    terrestrial_service_capacity_bits, satellite_service_capacity_bits, ...
    terrestrial_one_way_delay_ms, satellite_one_way_delay_ms, ...
    current_arrival_rate_bps, estimated_satellite_benefit_ms)

    global SPLIT_FRACTION_SEARCH_GRID_STEP
    global SNR_dB_FORCE_SATELLITE
    global SATELLITE_BENEFIT_MARGIN_ms
    global SUBQUEUE_TARGET_NUM_WINDOWS

    % Decide the satellite split traffic fraction [0, 1]

    % External event trigger override or catastrophic terrestrial condition ===> full satellite
    if external_trigger || (snr_dB < SNR_dB_FORCE_SATELLITE)
        desired_split_fraction = 1;
        return;
    end

    % If satellite is unusable ===> full terrestrial
    if ~is_satellite_available || satellite_rate_bits_per_second <= 0
        desired_split_fraction = 0;
        return;
    end

    % If terrestrial is unusable ===> full satellite
    if terrestrial_rate_bits_per_second <= 0
        desired_split_fraction = 1;
        return;
    end

    % Minimize the delay over a grid of possible fractions
    split_fractions = 0 : SPLIT_FRACTION_SEARCH_GRID_STEP : 1;
    predicted_times_ms = Inf(size(split_fractions));

    terrestrial_subqueue_target_bits = SUBQUEUE_TARGET_NUM_WINDOWS * terrestrial_service_capacity_bits;
    satellite_subqueue_target_bits   = SUBQUEUE_TARGET_NUM_WINDOWS * satellite_service_capacity_bits;

    terrestrial_subqueue_available_bits = max(0, terrestrial_subqueue_target_bits - terrestrial_subqueue_bits);
    satellite_subqueue_available_bits   = max(0, satellite_subqueue_target_bits   - satellite_subqueue_bits);

    for split_fraction_index = 1 : length(split_fractions)

        split_fraction_candidate = split_fractions(split_fraction_index);

        % Calculate number of bits to serve on each subqueue based on the link's service cap
        if split_fraction_candidate <= 0
            num_bits_to_dispatch = min(shared_queue_bits, terrestrial_subqueue_available_bits);

            num_bits_to_dispatch_to_satellite   = 0;
            num_bits_to_dispatch_to_terrestrial = num_bits_to_dispatch;

        elseif split_fraction_candidate >= 1
            num_bits_to_dispatch = min(shared_queue_bits, satellite_subqueue_available_bits);

            num_bits_to_dispatch_to_satellite   = num_bits_to_dispatch;
            num_bits_to_dispatch_to_terrestrial = 0;

        else
            num_bits_to_dispatch = min(shared_queue_bits, terrestrial_subqueue_available_bits + satellite_subqueue_available_bits);

            num_bits_to_dispatch_to_satellite   = min(satellite_subqueue_available_bits,   round(split_fraction_candidate * num_bits_to_dispatch));
            num_bits_to_dispatch_to_terrestrial = min(terrestrial_subqueue_available_bits, num_bits_to_dispatch - num_bits_to_dispatch_to_satellite);

            remaining_bits_to_dispatch = num_bits_to_dispatch - num_bits_to_dispatch_to_satellite - num_bits_to_dispatch_to_terrestrial;

            if remaining_bits_to_dispatch > 0
                extra_bits_to_dispatch_to_terrestrial = min(remaining_bits_to_dispatch, terrestrial_subqueue_available_bits - num_bits_to_dispatch_to_terrestrial);
                num_bits_to_dispatch_to_terrestrial = num_bits_to_dispatch_to_terrestrial + extra_bits_to_dispatch_to_terrestrial;
                remaining_bits_to_dispatch = remaining_bits_to_dispatch - extra_bits_to_dispatch_to_terrestrial;

                extra_bits_to_dispatch_to_satellite = min(remaining_bits_to_dispatch, satellite_subqueue_available_bits - num_bits_to_dispatch_to_satellite);
                num_bits_to_dispatch_to_satellite = num_bits_to_dispatch_to_satellite + extra_bits_to_dispatch_to_satellite;
            end
        end

        terrestrial_load_bps = (1 - split_fraction_candidate) * current_arrival_rate_bps;
        satellite_load_bps   = split_fraction_candidate       * current_arrival_rate_bps;
        
        candidate_terrestrial_predicted_backlog_clearance_time_ms = predict_backlog_clearance_time( ...
            terrestrial_subqueue_bits + num_bits_to_dispatch_to_terrestrial, terrestrial_load_bps, ...
            terrestrial_rate_bits_per_second, terrestrial_one_way_delay_ms);

        candidate_satellite_predicted_backlog_clearance_time_ms = predict_backlog_clearance_time( ...
            satellite_subqueue_bits + num_bits_to_dispatch_to_satellite, satellite_load_bps, ...
            satellite_rate_bits_per_second, satellite_one_way_delay_ms);

        if num_bits_to_dispatch <= 0
            candidate_predicted_backlog_clearance_time_ms = min(candidate_terrestrial_predicted_backlog_clearance_time_ms, candidate_satellite_predicted_backlog_clearance_time_ms);
        else
            candidate_predicted_backlog_clearance_time_ms = 0;

            if num_bits_to_dispatch_to_terrestrial > 0
                candidate_predicted_backlog_clearance_time_ms = candidate_predicted_backlog_clearance_time_ms + ...
                    (num_bits_to_dispatch_to_terrestrial / num_bits_to_dispatch) * candidate_terrestrial_predicted_backlog_clearance_time_ms;
            end

            if num_bits_to_dispatch_to_satellite > 0
                candidate_predicted_backlog_clearance_time_ms = candidate_predicted_backlog_clearance_time_ms + ...
                    (num_bits_to_dispatch_to_satellite / num_bits_to_dispatch) * candidate_satellite_predicted_backlog_clearance_time_ms;
            end
        end

        predicted_times_ms(split_fraction_index) = candidate_predicted_backlog_clearance_time_ms;
    end

    min_predicted_predicted_backlog_clearance_time_ms = min(predicted_times_ms);

    if isinf(min_predicted_predicted_backlog_clearance_time_ms)
        desired_split_fraction = current_split_fraction;
        return;
    end

    % Tie break: pick smallest split fraction (favor terrestrial)
    best_split_fraction_indices = find(predicted_times_ms == min_predicted_predicted_backlog_clearance_time_ms);
    desired_split_fraction = min(split_fractions(best_split_fraction_indices));

    desired_split_fraction = max(0, min(1, desired_split_fraction));

    % Satellite activation gate: if satellite does not save enough future queueing delay, do not use it.
    if desired_split_fraction > 0 && estimated_satellite_benefit_ms <= SATELLITE_BENEFIT_MARGIN_ms
        desired_split_fraction = 0;
    end

end


function [satellite_benefit_ms, backlog_reduction_bits] = estimate_satellite_benefit_ms(arrival_rate_bps, ...
                                                                                        terrestrial_rate_bps_now, ...
                                                                                        satellite_rate_bps, ...
                                                                                        terrestrial_future_drain_rate_bps, ...
                                                                                        terrestrial_one_way_delay_ms, ...
                                                                                        satellite_one_way_delay_ms)

    global DECISION_HORIZON_seconds

    terrestrial_backlog_growth_bps = max(0, arrival_rate_bps - terrestrial_rate_bps_now);
    satellite_backlog_growth_bps = max(0, arrival_rate_bps - satellite_rate_bps);

    backlog_reduction_bits = max(0, terrestrial_backlog_growth_bps - satellite_backlog_growth_bps) * DECISION_HORIZON_seconds;    % The backlog that the satellite link is expected to save over the horizon

    future_queueing_delay_saved_ms = 1000 * backlog_reduction_bits / max(1, terrestrial_future_drain_rate_bps - arrival_rate_bps);      
    satellite_delay_is_greater_than_terrestrial_by_this_much_ms = max(0, satellite_one_way_delay_ms - terrestrial_one_way_delay_ms);

    satellite_benefit_ms = future_queueing_delay_saved_ms - satellite_delay_is_greater_than_terrestrial_by_this_much_ms;    % The satellite link offers a benefit if its larger delay is offset by future queuing delay savings 
end


function value = weighted_percentile(values, weights, percentile)

    valid_mask = isfinite(values) & isfinite(weights) & (weights > 0);
    values = double(values(valid_mask));
    weights = double(weights(valid_mask));

    if isempty(values)
        value = NaN;
        return;
    end

    [values, sort_index] = sort(values);
    weights = weights(sort_index);

    cumulative_weights = cumsum(weights);
    threshold = (percentile / 100) * cumulative_weights(end);

    index = find(cumulative_weights >= threshold, 1, "first");
    value = values(index);

end