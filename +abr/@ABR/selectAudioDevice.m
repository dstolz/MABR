function obj = selectAudioDevice(obj,deviceString)
% obj.audioDevice([deviceString])

devices = getAudioDevices(obj.APR);

if nargin == 2 && ~isempty(deviceString) && ~ismember(deviceString,devices)
    warning('Invalid audio device "%s"\n',deviceString);
elseif nargin == 2 && ismember(deviceString,devices)
    obj.audioDevice = deviceString;
    return
end

if ~isempty(obj.audioDevice) && ismember(obj.audioDevice,devices)
    iv = find(ismember(devices,obj.audioDevice));
else
    iv = 1;
end

[s,ok] = listdlg('PromptString','Select audio device', ...
    'Name','Audio Device','ListString',devices,'SelectionMode','single', ...
    'ListSize',[160 100],'InitialValue',iv);

if ~ok, return; end

obj.audioDevice = devices{s};

fprintf('audioDevice selected: "%s"\n',obj.audioDevice)
