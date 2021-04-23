clear;

% Design Parameters 
Fs = 16; % sampling frequency in MHz
ch_space =0.5; % bandwidth in MHz

N_fft = 512; % FFT size
L_overlap = N_fft/2;   
N_time_block = 64; % Observation time

N_training = 20000;
N_test = 4000;
% N_training = 1;
% N_test = 1;

roll_off = 0.22;
over_s1 = 4; % oversampling ratio for PSF
over_s2 = 2; % oversampling ratio for 1st interpolation
over_s3 = 5; % oversampling ratio for 2nd interpolation
over_s = over_s1*over_s2*over_s3; % total oversampling ratio

L_time_total = (N_fft-L_overlap)*(N_time_block-1)+N_fft;
N_sym = ceil(L_time_total/over_s)+1;

psf = rcosdesign(roll_off,30,over_s1,'normal');
intp_flt1 = rcosdesign(0.5,20,over_s2*2,'normal');
intp_flt2 = rcosdesign(0.8,20,over_s3*2,'normal');
psf = psf/sum(psf);
intp_flt1 = intp_flt1/sum(intp_flt1);
intp_flt2 = intp_flt2/sum(intp_flt2);

mod_idx = 4; % 4:QPSK, 32:32QAM, 64:64QAM

% candidates of carrier frequencies
fc_table = -Fs/2+ch_space:ch_space:+Fs/2-ch_space;
fc_table = fc_table + max(fc_table);

width = round(N_fft/(Fs/ch_space));
N_ch = length(fc_table);

%%%%%%%%%%%%%%%%%%%%%%
%% Training data set generation %%
%%%%%%%%%%%%%%%%%%%%%%

XTrain = zeros(2*width, N_time_block, 1, N_training*N_ch);
YTrain = zeros(N_training*N_ch, 1);

