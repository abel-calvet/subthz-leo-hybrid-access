clear; close all; clc;
rng("default");

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Offline NR PUSCH BLER Table Generator %
%                                       %
% Output:                               %
%   data/bler_table_nr_pusch.mat        %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

bler_table_file = "data/bler_table.mat";

%%%%%%%%%%%%%%%%%%%
% NR PUSCH Config %
%%%%%%%%%%%%%%%%%%%

carrier_frequency_hz = 140e9;                % Sub-THz carrier
user_speed_mps       = 0.1 * 1000 / 3600;    % Nearly stationary user

subcarrier_spacing_hz = 60e3;
num_resource_blocks   = 132;
num_layers            = 1;
num_transmit_antennas = 1;
num_receive_antennas  = 1;

num_ofdm_symbols_per_slot = 14;
num_dmrs_symbols_per_slot = 2;

carrier = nrCarrierConfig;
carrier.SubcarrierSpacing = subcarrier_spacing_hz / 1e3;
carrier.CyclicPrefix      = "Normal";
carrier.NSizeGrid         = num_resource_blocks;
carrier.NStartGrid        = 0;
carrier.NCellID           = 1;
carrier.NSlot             = 0;
carrier.NFrame            = 0;

pusch = nrPUSCHConfig;
pusch.NID              = carrier.NCellID;
pusch.RNTI             = 1;
pusch.NumLayers        = num_layers;
pusch.PRBSet           = 0 : (num_resource_blocks - 1);
pusch.SymbolAllocation = [0 num_ofdm_symbols_per_slot];
pusch.DMRS.DMRSLength  = num_dmrs_symbols_per_slot;

ofdmInfo = nrOFDMInfo(carrier);
ofdm_sample_rate_hz = ofdmInfo.SampleRate;

% Data resource element count (excluding DM-RS resource elements)
%pusch_data_indices = nrPUSCHIndices(carrier, pusch);
%data_resource_elements_per_resource_block = numel(pusch_data_indices) / num_resource_blocks;

use_perfect_channel_estimate = true;

%%%%%%%%%%%%%%%
% TDL Channel %
%%%%%%%%%%%%%%%

maximum_doppler_shift_hz = (user_speed_mps / physconst("lightspeed")) * carrier_frequency_hz;
delay_profile            = "TDL-D";
delay_spread_seconds     = 0.3e-6;

use_tdl_channel = true;   % Set to false to use an AWGN-only channel

tdl = nrTDLChannel;
tdl.DelayProfile            = delay_profile;
tdl.DelaySpread             = delay_spread_seconds;
tdl.MaximumDopplerShift     = maximum_doppler_shift_hz;
tdl.SampleRate              = ofdm_sample_rate_hz;
tdl.NumTransmitAntennas     = num_transmit_antennas;
tdl.NumReceiveAntennas      = num_receive_antennas;
tdl.NormalizePathGains      = true;
tdl.NormalizeChannelOutputs = true;
tdl.RandomStream            = "Global stream";
tdl.KFactorScaling          = true;
tdl.KFactor                 = 10;

path_filters = getPathFilters(tdl);

if use_tdl_channel
    tdl_info = info(tdl);
    max_path_delay_seconds = max(tdl.PathDelays);
    max_path_delay_samples = ceil(max_path_delay_seconds * tdl.SampleRate);
    max_channel_delay_samples = tdl_info.ChannelFilterDelay + max_path_delay_samples;
else
    max_channel_delay_samples = 0;
end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% MCS (modulation and coding scheme) Table %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% MCS Table: Lookup table mapping an MCS index number (0-31) to:
%   A modulation order: Number of bits per symbol (QPSK, QAM, etc.)
%   A target code rate: ratio of information bits (data) to code bits (data + error-correction bits)
% Low index number: far from tower, heavy interference, use QPSK, low code rate, low speeed
% Mid index number: decent signal, use 16QAM or 64QAM, standard mode
% High index number: near a base station, clear LoS, use 256QAM, high code rate, max performance
% Link adaptation: If SNR drops, the base station detects it and drops the MCS index 

mcs_tables = nrPUSCHMCSTables;
mcs_table  = mcs_tables.QAM256Table;

valid_rows = ~isnan(mcs_table.TargetCodeRate);
mcs_indices = mcs_table.MCSIndex(valid_rows);


%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% UL-SCH encoder / decoder %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% 5G uplink shared channel (UL-SCH)
% Encoder perfoms low-density parity check (LDPC) coding (math to add error correction bits and do segmentation)
% Decoder at the receiver uses an algorithm to estimate the original bits using parity information
encoder = nrULSCH;
decoder = nrULSCHDecoder;

