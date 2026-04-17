clear; close all; clc;
rng("default");

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Terrestrial 5G NR physical trace generator / OFDM waveform simulation %
%                                                                       %
%   1. Build an NR uplink resource grid (PUSCH + DM-RS) for each slot   %
%   2. Modulate it (OFDM) into a time-domain waveform                   %
%   3. Pass the waveform through an nrTDLChannel (multipath + Doppler)  %
%   4. Add AWGN                                                         %
%   5. Demodulate back to a received grid                               %
%   6. Estimate the channel and noise variance using DM-RS              %
%   7. Compute SNR per resource element, then average into:             %
%       * SNR per Resource Block per 10-ms decision window              %
%       * Wideband SNR per 10-ms decision window                        %
%                                                                       %
% Output:                                                               %
%   wideband_snr_dB_per_window                                          %
%   snr_dB_per_resource_block_per_window                                %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

snr_base_file = "data/terrestrial_snr_base.mat";

%%%%%%%%%%%%%%%%%%%
% Timing settings %
%%%%%%%%%%%%%%%%%%%

total_duration_seconds  = 60;                           % Duration of signal
decision_window_seconds = 0.01;                         % 10-ms decision windows
num_windows             = round(total_duration_seconds / decision_window_seconds);
time_seconds_per_window = (0 : num_windows - 1).' * decision_window_seconds;


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% NR Physical Layer configuration %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

carrier_frequency_hz               = 140e9; % Sub-THz carrier. (Affects Doppler.)
subcarrier_spacing_hz              = 60e3;  % Inversely proportional to symbol duration
num_subcarriers_per_resource_block = 12;    % 1 resource block = 12 subcarriers
num_resource_blocks                = 132;   % Bandwidth = 132 * 12 * 60e3 ~ 100 MHz

pusch_modulation = "16QAM";     % Uplink modulation used on pusch (physical uplink shared channel) for probing signal

% Modulation scheme => bits per symbol (qammod)
% OFDM (orthogonal frequency division multiplexing) divides the channel into orthogonal subcarriers
% QAM dictates how many bits are mapped onto each subcarrier
switch pusch_modulation
    case "QPSK"
        modulation_order = 4;
    case "16QAM"
        modulation_order = 16;
    case "64QAM"
        modulation_order = 64;
    case "256QAM"
        modulation_order = 256;
    otherwise
        error("Unsupported modulation scheme: %s", pusch_modulation);
end

bits_per_symbol = log2(modulation_order);

num_transmit_antennas = 1;      % SISO
num_receive_antennas  = 1;

