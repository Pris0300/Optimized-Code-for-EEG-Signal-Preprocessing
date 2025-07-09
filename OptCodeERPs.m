%% Setup
condition = 'pitch'; % CAMBIAR SEGUN VARIACION (pitch, duration, intensity, position)

base_path = 'C:\\Users\\pmb_0\\OneDrive\\NeuroTechs\\Registros EEG\\Registros T0'; 
csv_folder = fullfile(base_path, 'Csv'); % Folder donde estan los registros en .csv
mat_folder = fullfile(base_path, 'Mat'); % Folder donde se guardan los .mat 
input_filepath = fullfile(base_path, 'Raw'); % Folder donde se guardan los .set crudos con canales y eventos importados
output_filepath = fullfile(base_path, 'Prepro'); % Folder donde se guardan los .set preprocesados
output_filepathICA = fullfile(output_filepath, 'ICA'); % Folder donde se guardan los .set con los pesos de ICA
event_file = fullfile('C:\\Users\\pmb_0\\OneDrive\\NeuroTechs\\Registros EEG\\Events', [condition '8020.csv']); % Archivo donde estan los eventos a importar
chanlocs_file = 'C:\\Users\\pmb_0\\OneDrive\\NeuroTechs\\Registros EEG\\8_channels.txt'; % Archivo donde estan los canales

num_sig = 3; % Num de sujetos
ica = cell(num_sig, 1);

% Color Palette
 colors = [
    3   201 184;   % 1 - #03c9b8
    27  132 229;   % 2 - #1b84e5
    0   74  173;   % 3 - #004aad
    175 238 238;   % 4 - #afeeee
    135 206 235;   % 5 - #87ceeb
    71  129 180;   % 6 - #4781b4
    166 166 166;   % 7 - #a6a6a6 Grey
    28  39  64     % 8 - #1c2740 Blackish Blue
] / 255;

%% .CSV to .SET conversion

for i = 1:num_sig
    subj_tag = sprintf('s%d_%s', i, condition);

    csv_filename = fullfile(csv_folder, [subj_tag '.csv']);
    mat_filename = fullfile(mat_folder, [subj_tag '.mat']);
    
    % Convert .csv to .mat
    dd = readtable(csv_filename);
    dd = rows2vars(dd);
    dd = dd(3:10, 1:50001);
    dd(:,1) = [];
    dd = table2array(dd);
    save(mat_filename, "dd", "-mat");

    % Load into EEGLAB, channels and events import
    EEG.etc.eeglabvers = '2023.1'; % EEGLAB version tracking
    EEG = pop_importdata('dataformat', 'matlab', 'nbchan', 0, 'data', mat_filename, ...
        'setname', subj_tag, 'srate', 250, 'pnts', 0, 'xmin', 0, 'chanlocs', chanlocs_file); % Import channels
    EEG = pop_importevent(EEG, 'event', event_file, 'fields', {'latency','type'}, 'skipline', 1, 'timeunit', 1); % Import events
    EEG = pop_saveset(EEG, 'filename', [subj_tag '.set'], 'filepath', input_filepath);
end

%% Preprocessing

for i = 1:num_sig
    subj_tag = sprintf('s%d_%s', i, condition);
    
    % Load dataset for high-pass filter
    EEG = pop_loadset('filename', [subj_tag '.set'], 'filepath', input_filepath);
    
    % Remove baseline
    EEG = pop_rmbase(EEG, [], []);
    EEG_baseline_removed = EEG;

    % ICA weights on high-pass filtered dataset
    EEG = pop_eegfiltnew(EEG, 'locutoff', 1);
    EEG.setname = [subj_tag '_preproICA'];
    EEG = pop_runica(EEG, 'icatype', 'runica', 'extended', 1, 'interrupt', 'on');

    % Save ICA dataset
    ica_filename = [subj_tag '_preproICA.set'];
    EEG = pop_saveset(EEG, 'filename', ica_filename, 'filepath', output_filepathICA);

    % Extract ICA weights
    ica_weights = EEG.icaweights;
    ica_sphere = EEG.icasphere;
    icachansind = EEG.icachansind;

    % Band-pass filter (1-30 Hz) on baseline removed dataset
    EEG = EEG_baseline_removed;
    EEG = pop_eegfiltnew(EEG, 'locutoff', 1, 'hicutoff', 30);

    % Apply ICA weights
    EEG = pop_editset(EEG, 'icaweights', ica_weights, 'icasphere', ica_sphere, 'icachansind', icachansind);
    EEG = pop_iclabel(EEG, 'default');

    % Save final dataset
    EEG.setname = [subj_tag '_prepro'];
    EEG = pop_saveset(EEG, 'filename', [EEG.setname '.set'], 'filepath', output_filepath);

    % ICA classif
    labels = mean(EEG.etc.ic_classification.ICLabel.classifications, 1);
    ica{i} = sprintf(['Signal S%d - Brain: %.2f%%, Eyes: %.2f%%, Muscles: %.2f%%, Heart: %.2f%%, ', ...
                          'Line Noise: %.2f%%, Channel Noise: %.2f%%, Others: %.2f%%'], ...
                          i, labels(1:7) * 100);
    
    clear EEG EEG_baseline_removed