% Disable HARQ (hybrid automatic repeat request)
% Retransmission system
%   If decoding fails, we ask to retransmit the packet and try again
encoder.MultipleHARQProcesses = false;
decoder.MultipleHARQProcesses = false;

decoder.MaximumLDPCIterationCount = 50;

% Control variables (for the decoder)
redundancy_version = 0;  % 0 = "sending original data" (not retransmission of parity bits)
harq_id = 0;
cbgti = 1;               % Code Block Group Transmission Information (tells the decoder which code block groups are in transmission, 1 = all of them)


%%%%%%%%%%%%%%%%%%%%%%
% Experimental setup %
%%%%%%%%%%%%%%%%%%%%%%

% SNR values I want to test:
snr_step_dB = 5;            % Decrease for finer resolution
snrs_dB =  -5 : snr_step_dB : 30;
num_trials_per_snr = 600;   % Increase for smoother curve and to show very low error rates

% To reduce runtime
min_trials_per_snr = 600;
max_block_errors_per_snr = 60; % Stop running if we've seen enough errors


%%%%%%%%%%%%%%%%%%%
% Run table sweep %
%%%%%%%%%%%%%%%%%%%

num_mcs_indices = length(mcs_indices);
num_snrs        = length(snrs_dB);

bler = nan(num_mcs_indices, num_snrs);                         % Block error rate = # transport blocks (not bits) with an error / # transport blocks received
transport_block_sizes_bits_per_slot = nan(num_mcs_indices, 1); % number of bits per slot (14 OFDM symbols)
target_code_rates = nan(num_mcs_indices, 1);
modulations       = strings(num_mcs_indices, 1);

