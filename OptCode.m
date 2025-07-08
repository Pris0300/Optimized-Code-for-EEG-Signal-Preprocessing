%% Setup
condition = 'pitch'; % CAMBIAR SEGUN VARIACION (pitch, duration, intensity, space)

base_path = 'C:\\Users\\pmb_0\\OneDrive\\NeuroTechs\\AD24\\OptCode'; 
csv_folder = fullfile(base_path, 'Csv'); % Folder donde estan los registros en .csv
mat_folder = fullfile(base_path, 'Mat'); % Folder donde se guardan los .mat 
input_filepath = fullfile(base_path, 'Raw'); % Folder donde se guardan los .set crudos con canales y eventos importados
output_filepath = fullfile(base_path, 'Prepro'); % Folder donde se guardan los .set preprocesados
output_filepathICA = fullfile(output_filepath, 'ICA'); % Folder donde se guardan los .set con los pesos de ICA
event_file = fullfile(base_path, 'Events', [condition '8020.csv']); % Archivo donde estan los eventos a importar
chanlocs_file = 'C:\\Users\\pmb_0\\OneDrive\\NeuroTechs\\8_channels.txt'; % Archivo donde estan los canales

num_sig = 1; % Num de sujetos
ica = cell(num_sig, 1);

%% .CSV to .SET conversion

for i = 1:num_sig
    subj_tag = sprintf('s%d_%s', i, condition);

    csv_filename = fullfile(csv_folder, [subj_tag '.csv']);
    mat_filename = fullfile(mat_folder, [subj_tag '.mat']);
    
    % Convert .csv to .mat
    dd = readtable(csv_filename);
    dd = rows2vars(dd);
    dd = dd(3:10, 1:55001);
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

    % Band-pass filter on baseline removed dataset
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

%% Epoching & MMN

