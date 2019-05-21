function obj = setupAudioChannels(obj)


adcs = obj.ADCsignalCh;
adct = obj.ADCtimingCh;
dacs = obj.DACsignalCh;
dact = obj.DACtimingCh;


opts.Resize = 'off';
opts.WindowStyle = 'modal';
opts.Interpreter = 'none';
ch = inputdlg({'Stimulus Output','Recording Input','Loop-Back Output','Loop-Back Input'}, ...
    'Audio',repmat([1 20],4,1), ...
    {num2str(dacs,0),num2str(adcs,0),num2str(dact,0),num2str(adct,0)}, ...
    opts);

if isempty(ch), return; end

info = obj.APR.info;

maxIn  = info.MaximumRecorderChannels;
maxOut = info.MaximumPlayerChannels;

ch = cellfun(@str2double,ch);

if any(ch < 1) || any(ch([1 3]) > maxIn) || any(ch([2 4]) > maxOut)
    h = errordlg(sprintf('Invalid Channel. Max Input Channels = %d; Max Output Channels = %d',maxIn,maxOut), ...
        'Setup Audio Channels','modal');
    uiwait(h);
    return
end


if any(ch(1) == ch(3) | ch(2) == ch(4))
    h = errordlg('Channels must be unique','Setup Audio Channels','modal');
    uiwait(h);
    return
end

obj.ADCsignalCh = ch(2);
obj.ADCtimingCh = ch(4);
obj.DACsignalCh = ch(1);
obj.DACtimingCh = ch(3);