for index = 1 : num_mcs_indices
    
    mcs_index = mcs_indices(index);
    
    row_at_mcs_index = mcs_table(mcs_table.MCSIndex == mcs_index, :);
    modulation = string(row_at_mcs_index.Modulation);
    
    target_code_rate = row_at_mcs_index.TargetCodeRate;
    if target_code_rate > 1
        target_code_rate = target_code_rate / 1024; % Some tables store code rate scaled by 1024
    end

    pusch.Modulation = modulation;

    % Precompute indices/symbols per MCS
    dmrs_indices = nrPUSCHDMRSIndices(carrier, pusch);
    dmrs_symbols = nrPUSCHDMRS(carrier, pusch);
    data_indices = nrPUSCHIndices(carrier, pusch);

    [~, puschInfo]                            = nrPUSCHIndices(carrier, pusch);
    G                                         = puschInfo.G;         % number of coded bits that fit in this slot allocation
    data_resource_elements_per_resource_block = puschInfo.NREPerPRB; % data RE per PRB
    
    % Set transport block size for this allocation
    transport_block_size_bits_per_slot = nrTBS(modulation, num_layers, ...
        num_resource_blocks, data_resource_elements_per_resource_block, ...
        target_code_rate, 0);

    transport_block_sizes_bits_per_slot(index) = transport_block_size_bits_per_slot;
    target_code_rates(index)                   = target_code_rate;
    modulations(index)                         = modulation;
    
    % Configure encoder and decoder
    decoder.TransportBlockLength = transport_block_size_bits_per_slot;
    decoder.TargetCodeRate       = target_code_rate;
    encoder.TargetCodeRate       = target_code_rate;

    if modulation == "QPSK"
        bits_per_modulation_symbol = 2;
    elseif modulation == "16QAM"
        bits_per_modulation_symbol = 4;
    elseif modulation == "64QAM"
        bits_per_modulation_symbol = 6;
    elseif modulation == "256QAM"
        bits_per_modulation_symbol = 8;
    else
        error("Unsupported modulation: %s", modulation);
    end

    % Run experiment
    for snr_index = 1 : num_snrs

        snr_dB = snrs_dB(snr_index);
        snr    = 10 ^ (snr_dB / 10);

        % Noise variance per resource element
        % See MathWorks "SNR definition used in link simulations"
        noise_standard_deviation_per_resource_element = 1 / sqrt(num_receive_antennas * snr);
        noise_variance_per_resource_element = noise_standard_deviation_per_resource_element ^ 2;

        num_errors = 0;
        sum_snr_estimates = 0; % For debugging / sanity checking
        num_trials_ran = 0;

        for trial_index = 1 : num_trials_per_snr

            reset(decoder);
            reset(encoder);

            transport_block = randi([0 1], transport_block_size_bits_per_slot, 1, "int8"); % Single random transport block
            
            % Encoding (UL-SCH)
            setTransportBlock(encoder, transport_block);
            coded_bits = encoder(modulation, num_layers, G, redundancy_version);
            
            % Map to resource grid
            transmit_resource_grid = nrResourceGrid(carrier, num_transmit_antennas);
            transmit_resource_grid(dmrs_indices) = dmrs_symbols;
            transmit_resource_grid(data_indices) = nrPUSCH(carrier, pusch, coded_bits);
            
            % OFDM modulate
            transmit_waveform = nrOFDMModulate(carrier, transmit_resource_grid);

            % Pass through multipath fading channel and do timing alignment
            if use_tdl_channel
                reset(tdl);

                transmit_waveform_with_padding = [transmit_waveform; ...
                    zeros(max_channel_delay_samples, size(transmit_waveform, 2), "like", transmit_waveform)];
                
                sample_times = [];
                try
                    [received_waveform_full, path_gains, sample_times] = tdl(transmit_waveform_with_padding);
                catch
                    [received_waveform_full, path_gains] = tdl(transmit_waveform_with_padding);
                end

                timing_offset_samples = nrPerfectTimingEstimate(path_gains, path_filters);
                timing_offset_samples = timing_offset_samples(1);            
                timing_offset_samples = max(0, floor(timing_offset_samples));

                max_cyclic_prefix_length_samples = max(ofdmInfo.CyclicPrefixLengths);
                timing_offset_samples = min(timing_offset_samples, max_cyclic_prefix_length_samples);

                received_waveform_aligned = received_waveform_full(timing_offset_samples + 1 : end, :);
            
                % Trim to exactly one-slot length for OFDM demodulation
                num_transmit_samples = size(transmit_waveform, 1);
                num_received_samples = min(num_transmit_samples, size(received_waveform_aligned, 1));

                received_waveform = received_waveform_aligned(1 : num_received_samples, :);
                if num_received_samples < num_transmit_samples
                    received_waveform = [received_waveform; zeros(num_transmit_samples - num_received_samples, num_receive_antennas)];
                end
            else
                % AWGN-only channel
                received_waveform = transmit_waveform;
            end

            % OFDM Demodulate (clean grid with no noise)
            receive_resource_grid_clean = nrOFDMDemodulate(carrier, received_waveform);

            % Add AWGN in resource grid domain
            noise_resource_grid = sqrt(noise_variance_per_resource_element / 2) * complex(randn(size(receive_resource_grid_clean)), randn(size(receive_resource_grid_clean)));
            receive_resource_grid = receive_resource_grid_clean + noise_resource_grid;

            % Sanity check: SNR must equal signal power / noise power
            clean_data_resource_elements = receive_resource_grid_clean(data_indices);
            noisy_data_resource_elements = noise_resource_grid(data_indices);
            noise_power = mean(abs(noisy_data_resource_elements) .^ 2, "all");
            signal_power = mean(abs(clean_data_resource_elements).^2, "all");
            snr_estimate = max(signal_power, eps) / max(noise_power, eps);
            sum_snr_estimates = sum_snr_estimates + snr_estimate;
            
            % Estimate channel and noise
            if ~use_tdl_channel
                % AWGN-only: perfect channel, use the injected noise variance
                channel_estimate = ones(size(receive_resource_grid), "like", receive_resource_grid);
            else
                if use_perfect_channel_estimate
                    if isempty(sample_times)
                        channel_estimate = nrPerfectChannelEstimate( ...
                            carrier, path_gains, path_filters, timing_offset_samples);
                    else
                        channel_estimate = nrPerfectChannelEstimate( ...
                            carrier, path_gains, path_filters, timing_offset_samples, sample_times);
                    end
                else
                    % More practical estimate
                    [channel_estimate, ~] = nrChannelEstimate( ...
                        carrier, receive_resource_grid, dmrs_indices, dmrs_symbols, ...
                        "CDMLengths", pusch.DMRS.CDMLengths);
                end
            end
            
            % Extract + equalize data resource elements
            [received_symbols, channel_estimate_data] = nrExtractResources( ...
                data_indices, receive_resource_grid, channel_estimate);
            
            [equalized_symbols, channel_state_information] = nrEqualizeMMSE( ...
                received_symbols, channel_estimate_data, noise_variance_per_resource_element);
            
            % Decoding (soft bits)
            log_likelihood_ratios = nrPUSCHDecode(carrier, pusch, equalized_symbols, noise_variance_per_resource_element); % Soft bits: Positive (high likelihood of a 0), Negative (high likelihood of a 1)
            
            % CSI (channel state information) weighting
            % Uses channel information to tell the Forward Error Correction (FEC) decoder which bits to trust and which to doubt
            if ~isempty(channel_state_information)
                % Ensure CSI values are clipped between 0 and 1
                % 1 = perfect, clear channel
                % 0 = completely faded channel
                channel_state_information_per_symbol = channel_state_information(:);
                channel_state_information_per_symbol = max(0, channel_state_information_per_symbol);
                channel_state_information_per_symbol = min(channel_state_information_per_symbol, 1);

                channel_state_information_per_bit = reshape( ...
                    repmat(channel_state_information_per_symbol.', bits_per_modulation_symbol, 1), [], 1);

                if length(channel_state_information_per_bit) == length(log_likelihood_ratios)
                    % Scale the LLRs by the CSI
                    log_likelihood_ratios = log_likelihood_ratios .* channel_state_information_per_bit;
                end
            end
            
            
            % LDPC Decoding (UL-SCH)
            [~, block_error] = decoder(log_likelihood_ratios, modulation, num_layers, ...
                redundancy_version); % block_error = 0 (CRC checksum matched), block_error = 1 (CRC checksum failed)

            num_errors     = num_errors + block_error;
            num_trials_ran = num_trials_ran + 1;

            % Early stop (to save running time)
            if trial_index >= min_trials_per_snr
                % If we've seen enough errors, our BLER is probably stable enough
                if num_errors >= max_block_errors_per_snr
                    break;
                end

                % If we've seen no errors, we can stop early
                if num_errors == 0
                    break;
                end
            end
        end
        
        % Sanity check: if this mean SNR estimate is way off from the
        % actual SNR (snr_dB), something went wrong.
        snr_estimate_dB = 10 * log10((sum_snr_estimates / num_trials_ran) + eps);
        %fprintf("MCS index: %d, target SNR = %.1f dB, SNR estimate = %.1f dB, Way off? %s\n", ...
        %    mcs_index, snr_dB, snr_estimate_dB, string(abs(snr_dB - snr_estimate_dB) > 2));

        %bler(index, snr_index) = (num_errors + 0.5) / (num_trials_ran + 1);   % Jeffreys smoothing
        bler(index, snr_index) = num_errors / num_trials_ran;
        fprintf("MCS index: %d, SNR: %.1f dB, BLER: %.5f\n", mcs_index, snr_dB, bler(index, snr_index));
    end

    fprintf("MCS Index # %d done.\n%s, target code rate = %.4f, transport block size = %d bits\n", ...
        mcs_index, modulation, target_code_rate, transport_block_size_bits_per_slot);
end


%%%%%%%%%%%%%%%%%%%%%%%%
% Build the BLER table %
%%%%%%%%%%%%%%%%%%%%%%%%

bler_table = struct();
bler_table.snrs_dB                             = snrs_dB;
bler_table.mcs_indices                         = mcs_indices;
bler_table.modulations                         = modulations;
bler_table.target_code_rates                   = target_code_rates;
bler_table.transport_block_sizes_bits_per_slot = transport_block_sizes_bits_per_slot;
bler_table.bler                                = bler;
bler_table.slot_duration_seconds               = 1e-3 / (2 ^ log2(subcarrier_spacing_hz / 15e3));
bler_table.subcarrier_spacing_hz               = subcarrier_spacing_hz;
bler_table.num_resource_blocks                 = num_resource_blocks;
bler_table.num_layers                          = num_layers;
bler_table.snr_step_dB                         = snr_step_dB;


bler_table.channel = struct( ...
    "use_tdl_channel", use_tdl_channel, ...
    "delay_profile", delay_profile, ...
    "delay_spread_seconds", delay_spread_seconds, ...
    "carrier_frequency_hz", carrier_frequency_hz, ...
    "user_speed_mps", user_speed_mps, ...
    "maximum_doppler_shift_hz", maximum_doppler_shift_hz, ...
    "use_perfect_channel_estimate", use_perfect_channel_estimate);


%%%%%%%%%
% Plots %
%%%%%%%%%

figure;
grid on;
hold on;
% Pick 3 MCS rows
row_indices = [1, 6, 12]; % low, mid, high MCS indices
for i = 1 : numel(row_indices)
    semilogy(snrs_dB, bler(row_indices(i), :));
end
ylim([1e-3 1]);
xlabel("SNR (dB)");
ylabel("Block error rate (log scale)");
legend("low MCS", "mid MCS", "high MCS", "Location", "southwest");
title("BLER vs SNR for a PUSCH TDL multipath channel (140 GHz, near-stationary user)");


%%%%%%%%%%%%%
% Save data %
%%%%%%%%%%%%%

save(bler_table_file, "bler_table");
disp("Wrote " + bler_table_file);