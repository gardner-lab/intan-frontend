function [EMAIL_FLAG,LAST_FILE]=intan_frontend_main(DIR,varargin)
%intan_frontend_main.m is the core script for processing Intan files
%on the fly.  Its primary task is to determine which bits of data
%to keep and which to throw-away.  This has been designed from the ground
%up to work with RHA/RHD-series Intan recordings aligned to vocalizations,
%but can easily be configured to work with other types of trial data.  
%
%	intan_frontend_main(DIR,varargin)
%
%	DIR
%	directory to process 
%
%	the following may be specified as parameter/value pairs
%
%
%		ratio_thresh
%		ratio between song frequencies and non-song frequencies for song detection (default: 4)
%
%		window
%		spectrogram window for song detection (default: 250 samples)
%		
%		noverlap
%		window overlap for song detection (default: 0)
%
%		song_thresh
%		song threshold (default: .2)
%	
%		songduration
%		song duration for song detection in secs (default: .8 seconds)
%
%		low
%		parameter for spectrogram display (default: 5), lower if spectrogram are dim		
%
%		high
%		parameter for spectrogram display (default: 10)
%
%		colors
%		spectrogram colormap (default: hot)		
%
%		filtering
%		high pass corner for mic trace (default: 300 Hz)
%
%		audio_pad
%		extra data to left and right of extraction points to extract (default: .2 secs)
%
%		folder_format
%		folder format (date string) (default: yyyy-mm-dd)
%
%		image_pre
%		image sub directory (default: 'gif')
%	
%		wav_pre
%		wav sub directory (default: 'wav')
%
%		data_pre
%		data sub directory (default: 'mat')
%	
%		delimiter
%		delimiter for filename parsing (default: '\_', or underscore)
%
%
%
% see also zftftb_song_det.m, im_reformat.m
%
%
% To run this in daemon mode, intan_frontend_daemon.m in the directory with unprocessed Intan
% files.  Be sure to create the appropriate directory structure using epys_pipeline_mkdirs.m first.

% while running the daemon this can be changed 

song_ratio=2; % power ratio between song and non-song band
song_len=.005; % window to calculate ratio in (ms)
song_overlap=0; % just do no overlap, faster
song_thresh=.25; % between .2 and .3 seems to work best (higher is more exlusive)
song_band=[2e3 6e3];
song_pow=-inf; % raw power threshold (so extremely weak signals are excluded)
song_duration=.8; % moving average of ratio
colors='hot';
disp_band=[1 10e3];
filtering=300; % changed to 100 from 700 as a more sensible default, leave empty to filter later
audio_pad=7; % pad on either side of the extraction (in seconds)

% directory names

image_pre='gif';
wav_pre='wav';
data_pre='mat';
sleep_pre='sleep';

delimiter='_'; % delimiter for splitting fields in filename

% sleep parameters

sleep_window=[ 22 7 ]; % times for keeping track of sleep data (24 hr time, start and stop)
sleep_fileinterval=10; % specify file interval (in minutes) 
sleep_segment=5; % how much data to keep (in seconds)

% email_parameters

email_monitor=0; % monitor file creation, email if no files created in email_monitor minutes
email_flag=0;
email_noisecut=0;
email_noiselen=4;

% define for manual parsing

parse_options='';
last_file=clock;

file_check=1; % how long to wait between file reads to check if file is no longer being written (in seconds)

mfile_path = mfilename('fullpath');
[script_path,~,~]=fileparts(mfile_path);

% where to place the parsed files
if ~endsWith(DIR,"/")
    DIR=DIR+"/";
end

% this step is very "dumb"!!!! 
% path needs to be "/Users/gardnerlab/Documents/Open Ephys/{expid}/...
% Record Node 102/experiment{i}"

splt=split(DIR, "/");
expid=splt(end-3);
expnum=splt(end-1);
splt2=split(expid,"_");
birdid=splt2(1);
recid=regexp(expnum,"[0-9]$","match");

root_dir=fullfile('/Users/gardnerlab/lab/ephys_data','open_ephys_data',expid,expnum); % where will the detected files go
proc_dir=fullfile('/Users/gardnerlab/lab/ephys_data','staging','processed',expid,expnum); % where do we put the files after processing, maybe auto-delete
					 % after we're confident in the operation of the pipeline
unorganized_dir=fullfile('/Users/gardnerlab/lab/ephys_data','staging','unorganized',splt(end-3),splt(end-1));


% internal parameters

% data_types={'ttl','playback','audio'};

hline=repmat('#',[1 80]);

if ~exist(root_dir,'dir')
	mkdir(root_dir);
end

if ~exist(proc_dir,'dir')
	mkdir(proc_dir);
end

% directory for files that have not been recognized

if ~exist(unorganized_dir,'dir')
	mkdir(unorganized_dir);
end

% we should write out a log file with filtering parameters, when we started, whether song was
% detected in certain files, etc.

nparams=length(varargin);

if mod(nparams,2)>0
	error('Parameters must be specified as parameter/value pairs!');
end