for i = 1:num_sig
    subj_tag = sprintf('s%d_%s_prepro', i, condition);
    filename = [subj_tag '.set'];

    colors = [
    3   201 184;   % 1 - #03c9b8
    27  132 229;   % 2 - #1b84e5
    0   74  173;   % 3 - #004aad
    166 166 166;   % 4 - #a6a6a6
    175 238 238;   % 5 - #afeeee
    135 206 235;   % 6 - #87ceeb
    71  129 180;   % 7 - #4781b4
    28  39  64     % 8 - #1c2740
] / 255;

    % Load dataset
    s_eeg = pop_loadset('filename', filename, 'filepath', output_filepath);
    suj = ['Subject ', num2str(i)];

    % Frequent
    dd_freq = pop_epoch(s_eeg, {'Frequent'}, [-0.1 0.5]);
    dd_freq = pop_rmbase(dd_freq, [-100 0], []);

    % Infrequent 1
    dd_infreq1 = pop_epoch(s_eeg, {'1-Infrequent'}, [-0.1 0.5]);
    dd_infreq1 = pop_rmbase(dd_infreq1, [-100 0], []);

    % Infrequent 2
    dd_infreq2 = pop_epoch(s_eeg, {'2-Infrequent'}, [-0.1 0.5]);
    dd_infreq2 = pop_rmbase(dd_infreq2, [-100 0], []);

    % Infrequent 3 
    dd_infreq3 = pop_epoch(s_eeg, {'3-Infrequent'}, [-0.1 0.5]);
    dd_infreq3 = pop_rmbase(dd_infreq3, [-100 0], []);

    % Infrequent 4 
    dd_infreq4 = pop_epoch(s_eeg, {'4-Infrequent'}, [-0.1 0.5]);
    dd_infreq4 = pop_rmbase(dd_infreq4, [-100 0], []);

    % MMN calculation
    chan = 2; % Fz
    delayms = -104;
    fs = 250;

    % Compute the MMN for each infrequent stimulus by subtracting the ERP of the frequent stimulus
    MMN1 = squeeze(mean(dd_infreq1.data(chan, :, :), 3)) - squeeze(mean(dd_freq.data(chan, :, :), 3));
    MMN2 = squeeze(mean(dd_infreq2.data(chan, :, :), 3)) - squeeze(mean(dd_freq.data(chan, :, :), 3));
    MMN3 = squeeze(mean(dd_infreq3.data(chan, :, :), 3)) - squeeze(mean(dd_freq.data(chan, :, :), 3));
    MMN4 = squeeze(mean(dd_infreq4.data(chan, :, :), 3)) - squeeze(mean(dd_freq.data(chan, :, :), 3));

    % Plotting
    figure;

    % Plot for dd_freq (Frequent Stimuli)
    subplot(5, 2, 1.5:2)
    plot(dd_freq.times, squeeze(mean(dd_freq.data(chan, :, :), 3)), 'Color', colors(3,:), 'LineWidth', 1.5)
    title(sprintf("Frequent Stimuli"));
    xlabel("Time (ms)")
    ylabel("Amplitude (uV)")
    xline(0, 'r--', 'HandleVisibility','off');
    yline(0, '--', 'HandleVisibility','off');
    ylim([-0.3 0.3]);

    % Plot for individual infrequent stimuli
    subplot(5, 2, 3)
    plot(dd_infreq1.times, squeeze(mean(dd_infreq1.data(chan,:,:), 3)), 'Color', colors(1,:), 'LineWidth', 1.5)
    title("Infrequent Stimuli 1")
    xlabel("Time (ms)")
    ylabel("Amplitude (uV)")
    xline(0, 'r--', 'HandleVisibility','off');
    yline(0, '--', 'HandleVisibility','off');
    ylim([-1.5 1.5]);

    subplot(5, 2, 5)
    plot(dd_infreq2.times, squeeze(mean(dd_infreq2.data(chan,:,:), 3)), 'Color', colors(2,:), 'LineWidth', 1.5)
    title("Infrequent Stimuli 2")
    xlabel("Time (ms)")
    ylabel("Amplitude (uV)")
    xline(0, 'r--', 'HandleVisibility','off');
    yline(0, '--', 'HandleVisibility','off');
    ylim([-1.5 1.5]);

    subplot(5, 2, 7)
    plot(dd_infreq3.times, squeeze(mean(dd_infreq3.data(chan,:,:), 3)), 'Color', colors(5,:), 'LineWidth', 1.5)
    title("Infrequent Stimuli 3")
    xlabel("Time (ms)")
    ylabel("Amplitude (uV)")
    xline(0, 'r--', 'HandleVisibility','off');
    yline(0, '--', 'HandleVisibility','off');
    ylim([-1.5 1.5]);

    subplot(5, 2, 9)
    plot(dd_infreq4.times, squeeze(mean(dd_infreq4.data(chan,:,:), 3)), 'Color', colors(6,:), 'LineWidth', 1.5)
    title("Infrequent Stimuli 4")
    xlabel("Time (ms)")
    ylabel("Amplitude (uV)")
    xline(0, 'r--', 'HandleVisibility','off');
    yline(0, '--', 'HandleVisibility','off');
    ylim([-1.5 1.5]);

    % Plot for MMN of individual infrequent stimuli
    subplot(5, 2, 4)
    plot(dd_infreq1.times, MMN1, 'Color', colors(7,:), 'LineWidth', 1.5)
    title("MMN for Infrequent Stimuli 1")
    xlabel("Time (ms)")
    ylabel("Amplitude (uV)")
    xline(0, 'r--', 'HandleVisibility','off');
    yline(0, '--', 'HandleVisibility','off');
    ylim([-1.5 1.5]);

    subplot(5, 2, 6)
    plot(dd_infreq2.times, MMN2, 'Color', colors(7,:), 'LineWidth', 1.5)
    title("MMN for Infrequent Stimuli 2")
    xlabel("Time (ms)")
    ylabel("Amplitude (uV)")
    xline(0, 'r--', 'HandleVisibility','off');
    yline(0, '--', 'HandleVisibility','off');
    ylim([-1.5 1.5]);

    subplot(5, 2, 8)
    plot(dd_infreq3.times, MMN3, 'Color', colors(7,:), 'LineWidth', 1.5)
    title("MMN for Infrequent Stimuli 3")
    xlabel("Time (ms)")
    ylabel("Amplitude (uV)")
    xline(0, 'r--', 'HandleVisibility','off');
    yline(0, '--', 'HandleVisibility','off');
    ylim([-1.5 1.5]);

    subplot(5, 2, 10)
    plot(dd_infreq4.times, MMN4, 'Color', colors(7,:), 'LineWidth', 1.5)
    title("MMN for Infrequent Stimuli 4")
    xlabel("Time (ms)")
    ylabel("Amplitude (uV)")
    xline(0, 'r--', 'HandleVisibility','off');
    yline(0, '--', 'HandleVisibility','off');
    ylim([-1.5 1.5]);

    cond_title = [upper(condition(1)) condition(2:end)];
    sgtitle([cond_title ' ERPs - ', suj], 'FontSize', 12, 'FontWeight', 'bold');
end