end

disp('ICA Component Averages:');
disp(ica);

%% Epoching

all_epochs(num_sig) = struct('freq', [], 'infreq1', [], 'infreq2', [], 'infreq3', [], 'infreq4', []);

for i = 1:num_sig
    subj_tag = sprintf('s%d_%s_prepro', i, condition);
    filename = [subj_tag '.set'];

    % Load dataset
    s_eeg = pop_loadset('filename', filename, 'filepath', output_filepath);
    suj = ['Subject ', num2str(i)];

    % Frequent
    dd_freq = pop_epoch(s_eeg, {'Frequent'}, [-0.2 0.6]);
    dd_freq = pop_rmbase(dd_freq, [-200 0], []);

    % Infrequent 1
    dd_infreq1 = pop_epoch(s_eeg, {'1-Infrequent'}, [-0.2 0.6]);
    dd_infreq1 = pop_rmbase(dd_infreq1, [-200 0], []);

    % Infrequent 2
    dd_infreq2 = pop_epoch(s_eeg, {'2-Infrequent'}, [-0.2 0.6]);
    dd_infreq2 = pop_rmbase(dd_infreq2, [-200 0], []);

    % Infrequent 3 
    dd_infreq3 = pop_epoch(s_eeg, {'3-Infrequent'}, [-0.2 0.6]);
    dd_infreq3 = pop_rmbase(dd_infreq3, [-200 0], []);

    % Infrequent 4 
    dd_infreq4 = pop_epoch(s_eeg, {'4-Infrequent'}, [-0.2 0.6]);
    dd_infreq4 = pop_rmbase(dd_infreq4, [-200 0], []);

    % Save epochs
    all_epochs(i).freq = dd_freq;
    all_epochs(i).infreq1 = dd_infreq1;
    all_epochs(i).infreq2 = dd_infreq2;
    all_epochs(i).infreq3 = dd_infreq3;
    all_epochs(i).infreq4 = dd_infreq4;
end

%% Calculate and Plot ERPs

chan = 2; % Channel Fz
n_timepoints = size(all_epochs(1).freq.data, 2);

freq_mean = NaN(num_sig, n_timepoints);
infreq1_mean = NaN(num_sig, n_timepoints);
infreq2_mean = NaN(num_sig, n_timepoints);
infreq3_mean = NaN(num_sig, n_timepoints);
infreq4_mean = NaN(num_sig, n_timepoints);

for i = 1:num_sig
   freq_mean(i, :) = mean(all_epochs(i).freq.data(chan, :, :), 3);
   infreq1_mean(i, :) = mean(all_epochs(i).infreq1.data(chan, :, :), 3);
   infreq2_mean(i, :) = mean(all_epochs(i).infreq2.data(chan, :, :), 3);
   infreq3_mean(i, :) = mean(all_epochs(i).infreq3.data(chan, :, :), 3);
   infreq4_mean(i, :) = mean(all_epochs(i).infreq4.data(chan, :, :), 3);

    figure;
    
    % Frequent
    subplot(2,1,1);
    plot(all_epochs(i).freq.times, freq_mean(i, :), 'Color', colors(3, :), 'LineWidth', 1.5);
    title('Frequent Stimuli');
    xlabel("Time (ms)");
    ylabel("Amplitude (uV)");
    yline(0, '--', 'HandleVisibility', 'off');
    xline(0, 'r--', 'HandleVisibility', 'off');

    % Infrequent
    subplot(2,1,2);
    plot(all_epochs(i).freq.times, infreq1_mean(i, :), 'Color', colors(1, :), 'LineWidth', 1.5); hold on;
    plot(all_epochs(i).freq.times, infreq2_mean(i, :), 'Color', colors(4, :), 'LineWidth', 1.5);
    plot(all_epochs(i).freq.times, infreq3_mean(i, :), 'Color', colors(5, :), 'LineWidth', 1.5);
    plot(all_epochs(i).freq.times, infreq4_mean(i, :), 'Color', colors(6, :), 'LineWidth', 1.5);
    title('Infrequent Stimuli');
    xlabel("Time (ms)");
    ylabel("Amplitude (uV)");
    legend({'Infrequent 1', 'Infrequent 2', 'Infrequent 3', 'Infrequent 4'}, 'Location', 'northeast');
    yline(0, '--', 'HandleVisibility', 'off');
    xline(0, 'r--', 'HandleVisibility', 'off');

    cond_title = [upper(condition(1)) condition(2:end)];
    sgtitle([cond_title ' ERPs - Subject ' num2str(i)], 'FontSize', 12, 'FontWeight', 'bold');
end