for i=1:2:nparams
	switch lower(varargin{i})
		case 'parse_options'
			parse_options=varargin{i+1};
		case 'last_file'
			last_file=varargin{i+1};
		case 'auto_delete_int'
			auto_delete_int=varargin{i+1};
		case 'sleep_window'
			sleep_window=varargin{i+1};
		case 'sleep_fileinterval'
			sleep_fileinterval=varargin{i+1};
		case 'sleep_segment'
			sleep_segment=varargin{i+1};
		case 'filtering'
			filtering=varargin{i+1};
		case 'audio_pad'
			audio_pad=varargin{i+1};
		case 'disp_band'
			disp_band=varargin{i+1};
		case 'song_thresh'
			song_thresh=varargin{i+1};
		case 'song_ratio'
			song_ratio=varargin{i+1};
		case 'song_duration'
			song_duration=varargin{i+1};
		case 'song_pow'
			song_pow=varargin{i+1};
		case 'song_len'
			song_len=varargin{i+1};
		case 'colors'
			colors=varargin{i+1};
		case 'folder_format'
			folder_format=varargin{i+1};
		case 'delimiter'
			delimiter=varargin{i+1};
		case 'ttl_skip'
			ttl_skip=varargin{i+1};
		case 'ttl_extract'
			ttl_extract=varargin{i+1};
		case 'email_monitor'
			email_monitor=varargin{i+1};
		case 'email_flag'
			email_flag=varargin{i+1};
		case 'playback_extract'
			playback_extract=varargin{i+1};
		case 'playback_thresh'
			playback_thresh=varargin{i+1};
		case 'playback_rmswin'
			playback_rmswin=varargin{i+1};
		case 'playback_skip'
			playback_skip=varargin{i+1};
		case 'birdid'
			birdid=varargin{i+1};
		case 'recid'
			recid=varargin{i+1};
		case 'root_dir'
			root_dir=varargin{i+1};
	end
end


% TODO: make data sorting more compact, map data sources and types automatically w/ fieldnames


if ~isempty(parse_options)
	if parse_options(1)~=delimiter
		parse_options=[delimiter parse_options ];
	end
end

% if exist('gmail_send')~=2
% 	disp('Email from MATLAB not figured, turning off auto-email features...');
% 	email_monitor=0;
% end

EMAIL_FLAG=email_flag;
LAST_FILE=last_file;

if nargin<1
	DIR=pwd;
end

filelisting=dir(fullfile(DIR));
names={filelisting(:).name};
hits=regexp(names,"recording", "match");
hits=cellfun(@length,hits)>0;
names(~hits)=[];

proc_files={};
for i=1:length(names)
    n=names{i}+"/structure.oebin"
	proc_files{i}=fullfile(DIR,n);
end

clear names;

for i=1:length(proc_files)

	fclose('all'); % seems to be necessary

	% read in the data

	disp([repmat(hline,[2 1])]);
	disp('Processing: '+proc_files{i});
    
    % make dir for processed
    match=regexp(proc_files{i}, "recording[0-9]*", "match");
    num=regexp(match, "[0-9]*", "match");
    
    cur_proc_dir=fullfile(proc_dir,num);
    
    if ~exist(cur_proc_dir, 'dir')
        mkdir(cur_proc_dir)
    end

	% try reading the file, if we fail, skip

	%%% check if file is still being written to, check byte change within N msec
	% when was the last file created

	dir1=dir(proc_files{i});
	pause(file_check);
	dir2=dir(proc_files{i});

	try
		bytedif=dir1.bytes-dir2.bytes;
	catch
		pause(10);
		bytedif=dir1.bytes-dir2.bytes;
	end

	% if we haven't written any new data in the past (file_check) seconds, assume
	% file has been written

	if bytedif==0
		[datastruct,EMAIL_FLAG]=intan_frontend_readfile(proc_files{i},EMAIL_FLAG,email_monitor);
	else
		disp('File still being written, continuing...');
		continue;
	end

	if datastruct.filestatus>0 
		disp('Could not read file, skipping...');
		continue;
    end

    % create the recording directory
    
    if ~exist(fullfile(root_dir,num),'dir')
        mkdir(fullfile(root_dir,num));
    end
    
    image_dir=fullfile(root_dir,num,image_pre);
    wav_dir=fullfile(root_dir,num,wav_pre);
    data_dir=fullfile(root_dir,num,data_pre);
    
    if ~exist(image_dir, 'dir')
        mkdir(image_dir);
    end
    if ~exist(wav_dir, 'dir')
        mkdir(wav_dir);
    end
    if ~exist(data_dir, 'dir')
        mkdir(data_dir);
    end
    
    dirstruct=struct('image',image_dir,'wav',wav_dir,'data',data_dir);

    disp('Entering song detection...');

    if ~isempty(filtering)
        [b,a]=butter(5,[filtering/(datastruct.audio.fs/2)],'high'); 
        datastruct.audio.norm_data=filtfilt(b,a,datastruct.audio.data);
    else
        datastruct.audio.norm_data=detrend(datastruct.audio.data);
    end

    datastruct.audio.norm_data=datastruct.audio.norm_data./max(abs(datastruct.audio.norm_data));

    [song_bin,song_t]=zftftb_song_det(datastruct.audio.norm_data,datastruct.audio.fs,'song_band',song_band,...
        'len',song_len,'overlap',song_overlap,'song_duration',song_duration,...
        'ratio_thresh',song_ratio,'song_thresh',song_thresh,'pow_thresh',song_pow);

    raw_t=[1:length(datastruct.audio.norm_data)]./datastruct.audio.fs;

    % interpolate song detection to original space, collate idxs

    detection=interp1(song_t,double(song_bin),raw_t,'nearest'); 
    ext_pts=markolab_collate_idxs(detection,round(audio_pad*datastruct.audio.fs))/datastruct.audio.fs;

    if ~isempty(ext_pts)
        disp('Song detected in recording');
        intan_frontend_dataextract(num,datastruct,dirstruct,...
            ext_pts,disp_band(1),disp_band(2),colors,'audio',1,'songdet','');	
    end
    
    disp('Data extraction complete');
    intan_frontend_finish(replace(proc_files{i}, "structure.oebin", ""), cur_proc_dir)

end

clearvars datastruct;