for loop=1:N_training
    
    SNR = rand(1)*70-20; % SNR -20~50dB random
        
    ch_status = randi([0 1],length(fc_table),1);
    YTrain(N_ch*(loop-1)+1:N_ch*loop) = ch_status;
    clear tx_sig
    for n=1:length(fc_table)
        if ch_status(n) == 1
            data_t = randi([0 mod_idx-1], N_sym, 1);
            data = [data_t; data_t; data_t];
            SYM_t = qammod(data, mod_idx)*sqrt(0.5);
            % Pulse shaping filter
            temp = upfirdn(SYM_t,psf,over_s1,1)*sqrt(over_s1);
            psf_out = temp((length(psf)+1)/2:end-(length(psf)-1)/2);
            % interpolation (x2)
            temp = upfirdn(psf_out,intp_flt1,over_s2,1)*sqrt(over_s2);
            intp_out1 = temp((length(intp_flt1)+1)/2:end-(length(intp_flt1)-1)/2);
            % interpolation (x5)
            temp = upfirdn(intp_out1,intp_flt2,over_s3,1)*sqrt(over_s3);
            intp_out2 = temp((length(intp_flt2)+1)/2:end-(length(intp_flt2)-1)/2);
            % extract center block
            if exist('tx_sig','var')
                block = intp_out2(N_sym*over_s+1:2*N_sym*over_s);
                tx_sig = tx_sig + block.*exp(1j*2*pi*fc_table(n)/Fs*[1:length(block)]');
            else
                block = intp_out2(N_sym*over_s+1:2*N_sym*over_s);
                tx_sig = block.*exp(1j*2*pi*fc_table(n)/Fs*[1:length(block)]');
            end
        end
    end
    
    % noise generation
    if exist('tx_sig','var')
        noise = sqrt(0.5)*crandn(size(tx_sig));
    else
        noise = sqrt(0.5)*crandn(L_time_total,1);
    end
    % rx signal + noise
    rx_sig = sqrt(10^(SNR/10))*tx_sig + noise;
    
    % rx signal scalining
    rx_sig = rx_sig/300;
    
    % rx signal vector to matrix
    rx_sig_mat = zeros(N_fft,N_time_block);
    idx = 1;
    for n=1:N_time_block
        temp = rx_sig(idx:idx+N_fft-1).*hanning(N_fft);
        temp = abs(fft(temp,N_fft)/sqrt(N_fft));
        temp = wshift('1D',temp,-round(N_fft/(Fs/ch_space)/2));
        rx_sig_mat(:,n) = temp/max(temp);
        idx = idx + N_fft - L_overlap;
    end
    
    for n=1:N_ch
        XTrain(:,:,1,(loop-1)*N_ch+n) = [rx_sig_mat(width*(n-1)+1:width*n,:); rx_sig_mat(end-width+1:end,:)];
    end
    
    %     figure(1); hold off;
    %     imshow(rx_sig_mat); disp(ch_status');
    %     figure(2); hold off;
    %     imshow(rx_sig_mat(width+1:width*2,:));
    
    if mod(loop,1000) == 0
        disp(loop);
    end
    
end
rand_idx = randperm(N_training*N_ch);
XTrain = XTrain(:,:,1,rand_idx); % shuffle
YTrain = YTrain(rand_idx);

im_h = width*2;
im_w = N_time_block;

S = sprintf('CNN_training_data_set_AWGN_fft512_%d.mat', N_time_block);
save(S, 'XTrain', 'YTrain', 'im_h', 'im_w', '-v7.3');

% figure(1)
% imshow(rx_sig_mat);
% figure(2)
% imshow(XTrain(:,:,1,1));

%%%%%%%%%%%%%%%%%%%%
%% Test data set generation  %%
%%%%%%%%%%%%%%%%%%%%

SNR_table = [-20:2:6];

XTest = zeros(2*width,N_time_block,1,N_test*N_ch,length(SNR_table));
YTest = zeros(N_test*N_ch,length(SNR_table));

for SNR_loop=1:length(SNR_table)
    
    SNR = SNR_table(SNR_loop);
    
    for loop=1:N_test
        
        ch_status = randi([0 1],length(fc_table),1);
        YTest(N_ch*(loop-1)+1:N_ch*loop, SNR_loop) = ch_status;
        clear tx_sig
        for n=1:length(fc_table)
            if ch_status(n) == 1
                data_t = randi([0 mod_idx-1], N_sym, 1);
                data = [data_t; data_t; data_t];
                SYM_t = qammod(data, mod_idx)*sqrt(0.5);
                % Pulse shaping filter
                temp = upfirdn(SYM_t,psf,over_s1,1)*sqrt(over_s1);
                psf_out = temp((length(psf)+1)/2:end-(length(psf)-1)/2);
                % interpolation (x2)
                temp = upfirdn(psf_out,intp_flt1,over_s2,1)*sqrt(over_s2);
                intp_out1 = temp((length(intp_flt1)+1)/2:end-(length(intp_flt1)-1)/2);
                % interpolation (x5)
                temp = upfirdn(intp_out1,intp_flt2,over_s3,1)*sqrt(over_s3);
                intp_out2 = temp((length(intp_flt2)+1)/2:end-(length(intp_flt2)-1)/2);
                % extract center block
                if exist('tx_sig','var')
                    block = intp_out2(N_sym*over_s+1:2*N_sym*over_s);
                    tx_sig = tx_sig + block.*exp(1j*2*pi*fc_table(n)/Fs*[1:length(block)]');
                else
                    block = intp_out2(N_sym*over_s+1:2*N_sym*over_s);
                    tx_sig = block.*exp(1j*2*pi*fc_table(n)/Fs*[1:length(block)]');
                end
            end
        end
        
        if exist('tx_sig','var')
            noise = sqrt(0.5)*crandn(size(tx_sig));
        else
            noise = sqrt(0.5)*crandn(L_time_total,1);
        end
        % rx signal + noise
        rx_sig = sqrt(10^(SNR/10))*tx_sig + noise;
        
        % rx signal scalining
        rx_sig = rx_sig/300;
        
        % rx signal vector to matrix
        rx_sig_mat = zeros(N_fft,N_time_block);
        idx = 1;
        for n=1:N_time_block
            temp = rx_sig(idx:idx+N_fft-1).*hanning(N_fft);
            temp = abs(fft(temp,N_fft)/sqrt(N_fft));
            temp = wshift('1D',temp,-round(N_fft/(Fs/ch_space)/2));
            rx_sig_mat(:,n) = temp/max(temp);
            idx = idx + N_fft - L_overlap;
        end
        
        for n=1:N_ch
            XTest(:,:,1,(loop-1)*N_ch+n,SNR_loop) = [rx_sig_mat(width*(n-1)+1:width*n,:); rx_sig_mat(end-width+1:end,:)];
        end
        
        if mod(loop,1000) == 0
            disp(loop);
        end
    end
end

S = sprintf('CNN_test_data_set_AWGN_fft512_%d.mat', N_time_block);
save(S, 'XTest', 'YTest', '-v7.3');

% figure(1)
% imshow(rx_sig_mat);
% figure(2)
% imshow(XTest(:,:,1,1,14));