nominal_snr_dB = 15;            % Average SNR. Channel creates fading around it.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Numerology index and slot timing %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% subcarrier spacing = 15 kHz * 2 ** numerology_index (0, 1, 2, 3, 4)
numerology_index = log2(subcarrier_spacing_hz / 15e3);
numerology_index = round(numerology_index);         % Needs to be an integer
num_slots_per_frame = 10 * (2 ^ numerology_index);  % 10-ms NR frame (Note: This 10-ms (defined by the NR standard) is unrelated to our choice of decision window. 
if ~ismember(numerology_index, [0, 1, 2, 3, 4])
    error("Subcarrier spacing must be 15, 30, 60, 120, or 240 kHz. Got %.1f kHz.", ...
        subcarrier_spacing_hz / 1e3);
end

% slot duration = 1 ms / (2 ** numerology_index)
slot_duration_seconds       = 1e-3 / (2 ^ numerology_index);
num_ofdm_symbols_per_slot   = 14;
num_slots_per_window        = round(decision_window_seconds / slot_duration_seconds);
num_ofdm_symbols_per_window = num_slots_per_window * num_ofdm_symbols_per_slot;


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% NR carrier and PUSCH configuration (5G Toolbox) %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Carrier config
% OFDM grid size and timing
carrier_config = nrCarrierConfig;
carrier_config.SubcarrierSpacing = subcarrier_spacing_hz / 1e3;    % in kHz
carrier_config.CyclicPrefix      = "Normal";   % Guard interval to prevent ISI
carrier_config.NSizeGrid         = num_resource_blocks;
carrier_config.NStartGrid        = 0;   % Start resource-block index
carrier_config.NCellID           = 1;   % Identify a unique base station cell


% PUSCH (physical uplink shared channel) config
pusch_config = nrPUSCHConfig;
pusch_config.NID              = carrier_config.NCellID;
pusch_config.RNTI             = 1;                               % Radio network temporary identifier (16-bit number to identify a specific user)
pusch_config.Modulation       = pusch_modulation;                % 16QAM
pusch_config.NumLayers        = 1;                               % 1 layer (SISO)
pusch_config.PRBSet           = 0 : (num_resource_blocks - 1);   % Physical resource block set
pusch_config.SymbolAllocation = [0 num_ofdm_symbols_per_slot];   % Use full slot

% Which resource elements (12 resource elements per resource block)
% carry data vs DM-RS (demodulation reference signal)
num_dmrs_symbols_per_slot    = 2;
pusch_config.DMRS.DMRSLength = num_dmrs_symbols_per_slot;


%%%%%%%%%%%%%%%%%%%%
% OFDM Sample Rate %
%%%%%%%%%%%%%%%%%%%%

ofdm_info = nrOFDMInfo(carrier_config);         % Gives us OFDM numerology, fast fourier transform (FFT), sample rate, symbol length
ofdm_sample_rate_hz = ofdm_info.SampleRate;     % Number of complex samples per second in OFDM waveform

fprintf("Sample Rate: %.1f MHz\n", ofdm_sample_rate_hz / 1e6);


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Channel configuration (nrTDLChannel) %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

user_speed_meters_per_second = 0.1 * 1000 / 3600;      % 0.1 km/h
maximum_doppler_shift_hz = (user_speed_meters_per_second / physconst("lightspeed")) * carrier_frequency_hz;
delay_profile = "TDL-D";
delay_spread_seconds = 0.3e-6;

tdl_channel = nrTDLChannel;
tdl_channel.DelayProfile        = delay_profile;
tdl_channel.DelaySpread         = delay_spread_seconds;
tdl_channel.MaximumDopplerShift = maximum_doppler_shift_hz;
tdl_channel.SampleRate          = ofdm_sample_rate_hz;
tdl_channel.NumTransmitAntennas = num_transmit_antennas;
tdl_channel.NumReceiveAntennas  = num_receive_antennas;
tdl_channel.NormalizePathGains  = true; % Normalize path gains so the average channel power is stable
tdl_channel.KFactorScaling      = true;
tdl_channel.KFactor             = 10;

%%%%%%%%%%%
% Outputs %
%%%%%%%%%%%

wideband_snr_dB_per_window           = nan(num_windows, 1);   % SNR over the total bandwidth per 10-ms window
snr_dB_per_resource_block_per_window = nan(num_windows, num_resource_blocks);


%%%%%%%%%
% Noise %
%%%%%%%%%

nominal_snr = 10 ^ (nominal_snr_dB / 10);
% Noise variance is based on the average transmit waveform power
noise_variance = NaN;     % per time sample


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Generate trace 1 decision window at a time %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

slot_index_counter = 0;
tic;

for window_index = 1 : num_windows
    % Build a transmit waveform for this 10-ms window (concatenate slot waveforms)
    transmit_waveform = complex(zeros(0, num_transmit_antennas));
    % Store the SNR per resource block for every slot in this window
    snr_per_resource_block_per_slot = nan(num_slots_per_window, num_resource_blocks);
    % Store the number of time samples for each slot
    samples_per_slot = zeros(num_slots_per_window, 1);

    % Create transmit waveform slot by slot
    for slot_index = 1 : num_slots_per_window
        % Slot number (carrier time index) within a 10-ms frame
        carrier_config.NSlot  = mod(slot_index_counter, num_slots_per_frame);
        % Frame number
        carrier_config.NFrame = floor(slot_index_counter / num_slots_per_frame);

        % Empty resource grid for one slot
        % Dimensions: num_subcarriers x num_ofdm_symbols_per_slot x num_transmit_antennas
        transmit_resource_grid = nrResourceGrid(carrier_config, num_transmit_antennas);
        
        % Compute resource element indices used for PUSCH data 
        pusch_data_indices = nrPUSCHIndices(carrier_config, pusch_config);
        % Compute DM-RS indices and symbols (pilot resource elements used for channel estimation at the receiver)
        dmrs_indices = nrPUSCHDMRSIndices(carrier_config, pusch_config);
        dmrs_symbols = nrPUSCHDMRS(carrier_config, pusch_config);

        % Create random data bits for the PUSCH payload
        num_data_resource_elements = numel(pusch_data_indices);
        num_data_symbols = num_data_resource_elements;
        num_data_bits = num_data_symbols * bits_per_symbol;
        transmit_data_bits = randi([0 1], num_data_bits, 1);

        % Map bits to complex QAM symbols (with unit average power)
        transmit_data_symbols = qammod(transmit_data_bits, modulation_order, ...
            "UnitAveragePower", true, "InputType", "bit");
        
        % Place data symbols and DM-RS symbols into the grid
        transmit_resource_grid(dmrs_indices) = dmrs_symbols;
        transmit_resource_grid(pusch_data_indices) = transmit_data_symbols;

        % OFDM modulate the grid into a time-domain waveform for this slot
        % Concatenate per-slot waveforms to form the 10-ms window waveform
        slot_waveform = nrOFDMModulate(carrier_config, transmit_resource_grid);
        samples_per_slot(slot_index) = size(slot_waveform, 1);
        transmit_waveform = [transmit_waveform; slot_waveform];

        % Increment slot index counter
        slot_index_counter = slot_index_counter + 1;
    end
    
    % Initialize noise variance using the first window's waveform power
    if isnan(noise_variance)
        average_transmit_waveform_power = mean(abs(transmit_waveform) .^ 2, "all");
        noise_variance = average_transmit_waveform_power / nominal_snr;
    end
    
    %{
    % Pass waveform through the fading channel
    channel_filter_delay_samples = info(tdl_channel).ChannelFilterDelay;  % delay due to input signal passing through channel (in number of time samples) 
    % Pad transmit waveform with zeros
    transmit_waveform = [transmit_waveform; zeros(channel_filter_delay_samples, num_transmit_antennas)];
    % Trim received waveform so received and transmit waveform durations align
    received_waveform = tdl_channel(transmit_waveform);
    received_waveform = received_waveform(channel_filter_delay_samples + 1 : size(transmit_waveform, 1), :);
    %}

    % Pass waveform through the fading channel and perform timing alignment
    [received_waveform_full, path_gains, ~] = tdl_channel(transmit_waveform);
    
    path_filter_coefficients = getPathFilters(tdl_channel);
    timing_offset_samples = nrPerfectTimingEstimate(path_gains, path_filter_coefficients);
    
    received_waveform_aligned = received_waveform_full(timing_offset_samples + 1 : end, :);
    
    num_transmit_samples = size(transmit_waveform, 1);
    num_received_samples = min(num_transmit_samples, size(received_waveform_aligned, 1));
    
    received_waveform = received_waveform_aligned(1 : num_received_samples, :);
    if num_received_samples < num_transmit_samples
        received_waveform = [received_waveform; zeros(num_transmit_samples - num_received_samples, num_receive_antennas)];
    end

    % Add AWGN (additive white Gaussian noise)
    noise = sqrt(noise_variance / 2) * ...
        (randn(size(received_waveform)) + 1j * randn(size(received_waveform)));
    received_waveform = received_waveform + noise;
    
    % Processing at receiver (slot by slot):
    %   Demodulate slot by slot
    %   Estimate channel from DM-RS
    %   Estimate noise
    %   Compute the SNR
    for slot_index = 1 : num_slots_per_window
        % Determine the time samples corresponding to the current slot
        start_sample_index = 1 + sum(samples_per_slot(1 : slot_index - 1));
        end_sample_index = sum(samples_per_slot(1 : slot_index));
        received_waveform_at_slot = received_waveform(start_sample_index : end_sample_index, :);
        
        % Set the slot number and frame number
        reconstructed_slot_index_counter = (window_index - 1) * num_slots_per_window + slot_index - 1;
        carrier_config.NSlot  = mod(reconstructed_slot_index_counter, num_slots_per_frame);
        carrier_config.NFrame = floor(reconstructed_slot_index_counter / num_slots_per_frame);

        % OFDM demodulate the waveform back into a resource grid
        received_resource_grid = nrOFDMDemodulate(carrier_config, received_waveform_at_slot);
        
        if size(received_resource_grid, 2) ~= num_ofdm_symbols_per_slot
            error("Received grid has %d OFDM symbols, expected %d.", ...
                size(received_resource_grid, 2), num_ofdm_symbols_per_slot);
        end

        % Compute DM-RS indices and symbols for this slot
        dmrs_indices = nrPUSCHDMRSIndices(carrier_config, pusch_config);
        dmrs_symbols = nrPUSCHDMRS(carrier_config, pusch_config);

        % Channel estimate from DM-RS
        [channel_estimate_grid, noise_variance_estimate_per_resource_element] = nrChannelEstimate( ...
            carrier_config, received_resource_grid, dmrs_indices, dmrs_symbols);
    
        % Extract channel estimate on data resource elements
        pusch_data_indices = nrPUSCHIndices(carrier_config, pusch_config);
        channel_estimate_data = channel_estimate_grid(pusch_data_indices);
        
        % Compute SNR per (data) resource element
        % SNR = |H|**2 / noise_variance
        snr_per_data_resource_element = (abs(channel_estimate_data) .^ 2) ./ max(noise_variance_estimate_per_resource_element, eps);

        % Map each data resource element to its resource block
        [subcarrier_index_per_data_resource_element, ~] = ind2sub(size(received_resource_grid), pusch_data_indices);
        resource_block_index_per_data_resource_element = floor((subcarrier_index_per_data_resource_element - 1) / num_subcarriers_per_resource_block) + 1;
        
        % Average SNR per resource block
        snr_per_resource_block = accumarray( ...
            resource_block_index_per_data_resource_element, ...
            snr_per_data_resource_element, ...
            [num_resource_blocks 1], @mean, NaN);
        snr_per_resource_block_per_slot(slot_index, :) = snr_per_resource_block(:).';
    end

    % Average resource-block SNR across all slots in 10-ms window
    average_snr_per_resource_block = mean(snr_per_resource_block_per_slot, 1, "omitnan");
    
    % Save SNR per resource block per window
    snr_dB_per_resource_block_per_window(window_index, :) = 10 * log10(average_snr_per_resource_block + eps);

    % Compute single wideband SNR per window
    wideband_snr = mean(average_snr_per_resource_block, "omitnan");
    wideband_snr_dB_per_window(window_index) = 10 * log10(wideband_snr + eps);
    
    seconds_per_loop_iteration = toc;
    fprintf("Window %d done: %.3f s\n", window_index, seconds_per_loop_iteration);
    if window_index == 1
        fprintf("Estimated total time to run simulation: %.1f minutes\n", seconds_per_loop_iteration * num_windows / 60);
    end
    
end


%%%%%%%%%
% Plots %
%%%%%%%%%

figure;
grid on;
hold on;
ylim([-20, 30]);
plot(time_seconds_per_window, wideband_snr_dB_per_window, "LineWidth", 2);
xlabel("Time (s)");
ylabel("Wideband SNR (dB)");
title('Base terrestrial NR wideband signal-to-noise ratio over time');
saveas(gcf, "fig/terrestrial/snr/base_terrestrial_snr.png");
close(gcf);

%%%%%%%%%%%%%
% Save data %
%%%%%%%%%%%%%

save(snr_base_file, ...
    "wideband_snr_dB_per_window", ...
    "snr_dB_per_resource_block_per_window", ...
    "time_seconds_per_window", "decision_window_seconds", ...
    "carrier_frequency_hz", ...
    "subcarrier_spacing_hz", "numerology_index", ...
    "num_resource_blocks", "num_subcarriers_per_resource_block", ...
    "slot_duration_seconds", "num_slots_per_window", ...
    "num_ofdm_symbols_per_slot", "num_ofdm_symbols_per_window", ...
    "pusch_modulation", ...
    "nominal_snr_dB", "user_speed_meters_per_second", "delay_profile", ...
    "delay_spread_seconds", "maximum_doppler_shift_hz");

disp("Wrote " + snr_base_file);