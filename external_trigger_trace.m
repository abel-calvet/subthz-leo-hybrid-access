clear; close all; clc;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Generate an external trigger mask trace                              %
%                                                                      %
% Output:                                                              %
%   external_trigger_at_window                                         %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

external_trigger_file = "data/external_trigger_trace.mat";

%
% Timing Settings
%

total_duration_seconds  = 60;
decision_window_seconds = 0.01;
num_windows             = round(total_duration_seconds / decision_window_seconds);
time_seconds_per_window = (0 : num_windows - 1).' * decision_window_seconds;


%
% External trigger event settings
%

enable_external_triggers = true;

% List of hardcoded events (weather, security, interference, etc.)
% Row: [start_time_seconds, duration_seconds]
external_triggers = [2.0,   0.6;
                     52.0,  0.8];

%
% Outputs
%

external_trigger_at_window = false(num_windows, 1);


%
% Build external trigger mask
%

if enable_external_triggers
    for trigger_index = 1 : size(external_triggers, 1)
        event_start_seconds    = external_triggers(trigger_index, 1);
        event_duration_seconds = external_triggers(trigger_index, 2);

        start_window_index = max(1, round(event_start_seconds / decision_window_seconds) + 1);
        duration_windows   = max(1, round(event_duration_seconds / decision_window_seconds));
        end_window_index   = min(num_windows, start_window_index + duration_windows - 1);

        external_trigger_at_window(start_window_index : end_window_index) = true;
    end    
end


%
% Plots 
%

figure;
grid on;
hold on;
stairs(time_seconds_per_window, double(external_trigger_at_window), "LineWidth", 2);
xlabel("Time (s)");
ylabel("External trigger");
title("External trigger mask over time");
ylim([-0.05 1.05]);

if ~isfolder("fig/terrestrial")
        mkdir("fig/terrestrial");
end
saveas(gcf, "fig/terrestrial/trigger_events.png");
close(gcf);


%
% Save data
%

save(external_trigger_file, "external_trigger_at_window", "time_seconds_per_window", ...
    "decision_window_seconds", "external_triggers");

disp("Wrote " + external_trigger_file);